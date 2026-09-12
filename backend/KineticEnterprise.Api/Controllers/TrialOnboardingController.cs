using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Controllers;

public record TrialRegistrationRequest(
    string BusinessName,
    string BusinessType,
    string AdminFullName,
    string AdminEmail,
    string AdminPhone,
    string AdminPassword,
    string? ReferralCode = null
);

public record TrialRegistrationResponse(
    Guid OrganizationId,
    string OrganizationName,
    string LicenseKey,
    DateTime ExpiresAt,
    string Token,
    string UserRole,
    string FullName,
    string Message
);

/// <summary>
/// بوابة التسجيل الذاتي للنسخة التجريبية (14 يوماً).
/// 
/// تتيح للعملاء الجدد التسجيل مباشرة من الموقع بدون تدخل يدوي:
/// - اختيار نوع النشاط (صيدلية، تجزئة، جملة، مقاولات، خدمات).
/// - إنشاء المنظمة والفرع الافتراضي وحساب المدير فوراً مع عزل RLS.
/// - توليد ترخيص تجريبي لمدة 14 يوماً مع تفعيل الوحدات المناسبة للنشاط.
/// - ربط المنظمة تلقائياً بالمهندس المسوّق إن وُجد كود الإحالة (ReferralCode / Dongle).
/// - إصدار توكن الدخول الفوري ليدخل العميل المنظومة مباشرة دون انتظار.
/// </summary>
[ApiController]
[Route("api/trial")]
[AllowAnonymous]
public class TrialOnboardingController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly IConfiguration _config;
    private readonly ILogger<TrialOnboardingController> _logger;

    public TrialOnboardingController(AppDbContext db, IConfiguration config, ILogger<TrialOnboardingController> logger)
    {
        _db = db;
        _config = config;
        _logger = logger;
    }

    [HttpPost("register")]
    public async Task<ActionResult<TrialRegistrationResponse>> Register(TrialRegistrationRequest request)
    {
        // 1. التحقق من صحة المدخلات
        if (string.IsNullOrWhiteSpace(request.BusinessName)
            || string.IsNullOrWhiteSpace(request.AdminFullName)
            || string.IsNullOrWhiteSpace(request.AdminEmail)
            || string.IsNullOrWhiteSpace(request.AdminPassword))
        {
            return BadRequest(new { message = "جميع الحقول الأساسية مطلوبة (اسم المؤسسة، الاسم الكامل، البريد، وكلمة المرور)" });
        }

        if (request.AdminPassword.Length < 8)
        {
            return BadRequest(new { message = "كلمة المرور يجب أن لا تقل عن 8 أحرف" });
        }

        var email = request.AdminEmail.Trim().ToLowerInvariant();

        // 2. فحص عدم تكرار البريد الإلكتروني
        if (await _db.AppUsers.AnyAsync(u => u.IsActive && u.Email.ToLower() == email))
        {
            return Conflict(new { message = "البريد الإلكتروني مسجّل بالفعل في منظومة أخرى. الرجاء استخدام بريد مختلف أو تسجيل الدخول." });
        }

        // 3. تحديد الإصدار المناسب لنوع النشاط
        var businessType = (request.BusinessType ?? "general").Trim().ToLowerInvariant();
        var edition = businessType switch
        {
            "pharmacy" => Editions.Pharmacy,
            "wallet" => Editions.WalletPlus,
            "enterprise" or "contracting" or "wholesale" => Editions.Enterprise,
            _ => Editions.Standard
        };

        // 4. التحقق من كود المهندس المسوّق (إن وُجد)
        Guid? ownerUserId = null;
        if (!string.IsNullOrWhiteSpace(request.ReferralCode))
        {
            var refCode = request.ReferralCode.Trim();
            var engineer = await _db.AppUsers
                .FirstOrDefaultAsync(u => u.IsPlatformAdmin && u.IsActive
                    && (u.ResellerLicense == refCode || u.Id.ToString() == refCode || u.Username == refCode));

            if (engineer is not null)
            {
                ownerUserId = engineer.Id;
                _logger.LogInformation("Trial registration attributed to engineer: {EngineerName} ({RefCode})", engineer.FullName, refCode);
            }
        }

        // 5. إنشاء المعرّفات والسيريال
        var orgId = Guid.NewGuid();
        var branchId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var licenseKey = $"KIN-TRIAL-{Guid.NewGuid().ToString("N")[..6].ToUpperInvariant()}-{Guid.NewGuid().ToString("N")[..6].ToUpperInvariant()}";
        var expiresAt = DateTime.UtcNow.AddDays(14); // 14 يوماً تجريبية

        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlServer(_config.GetConnectionString("Default"))
            .UseSnakeCaseNamingConvention()
            .Options;

        await using var db = new AppDbContext(options);
        var connection = db.Database.GetDbConnection();
        await connection.OpenAsync();

        // ضبط سياق الجلسة RLS
        await using (var cmd = connection.CreateCommand())
        {
            cmd.CommandText = "EXEC sp_set_session_context @key=N'organization_id', @value=@orgId;";
            var p = cmd.CreateParameter();
            p.ParameterName = "@orgId";
            p.Value = orgId;
            cmd.Parameters.Add(p);
            await cmd.ExecuteNonQueryAsync();
        }

        await using var transaction = await db.Database.BeginTransactionAsync();
        try
        {
            var org = new Organization
            {
                Id = orgId,
                LegalName = request.BusinessName.Trim(),
                DisplayName = request.BusinessName.Trim(),
                Edition = edition,
                PosAllowOpenProduct = Editions.AllowsOpenProduct(edition),
            };
            db.Organizations.Add(org);
            await db.SaveChangesAsync();

            // الفهرس العالمي للمنظمات (لإدارة المنصة)
            db.PlatformOrganizations.Add(new PlatformOrganizationRecord
            {
                Id = orgId,
                LegalName = request.BusinessName.Trim(),
                DisplayName = request.BusinessName.Trim(),
                OwnerUserId = ownerUserId,
                IsActive = true,
                CreatedAt = DateTime.UtcNow
            });
            await db.SaveChangesAsync();

            // الفرع الرئيسي الافتراضي
            var branch = new Branch
            {
                Id = branchId,
                OrganizationId = orgId,
                Name = "الفرع الرئيسي",
                Code = "MAIN-01",
            };
            db.Branches.Add(branch);
            await db.SaveChangesAsync();

            // حساب المدير العام للشركة المشتركة
            var user = new AppUser
            {
                Id = userId,
                OrganizationId = orgId,
                BranchId = branchId,
                FullName = request.AdminFullName.Trim(),
                Email = email,
                PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.AdminPassword),
                Role = "super_admin",
                IsPlatformAdmin = false,
                IsActive = true,
                MustChangePassword = false,
            };
            db.AppUsers.Add(user);
            await db.SaveChangesAsync();

            // الترخيص التجريبي (14 يوم)
            var license = new License
            {
                Id = Guid.NewGuid(),
                OrganizationId = orgId,
                LicenseKey = licenseKey,
                PlanTier = "trial",
                MaxBranches = 2,
                MaxUsers = 5,
                ExpiresAt = expiresAt,
                IssuedAt = DateTime.UtcNow,
                Status = "active",
                StatusReason = "نسخة تجريبية مجانية لمدة 14 يوماً",
                EnabledModulesJson = JsonSerializer.Serialize(Editions.ModulesOf(edition)),
                GrantedModulesJson = "[]",
                RevokedModulesJson = "[]",
                IsReadOnly = false,
                MonthlyFee = 0,
                StorageFee = 0,
                MaintenanceRate = 0
            };
            db.Licenses.Add(license);
            await db.SaveChangesAsync();

            await transaction.CommitAsync();

            _logger.LogInformation("New trial organization registered: {OrgName} ({OrgId}) - Edition: {Edition}", org.DisplayName, orgId, edition);

            // إصدار توكن الدخول الفوري
            var token = IssueToken(user);

            return Ok(new TrialRegistrationResponse(
                OrganizationId: orgId,
                OrganizationName: org.DisplayName,
                LicenseKey: licenseKey,
                ExpiresAt: expiresAt,
                Token: token,
                UserRole: user.Role,
                FullName: user.FullName,
                Message: "تم إنشاء نسختك التجريبية بنجاح! مرحباً بك في المنظومة."
            ));
        }
        catch (Exception ex)
        {
            await transaction.RollbackAsync();
            _logger.LogError(ex, "Error creating trial organization: {BusinessName}", request.BusinessName);
            return StatusCode(500, new { message = "حدث خطأ أثناء إعداد النسخة التجريبية. الرجاء المحاولة مرة أخرى." });
        }
    }

    private string IssueToken(AppUser user)
    {
        var claims = new List<Claim>
        {
            new(JwtRegisteredClaimNames.Sub, user.Id.ToString()),
            new("organization_id", user.OrganizationId.ToString()),
            new(ClaimTypes.Role, user.Role),
            new("role", user.Role),
            new(ClaimTypes.Name, user.FullName),
            new("remember", "1")
        };

        if (user.BranchId.HasValue)
        {
            claims.Add(new Claim("branch_id", user.BranchId.Value.ToString()));
        }

        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_config["Jwt:Key"]!));
        var creds = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);
        var jwt = new JwtSecurityToken(
            issuer: _config["Jwt:Issuer"],
            audience: _config["Jwt:Audience"],
            claims: claims,
            expires: DateTime.UtcNow.AddDays(14),
            signingCredentials: creds
        );

        return new JwtSecurityTokenHandler().WriteToken(jwt);
    }
}
