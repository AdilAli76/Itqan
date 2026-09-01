﻿using System.IdentityModel.Tokens.Jwt;
using System.Text.Json;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Data.SqlClient;
using KineticEnterprise.Api.Authorization;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Controllers;

public record CreateOrganizationRequest(
    string LegalName, string DisplayName,
    string AdminFullName, string AdminEmail, string AdminPassword,
    string BranchName, string BranchCode,
    string PlanTier, int LicenseMonths,
    /// شكل النظام — standard | wallet | trial | enterprise. انظر [Editions].
    /// فارغ يعني القياسي، فالطلبات القديمة تبقى صالحة.
    string? Edition = null,
    /// شروط العقد المالية — تُحفَظ مع الترخيص وتُطبَع في العقد.
    decimal MonthlyFee = 0,
    decimal StorageFee = 0,
    decimal MaintenanceRate = 0);

public record CreateOrganizationResponse(Guid OrganizationId, Guid BranchId, string LicenseKey, DateTime ExpiresAt);
public record PlatformOrganizationDto(
    Guid Id, string LegalName, string DisplayName, bool IsActive, DateTime CreatedAt,
    string Edition, string PlanTier, DateTime? LicenseExpiresAt, string? LicenseStatus,
    int BranchCount, int UserCount,
    decimal MonthlyFee, decimal StorageFee, decimal MaintenanceRate, DateTime? LicenseIssuedAt,
    /// حجم مرفقات هذا العميل على القرص — الرقم الذي يُسنِد StorageFee.
    long StorageBytes,
    /// وحدات بيعت فوق الإصدار، ووحدات سُحبت منه، والحاصل الفعلي بعدهما.
    ///
    /// <para>الثلاثة معاً لا الفوارق وحدها: شاشةٌ تعرض «مُنح: pharmacy» ولا
    /// تقول ما الذي يعمل عند العميل فعلاً تترك مالك المنصّة يحسب الاتّحاد
    /// والطرح في رأسه — وهو ما يُخطئ فيه.</para>
    List<string> GrantedModules,
    List<string> RevokedModules,
    List<string> EffectiveModules,
    /// حساب المنصّة الذي باع هذه المنظمة — عليه يُرشَّح مالك المنصّة.
    ///
    /// <para>و<c>null</c> = بلا نسبة (منظمة أُنشئت قبل وجود المهندسين).
    /// يراها المالك وحده.</para>
    Guid? OwnerUserId,
    /// اسم البائع ورقم ترخيصه — للعرض، فالمعرّف وحده لا يُقرأ.
    string? OwnerName,
    string? OwnerLicense);

/// <summary>مستخدم في منظمة عميل — كما يراه مالك المنصّة.</summary>
public record OrganizationUserDto(
    Guid Id, string FullName, string Email, string Role,
    bool IsActive, bool IsPlatformAdmin, DateTime CreatedAt, DateTime? LastLoginAt);

public record ResetOrgUserPasswordRequest(
    /// سبب إعادة التعيين — يُحفظ في سجلّ التدقيق.
    string Reason);

/// <summary>كلمة المرور المؤقّتة — تُعرَض مرّةً واحدة ولا تُخزَّن نصّاً.</summary>
public record ResetOrgUserPasswordResponse(string Email, string TemporaryPassword);

public record UpdateOrgUserRequest(string FullName, string Email, bool IsActive);

/// <summary>منظمةٌ يقترب ترخيصها من الانتهاء — أو انتهى.</summary>
public record ExpiringLicenseDto(
    Guid OrganizationId, string DisplayName, DateTime? ExpiresAt, int DaysLeft, string PlanTier);

/// <summary>
/// لوحة مالك المنصّة — حال العملاء كلّهم في شاشة.
///
/// <para><b>الفجوة التي تسدّها:</b> بنود المنصّة كانت مدسوسة في آخر مجموعة
/// «النظام» بجانب الإعدادات، ومالك المنصّة يدخل كأي مدير منظمة فيجد ثلاثة
/// بنودٍ زائدة. فلا يرى حال أعماله كمشغّل: كم عميلاً، وكم اشتراكاً يقترب
/// انتهاؤه، وكم يُحصّل شهرياً، وكم يشغل الجميع من قرص.</para>
///
/// <para><b>ومنظمتُه هو ليست فيها:</b> بذرُ حساب المنصّة يُنشئ منظمةً بلا
/// صفٍّ في <c>platform_organizations</c> — فالفهرس يحمل العملاء وحدهم،
/// وأرقام هذه اللوحة لا تُحسَب فيها أعماله.</para>
/// </summary>
public record PlatformDashboardDto(
    int TotalOrganizations, int ActiveOrganizations, int SuspendedOrganizations,
    int TotalBranches, int TotalUsers,
    /// ما يُحصَّل شهرياً من المنظمات النشطة وحدها — الموقوفة لا تدفع.
    decimal MonthlyRecurring,
    long TotalStorageBytes,
    /// تنتهي خلال ثلاثين يوماً أو انتهت — مرتَّبةً بالأقرب.
    List<ExpiringLicenseDto> ExpiringSoon);

public record ChangeSubscriptionStatusRequest(string Status, string? Reason = null);
public record WarnOrganizationRequest(string Message, string? Title = null);

public record UpdatePlatformOrganizationRequest(
    string LegalName, string DisplayName, bool IsActive,
    /// اختياري — تمديد الترخيص بعدد أشهر من تاريخ انتهائه الحالي.
    int? ExtendMonths = null,
    string? PlanTier = null,
    /// اختياري — نقل العميل إلى إصدار آخر. فوارق الوحدات تبقى فوقه.
    string? Edition = null,
    /// <summary>
    /// الوحدات المطلوب أن تعمل عند العميل بعد الحفظ — **الحاصل لا الفارق**.
    ///
    /// <para>الخادم يشتقّ منها المنح والسحب مقيساً على وحدات الإصدار. وهذا
    /// عمداً: اشتقاقها في الواجهة كان يستلزم نسخة Dart من
    /// [Editions.ModulesOf]، ونسخةٌ ثانية للخريطة تفترق عن الأولى عند أوّل
    /// إصدارٍ يُضاف — فيُخزَّن منحٌ لوحدةٍ يملكها الإصدار أصلاً، أو أسوأ:
    /// سحبٌ لوحدةٍ ظنّت الواجهة أنها ليست فيه.</para>
    ///
    /// <para><c>null</c> = لا تمسّ الفوارق القائمة. وهو التمييز الذي يمنع
    /// شاشةً تُصحّح اسماً من أن تمحو كل وحدة بيعت منفردة.</para>
    /// </summary>
    List<string>? Modules = null);

/// <summary>
/// تزويد عملاء (منظمات) جدد على نفس السيرفر — مقصورة على "مالك المنصة"
/// (أنت، مشغّل النظام) عبر ادّعاء is_platform_admin في التوكن، وليست جزءاً
/// من صلاحيات super_admin العادية لأي عميل، وإلا لاستطاع أي عميل تزويد
/// عملاء آخرين على نفس السيرفر.
///
/// تتجاوز عزل RLS عمداً وبأمان: TenantContextMiddleware يضبط SESSION_CONTEXT
/// كـ read_only=1 على اتصال الطلب العادي (منظمتك أنت)، فلا يمكن الكتابة
/// فوقه لمنظمة جديدة. لذلك نفتح اتصال AppDbContext منفصل تماماً هنا، ونضبط
/// عليه SESSION_CONTEXT بمعرّف المنظمة الجديدة نفسه قبل الإدراج — فتمر
/// العملية عبر BLOCK PREDICATE بشكل طبيعي تماماً كأي منظمة أخرى، لا عبر
/// تعطيل RLS.
/// </summary>
[ApiController]
[Route("api/platform/organizations")]
[Authorize]
public class PlatformController : ControllerBase
{
    private readonly IConfiguration _config;
    private readonly AppDbContext _db;
    private readonly ILogger<PlatformController> _logger;
    public PlatformController(IConfiguration config, AppDbContext db, ILogger<PlatformController> logger)
    {
        _config = config;
        _db = db;
        _logger = logger;
    }

