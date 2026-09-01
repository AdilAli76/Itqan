using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Authorization;
using KineticEnterprise.Api.Data;

namespace KineticEnterprise.Api.Controllers;

public record LicenseActivationDto(
    /// بصمة **جهاز الخادم** — تُرسَل لمالك المنصّة ليُصدر مفتاحاً لها.
    string MachineFingerprint,
    bool IsValid,
    string? Message,
    string? CurrentKey,
    /// أمضبوطٌ المفتاح العامّ؟ بلا ضبطه لا يُفرَض ترخيصٌ أصلاً.
    bool Enforced);

public record ActivateLicenseRequest(string LicenseKey);

public record LicenseStatusDto(
    Guid Id, string LicenseKey, string PlanTier, string Status,
    int MaxBranches, int MaxUsers, int CurrentBranches, int CurrentUsers,
    List<string> EnabledModules, DateTime IssuedAt, DateTime ExpiresAt, int DaysRemaining);

/// <summary>
/// عرض للقراءة فقط عمداً — لا توجد بوابة دفع أو جهة إصدار تراخيص فعلية في
/// هذا النظام بعد (راجع README: "منطق الترخيص الفعلي... لم يُبنَ بعد"). بناء
/// أزرار "تجديد/ترقية" هنا كانت ستبدو فعّالة دون أن تُنفّذ أي شيء حقيقي —
/// التجديد الفعلي يتم من طرف البائع (مشغّل النظام) خارج التطبيق حالياً.
/// </summary>
[ApiController]
[Route("api/license")]
[Authorize]
[RequirePermission("license.view")]
public class LicensesController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly IConfiguration _config;
    public LicensesController(AppDbContext db, IConfiguration config)
    {
        _db = db;
        _config = config;
    }

    /// <summary>
    /// ما يحتاجه الزبون ليُفعّل نسخته المحلّية: بصمة جهازه وحال ترخيصه.
    ///
    /// <para><b>الفجوة التي تسدّها:</b> التركيب المحلّي بلا إنترنت مبنيٌّ
    /// بالكامل — التوقيع وربط المنظمة وبصمة الجهاز والمهلة كلّها تُفرَض في
    /// [LicenseVerification]. لكن إدخال المفتاح كان يتطلّب طرفيةً وأمراً
    /// على سطر الأوامر، وصاحبُ محلٍّ لا يفتح PowerShell. فتُقرأ البصمة هنا
    /// ويُلصق المفتاح من نفس الشاشة.</para>
    ///
    /// <para>والبصمة تُقرأ من الخادم لا من الجهاز الذي يعرض الشاشة: النسخة
    /// المحلّية تعمل على جهاز المحلّ، وقد يُفتح التطبيق من جهازٍ ثانٍ على
    /// نفس السويتش — وبصمةُ ذلك الجهاز لا تُرخَّص شيئاً.</para>
    /// </summary>
    [HttpGet("activation")]
    public async Task<ActionResult<LicenseActivationDto>> Activation()
    {
        var check = await LicenseVerification.CheckAsync(_db, _config);
        var license = await _db.Licenses.OrderByDescending(l => l.IssuedAt).FirstOrDefaultAsync();

        return new LicenseActivationDto(
            HardwareFingerprint.Current(),
            check.Valid,
            check.Message,
            license?.LicenseKey,
            // بلا مفتاح عامّ لا يُفرَض شيء — والشاشة تقول ذلك صراحةً بدل
            // أن تعرض «الترخيص سليم» على تركيبٍ لا يفحص أصلاً.
            !string.IsNullOrWhiteSpace(_config["License:PublicKey"]));
    }

    /// <summary>
    /// يحفظ مفتاح ترخيص بعد التحقّق منه.
    ///
    /// <para><b>يُفحَص قبل أن يُحفَظ لا بعده:</b> حفظُ مفتاح فاسد ثم اكتشافُ
    /// ذلك عند أوّل كتابة يترك العميل بنظامٍ للقراءة فقط ورسالةٍ يظنّها
    /// عطباً في الحفظ. والفحص هنا هو **نفسه** الذي يفرضه
    /// [LicenseVerification] — لا نسخةٌ ثانية منه تفترق عنه.</para>
    ///
    /// <para>ومقصور على <c>super_admin</c>: الترخيص عقد المنظمة كلّها، لا
    /// شأنَ لكاشير به.</para>
    /// </summary>
    [HttpPost("activate")]
    [Authorize(Roles = "super_admin")]
    public async Task<ActionResult<LicenseActivationDto>> Activate(ActivateLicenseRequest request)
    {
        var key = (request?.LicenseKey ?? "").Trim();
        if (key.Length == 0) return BadRequest(new { message = "الصق مفتاح الترخيص" });

        var license = await _db.Licenses.OrderByDescending(l => l.IssuedAt).FirstOrDefaultAsync();
        if (license is null) return NotFound(new { message = "لا يوجد ترخيص مسجَّل لهذه المنظمة" });

        var verdict = LicenseVerification.Inspect(license.OrganizationId, key, _config);
        if (!verdict.Valid)
        {
            return BadRequest(new { message = verdict.Message ?? "مفتاح غير صالح" });
        }

        license.LicenseKey = key;

        // وتُحدَّث الحدود من الحمولة الموقَّعة لا تُترك كما كانت: مفتاحٌ
        // جديد بمدّة أطول أو فروع أكثر يُحفَظ ثم لا يُغيّر شيئاً، فيدفع
        // العميل ترقيةً لا يراها.
        if (verdict.Payload is not null)
        {
            license.ExpiresAt = verdict.Payload.ExpiresAt;
            license.MaxBranches = verdict.Payload.MaxBranches;
            license.MaxUsers = verdict.Payload.MaxUsers;
            license.PlanTier = verdict.Payload.PlanTier;
            license.Status = "active";
        }

        await _db.SaveChangesAsync();

        // النتيجة محفوظة مؤقّتاً خمس دقائق — بلا هذا يبقى العميل ممنوعاً
        // بعد تفعيلٍ ناجح ويظنّ المفتاح فاسداً.
        LicenseVerification.Forget(license.OrganizationId);

        var after = await LicenseVerification.CheckAsync(_db, _config);
        return new LicenseActivationDto(
            HardwareFingerprint.Current(), after.Valid, after.Message, license.LicenseKey,
            !string.IsNullOrWhiteSpace(_config["License:PublicKey"]));
    }

    [HttpGet("me")]
    public async Task<ActionResult<LicenseStatusDto>> GetMine()
    {
        var license = await _db.Licenses.OrderByDescending(l => l.IssuedAt).FirstOrDefaultAsync();
        if (license is null)
        {
            return NotFound(new { message = "لا يوجد ترخيص مسجَّل لهذه المنظمة" });
        }

        // app_users بلا Security Policy عمداً (راجع تعليق AppDbContext) —
        // فلترة المنظمة هنا يدوية وإلا يُحسَب كل مستخدمي كل العملاء معاً،
        // بعكس Branches المحمي أصلاً بـ RLS فلا يحتاج شرطاً يدوياً.
        var orgId = Guid.Parse(User.FindFirstValue("organization_id")!);
        var currentBranches = await _db.Branches.CountAsync(b => b.IsActive);
        var currentUsers = await _db.AppUsers.CountAsync(u => u.IsActive && u.OrganizationId == orgId);

        List<string> modules;
        try
        {
            modules = JsonSerializer.Deserialize<List<string>>(license.EnabledModulesJson) ?? new();
        }
        catch (JsonException)
        {
            modules = new();
        }

        var daysRemaining = (int)Math.Ceiling((license.ExpiresAt - DateTime.UtcNow).TotalDays);

        return new LicenseStatusDto(
            license.Id, license.LicenseKey, license.PlanTier, license.Status,
            license.MaxBranches, license.MaxUsers, currentBranches, currentUsers,
            modules, license.IssuedAt, license.ExpiresAt, daysRemaining);
    }
}
