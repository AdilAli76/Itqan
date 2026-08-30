using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Controllers;

public record CreateBranchRequest(string Name, string Code, string? Address, string? Phone, string? ThemePalette = null);
public record UpdateBranchRequest(string Name, string Code, string? Address, string? Phone, bool IsActive, string? ThemePalette = null);

/// <summary>
/// إدارة الفروع (إضافة/تعديل) مقصورة على super_admin عمداً — هيكلة فروع
/// المنظمة قرار على مستوى المنظمة كلها، بعكس البيانات التشغيلية اليومية.
/// القراءة مفتوحة لأي مستخدم مسجَّل دخول (تحتاجها شاشات كثيرة: المستخدمون،
/// تحويل المخزون، الجرد، لوحة التحكم).
/// </summary>
[ApiController]
[Route("api/branches")]
[Authorize]
public class BranchesController : ControllerBase
{
    private readonly AppDbContext _db;
    public BranchesController(AppDbContext db) => _db = db;

    [HttpGet]
    public async Task<ActionResult<List<Branch>>> GetAll([FromQuery] bool includeInactive = false)
    {
        var query = _db.Branches.AsQueryable();
        if (!includeInactive) query = query.Where(b => b.IsActive);
        return await query.OrderBy(b => b.Name).ToListAsync();
    }

    [HttpPost]
    [Authorize(Roles = "super_admin")]
    public async Task<ActionResult<Branch>> Create(CreateBranchRequest request)
    {
        var organizationId = Guid.Parse(User.FindFirstValue("organization_id")!);

        // حدّ الترخيص يُفحَص قبل أي كتابة — راجع [LicenseLimits].
        try
        {
            await LicenseLimits.EnsureCanAddBranchAsync(_db, organizationId);
        }
        catch (LicenseLimitException ex)
        {
            return BadRequest(new { message = ex.Message });
        }

        var branch = new Branch
        {
            OrganizationId = organizationId,
            Name = request.Name,
            Code = request.Code,
            Address = request.Address,
            Phone = request.Phone,
            ThemePalette = NormalizePalette(request.ThemePalette),
        };
        _db.Branches.Add(branch);
        _db.LogAudit(branch.OrganizationId, CurrentUserId(), "branch.created", "branches", branch.Id,
            newValues: new { branch.Name, branch.Code });

        await _db.SaveChangesAsync();
        return CreatedAtAction(nameof(GetAll), new { }, branch);
    }

    [HttpPut("{id:guid}")]
    [Authorize(Roles = "super_admin")]
    public async Task<IActionResult> Update(Guid id, UpdateBranchRequest request)
    {
        var branch = await _db.Branches.FindAsync(id);
        if (branch is null) return NotFound();

        branch.Name = request.Name;
        branch.Code = request.Code;
        branch.Address = request.Address;
        branch.Phone = request.Phone;
        branch.IsActive = request.IsActive;
        branch.ThemePalette = NormalizePalette(request.ThemePalette);

        _db.LogAudit(branch.OrganizationId, CurrentUserId(), "branch.updated", "branches", branch.Id,
            newValues: new { branch.Name, branch.Code, branch.IsActive });

        await _db.SaveChangesAsync();
        return NoContent();
    }

    /// <summary>
    /// لوح غير معروف يُردّ إلى الافتراضي بدل رفض الطلب: قيمة عرض لا تستحقّ
    /// أن تُفشل حفظ فرع، وعميل من نسخة أقدم قد يرسل اسماً حُذف.
    /// </summary>
    private static string NormalizePalette(string? value)
    {
        string[] known = { "default", "warm", "cool", "green", "slate" };
        return value is not null && known.Contains(value) ? value : "default";
    }

    private Guid? CurrentUserId()
    {
        var raw = User.FindFirstValue(JwtRegisteredClaimNames.Sub) ?? User.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(raw, out var id) ? id : null;
    }
}