    // فهرس عالمي (لا RLS) — راجع تعليق PlatformOrganizationRecord. أي حساب
    // منصّة يرى كل عملائه معاً، لا عبر تعديل دوال مسند RLS المشتركة.
    [HttpGet]
    public async Task<ActionResult<List<PlatformOrganizationDto>>> GetAll()
    {
        if (User.FindFirstValue("is_platform_admin") != "True")
        {
            return Forbid();
        }

        var orgs = await _db.PlatformOrganizations.OrderByDescending(o => o.CreatedAt).ToListAsync();

        // الترشيح **بعد** القراءة لا في الاستعلام: الفهرس العالمي صغير
        // (صفٌّ لكل عميل)، والشرط في LINQ يحتاج معرّف الطالب مقروءاً من
        // التوكن على أي حال. والوضوح هنا أهمّ من صفّين أقلّ.
        //
        // ومهندسٌ يرى ما باعه وحده: لا شيء في قاعدة البيانات يمنعه — الفهرس
        // غير محميّ بعزل الصفوف عمداً ليراه المالك كلّه. فالمنع هنا، وهو
        // السبب في كون [PlatformScope] نقطةً واحدة لا فحصاً مبعثراً.
        if (!PlatformScope.IsOwner(User))
        {
            orgs = orgs.Where(o => PlatformScope.CanSee(User, o.OwnerUserId)).ToList();
        }

        var ids = orgs.Select(o => o.Id).ToList();

        // أسماء البائعين دفعةً واحدة لا استعلاماً لكل صفّ: مئة عميل يعني
        // مئة رحلة إلى القاعدة في نداءٍ يُفتح مع كل شاشة.
        var sellerIds = orgs.Where(o => o.OwnerUserId != null)
            .Select(o => o.OwnerUserId!.Value).Distinct().ToList();
        var sellers = await _db.AppUsers
            .Where(u => sellerIds.Contains(u.Id))
            .Select(u => new { u.Id, u.FullName, u.ResellerLicense })
            .ToDictionaryAsync(u => u.Id, u => (Name: u.FullName, License: u.ResellerLicense));

        // القراءة عبر SQL خام لا عبر DbSet: جداول المنظمات والفروع
        // والمستخدمين محكومة بسياسة عزل تُرجع منظمة الطالب وحدها، ومالك
        // المنصة يحتاج رؤيتها كلها. وهذا هو سبب وجود الفهرس العالمي أصلاً.
        var details = await ReadOrgDetailsAsync(ids);

        return orgs.Select(o =>
        {
            details.TryGetValue(o.Id, out var d);
            return new PlatformOrganizationDto(
                o.Id, o.LegalName, o.DisplayName, o.IsActive, o.CreatedAt,
                d?.Edition ?? "standard", d?.PlanTier ?? "-",
                d?.ExpiresAt, d?.LicenseStatus, d?.Branches ?? 0, d?.Users ?? 0,
                d?.MonthlyFee ?? 0, d?.StorageFee ?? 0, d?.MaintenanceRate ?? 0, d?.IssuedAt,
                StorageBytesOf(o.Id),
                ModuleList(d?.GrantedModulesJson),
                ModuleList(d?.RevokedModulesJson),
                LicenseLimits.EffectiveModules(
                    d?.Edition ?? Editions.Standard,
                    d?.GrantedModulesJson, d?.RevokedModulesJson).ToList(),
                o.OwnerUserId,
                o.OwnerUserId is null ? null : sellers.GetValueOrDefault(o.OwnerUserId.Value).Name,
                o.OwnerUserId is null ? null : sellers.GetValueOrDefault(o.OwnerUserId.Value).License);
        }).ToList();
    }

    /// <summary>
    /// لوحة مالك المنصّة — الأرقام الإجمالية وما يقترب انتهاؤه.
    ///
    /// <para>تُبنى من نفس قراءة قائمة العملاء لا من استعلامٍ ثانٍ: رقمان
    /// يُحسبان بطريقتين يفترقان أوّل مرّة تتغيّر إحداهما، فيرى مالك المنصّة
    /// «١٢ عميلاً» في اللوحة و«١١» في القائمة ولا يعرف أيّهما الصحيح.</para>
    /// </summary>
    [HttpGet("dashboard")]
    public async Task<ActionResult<PlatformDashboardDto>> Dashboard()
    {
        if (!PlatformScope.IsPlatformUser(User)) return Forbid();

        var orgs = await _db.PlatformOrganizations.ToListAsync();

        // ومهندس البيع يرى **أرقامه هو**: لوحةٌ تقول له «٦٣ مستخدماً» وقائمةٌ
        // تحته بأربعة عملاء تفضح عملاء زملائه بالجمع لا بالاسم — وهو تسريب
        // بالأرقام لا يقلّ عن تسريبٍ بالأسماء.
        if (!PlatformScope.IsOwner(User))
        {
            orgs = orgs.Where(o => PlatformScope.CanSee(User, o.OwnerUserId)).ToList();
        }

        if (orgs.Count == 0)
        {
            return new PlatformDashboardDto(0, 0, 0, 0, 0, 0, 0, new List<ExpiringLicenseDto>());
        }

        var details = await ReadOrgDetailsAsync(orgs.Select(o => o.Id).ToList());
        var today = DateTime.UtcNow.Date;

        var active = orgs.Count(o => o.IsActive);
        var branches = 0;
        var users = 0;
        var monthly = 0m;
        long storage = 0;
        var expiring = new List<ExpiringLicenseDto>();

        foreach (var org in orgs)
        {
            details.TryGetValue(org.Id, out var d);
            branches += d?.Branches ?? 0;
            users += d?.Users ?? 0;
            storage += StorageBytesOf(org.Id);

            // الموقوفة لا تدفع: جمعُها في الإيراد الشهري يُعطي رقماً لا
            // يصل الحساب، ويبني عليه صاحبه قراراً.
            if (org.IsActive) monthly += (d?.MonthlyFee ?? 0) + (d?.StorageFee ?? 0);

            if (d?.ExpiresAt is { } expiresAt)
            {
                var daysLeft = (expiresAt.Date - today).Days;
                if (daysLeft <= 30)
                {
                    expiring.Add(new ExpiringLicenseDto(
                        org.Id, org.DisplayName, expiresAt, daysLeft, d?.PlanTier ?? "-"));
                }
            }
        }

        return new PlatformDashboardDto(
            orgs.Count, active, orgs.Count - active,
            branches, users, monthly, storage,
            expiring.OrderBy(e => e.DaysLeft).ToList());
    }

