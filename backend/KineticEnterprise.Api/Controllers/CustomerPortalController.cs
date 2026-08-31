using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Data.SqlClient;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Controllers;

/// <param name="Pin">
/// اختياري: البطاقة بلا رقم سرّي تدخل بالمسح وحده — راجع GlanceEntries.
/// </param>
public record PortalLoginRequest(string CardCode, string? Pin = null);

public record PortalAccountDto(
    string CustomerName, string OrganizationName, string CardCode,
    decimal Balance, decimal CreditLimit, int LoyaltyPoints,
    /// <summary>
    /// هل تحقّق رقمٌ سرّي فعلاً — لا أن البطاقة تحمله.
    ///
    /// <para>تقرؤه الواجهة لتقول لصاحب البطاقة إن ما يراه مختصر، وكيف
    /// يرى الكشف الكامل. وبلا هذا يظنّ أن حركاته خمس فقط.</para>
    /// </summary>
    bool PinVerified,
    List<PortalTransactionDto> Transactions);

public record PortalTransactionDto(string Kind, decimal SignedAmount, string? Note, DateTime CreatedAt);

/// <summary>
/// بوابة العميل — للقراءة فقط تماماً: يرى رصيده وحركاته ولا يستطيع تنفيذ أي
/// عملية (الشحن والخصم من الإدارة وحدها، وكشف الحساب يُطلَب منها).
///
/// [AllowAnonymous] لأن العميل ليس مستخدَم نظام ولا يملك حساب app_users —
/// المصادقة هنا برمز البطاقة + الرقم السري فقط، وكل استجابة تُبنى من بيانات
/// العميل المُتحقَّق منه في نفس الطلب (لا توكن ولا جلسة محفوظة)، فلا يمكن
/// لطلب أن يقرأ بيانات عميل آخر دون معرفة رمزه ورقمه السري معاً.
/// </summary>
[ApiController]
[Route("api/customer-portal")]
[AllowAnonymous]
public class CustomerPortalController : ControllerBase
{
    /// <summary>ما يراه المسح وحده — يكفي «كم بقي لي؟» ولا يكشف تاريخاً.</summary>
    private const int GlanceEntries = 5;

    /// <summary>الكشف الكامل — لبطاقةٍ تحقّق رقمها السرّي.</summary>
    private const int FullEntries = 50;

    private readonly IConfiguration _config;
    public CustomerPortalController(IConfiguration config) => _config = config;

