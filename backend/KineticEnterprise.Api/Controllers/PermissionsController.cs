using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Controllers;

public record PermissionDto(string Code, string LabelAr, string Module);
public record UpdateRoleMatrixRequest(string Role, List<string> PermissionCodes);

/// <summary>
/// إدارة مصفوفة الصلاحيات الفعلية — راجع RequirePermissionAttribute.cs
/// للتطبيق وقت الطلب. مقصورة على super_admin عمداً: منح صلاحيات لدور هو
/// بحد ذاته قرار تصعيد امتيازات، فلا يجوز تفويضه.
/// </summary>
[ApiController]
[Route("api/permissions")]
[Authorize(Roles = "super_admin")]
public class PermissionsController : ControllerBase
{
    // super_admin مستثنى عمداً — صلاحياته كاملة دائماً وليست عنصراً في
    // المصفوفة (راجع RequirePermissionAttribute).
    private static readonly string[] EditableRoles =
        { "branch_manager", "cashier", "inventory_officer", "accountant", "custom" };

    private readonly AppDbContext _db;
    public PermissionsController(AppDbContext db) => _db = db;

    [HttpGet("catalog")]
    public async Task<ActionResult<List<PermissionDto>>> GetCatalog()
    {
        var permissions = await _db.Permissions.OrderBy(p => p.Module).ThenBy(p => p.Code).ToListAsync();
        return permissions.Select(p => new PermissionDto(p.Code, p.LabelAr, p.Module)).ToList();
    }

    [HttpGet("matrix")]
    public async Task<ActionResult<Dictionary<string, List<string>>>> GetMatrix()
    {
        var orgId = CurrentOrgId();
        var rows = await _db.RolePermissions.Where(rp => rp.OrganizationId == orgId).ToListAsync();

        var matrix = EditableRoles.ToDictionary(r => r, _ => new List<string>());
        foreach (var row in rows)
        {
            if (matrix.TryGetValue(row.Role, out var list)) list.Add(row.PermissionCode);
        }
        return matrix;
    }

    [HttpPut("matrix")]
    public async Task<IActionResult> UpdateMatrix(UpdateRoleMatrixRequest request)
    {
        if (!EditableRoles.Contains(request.Role))
        {
            return BadRequest(new { message = "دور غير قابل للتعديل" });
        }

        var validCodes = (await _db.Permissions.Select(p => p.Code).ToListAsync()).ToHashSet();
        var invalid = request.PermissionCodes.Where(c => !validCodes.Contains(c)).ToList();
        if (invalid.Count > 0)
        {
            return BadRequest(new { message = $"أكواد صلاحيات غير معروفة: {string.Join(", ", invalid)}" });
        }

        var orgId = CurrentOrgId();
        var existing = await _db.RolePermissions
            .Where(rp => rp.OrganizationId == orgId && rp.Role == request.Role)
            .ToListAsync();
        _db.RolePermissions.RemoveRange(existing);

        foreach (var code in request.PermissionCodes.Distinct())
        {
            _db.RolePermissions.Add(new RolePermission { OrganizationId = orgId, Role = request.Role, PermissionCode = code });
        }

        _db.LogAudit(orgId, CurrentUserId(), "permissions.role_matrix_updated", "role_permissions", null,
            newValues: new { request.Role, request.PermissionCodes });

        await _db.SaveChangesAsync();
        return NoContent();
    }

    private Guid CurrentOrgId() => Guid.Parse(User.FindFirstValue("organization_id")!);

    private Guid? CurrentUserId()
    {
        var raw = User.FindFirstValue(System.IdentityModel.Tokens.Jwt.JwtRegisteredClaimNames.Sub) ?? User.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(raw, out var id) ? id : null;
    }
}