    /// <summary>
    /// مستخدمو منظمة عميل — أسماؤهم وبُرُدهم وأدوارهم.
    ///
    /// <para><b>الفجوة التي تسدّها:</b> مالك المنصّة يُنشئ المنظمة ومعها
    /// بريد مديرها وكلمة مروره **مرّةً واحدة**، ثم لا يجدهما في أي شاشة
    /// بعدها. فإذا نسي مدير المنظمة بريده، أو أُدخل خطأً، أو طلب إعادة
    /// كلمة مروره — لا سبيل إلى شيء من ذلك إلا بفتح قاعدة البيانات.</para>
    ///
    /// <para>ولا تُعاد بصمة كلمة المرور ولا جزءٌ منها: قائمةٌ تحمل البصمات
    /// تُسرّبها كلّها بتسريبٍ واحد، وBCrypt يُكسَر بالقوّة الغاشمة على
    /// كلمات المرور الضعيفة.</para>
    /// </summary>
    [HttpGet("{id:guid}/users")]
    public async Task<ActionResult<List<OrganizationUserDto>>> GetOrganizationUsers(Guid id)
    {
        if (!PlatformScope.IsPlatformUser(User)) return Forbid();
        if (!await CanTouchAsync(id)) return NotFoundOrForbid();

        await using var db = OpenPlatformContext();
        var conn = db.Database.GetDbConnection();
        await conn.OpenAsync();
        await SetOrgContextAsync(conn, id);

        var users = new List<OrganizationUserDto>();
        try
        {
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = @"
SELECT id, full_name, email, role, is_active, is_platform_admin, created_at, last_login_at
FROM dbo.app_users
ORDER BY is_platform_admin DESC, created_at;";

            await using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                users.Add(new OrganizationUserDto(
                    reader.GetGuid(0),
                    reader.IsDBNull(1) ? "" : reader.GetString(1),
                    reader.IsDBNull(2) ? "" : reader.GetString(2),
                    reader.IsDBNull(3) ? "" : reader.GetString(3),
                    !reader.IsDBNull(4) && reader.GetBoolean(4),
                    !reader.IsDBNull(5) && reader.GetBoolean(5),
                    reader.IsDBNull(6) ? DateTime.MinValue : reader.GetDateTime(6),
                    reader.IsDBNull(7) ? null : reader.GetDateTime(7)));
            }
        }
        finally
        {
            await ClearOrgContextAsync(conn);
        }

