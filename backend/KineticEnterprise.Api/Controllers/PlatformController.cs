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
    string PlanTier, int LicenseMonths);

public record CreateOrganizationResponse(Guid OrganizationId, Guid BranchId, string LicenseKey, DateTime ExpiresAt);
public record PlatformOrganizationDto(Guid Id, string LegalName, string DisplayName, bool IsActive, DateTime CreatedAt);

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
        return orgs.Select(o => new PlatformOrganizationDto(o.Id, o.LegalName, o.DisplayName, o.IsActive, o.CreatedAt)).ToList();
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
        ("cashier", "customers.manage"), ("cashier", "customers.wallet_adjust"), ("cashier", "invoices.refund"),
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
                Email = request.AdminEmail,
                PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.AdminPassword),
                Role = "super_admin",
                IsActive = true,
            });
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
