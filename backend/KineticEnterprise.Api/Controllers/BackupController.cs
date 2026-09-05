using System.Data.Common;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Authorization;
using KineticEnterprise.Api.Data;

namespace KineticEnterprise.Api.Controllers;

/// <summary>
/// نسخة احتياطية كاملة لبيانات المنظمة — ملفٌ واحد يُنزَّل ويُحفظ خارج
/// الجهاز.
///
/// <para><b>سبب وجوده:</b> لم يكن في النظام أي طريق يُخرج البيانات. جهةٌ
/// أدخلت ألف منتسب وسنةً من الحركات كانت كل نسختها الوحيدة على قرص خادمٍ
/// واحد: قرصٌ يتلف، أو مزوّد استضافة يُغلق الحساب، أو خادمٌ يُسرَق —
/// وينتهي كل شيء بلا شيء يُستعاد منه. وهذا وحده يمنع تسليم النظام لجهةٍ
/// جادّة.</para>
///
/// <para><b>ولماذا لقطةٌ من الجداول لا نسخة SQL:</b> نسخة القاعدة
/// (<c>BACKUP DATABASE</c>) تلزمها صلاحية على الخادم ومسارٌ على قرصه،
/// وتُخرج **كل** المنظمات في ملف واحد — وهو ما لا يجوز تسليمه لعميل. أمّا
/// القراءة عبر اتصال الطلب فتمرّ على سياسات العزل نفسها، فلا يخرج في
/// الملف إلا صفوف صاحبه.</para>
///
/// <para><b>ويُبَثّ ولا يُجمَع في الذاكرة:</b> منظمةٌ بسنتين من الفواتير
/// تُنتج ملفاً بعشرات الميغابايتات، وبناؤه في مصفوفة بايتات قبل إرساله
/// كان يعني خادماً يسقط تحت أول نسخةٍ حقيقية.</para>
///
/// <para><b>وبصلاحية يمنحها مالك المنظمة</b> — <c>backup.manage</c> — لا
/// بدورٍ ثابت في الكود. الملف يحوي كل ما في النظام (أرصدة العملاء، وبصمات
/// كلمات المرور، وبصمات أرقام البطاقات السرية)، لكن **من يتحمّل هذا الخطر
/// هو صاحب البيانات**: جهةٌ محاسبها هو من يحفظ نسخها الأسبوعية لا يجوز أن
/// تنتظر مالكها كل مرّة، وأخرى ترى الملف أخطر من أن يخرج من يد المالك.
/// فالقرار في «مصفوفة الصلاحيات» لا هنا.</para>
///
/// <para>ولا تُمنَح الصلاحية لأي دور افتراضاً: من يريدها يمنحها صراحةً،
/// وsuper_admin يتجاوز الفحص كعادته فلا يُغلَق الباب على المالك.</para>
/// </summary>
[ApiController]
[Route("api/backup")]
[Authorize]
public class BackupController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly IConfiguration _config;
    private readonly IHttpClientFactory _http;

    public BackupController(AppDbContext db, IConfiguration config, IHttpClientFactory http)
    {
        _db = db;
        _config = config;
        _http = http;
    }

    /// <summary>
    /// ما الذي ستحويه النسخة وكم حجمها تقريباً — يُسأل قبل التنزيل.
    ///
    /// <para>تنزيلٌ يبدأ بلا رقم يترك المستخدم أمام شريط تقدّم لا يعرف
    /// أينتهي بعد ثانية أم بعد ربع ساعة، فيلغيه ويظنّ النظام معطوباً.</para>
    /// </summary>
    [HttpGet("summary")]
    [RequirePermission("backup.manage")]
    public async Task<ActionResult<object>> Summary()
    {
        var scope = await BranchScopeGuard();
        if (scope is not null) return scope;

        var org = await _db.Organizations
            .Select(o => new { o.Id, o.DisplayName, o.Edition })
            .FirstOrDefaultAsync();
        if (org is null) return Forbid();

        // متى كانت آخر نسخة — من سجل التدقيق لا من جدولٍ جديد: التصدير
        // مسجَّلٌ فيه أصلاً، وجدولٌ ثانٍ يحمل نفس الحقيقة يفترقان عند أول
        // خطأ. والسؤال الذي يجيب عنه هو السؤال الحقيقي: «هل نحن محميّون
        // اليوم؟» — ونسخةٌ عمرها ثمانية أشهر تُقرأ كأنها لا نسخة.
        var lastExport = await _db.AuditLogs
            .Where(l => l.Action == "backup.exported")
            .OrderByDescending(l => l.CreatedAt)
            .Select(l => (DateTime?)l.CreatedAt)
            .FirstOrDefaultAsync();

        var connection = await OpenConnectionAsync();
        var plan = await BackupArchive.PlanAsync(_db, connection);
        var counts = new List<object>();
        var totalRows = 0L;

        foreach (var table in plan.Include)
        {
            await using var command = connection.CreateCommand();
            command.CommandText = BackupArchive.Select("COUNT_BIG(*)", table);
            BackupArchive.AddOrgParameter(command, table, org.Id);
            var rows = Convert.ToInt64(await command.ExecuteScalarAsync() ?? 0L);
            totalRows += rows;
            if (rows > 0) counts.Add(new { table = table.Name, rows });
        }

        return Ok(new
        {
            organization = org.DisplayName,
            edition = org.Edition,
            tables = counts.Count,
            totalRows,
            // يُعرَض ولا يُبتلَع: قاعدةٌ متأخّرة عن النموذج تعني نسخةً
            // ناقصة، ومعرفة ذلك قبل الاعتماد عليها هي كل الفائدة.
            missingTables = plan.Missing,
            // وما استُبعد لأنه ليس بيانات هذه المنظمة — يُذكَر حتى لا
            // يُظنّ غيابه عطباً.
            skippedTables = plan.Skipped,
            lastExportAt = lastExport,
            generatedAt = DateTime.UtcNow,
            auto = await AutoStateAsync(),
        });
    }

    /// <summary>
    /// حالة الرفع التلقائي: أمُهيّأ الخادم، أمربوطٌ الحساب، ومتى آخر رفع.
    ///
    /// <para><b>ولا يخرج رمز التحديث أبداً</b> — البريد وحده. من يملك الرمز
    /// يكتب في درايف صاحبه بلا كلمة مرور، فلا يُرسَل إلى شاشةٍ لأي سبب.
    /// </para>
    /// </summary>
    async Task<object> AutoStateAsync()
    {
        var options = GoogleOptions.From(_config);
        var org = await _db.Organizations
            .Select(o => new
            {
                o.AutoBackupEnabled,
                o.AutoBackupHour,
                o.GoogleAccountEmail,
                o.GoogleRefreshToken,
                o.LastAutoBackupAt,
                o.LastAutoBackupStatus,
                o.LastAutoBackupError,
            })
            .FirstOrDefaultAsync();

        return new
        {
            // «غير مهيّأ» حالةٌ تُقال صراحةً: بلا تسجيل التطبيق لدى قوقل لا
            // شيء يعمل، وزرُّ ربطٍ يفشل بلا سبب أسوأ من زرٍّ يشرح غيابه.
            serverConfigured = options.Configured,
            connected = !string.IsNullOrEmpty(org?.GoogleRefreshToken),
            accountEmail = org?.GoogleAccountEmail,
            enabled = org?.AutoBackupEnabled ?? false,
            hour = org?.AutoBackupHour ?? 3,
            lastAt = org?.LastAutoBackupAt,
            lastStatus = org?.LastAutoBackupStatus,
            lastError = org?.LastAutoBackupError,
        };
    }

    public record AutoBackupSettingsRequest(bool Enabled, int Hour);

    /// <summary>تشغيل الرفع الليلي وضبط ساعته — بتوقيت المنظمة.</summary>
    [HttpPut("auto")]
    [RequirePermission("backup.manage")]
    public async Task<IActionResult> SetAuto(AutoBackupSettingsRequest request)
    {
        if (request.Hour < 0 || request.Hour > 23)
            return BadRequest(new { message = "الساعة بين 0 و23" });

        var org = await _db.Organizations.FirstOrDefaultAsync();
        if (org is null) return Forbid();

        // لا تشغيل بلا حساب مربوط: مفتاحٌ مفتوح ورفعٌ لا يحدث هو أخطر ما في
        // الباب — المالك يظنّ نفسه محميّاً وليس كذلك.
        if (request.Enabled && string.IsNullOrEmpty(org.GoogleRefreshToken))
            return BadRequest(new { message = "اربط حساب قوقل أولاً" });

        org.AutoBackupEnabled = request.Enabled;
        org.AutoBackupHour = request.Hour;
        _db.LogAudit(org.Id, CurrentUserId(), "backup.auto_changed", "organizations", org.Id,
            newValues: new { request.Enabled, request.Hour });
        await _db.SaveChangesAsync();
        return NoContent();
    }

    /// <summary>
    /// رابط شاشة موافقة قوقل.
    ///
    /// <para>الحالة (<c>state</c>) تحمل معرّف المنظمة موقَّعاً بمفتاح
    /// الخادم: نقطة العودة من قوقل تأتي **بلا توكن** (المتصفّح يعود من
    /// نطاق قوقل)، فلولا التوقيع لاستطاع أي أحد ربط حسابه بأي منظمة.</para>
    /// </summary>
    [HttpGet("google/authorize")]
    [RequirePermission("backup.manage")]
    public async Task<ActionResult<object>> Authorize()
    {
        var options = GoogleOptions.From(_config);
        if (!options.Configured)
            return BadRequest(new { message = "الرفع إلى درايف غير مهيّأ على هذا الخادم" });

        var org = await _db.Organizations.Select(o => new { o.Id }).FirstOrDefaultAsync();
        if (org is null) return Forbid();

        return Ok(new { url = GoogleDrive.ConsentUrl(options, OAuthState.Sign(org.Id, _config)) });
    }

    /// <summary>
    /// عودة قوقل بعد الموافقة — تُفتح في متصفّح المستخدم لا في التطبيق.
    /// </summary>
    [AllowAnonymous]
    [HttpGet("google/callback")]
    public async Task<IActionResult> Callback([FromQuery] string? code, [FromQuery] string? state,
        [FromQuery] string? error)
    {
        if (!string.IsNullOrEmpty(error)) return Html($"لم تكتمل الموافقة: {error}");
        if (string.IsNullOrEmpty(code) || string.IsNullOrEmpty(state)) return Html("طلب غير مكتمل");

        if (!OAuthState.TryRead(state, _config, out var orgId))
            return Html("رابط العودة غير صالح أو منتهٍ — أعد المحاولة من الإعدادات");

        var options = GoogleOptions.From(_config);
        if (!options.Configured) return Html("الرفع إلى درايف غير مهيّأ على هذا الخادم");

        try
        {
            var http = _http.CreateClient();
            var tokens = await GoogleDrive.ExchangeCodeAsync(http, options, code);
            if (string.IsNullOrEmpty(tokens.RefreshToken))
                return Html("لم يُرسل قوقل رمز تحديث — أزل صلاحية التطبيق من حسابك ثم أعد الربط");

            var email = await GoogleDrive.AccountEmailAsync(http, tokens.AccessToken);

            // الاتصال هنا بلا SESSION_CONTEXT: الطلب مجهول الهوية (العودة من
            // قوقل)، فالتحديث بمعرّفٍ صريح من الحالة الموقَّعة.
            await _db.Database.ExecuteSqlInterpolatedAsync($@"
                UPDATE organizations
                SET google_refresh_token = {tokens.RefreshToken},
                    google_account_email = {email}
                WHERE id = {orgId}");

            return Html($"تم ربط الحساب {email}. أغلق هذه الصفحة وعُد إلى النظام.");
        }
        catch (Exception ex)
        {
            return Html($"تعذّر الربط: {ex.Message}");
        }
    }

    /// <summary>فكّ الارتباط: يُنسى الرمز ويتوقّف الرفع.</summary>
    [HttpPost("google/disconnect")]
    [RequirePermission("backup.manage")]
    public async Task<IActionResult> Disconnect()
    {
        var org = await _db.Organizations.FirstOrDefaultAsync();
        if (org is null) return Forbid();

        org.GoogleRefreshToken = null;
        org.GoogleAccountEmail = null;
        org.GoogleFolderId = null;
        // ويُطفأ التلقائي معه: تركُه مفعَّلاً بلا حساب يعني مفتاحاً مضاءً
        // لا يفعل شيئاً.
        org.AutoBackupEnabled = false;

        _db.LogAudit(org.Id, CurrentUserId(), "backup.google_disconnected", "organizations", org.Id);
        await _db.SaveChangesAsync();
        return NoContent();
    }

    /// <summary>
    /// صفحة نصّية بسيطة لمتصفّح المستخدم — لا JSON.
    ///
    /// <para>العودة من قوقل تقع في المتصفّح لا في التطبيق، ومن يراها إنسانٌ
    /// لا كود. وJSON خامّ في نافذة متصفّح يبدو عطلاً.</para>
    /// </summary>
    ContentResult Html(string message) => Content(
        $"<!doctype html><html lang=ar dir=rtl><meta charset=utf-8>"
        + "<title>ربط Google Drive</title>"
        + "<body style='font-family:system-ui;padding:48px;text-align:center'>"
        + $"<p style='font-size:18px'>{System.Net.WebUtility.HtmlEncode(message)}</p></body></html>",
        // الترميز في الترويسة لا في وسم meta وحده: متصفّحٌ يقرأ الترويسة
        // أوّلاً، وبلا charset تخرج العربية طلاسم قبل أن يصل إلى الوسم.
        "text/html; charset=utf-8");

    /// <summary>
    /// تنزيل النسخة: ملف ZIP فيه مانيفست وملف JSON لكل جدول.
    ///
    /// <para>ZIP لا JSON واحد: ملفٌ واحد بعشرات الميغابايتات لا يفتحه محرّر
    /// نصوص، وتقسيمه بالجداول يجعل استخراج «العملاء» وحدهم ممكناً بلا أداة
    /// خاصة. والضغط يردّ الحجم إلى عُشره تقريباً — والفرق بين 80 و8
    /// ميغابايت هو الفرق بين نسخةٍ تُرفع من هاتف على شبكة ضعيفة ونسخةٍ
    /// تُترك.</para>
    /// </summary>
    [HttpGet("export")]
    [RequirePermission("backup.manage")]
    public async Task<IActionResult> Export()
    {
        var scope = await BranchScopeGuard();
        if (scope is not null) return scope;

        var org = await _db.Organizations
            .Select(o => new { o.Id, o.DisplayName, o.LegalName, o.Edition })
            .FirstOrDefaultAsync();
        if (org is null) return Forbid();

        // التسجيل قبل البثّ: بعد أول بايت لا يمكن تغيير الاستجابة، وتنزيلٌ
        // انقطع في منتصفه يبقى تنزيلاً حدث فعلاً ويجب أن يُرى في السجل.
        _db.LogAudit(org.Id, CurrentUserId(), "backup.exported", "organizations", org.Id,
            newValues: new { At = DateTime.UtcNow, Format = BackupArchive.FormatVersion });
        await _db.SaveChangesAsync();

        var stamp = DateTime.UtcNow.ToString("yyyy-MM-dd-HHmm");
        var asciiName = $"kinetic-backup-{stamp}.zip";
        var fullName = $"kinetic-backup-{Slug(org.DisplayName)}-{stamp}.zip";

        Response.ContentType = "application/zip";
        // بلا طول معلوم: الملف يُبَثّ ولا يُعرف حجمه قبل ضغطه، وادّعاء طولٍ
        // خاطئ يقطع التنزيل عند المتصفّح.
        //
        // واسمان: ترويسات HTTP لاتينية، واسم منظمةٍ عربي فيها يُنتج ترويسة
        // تالفة أو استثناءً عند الإرسال. فالاسم اللاتيني للمتصفّحات القديمة
        // و<c>filename*</c> بترميز RFC 5987 لما يفهمه — وهو ما يصل فعلاً
        // إلى قرص المستخدم في كل متصفّح حديث.
        Response.Headers.ContentDisposition =
            $"attachment; filename=\"{asciiName}\"; filename*=UTF-8''{Uri.EscapeDataString(fullName)}";

        // ZipArchive يكتب على المجرى كتابةً متزامنة، وKestrel يمنعها
        // افتراضياً فيرمي «Synchronous operations are disallowed» بعد أن
        // تكون الترويسات خرجت — أي تنزيلاً ينقطع بلا رسالة. والسماح هنا
        // لهذا الطلب وحده لا للخادم كلّه: نقطةٌ يستدعيها المالك مرّةً في
        // اليوم لا مسارٌ ساخن، والبديل — بناء الملف على القرص ثم إرساله —
        // يشتري إلغاء التزامن بملفٍ مؤقّت بحجم النسخة كاملة.
        var bodyControl = HttpContext.Features.Get<IHttpBodyControlFeature>();
        if (bodyControl is not null) bodyControl.AllowSynchronousIO = true;

        var connection = await OpenConnectionAsync();
        var plan = await BackupArchive.PlanAsync(_db, connection);

        await BackupArchive.WriteAsync(
            connection,
            new BackupOrg(org.Id, org.DisplayName, org.LegalName, org.Edition),
            plan,
            Response.Body);

        return new EmptyResult();
    }

    /// <summary>
    /// اتصال الطلب نفسه — لأن <c>SESSION_CONTEXT</c> مضبوط عليه.
    ///
    /// <para>اتصالٌ جديد يعني سياقاً فارغاً، وسياساتُ العزل حينها إمّا
    /// تُرجع لا شيء أو — والأسوأ — تُرجع كل المنظمات في ملف عميل واحد.
    /// راجع [TenantContextMiddleware].</para>
    /// </summary>
    async Task<DbConnection> OpenConnectionAsync()
    {
        var connection = _db.Database.GetDbConnection();
        if (connection.State != System.Data.ConnectionState.Open) await connection.OpenAsync();
        return connection;
    }

    /// <summary>
    /// حسابٌ محصور بفرع لا يُخرج نسخة.
    ///
    /// <para>سياسات العزل تُرشّح بالفرع أيضاً، فنسخة مالكٍ مربوطٍ بفرعٍ
    /// تخرج ناقصةً بلا أي علامة على نقصها — وأخطر من ألّا تكون عندك نسخة
    /// أن تكون عندك نسخة تظنّها كاملة.</para>
    /// </summary>
    async Task<ActionResult?> BranchScopeGuard()
    {
        await Task.CompletedTask;
        var branchId = User.FindFirstValue("branch_id");
        if (string.IsNullOrWhiteSpace(branchId)) return null;

        return new ObjectResult(new
        {
            message = "هذا الحساب محصور بفرع، والنسخة تخرج ناقصة — استخدم حساب المالك العام",
        })
        { StatusCode = StatusCodes.Status403Forbidden };
    }

    /// <summary>اسم ملف صالح على ويندوز وأندرويد — والعربية تُترك كما هي.</summary>
    static string Slug(string name)
    {
        var cleaned = new string(name.Select(c =>
            char.IsLetterOrDigit(c) || c == '-' || c == '_' ? c : '-').ToArray());
        cleaned = string.Join('-', cleaned.Split('-', StringSplitOptions.RemoveEmptyEntries));
        return string.IsNullOrWhiteSpace(cleaned) ? "org" : cleaned;
    }

    Guid? CurrentUserId()
    {
        var raw = User.FindFirstValue(System.IdentityModel.Tokens.Jwt.JwtRegisteredClaimNames.Sub)
                  ?? User.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(raw, out var id) ? id : null;
    }
}
