using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Data;

/// <summary>نتيجة فحص نمط البطاقة قبل الصرف.</summary>
public record CardModeCheck(bool Allowed, string? Message, string Mode);

/// <summary>
/// يقرّر كيف يُتحقَّق من صاحب البطاقة عند الصرف — الطريق الوحيد لذلك.
///
/// <para><b>العطب الذي يصلحه:</b> الرقم السري كان إلزامياً دائماً بلا
/// بديل، والرقم وسيلةُ إثبات **يعرفها طرفان**: الزبون يُدخله على جهاز
/// الكاشير فيراه أو يحفظه، ثم يسحب بعد انصرافه بالبحث عن اسمه. إلزامٌ بلا
/// بديل هو ما يخلق الثغرة — لا ضعف الرقم نفسه.</para>
///
/// <para><b>ونمط «بطاقة فقط» ليس تراخياً:</b> فيه يختفي الرقم السرّي تماماً
/// فلا شيء يُحفَظ أصلاً، ويُحصر الخطر بسقف يومي يضعه صاحب المحل. الثغرة
/// تُغلق بحذف الوسيلة لا بحراستها.</para>
///
/// <para><b>القسمة الحاكمة:</b> المنظمة تحدّد المظروف (الأنماط المسموحة
/// والسقف الأقصى والافتراضي)، والزبون يختار داخله. والكاشير لا يغيّر شيئاً
/// — من يستطيع خفض الحماية لحظة الصرف لا تحميه حمايةٌ.</para>
/// </summary>
public static class CardModeGate
{
    /// <summary>
    /// النمط الفعّال لهذا العميل: اختياره إن كان مسموحاً في منظمته، وإلا
    /// افتراضُ المنظمة.
    ///
    /// <para>سقوطُ اختيارٍ لم يعد مسموحاً إلى الافتراضي — لا رفضُ العملية:
    /// المدير قد يُلغي نمطاً بعد أن اختاره زبائن، وتعطيل حساباتهم عقوبةٌ
    /// على قرار ليس لهم فيه يد.</para>
    /// </summary>
    public static string EffectiveMode(Organization org, Customer customer)
    {
        var allowed = AllowedModes(org);

        if (customer.CardMode is { } chosen && allowed.Contains(chosen)) return chosen;
        if (allowed.Contains(org.CardModeDefault)) return org.CardModeDefault;

        // لا نمط صالحاً في الإعدادات: يُرجَع إلى الرقم السرّي — الأشدّ بين
        // المتاح. الفشل هنا **مغلق** بخلاف بوّابة الترخيص: هذه تحرس مال
        // زبون، وتلك تحرس تحصيل اشتراك.
        return CardModes.Pin;
    }

    public static string[] AllowedModes(Organization org)
    {
        var configured = (org.CardModesAllowed ?? "")
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Where(CardModes.IsSelectable)
            .ToArray();

        // قائمة فارغة أو كلها غير صالحة: الرقم السرّي وحده. الفراغ لا يعني
        // «كل شيء مسموح» أبداً.
        return configured.Length > 0 ? configured : new[] { CardModes.Pin };
    }

    /// <summary>
    /// السقف اليومي الفعّال: الأشدّ بين سقف المنظمة وسقف الزبون.
    ///
    /// <para>سقف الزبون يُقبل إن كان **أقلّ** فقط: الأعلى تجاوزٌ لحدٍّ وضعه
    /// صاحب المحل لمخاطرته هو، والتشديد على النفس حقٌّ بلا إذن.</para>
    /// </summary>
    public static decimal EffectiveCap(Organization org, Customer customer)
    {
        var orgCap = Math.Max(0, org.CardOpenModeDailyCap);
        var own = Math.Max(0, customer.DailyCap);
        return own > 0 && own < orgCap ? own : orgCap;
    }

    /// <summary>
    /// يفحص إن كان الصرف مسموحاً بهذا المبلغ في النمط الفعّال.
    ///
    /// <para>الرقم السرّي يُتحقَّق منه خارج هذه الدالة (راجع
    /// [CustomerPinGate]) لأنه يكتب محاولات فاشلة ويحتاج ترتيباً دقيقاً مع
    /// المعاملة. هنا يُقال فقط **هل يُطلَب**.</para>
    /// </summary>
    public static async Task<CardModeCheck> CheckAsync(
        AppDbContext db, Organization org, Customer customer, decimal amount, DateTime now)
    {
        var mode = EffectiveMode(org, customer);

        if (mode != CardModes.Card)
        {
            return new CardModeCheck(true, null, mode);
        }

        var cap = EffectiveCap(org, customer);
        if (cap <= 0)
        {
            return new CardModeCheck(false,
                "الصرف بالبطاقة وحدها غير مفعَّل — يلزم الرقم السرّي.", mode);
        }

        // ما صُرف اليوم من هذه المحفظة. اليوم تقويميّ لا آخر 24 ساعة:
        // «سقف يومي» يفهمه الزبون والكاشير بمعناه المتعارف، ونافذةٌ متحرّكة
        // تجعل الرفض يبدو عشوائياً.
        var dayStart = now.Date;
        var spentToday = await db.CustomerWalletTransactions
            .Where(t => t.CustomerId == customer.Id
                     && t.Kind == WalletKinds.Spend
                     && t.CreatedAt >= dayStart)
            .SumAsync(t => (decimal?)t.Amount) ?? 0;

        if (spentToday + amount > cap)
        {
            var remaining = Math.Max(0, cap - spentToday);
            return new CardModeCheck(false,
                $"تجاوز السقف اليومي للصرف بالبطاقة ({cap:0.##}). " +
                $"صُرف اليوم {spentToday:0.##}، والمتبقّي {remaining:0.##}. " +
                "للمبالغ الأكبر يلزم الرقم السرّي.", mode);
        }

        return new CardModeCheck(true, null, mode);
    }
}