        return users;
    }

    /// <summary>
    /// إعادة تعيين كلمة مرور مستخدم في منظمة عميل.
    ///
    /// <para><b>ولماذا كلمة مؤقّتة يولّدها النظام لا كلمة يكتبها مالك
    /// المنصّة:</b> كلمةٌ يختارها هو يعرفها هو، فيستطيع الدخول بحساب العميل
    /// بعدها بلا أثر يميّز دخوله من دخول صاحب الحساب. والمولَّدة تُعرَض
    /// مرّةً وتُسلَّم للعميل ليغيّرها — والفارق أن الدخول بعدها فعلُ من
    /// يملكها لا من أنشأها.</para>
    ///
    /// <para><b>ويُسجَّل في التدقيق دائماً:</b> إعادة تعيين كلمة مرور
    /// عميلٍ حدثٌ يجب أن يُسأل عنه. سجلٌّ بلا هذا الحدث يجعل الوصول إلى
    /// حسابات العملاء غير قابل للمراجعة أصلاً.</para>
    /// </summary>
    [HttpPost("{id:guid}/users/{userId:guid}/reset-password")]
    public async Task<ActionResult<ResetOrgUserPasswordResponse>> ResetOrganizationUserPassword(
        Guid id, Guid userId, ResetOrgUserPasswordRequest request)
    {
        if (!PlatformScope.IsPlatformUser(User)) return Forbid();
        if (!await CanTouchAsync(id)) return NotFoundOrForbid();

        var reason = (request?.Reason ?? "").Trim();
        if (reason.Length == 0) return BadRequest(new { message = "سبب إعادة التعيين إلزامي" });

        var temporary = GenerateTemporaryPassword();
        var hash = BCrypt.Net.BCrypt.HashPassword(temporary);

        await using var db = OpenPlatformContext();
        var conn = db.Database.GetDbConnection();
        await conn.OpenAsync();
        await SetOrgContextAsync(conn, id);

        string? email = null;
        try
        {
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = @"
UPDATE dbo.app_users SET password_hash = @hash
OUTPUT inserted.email
WHERE id = @userId;";
            AddParam(cmd, "@hash", hash);
            AddParam(cmd, "@userId", userId);

            await using var reader = await cmd.ExecuteReaderAsync();
            if (await reader.ReadAsync()) email = reader.IsDBNull(0) ? "" : reader.GetString(0);
        }
        finally
        {
            await ClearOrgContextAsync(conn);
        }

        // صفر صفوف يعني أن المستخدم ليس في هذه المنظمة — وسياسة العزل هي
        // التي منعت، لا شرطٌ في الكود. فالرسالة «غير موجود» صادقة.
        if (email is null) return NotFound(new { message = "المستخدم غير موجود في هذه المنظمة" });

        _db.LogAudit(id, CurrentUserId(), "platform.user_password_reset", "app_users", userId,
            newValues: new { Email = email, Reason = reason });
        await _db.SaveChangesAsync();

        _logger.LogWarning(
            "مالك المنصّة {Admin} أعاد تعيين كلمة مرور {Email} في المنظمة {OrganizationId}. السبب: {Reason}",
            User.FindFirstValue(ClaimTypes.NameIdentifier), email, id, reason);

        return new ResetOrgUserPasswordResponse(email, temporary);
    }

    /// <summary>
    /// تصحيح اسم مستخدم أو بريده، أو إيقافه.
    ///
    /// <para>البريد يُدخَل مرّةً عند الإنشاء، وخطأُ حرفٍ فيه يجعل الحساب
    /// غير قابل للدخول ولا للاسترجاع — فلا بدّ من تصحيحه من هنا.</para>
    /// </summary>
    [HttpPut("{id:guid}/users/{userId:guid}")]
    public async Task<IActionResult> UpdateOrganizationUser(
        Guid id, Guid userId, UpdateOrgUserRequest request)
    {
        if (!PlatformScope.IsPlatformUser(User)) return Forbid();
        if (!await CanTouchAsync(id)) return NotFoundOrForbid();

        var email = (request?.Email ?? "").Trim().ToLowerInvariant();
        var fullName = (request?.FullName ?? "").Trim();
        if (email.Length == 0 || !email.Contains('@'))
            return BadRequest(new { message = "بريد إلكتروني غير صالح" });
        if (fullName.Length == 0)
            return BadRequest(new { message = "الاسم إلزامي" });

        await using var db = OpenPlatformContext();
        var conn = db.Database.GetDbConnection();
        await conn.OpenAsync();
        await SetOrgContextAsync(conn, id);

        int affected;
        try
        {
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = @"
UPDATE dbo.app_users
SET full_name = @name, email = @email, is_active = @active
WHERE id = @userId;";
            AddParam(cmd, "@name", fullName);
            AddParam(cmd, "@email", email);
            AddParam(cmd, "@active", request!.IsActive);
            AddParam(cmd, "@userId", userId);
            affected = await cmd.ExecuteNonQueryAsync();
        }
        catch (Microsoft.Data.SqlClient.SqlException ex) when (ex.Number is 2601 or 2627)
        {
            // البريد فريد على مستوى النشِطين — راجع UQ_app_users_email_active.
            return Conflict(new { message = $"البريد {email} مستعمَل في حساب نشط آخر" });
        }
        finally
        {
            await ClearOrgContextAsync(conn);
        }

        if (affected == 0) return NotFound(new { message = "المستخدم غير موجود في هذه المنظمة" });

        _db.LogAudit(id, CurrentUserId(), "platform.user_updated", "app_users", userId,
            newValues: new { FullName = fullName, Email = email, request.IsActive });
        await _db.SaveChangesAsync();

        return NoContent();
    }

    // ── مشتركات القراءة عبر المنظمات ────────────────────────────────────

    private Guid? CurrentUserId()
    {
        var raw = User.FindFirstValue(JwtRegisteredClaimNames.Sub)
                  ?? User.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(raw, out var id) ? id : null;
    }

    private AppDbContext OpenPlatformContext()
    {
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlServer(_config.GetConnectionString("Default"))
            .UseSnakeCaseNamingConvention()
            .Options;
        return new AppDbContext(options);
    }

    private static async Task SetOrgContextAsync(System.Data.Common.DbConnection conn, Guid id)
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "EXEC sp_set_session_context @key=N'organization_id', @value=@org;";
        AddParam(cmd, "@org", id);
        await cmd.ExecuteNonQueryAsync();
    }

    /// <summary>
    /// يمسح السياق قبل عودة الاتصال إلى المجمّع.
    ///
    /// <para>اتصالٌ يعود بسياق منظمةٍ مضبوط قد يخدم طلباً آخر فيراها —
    /// وهو خرقٌ للعزل لا يظهر في أي اختبار.</para>
    /// </summary>
    private static async Task ClearOrgContextAsync(System.Data.Common.DbConnection conn)
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "EXEC sp_set_session_context @key=N'organization_id', @value=NULL;";
        await cmd.ExecuteNonQueryAsync();
    }

    private static void AddParam(System.Data.Common.DbCommand cmd, string name, object value)
    {
        var p = cmd.CreateParameter();
        p.ParameterName = name;
        p.Value = value;
        cmd.Parameters.Add(p);
    }

    /// <summary>
    /// كلمة مرور مؤقّتة قوية — من مولّد عشوائي تشفيري لا من <c>Random</c>.
    ///
    /// <para><c>Random</c> يُبذَر بالوقت، فكلمتان تُولَّدان في نفس الثانية
    /// قد تتطابقان، ومن يعرف وقت الإنشاء يُضيّق مجال التخمين.</para>
    /// </summary>
    private static string GenerateTemporaryPassword()
    {
        // بلا حروف تلتبس بالأرقام (O/0، l/1، I): الكلمة تُملى هاتفياً
        // للعميل، والالتباس يُنتج محاولات فاشلة تُلام على النظام.
        const string alphabet = "ABCDEFGHJKMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789";
        var bytes = System.Security.Cryptography.RandomNumberGenerator.GetBytes(14);
        return new string(bytes.Select(b => alphabet[b % alphabet.Length]).ToArray());
    }

    /// <summary>
    /// حجم مرفقات منظمة على القرص.
    ///
    /// <para><b>لماذا صار ممكناً الآن:</b> كانت ملفات كل العملاء في مجلد
    /// واحد مسطّح بأسماء عشوائية، فلا سبيل لنسبة بايت إلى صاحبه. وبعد
    /// تقسيمها بمجلد لكل منظمة (راجع FilesController.OrgFolder) صار القياس
    /// جمعاً بسيطاً.</para>
    ///
    /// <para>وهو ليس ترفاً: <c>License.StorageFee</c> رسمٌ شهري يُحاسَب
    /// عليه العميل، وكان يُفرَض بلا أي رقم يُسنده.</para>
    /// </summary>
    private long StorageBytesOf(Guid organizationId)
    {
        var configured = _config["Storage:Path"];
        var root = string.IsNullOrWhiteSpace(configured)
            ? Path.Combine(Directory.GetCurrentDirectory(), "uploads")
            : configured;

        var folder = Path.Combine(root, organizationId.ToString("N"));
        if (!Directory.Exists(folder)) return 0;

        try
        {
            return new DirectoryInfo(folder)
                .EnumerateFiles("*", SearchOption.AllDirectories)
                .Sum(f => f.Length);
        }
        catch (Exception)
        {
            // صفر لا استثناء — شاشة إدارة العملاء لا تسقط لأجل رقم إعلامي.
            //
            // **كان يُمسك IOException وحده، وهي ثغرة حقيقية:**
            // UnauthorizedAccessException لا يرث IOException بل SystemException.
            // ومجلد المرفوعات على IIS مملوك لهوية مجمّع التطبيقات، فمجلّدُ
            // منظمة واحدة بصلاحيات ناقصة كان يُسقط **قائمة الشركات كلّها**
            // بـ500 بجسم فارغ — فتقول الشاشة «تعذّر تحميل الشركات» بلا سبب.
            //
            // والالتقاط عريض عمداً: هذا رقم إعلامي على شاشة إدارية، ولا
            // استثناء منه يستحقّ إسقاط الشاشة.
            return 0;
        }
    }

    private record OrgDetail(string Edition, string PlanTier, DateTime? ExpiresAt, string? LicenseStatus,
        int Branches, int Users, decimal MonthlyFee, decimal StorageFee, decimal MaintenanceRate, DateTime? IssuedAt,
        string? GrantedModulesJson, string? RevokedModulesJson);

    /// <summary>
    /// تفاصيل كل منظمة — إصدارها وترخيصها وعدد فروعها ومستخدميها.
    ///
    /// <para><b>الدوران على المنظمات ليس إسرافاً بل ضرورة:</b> كان هنا
    /// استعلام واحد بـSQL خام، وتعليقٌ يقول إنه يتجاوز سياسة العزل. **وهو
    /// لا يتجاوزها** — عزل الصفوف في SQL Server يُطبَّق على كل استعلام
    /// سواء جاء من EF أو من نصّ خام، والاتصال بلا <c>SESSION_CONTEXT</c>
    /// يعني <c>organization_id = NULL</c> فلا يطابق صفّاً واحداً.</para>
    ///
    /// <para>النتيجة أن الشاشة كانت تعرض كل عميل بإصدار «standard» وترخيص
    /// «-» وصفر فروع وصفر مستخدمين — أرقاماً خاطئة لا فارغة، وهو أسوأ،
    /// لأنها تبدو صحيحة.</para>
    ///
    /// <para>والعدد هنا عدد **عملائك** لا عدد صفوف بيانات: عشرات لا آلاف،
    /// فاستعلام لكل واحد مقبول تماماً — والبديل (استثناء مالك المنصّة داخل
    /// دوال المسند المشتركة) يمسّ حماية كل الجداول لأجل شاشة واحدة.</para>
    /// </summary>
    private async Task<Dictionary<Guid, OrgDetail>> ReadOrgDetailsAsync(List<Guid> ids)
    {
        var result = new Dictionary<Guid, OrgDetail>();
        if (ids.Count == 0) return result;

        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlServer(_config.GetConnectionString("Default"))
            .UseSnakeCaseNamingConvention()
            .Options;
        await using var db = new AppDbContext(options);
        var conn = db.Database.GetDbConnection();
        await conn.OpenAsync();

        foreach (var id in ids)
        {
            await using (var ctx = conn.CreateCommand())
            {
                ctx.CommandText = "EXEC sp_set_session_context @key=N'organization_id', @value=@org;";
                var p = ctx.CreateParameter();
                p.ParameterName = "@org";
                p.Value = id;
                ctx.Parameters.Add(p);
                await ctx.ExecuteNonQueryAsync();
            }

            await using var cmd = conn.CreateCommand();
            cmd.CommandText = @"
SELECT o.edition,
       ISNULL(l.plan_tier, '-')  AS plan_tier,
       l.expires_at, l.status,
       ISNULL(l.monthly_fee, 0), ISNULL(l.storage_fee, 0), ISNULL(l.maintenance_rate, 0), l.issued_at,
       (SELECT COUNT(*) FROM dbo.branches  b WHERE b.organization_id = o.id) AS branches,
       (SELECT COUNT(*) FROM dbo.app_users u WHERE u.organization_id = o.id AND u.is_active = 1) AS users,
       l.granted_modules, l.revoked_modules
FROM dbo.organizations o
LEFT JOIN dbo.licenses l ON l.organization_id = o.id;";

            // منظمةٌ تفشل قراءتها لا تُسقط القائمة كلّها: تُعرَض بقيمها
            // الافتراضية ويُسجَّل سببها. صفٌّ واحد تالف كان يحجب كل العملاء.
            try
            {
                await using var reader = await cmd.ExecuteReaderAsync();
                if (await reader.ReadAsync())
                {
                    result[id] = new OrgDetail(
                        // GetString على عمود NULL يرمي InvalidCastException.
                        // وedition عمود أُضيف لاحقاً بترحيل — فمنظمة أُنشئت
                        // قبله على قاعدة لم تُرحَّل بعدُ تحمل NULL.
                        reader.IsDBNull(0) ? "standard" : reader.GetString(0),
                        reader.IsDBNull(1) ? "-" : reader.GetString(1),
                        reader.IsDBNull(2) ? null : reader.GetDateTime(2),
                        reader.IsDBNull(3) ? null : reader.GetString(3),
                        reader.IsDBNull(8) ? 0 : reader.GetInt32(8),
                        reader.IsDBNull(9) ? 0 : reader.GetInt32(9),
                        reader.IsDBNull(4) ? 0 : reader.GetDecimal(4),
                        reader.IsDBNull(5) ? 0 : reader.GetDecimal(5),
                        reader.IsDBNull(6) ? 0 : reader.GetDecimal(6),
                        reader.IsDBNull(7) ? null : reader.GetDateTime(7),
                        reader.IsDBNull(10) ? null : reader.GetString(10),
                        reader.IsDBNull(11) ? null : reader.GetString(11));
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "تعذّرت قراءة تفاصيل المنظمة {OrganizationId}", id);
            }
        }

        // السياق يُمسح قبل ترك الاتصال: يعود إلى المجمّع، ومهما فعل
        // sp_reset_connection فالاعتماد عليه رهانٌ لا داعي له حين يكفي سطر.
        await using (var clear = conn.CreateCommand())
        {
            clear.CommandText = "EXEC sp_set_session_context @key=N'organization_id', @value=NULL;";
            await clear.ExecuteNonQueryAsync();
        }

        return result;
    }

    /// <summary>
    /// تعديل بيانات منظمة عميل — الاسم القانوني والمعروض، وتفعيلها أو
    /// إيقافها، وتمديد ترخيصها.
    ///
    /// يمرّ عبر سياق مضبوط على معرّف المنظمة المستهدَفة لا على منظمة مالك
    /// المنصة: سياسة العزل تحجب صف أي منظمة أخرى، فبلا ضبط السياق يُحدَّث
    /// صفر صفوف ويبدو الأمر ناجحاً بلا أثر.
    /// </summary>
    [HttpPut("{id:guid}")]
    public async Task<IActionResult> Update(Guid id, UpdatePlatformOrganizationRequest request)
    {
        if (!PlatformScope.IsPlatformUser(User)) return Forbid();
        if (!await CanTouchAsync(id)) return NotFoundOrForbid();
        if (string.IsNullOrWhiteSpace(request.LegalName) || string.IsNullOrWhiteSpace(request.DisplayName))
        {
            return BadRequest(new { message = "الاسم القانوني والاسم المعروض إلزاميان" });
        }
        if (request.PlanTier is not null && !ValidTiers.Contains(request.PlanTier))
        {
            return BadRequest(new { message = "باقة ترخيص غير معروفة" });
        }
        if (request.Edition is not null && !Editions.All.Contains(request.Edition))
        {
            return BadRequest(new { message = "إصدار غير معروف" });
        }
        // اسمٌ مجهول يُرفض ولا يُنقّى صامتاً هنا: مالك المنصّة يختار من قائمة
        // معروضة، فاسمٌ خارجها يعني خللاً في الواجهة لا خطأ إملائياً — وقبوله
        // بصمتٍ يترك زرّاً يُضغط ولا يفعل شيئاً.
        var unknown = (request.Modules ?? new List<string>())
            .Where(m => !Editions.AllModules.Contains(m))
            .Distinct()
            .ToList();
        if (unknown.Count > 0)
        {
            return BadRequest(new { message = $"وحدات غير معروفة: {string.Join("، ", unknown)}" });
        }

        var index = await _db.PlatformOrganizations.FirstOrDefaultAsync(o => o.Id == id);
        if (index is null) return NotFound();

        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlServer(_config.GetConnectionString("Default"))
            .UseSnakeCaseNamingConvention()
            .Options;
        await using var db = new AppDbContext(options);
        var conn = db.Database.GetDbConnection();
        await conn.OpenAsync();
        await using (var ctx = conn.CreateCommand())
        {
            ctx.CommandText = "EXEC sp_set_session_context @key=N'organization_id', @value=@orgId;";
            ctx.Parameters.Add(new SqlParameter("@orgId", id));
            await ctx.ExecuteNonQueryAsync();
        }

        var org = await db.Organizations.FirstOrDefaultAsync(o => o.Id == id);
        if (org is null) return NotFound();

        org.LegalName = request.LegalName;
        org.DisplayName = request.DisplayName;
        if (request.Edition is not null)
        {
            org.Edition = request.Edition;
            // البيع بالقيمة الحرّة يتبع **شكل** الإصدار لا وحداته: نقل عميل
            // إلى إصدار المحفظة بلا ضبطها يترك نقطة بيع تطلب صنفاً من كتالوج
            // لا وجود له. نفس ما يفعله [Create] عند الإنشاء.
            org.PosAllowOpenProduct = Editions.AllowsOpenProduct(request.Edition);
        }

        var license = await db.Licenses.FirstOrDefaultAsync(l => l.OrganizationId == id);
        if (license is not null)
        {
            if (request.PlanTier is not null)
            {
                var (maxBranches, maxUsers) = LimitsFor(request.PlanTier);
                license.PlanTier = request.PlanTier;
                license.MaxBranches = maxBranches;
                license.MaxUsers = maxUsers;
            }

            // الفوارق تُشتقّ من الحاصل المطلوب مقيساً على **الإصدار بعد
            // تعديله** لا قبله: من رفع عميلاً إلى إصدار المؤسسات وأبقى
            // المحاسبة مؤشَّرة لا يُقصد أنه اشتراها منفردة — هي في إصداره
            // الجديد أصلاً، وتخزينها منحاً يترك أثراً كاذباً في العقد.
            if (request.Modules is not null)
            {
                var wanted = LicenseLimits.SanitizeModules(request.Modules);
                var ofEdition = Editions.ModulesOf(org.Edition);

                license.GrantedModulesJson = JsonSerializer.Serialize(
                    wanted.Where(m => !ofEdition.Contains(m)).ToArray());
                license.RevokedModulesJson = JsonSerializer.Serialize(
                    ofEdition.Where(m => !wanted.Contains(m)).ToArray());
            }

            // والقائمة المعروضة تُشتقّ بعدها لا قبلها — راجع
            // [LicenseLimits.MaterializeModules]. وتُستدعى حتى حين لا تُرسَل
            // وحدات: تغيير الإصدار وحده يغيّر الحاصل.
            LicenseLimits.MaterializeModules(license, org.Edition);
            if (request.ExtendMonths is > 0)
            {
                // التمديد من الأبعد بين اليوم وتاريخ الانتهاء: تمديد ترخيص
                // منتهٍ منذ شهرين من تاريخه القديم كان يمنح شهراً مضى.
                var from = license.ExpiresAt > DateTime.UtcNow ? license.ExpiresAt : DateTime.UtcNow;
                license.ExpiresAt = from.AddMonths(request.ExtendMonths.Value);
                license.Status = "active";
            }
        }

        // الفهرس العالمي يُحدَّث معه — هو ما يقرؤه مالك المنصة، وتركه
        // متخلّفاً يعني قائمة تعرض اسماً غير الاسم الحقيقي.
        index.LegalName = request.LegalName;
        index.DisplayName = request.DisplayName;
        index.IsActive = request.IsActive;

        await db.SaveChangesAsync();
        await _db.SaveChangesAsync();

        return NoContent();
    }

    /// <summary>
    /// أيملك الطالبُ حقَّ العمل على هذه المنظمة؟
    ///
    /// <para>المالك على الكلّ، والمهندس على ما باعه. راجع
    /// [PlatformScope].</para>
    /// </summary>
    private async Task<bool> CanTouchAsync(Guid organizationId)
    {
        if (PlatformScope.IsOwner(User)) return true;

        var owner = await _db.PlatformOrganizations
            .Where(o => o.Id == organizationId)
            .Select(o => o.OwnerUserId)
            .FirstOrDefaultAsync();

        return PlatformScope.CanSee(User, owner);
    }

    /// <summary>
    /// ردٌّ واحد لـ«ليست لك» و«غير موجودة».
    ///
    /// <para><b>ولماذا 404 لا 403:</b> 403 على معرّفٍ بعينه يقول «هذه
    /// المنظمة موجودة ولكنها ليست لك» — فيستطيع مهندسٌ أن يستدلّ بها على
    /// عملاء زملائه واحداً واحداً. و404 لا يفرّق بين ما لا يخصّه وما لا
    /// وجود له، وهو كل ما يحتاج أن يعرفه.</para>
    /// </summary>
    private ActionResult NotFoundOrForbid() =>
        NotFound(new { message = "لا توجد منظمة بهذا المعرّف ضمن عملائك" });

    /// <summary>
    /// قائمة وحدات من نصّ JSON للعرض — التالف يُقرأ فارغاً.
    ///
    /// <para>لا تُستعمل للفرض: الفرض كلّه في
    /// [LicenseLimits.EffectiveModules] وحده.</para>
    /// </summary>
    private static List<string> ModuleList(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return new List<string>();
        try { return JsonSerializer.Deserialize<List<string>>(json) ?? new List<string>(); }
        catch (JsonException) { return new List<string>(); }
    }

    private static readonly string[] ValidTiers = { "trial", "standard", "professional", "enterprise" };

    private static (int MaxBranches, int MaxUsers) LimitsFor(string tier) => tier switch
    {
        "trial" => (1, 3),
        "standard" => (3, 10),
        "professional" => (10, 50),
        "enterprise" => (999, 999),
        _ => (1, 5),
    };

    // نفس الصلاحيات الافتراضية لكل منظمة جديدة، مطابقة تماماً لما كان
    // مبرمجاً مباشرة في كل Controller قبل بناء مصفوفة الصلاحيات — راجع
    // RequirePermissionAttribute.cs. المالك يستطيع تخصيصها لاحقاً من شاشة
    // "مصفوفة الصلاحيات" دون أي تدخل من طرفك.
    private static readonly (string Role, string Code)[] DefaultRolePermissions =
    {
        ("branch_manager", "inventory.manage"), ("branch_manager", "inventory.delete"),
        ("branch_manager", "categories.manage"), ("branch_manager", "suppliers.manage"),
        ("branch_manager", "suppliers.delete"), ("branch_manager", "stock_transfer.manage"),
        ("branch_manager", "stock_count.manage"), ("branch_manager", "customers.manage"),
        ("branch_manager", "customers.wallet_adjust"), ("branch_manager", "customers.delete"),
        ("branch_manager", "invoices.refund"), ("branch_manager", "reports.view"),
        ("branch_manager", "audit_log.view"), ("branch_manager", "license.view"),
        ("inventory_officer", "inventory.manage"), ("inventory_officer", "categories.manage"),
        ("inventory_officer", "suppliers.manage"), ("inventory_officer", "stock_transfer.manage"),
        ("inventory_officer", "stock_count.manage"), ("inventory_officer", "purchasing.manage"),
        ("branch_manager", "purchasing.manage"),
        // إصدار البطاقات وضبط أرقامها السرية: مدير الفرع فما فوق فقط.
        ("branch_manager", "cards.issue"),

        // الكاشير: بيع وتعديل بيانات العملاء — لا أكثر.
        //
        // سُحبت منه customers.wallet_adjust و(ضمناً) إصدار البطاقات، لأن
        // اجتماعهما كان يفتح باب خلق نقود: إنشاء عميل وهمي ← إصدار بطاقة له
        // ← شحنها بمبلغ لم يدخل الصندوق ← ضبط رقمها السري ← إنفاقها على
        // بضاعة حقيقية. المخزون ينقص والإيراد لا يزيد، ولا يكشفه إلا جرد.
        //
        // البيع من محفظة العميل لا يتأثر: حركة الخصم تُكتب داخل
        // InvoicesController بعد التحقق من الرقم السري، لا عبر نقطة
        // wallet-adjustments المحروسة بهذه الصلاحية.
        //
        // ⚠ **والاسترجاع سُحب منه**: كان يُمنح افتراضاً، فكل من يبيع يستطيع
        // أن يُرجِع. والإرجاع نقدٌ يخرج من الدرج بلا بيع — أخطر ما يفعله
        // كاشير، ولا يُكتشف إلا بجرد أو بمراجعة سجلّ.
        //
        // ولا يُمنَع منعاً باتّاً: مدير المنظمة يمنحه لمن يشاء من شاشة
        // «الصلاحيات والمستخدمون» — كاشيراً كان أو محاسباً. الفرق أن
        // منحه **قرارٌ يُتخذ** لا حالةٌ يُولَد عليها كل حساب.
        ("cashier", "customers.manage"),
    };

    /// <summary>
    /// تغيير حالة اشتراك عميل: تجميد، أو إنهاء خدمة، أو استئناف.
    ///
    /// <para><b>التجميد قراءة فقط لا قطع:</b> حجب دفاتر عميل متأخّر عنه —
    /// فواتيره وأرصدة عملائه — لا يضغط عليه للدفع بل يدفعه إلى إنكار الخدمة،
    /// ويضعنا في موقف من يحتجز بيانات لا من يطالب بحقّ. راجع
    /// [LicenseGateAttribute].</para>
    ///
    /// <para>والسبب إلزامي: «قراءة فقط» بلا سبب تجعل العميل يتّصل ليسأل عمّا
    /// نعرفه سلفاً، وتترك سجلّاً لا يُفهم بعد سنة.</para>
    /// </summary>
    [HttpPost("{id:guid}/status")]
    public async Task<IActionResult> ChangeStatus(Guid id, ChangeSubscriptionStatusRequest request)
    {
        if (!PlatformScope.IsPlatformUser(User)) return Forbid();
        if (!await CanTouchAsync(id)) return NotFoundOrForbid();

        var allowed = new[] { "active", "grace_period", "expired", "revoked" };
        if (!allowed.Contains(request.Status))
        {
            return BadRequest(new { message = "حالة اشتراك غير معروفة" });
        }
        if (request.Status != "active" && string.IsNullOrWhiteSpace(request.Reason))
        {
            return BadRequest(new { message = "السبب إلزامي عند التجميد أو الإنهاء" });
        }

        await using var db = await ScopedDbAsync(id);
        var license = await db.Licenses.FirstOrDefaultAsync(l => l.OrganizationId == id);
        if (license is null) return NotFound(new { message = "لا ترخيص لهذه المنظمة" });

        license.Status = request.Status;
        license.StatusReason = string.IsNullOrWhiteSpace(request.Reason) ? null : request.Reason.Trim();
        license.StatusChangedAt = DateTime.UtcNow;
        // active وحدها ترفع القراءة فقط: كل ما عداها تجميد بدرجة ما.
        license.IsReadOnly = request.Status != "active";

        // إشعار في غرفة إشعارات العميل: التغيير الذي لا يراه العميل إلا حين
        // يصطدم برفض عملية هو أسوأ طريقة لإبلاغه.
        db.Notifications.Add(new NotificationItem
        {
            OrganizationId = id,
            Type = "license",
            Title = request.Status == "active"
                ? "استُؤنفت الخدمة"
                : request.Status == "revoked" ? "أُنهيت خدمة الاشتراك" : "الحساب في وضع القراءة فقط",
            Body = license.StatusReason ?? "تواصل مع الدعم لمزيد من التفاصيل.",
        });

        await db.SaveChangesAsync();
        return NoContent();
    }

    /// <summary>
    /// تحذير يظهر في غرفة إشعارات العميل — بلا أي أثر على عمله.
    ///
    /// <para>خطوة تسبق التجميد: عميلٌ يُجمَّد بلا إنذار سابق يشعر بالغدر
    /// مهما كان محقّاً عليه الدَّين. والتحذير المكتوب يبقى سجلّاً لمن راجعه
    /// لاحقاً.</para>
    /// </summary>
    [HttpPost("{id:guid}/warn")]
    public async Task<IActionResult> Warn(Guid id, WarnOrganizationRequest request)
    {
        if (!PlatformScope.IsPlatformUser(User)) return Forbid();
        if (!await CanTouchAsync(id)) return NotFoundOrForbid();
        if (string.IsNullOrWhiteSpace(request.Message))
        {
            return BadRequest(new { message = "نصّ التحذير إلزامي" });
        }

        await using var db = await ScopedDbAsync(id);
        db.Notifications.Add(new NotificationItem
        {
            OrganizationId = id,
            Type = "license",
            Title = string.IsNullOrWhiteSpace(request.Title) ? "تنبيه من إدارة النظام" : request.Title!.Trim(),
            Body = request.Message.Trim(),
        });
        await db.SaveChangesAsync();
        return NoContent();
    }

    /// <summary>
    /// حذف منظمة نهائياً — هي وكل بياناتها.
    ///
    /// <para><b>يُطلَب الاسم القانوني كاملاً للتأكيد</b>: زرّ حذف بنافذة
    /// «هل أنت متأكد» يُضغط بلا قراءة، وكتابة الاسم تُجبر على النظر إلى
    /// **أيّ** عميل يُحذف. وهذا العمل لا رجعة فيه إلا من نسخة احتياطية.</para>
    ///
    /// <para>والمرفقات تُحذف معها: تركُها يترك ملفات عميل انتهى عقده على
    /// قرصنا بلا سجلّ يشير إليها — وهو ما يجعل مجلد كل منظمة على حدة
    /// (راجع FilesController) شرطاً لهذه العملية أصلاً.</para>
    /// </summary>
    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id, [FromQuery] string confirm)
    {
        // مالك المنصّة وحده — قرارُك أنت لا قرار المهندس.
        //
        // الحذف بلا رجعة: يمحو فواتير العميل وقيوده ومرفقاته وحسابات
        // مستخدميه. ومهندسٌ يخسر عميلاً قد يمحوه غضباً أو خطأً، والإيقاف
        // يكفيه لمنع الدخول ويُبقي ما يُسترجَع.
        if (!PlatformScope.IsOwner(User)) return Forbid();

        var index = await _db.PlatformOrganizations.FirstOrDefaultAsync(o => o.Id == id);
        if (index is null) return NotFound();

        if (!string.Equals(confirm?.Trim(), index.LegalName, StringComparison.Ordinal))
        {
            return BadRequest(new
            {
                message = $"للتأكيد اكتب الاسم القانوني للشركة حرفياً: «{index.LegalName}»"
            });
        }

        await using (var db = await ScopedDbAsync(id))
        {
            var org = await db.Organizations.FirstOrDefaultAsync(o => o.Id == id);
            // الحذف بالتتالي على مستوى قاعدة البيانات: كل جدول تشغيلي يحمل
            // organization_id بـ ON DELETE CASCADE (راجع المخطّط)، فحذف الصف
            // الأمّ يكفي — والحذف يدوياً جدولاً جدولاً ينسى واحداً حتماً.
            if (org is not null)
            {
                db.Organizations.Remove(org);
                await db.SaveChangesAsync();
            }
        }

        _db.PlatformOrganizations.Remove(index);
        await _db.SaveChangesAsync();

        // الملفات بعد نجاح حذف الصفوف لا قبله: فشل الحذف في القاعدة مع
        // ملفات ممحوّة يترك مرفقات لا تُفتح.
        var configured = _config["Storage:Path"];
        var root = string.IsNullOrWhiteSpace(configured)
            ? Path.Combine(Directory.GetCurrentDirectory(), "uploads")
            : configured;
        var folder = Path.Combine(root, id.ToString("N"));
        if (Directory.Exists(folder))
        {
            try { Directory.Delete(folder, recursive: true); }
            catch (IOException) { /* مقفول — يُنظَّف يدوياً */ }
        }

        return NoContent();
    }

    /// <summary>سياق قاعدة بيانات مضبوط على منظمة بعينها — راجع Update.</summary>
    private async Task<AppDbContext> ScopedDbAsync(Guid organizationId)
    {
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlServer(_config.GetConnectionString("Default"))
            .UseSnakeCaseNamingConvention()
            .Options;
        var db = new AppDbContext(options);
        var conn = db.Database.GetDbConnection();
        await conn.OpenAsync();
        await using var ctx = conn.CreateCommand();
        ctx.CommandText = "EXEC sp_set_session_context @key=N'organization_id', @value=@orgId;";
        ctx.Parameters.Add(new SqlParameter("@orgId", organizationId));
        await ctx.ExecuteNonQueryAsync();
        return db;
    }

    [HttpPost]
    public async Task<ActionResult<CreateOrganizationResponse>> Create(CreateOrganizationRequest request)
    {
        if (!PlatformScope.IsPlatformUser(User))
        {
            return Forbid();
        }

        if (string.IsNullOrWhiteSpace(request.LegalName) || string.IsNullOrWhiteSpace(request.DisplayName)
            || string.IsNullOrWhiteSpace(request.AdminFullName) || string.IsNullOrWhiteSpace(request.AdminEmail)
            || string.IsNullOrWhiteSpace(request.BranchName) || string.IsNullOrWhiteSpace(request.BranchCode))
        {
            return BadRequest(new { message = "الرجاء تعبئة كل الحقول الإلزامية" });
        }
        if (request.AdminPassword.Length < 8)
        {
            return BadRequest(new { message = "كلمة مرور المدير العام يجب أن تكون 8 أحرف على الأقل" });
        }
        if (!ValidTiers.Contains(request.PlanTier))
        {
            return BadRequest(new { message = "باقة ترخيص غير معروفة" });
        }
        var edition = string.IsNullOrWhiteSpace(request.Edition) ? Editions.Standard : request.Edition!;
        if (!Editions.All.Contains(edition))
        {
            return BadRequest(new { message = "إصدار غير معروف" });
        }

        // من هنا جاء التكرار الذي وُجد على قاعدة التطوير: إنشاء منظمة جديدة
        // بنفس بريد مدير منظمة قائمة. تسجيل الدخول يبحث بالبريد بلا منظمة،
        // فيصبح الدخول بهذا البريد غير محدَّد النتيجة بين المنظمتين.
        var adminEmail = request.AdminEmail.Trim();
        if (await _db.AppUsers.AnyAsync(u => u.IsActive && u.Email == adminEmail))
        {
            return Conflict(new { message = "بريد المدير العام مستخدَم بالفعل على حساب نشط في منظمة أخرى — استخدم بريداً مختلفاً" });
        }

        var orgId = Guid.NewGuid();
        var branchId = Guid.NewGuid();
        var (maxBranches, maxUsers) = LimitsFor(request.PlanTier);
        var licenseKey = $"KIN-{Guid.NewGuid().ToString("N")[..8].ToUpperInvariant()}-{Guid.NewGuid().ToString("N")[..8].ToUpperInvariant()}";
        var expiresAt = DateTime.UtcNow.AddMonths(request.LicenseMonths <= 0 ? 12 : request.LicenseMonths);

        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlServer(_config.GetConnectionString("Default"))
            .UseSnakeCaseNamingConvention()
            .Options;

        await using var db = new AppDbContext(options);
        var connection = db.Database.GetDbConnection();
        await connection.OpenAsync();
        await using (var cmd = connection.CreateCommand())
        {
            cmd.CommandText = "EXEC sp_set_session_context @key=N'organization_id', @value=@orgId;";
            cmd.Parameters.Add(new SqlParameter("@orgId", orgId));
            await cmd.ExecuteNonQueryAsync();
        }

        // منظمات/فروع/تراخيص/مستخدمون بلا Navigation properties بين بعضها في
        // AppDbContext (كل جدول مستقل من منظور EF) — فـ EF Core لا "يعرف"
        // ترتيب الاعتماد بينها ويُدرجها بترتيب داخلي عشوائي عند حفظها معاً
        // في SaveChangesAsync واحدة، ما كان يُدرج الفرع/الترخيص/المستخدم
        // قبل صف المنظمة نفسه فترفضه قيود FOREIGN KEY. لذلك: صف المنظمة أولاً
        // في SaveChangesAsync منفصلة داخل معاملة صريحة، ثم البقية معاً.
        await using var transaction = await db.Database.BeginTransactionAsync();
        try
        {
            db.Organizations.Add(new Organization
            {
                Id = orgId,
                LegalName = request.LegalName,
                DisplayName = request.DisplayName,
                Edition = edition,
                // إصدار المحفظة يبيع بالقيمة الحرّة حصراً — لا كتالوج يُختار
                // منه. ضبطها هنا لا يدوياً بعد الإنشاء: منظمة تُسلَّم للعميل
                // بإعداد ناقص تعني نقطة بيع لا تعمل من أول يوم.
                PosAllowOpenProduct = Editions.AllowsOpenProduct(edition),
            });
            await db.SaveChangesAsync();

            db.Branches.Add(new Branch
            {
                Id = branchId,
                OrganizationId = orgId,
                Name = request.BranchName,
                Code = request.BranchCode,
            });
            db.Licenses.Add(new License
            {
                OrganizationId = orgId,
                LicenseKey = licenseKey,
                PlanTier = request.PlanTier,
                // من [Editions] لا بيد: الفوارق تبدأ فارغة عند الإنشاء،
                // فالقائمة هنا هي وحدات الإصدار عينها — وتُعاد اشتقاقها من
                // [LicenseLimits.MaterializeModules] عند أول تعديل.
                EnabledModulesJson = JsonSerializer.Serialize(Editions.ModulesOf(edition)),
                MonthlyFee = request.MonthlyFee,
                StorageFee = request.StorageFee,
                MaintenanceRate = request.MaintenanceRate,
                MaxBranches = maxBranches,
                MaxUsers = maxUsers,
                ExpiresAt = expiresAt,
                Status = "active",
                // إصدار التجربة يُنشأ للقراءة فقط: نسخة تُعرَض ويُتجوَّل في
                // بياناتها بلا أن يعبث بها زائر — وهو المطلوب من نسخة عرض.
                //
                // وهو **قابل للرفع** من شاشة إدارة العملاء متى أُريدت تجربة
                // حقيقية يُدخِل فيها العميل بياناته: الصفة على العقد لا على
                // شكل المنتج، فتخدم الحالتين بلا كود ثانٍ.
                IsReadOnly = edition == Editions.Trial,
                StatusReason = edition == Editions.Trial ? "نسخة للعرض — تُقرأ ولا تُعدَّل" : null,
            });
            db.AppUsers.Add(new AppUser
            {
                OrganizationId = orgId,
                BranchId = null,
                FullName = request.AdminFullName,
                Email = adminEmail,
                PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.AdminPassword),
                Role = "super_admin",
                IsActive = true,
            });
            // إصدار المحفظة يحتاج صنفاً واحداً مخفياً.
            //
            // البيع بقيمة حرّة في هذا النظام يمرّ على صفّ صنف حقيقي
            // (TracksStock = false) — وهو ما يجعل الفاتورة وسطرها والتقارير
            // تعمل بلا استثناءات في المسار كله. وكتالوج منظمة المحفظة فارغ
            // بالتعريف، فبلا هذا الصنف تفتح نقطة البيع ولا تبيع شيئاً.
            //
            // يُزرع هنا لا يُطلَب من العميل إنشاؤه: شاشات المخزون مخفية عنه
            // أصلاً في هذا الإصدار، فلا سبيل له إليه.
            if (Editions.IsWalletShaped(edition))
            {
                db.Products.Add(new Product
                {
                    OrganizationId = orgId,
                    Sku = "WALLET-VALUE",
                    Name = "قيمة",
                    UnitBase = "unit",
                    TracksStock = false,
                    SalePrice = 0,
                    CostPrice = 0,
                });
            }

            foreach (var (role, code) in DefaultRolePermissions)
            {
                db.RolePermissions.Add(new RolePermission { OrganizationId = orgId, Role = role, PermissionCode = code });
            }
            await db.SaveChangesAsync();

            await transaction.CommitAsync();
        }
        catch (DbUpdateException)
        {
            await transaction.RollbackAsync();
            return Conflict(new { message = "تعذّر إنشاء المنظمة — تحقق من عدم تكرار البريد الإلكتروني أو رمز الفرع" });
        }

        // عبر الاتصال العادي (_db المُحقَن) — لا Security Policy على هذا
        // الجدول إطلاقاً فلا داعٍ للاتصال الخاص المستخدَم أعلاه.
        _db.PlatformOrganizations.Add(new PlatformOrganizationRecord
        {
            Id = orgId,
            LegalName = request.LegalName,
            DisplayName = request.DisplayName,
            IsActive = true,
            // من أنشأها يملكها — ولا يُؤخذ من الطلب.
            //
            // حقلٌ في الجسم كان يجعل مهندساً ينسب عميلاً لمهندسٍ آخر بتعديل
            // نداء، وهو **أخطر** من رؤية عميلٍ ليس له: النسبة هي ما يُبنى
            // عليه العزل كلّه. وإعادة النسبة قرار المالك وحده من نقطته.
            OwnerUserId = PlatformScope.UserId(User),
        });
        await _db.SaveChangesAsync();

        return StatusCode(201, new CreateOrganizationResponse(orgId, branchId, licenseKey, expiresAt));
    }
}
