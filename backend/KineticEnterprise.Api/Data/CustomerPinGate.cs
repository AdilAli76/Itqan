using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Data;

public enum PinCheck
{
    Ok,
    Invalid,
    Locked,
    NotSet,
}

public record PinOutcome(PinCheck Result, string Message);

/// <summary>
/// التحقق من الرقم السري للعميل وعدّ محاولاته الفاشلة — في مكان واحد يستخدمه
/// كل من بوابة العميل ونقطة البيع.
///
/// المشاركة هنا ليست تنظيماً للكود بل شرط أمني: لو كان لكل مدخل عدّاد قفل
/// خاص به، لصار بالإمكان تخمين الرقم السري على نقطة البيع بلا حد بعد أن يقفل
/// المهاجم نفسه على البوابة (أو العكس) — أي أن عدّادين يعنيان ضِعف المحاولات
/// المسموحة فعلياً. كلا المدخلين يكتبان في customer_pin_attempts ويقرآن
/// pin_locked_until نفسه، فالحد 5 محاولات هو 5 إجمالاً لا 5 لكل باب.
/// </summary>
public static class CustomerPinGate
{
    /// <summary>
    /// يتحقق ويُسجّل المحاولة ويضبط القفل عند تجاوز الحد. لا يستدعي
    /// SaveChangesAsync — يتركه للمُستدعي ليضمّه لمعاملته الخاصة (إنشاء
    /// الفاتورة مثلاً) فلا تُحفَظ محاولة دون العملية التي رافقتها.
    /// </summary>
    public static async Task<PinOutcome> VerifyAsync(
        AppDbContext db,
        Customer customer,
        string? pin,
        string? ipAddress)
    {
        if (customer.PinHash is null)
        {
            return new PinOutcome(PinCheck.NotSet, "لا يوجد رقم سري لهذا العميل — أصدر له بطاقة أولاً");
        }

        if (customer.PinLockedUntil is not null && customer.PinLockedUntil > DateTime.UtcNow)
        {
            var minutes = (int)Math.Ceiling((customer.PinLockedUntil.Value - DateTime.UtcNow).TotalMinutes);
            return new PinOutcome(PinCheck.Locked, $"البطاقة مقفلة مؤقتاً — حاول بعد {minutes} دقيقة");
        }

        var ok = !string.IsNullOrEmpty(pin) && BCrypt.Net.BCrypt.Verify(pin, customer.PinHash);

        db.CustomerPinAttempts.Add(new CustomerPinAttempt
        {
            OrganizationId = customer.OrganizationId,
            CustomerId = customer.Id,
            Success = ok,
            IpAddress = ipAddress,
        });

        if (ok)
        {
            customer.PinLockedUntil = null;
            return new PinOutcome(PinCheck.Ok, "");
        }

        // القفل يعتمد على الإخفاقات المتتالية داخل نافذة القفل نفسها، فمحاولة
        // ناجحة قديمة لا تُلغي عدّ إخفاقات حديثة.
        var since = DateTime.UtcNow.AddMinutes(-CustomerCards.PinLockoutMinutes);
        var recentFailures = await db.CustomerPinAttempts
            .CountAsync(a => a.CustomerId == customer.Id && !a.Success && a.CreatedAt >= since);

        if (recentFailures + 1 >= CustomerCards.PinMaxAttempts)
        {
            customer.PinLockedUntil = DateTime.UtcNow.AddMinutes(CustomerCards.PinLockoutMinutes);
        }

        return new PinOutcome(PinCheck.Invalid, "الرقم السري غير صحيح");
    }
}
