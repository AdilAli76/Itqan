using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Authorization;
using KineticEnterprise.Api.Data;

namespace KineticEnterprise.Api.Controllers;

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
    public LicensesController(AppDbContext db) => _db = db;

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