    [HttpPost("login")]
    public async Task<ActionResult<PortalAccountDto>> Login(PortalLoginRequest request)
    {
        var code = (request.CardCode ?? "").Trim().ToUpperInvariant();
        if (string.IsNullOrEmpty(code))
        {
            return Unauthorized(new { message = "رمز البطاقة أو الرقم السري غير صحيح" });
        }

        // اتصال مستقل: TenantContextMiddleware لم يضبط SESSION_CONTEXT (الطلب
        // مجهول الهوية)، فنحدّد المنظمة من الفهرس المعفى من RLS ثم نضبط
        // السياق يدوياً لتُقرأ بقية الجداول المحمية بشكل طبيعي.
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlServer(_config.GetConnectionString("Default"))
            .UseSnakeCaseNamingConvention()
            .Options;

        await using var db = new AppDbContext(options);
        var card = await db.CustomerCardIndexes.FirstOrDefaultAsync(c => c.CardCode == code);
        if (card is null)
        {
            return Unauthorized(new { message = "رمز البطاقة أو الرقم السري غير صحيح" });
        }

        // حالة البطاقة تُفرَض هنا فعلياً — الحظر في شاشة المدير بلا أثر على
        // الدخول كان سيجعله زراً تجميلياً. الرسالة صريحة (بعكس رسالة الرمز
        // الخاطئ العامة) لأن العميل يحتاج معرفة أن عليه مراجعة الإدارة.
        if (!card.IsUsable(DateOnly.FromDateTime(DateTime.UtcNow)))
        {
            var reason = card.State == CardStates.Blocked
                ? "البطاقة محظورة — راجع إدارة المتجر"
                : "انتهت صلاحية البطاقة — راجع إدارة المتجر";
            return StatusCode(403, new { message = reason });
        }

        var connection = db.Database.GetDbConnection();
        await connection.OpenAsync();
        await using (var cmd = connection.CreateCommand())
        {
            cmd.CommandText = "EXEC sp_set_session_context @key=N'organization_id', @value=@orgId;";
            cmd.Parameters.Add(new SqlParameter("@orgId", card.OrganizationId));
            await cmd.ExecuteNonQueryAsync();
        }

        var customer = await db.Customers.FirstOrDefaultAsync(c => c.Id == card.CustomerId && !c.IsDeleted);
        if (customer is null)
        {
            return Unauthorized(new { message = "رمز البطاقة أو الرقم السري غير صحيح" });
        }

        // ── ما يفتحه المسح وحده ─────────────────────────────────────────
        //
        // كان الحساب بلا رقم سرّي يُمنع من البوابة كلّها. وذاك حَمى بثمنٍ
        // باهظ: أكثر حاملي البطاقات في نسخة المحفظة بلا رقم سرّي عمداً
        // (بطاقات مرتَّبات تُصدَر جماعياً)، فكانوا يسألون الكاشير «كم بقي
        // لي؟» ويتوقّف الصندوق ليجيب.
        //
        // فصار المسح يفتح **الرصيد وآخر خمس حركات** — يجيب سؤاله الحقيقي
        // ولا يكشف تاريخه. والكشف الكامل يشترط رقماً سرّياً تحقّق فعلاً.
        //
        // ⚠ **والثمن مقصود ومقبول:** من يجد بطاقةً بلا رقم سرّي يرى رصيد
        // صاحبها وآخر خمس حركات. ولا حاجز بعد البطاقة — هي المفتاح. ومن
        // أراد حاجزاً أصدر بطاقةً برقم سرّي، والخيار بيد الإدارة كما كان.
        var pinVerified = false;

        if (customer.PinHash is not null)
        {
            if (string.IsNullOrEmpty(request.Pin))
            {
                // رسالة صريحة لا «رمز خاطئ»: البطاقة تحمل رقماً ولم يُرسَل،
                // وإخفاء ذلك يجعل صاحبها يعيد المسح عشرات المرّات.
                return StatusCode(403, new
                {
                    message = "هذه البطاقة تحتاج رقماً سرّياً — أدخله للمتابعة."
                });
            }

            // نفس البوابة التي تستخدمها نقطة البيع — عدّاد قفل واحد لا اثنان.
            var pinResult = await CustomerPinGate.VerifyAsync(
                db, customer, request.Pin, HttpContext.Connection.RemoteIpAddress?.ToString());
            await db.SaveChangesAsync();

            if (pinResult.Result == PinCheck.Locked)
            {
                return StatusCode(429, new { message = pinResult.Message });
            }
            if (pinResult.Result != PinCheck.Ok)
            {
                // رسالة عامة عمداً هنا (بعكس نقطة البيع): البوابة مفتوحة
                // للإنترنت، والتمييز بين «رمز خاطئ» و«رقم سري خاطئ» يكشف أي
                // الرموز موجود فعلاً.
                return Unauthorized(new { message = "رمز البطاقة أو الرقم السري غير صحيح" });
            }

            pinVerified = true;
        }

        var org = await db.Organizations.FirstOrDefaultAsync();
        var balance = await WalletBalances.ComputeAsync(db, customer.Id);
        var transactions = await db.CustomerWalletTransactions
            .Where(t => t.CustomerId == customer.Id)
            .OrderByDescending(t => t.CreatedAt)
            .Take(pinVerified ? FullEntries : GlanceEntries)
            .ToListAsync();

        return new PortalAccountDto(
            customer.FullName,
            org?.DisplayName ?? "",
            card.CardCode,
            balance,
            customer.CreditLimit,
            customer.LoyaltyPoints,
            pinVerified,
            transactions.Select(t => new PortalTransactionDto(
                t.Kind, t.Amount * WalletKinds.SignOf(t.Kind), t.Note, t.CreatedAt)).ToList());
    }
}
