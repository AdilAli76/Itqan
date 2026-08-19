using System.Text.Json;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Data.SqlClient;
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
    decimal MonthlyFee, decimal StorageFee, decimal MaintenanceRate, DateTime? LicenseIssuedAt);

public record UpdatePlatformOrganizationRequest(
    string LegalName, string DisplayName, bool IsActive,
    /// اختياري — تمديد الترخيص بعدد أشهر من تاريخ انتهائه الحالي.
    int? ExtendMonths = null,
    string? PlanTier = null);

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
    public PlatformController(IConfiguration config, AppDbContext db)
    {
        _config = config;
        _db = db;
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
        var ids = orgs.Select(o => o.Id).ToList();

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
                d?.MonthlyFee ?? 0, d?.StorageFee ?? 0, d?.MaintenanceRate ?? 0, d?.IssuedAt);
        }).ToList();
    }

    private record OrgDetail(string Edition, string PlanTier, DateTime? ExpiresAt, string? LicenseStatus,
        int Branches, int Users, decimal MonthlyFee, decimal StorageFee, decimal MaintenanceRate, DateTime? IssuedAt);

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

        await using var cmd = conn.CreateCommand();
        cmd.CommandText = @"
SELECT o.id, o.edition,
       ISNULL(l.plan_tier, '-')  AS plan_tier,
       l.expires_at, l.status,
       ISNULL(l.monthly_fee, 0), ISNULL(l.storage_fee, 0), ISNULL(l.maintenance_rate, 0), l.issued_at,
       (SELECT COUNT(*) FROM dbo.branches  b WHERE b.organization_id = o.id) AS branches,
       (SELECT COUNT(*) FROM dbo.app_users u WHERE u.organization_id = o.id AND u.is_active = 1) AS users
FROM dbo.organizations o
LEFT JOIN dbo.licenses l ON l.organization_id = o.id;";

        await using var reader = await cmd.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            result[reader.GetGuid(0)] = new OrgDetail(
                reader.GetString(1),
                reader.GetString(2),
                reader.IsDBNull(3) ? null : reader.GetDateTime(3),
                reader.IsDBNull(4) ? null : reader.GetString(4),
                reader.GetInt32(9),
                reader.GetInt32(10),
                reader.GetDecimal(5),
                reader.GetDecimal(6),
                reader.GetDecimal(7),
                reader.IsDBNull(8) ? null : reader.GetDateTime(8));
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
        if (User.FindFirstValue("is_platform_admin") != "True")
        {
            return Forbid();
        }
        if (string.IsNullOrWhiteSpace(request.LegalName) || string.IsNullOrWhiteSpace(request.DisplayName))
        {
            return BadRequest(new { message = "الاسم القانوني والاسم المعروض إلزاميان" });
        }
        if (request.PlanTier is not null && !ValidTiers.Contains(request.PlanTier))
        {
            return BadRequest(new { message = "باقة ترخيص غير معروفة" });
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

        // الكاشير: بيع واسترجاع وتعديل بيانات العملاء — لا أكثر.
        //
        // سُحبت منه customers.wallet_adjust و(ضمناً) إصدار البطاقات، لأن
        // اجتماعهما كان يفتح باب خلق نقود: إنشاء عميل وهمي ← إصدار بطاقة له
        // ← شحنها بمبلغ لم يدخل الصندوق ← ضبط رقمها السري ← إنفاقها على
        // بضاعة حقيقية. المخزون ينقص والإيراد لا يزيد، ولا يكشفه إلا جرد.
        //
        // البيع من محفظة العميل لا يتأثر: حركة الخصم تُكتب داخل
        // InvoicesController بعد التحقق من الرقم السري، لا عبر نقطة
        // wallet-adjustments المحروسة بهذه الصلاحية.
        ("cashier", "customers.manage"), ("cashier", "invoices.refund"),
    };

    [HttpPost]
    public async Task<ActionResult<CreateOrganizationResponse>> Create(CreateOrganizationRequest request)
    {
        if (User.FindFirstValue("is_platform_admin") != "True")
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
                EnabledModulesJson = JsonSerializer.Serialize(Editions.ModulesOf(edition)),
                MonthlyFee = request.MonthlyFee,
                StorageFee = request.StorageFee,
                MaintenanceRate = request.MaintenanceRate,
                MaxBranches = maxBranches,
                MaxUsers = maxUsers,
                ExpiresAt = expiresAt,
                Status = "active",
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
            if (edition == Editions.Wallet)
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
        });
        await _db.SaveChangesAsync();

        return StatusCode(201, new CreateOrganizationResponse(orgId, branchId, licenseKey, expiresAt));
    }
}
