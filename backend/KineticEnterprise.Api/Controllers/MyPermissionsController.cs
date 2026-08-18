using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Data;

namespace KineticEnterprise.Api.Controllers;

public record MyPermissionsDto(string Role, bool IsSuperAdmin, List<string> Permissions);

/// <summary>
/// الصلاحيات الفعّالة للمستخدم الحالي — الطرف الذي كانت الواجهة تفتقده.
///
/// لماذا لا يكفي التوكن: JWT يحمل الدور (role) لا الصلاحيات، وربط الدور
/// بالصلاحيات مخزَّن في RolePermissions ويختلف من منظمة لأخرى ويُعدَّل من
/// شاشة مصفوفة الصلاحيات وقت التشغيل. حشو القائمة في التوكن كان سيعني أن
/// سحب صلاحية من موظف لا يسري حتى ينتهي توكنه.
///
/// ولماذا لا يكفي الفحص على الخادم وحده: هو كافٍ للأمان، وغير كافٍ للتجربة.
/// الفحص الخادمي يمنع الفعل بعد وقوعه (403)، بينما المستخدم يكون قد ملأ
/// نموذجاً كاملاً قبل أن يُخبَر أنه لا يملك الصلاحية أصلاً. هذه النقطة هي
/// وحدها ما تُضيفه الواجهة — لا الأمان.
///
/// منفصل عن PermissionsController لأن ذاك مقصور على super_admin بالكامل
/// (منح الصلاحيات تصعيد امتيازات)، بينما قراءة صلاحياتي أنا حقّ كل مستخدم.
/// </summary>
[ApiController]
[Route("api/permissions/me")]
[Authorize]
public class MyPermissionsController : ControllerBase
{
    private readonly AppDbContext _db;
    public MyPermissionsController(AppDbContext db) => _db = db;

    [HttpGet]
    public async Task<ActionResult<MyPermissionsDto>> GetMine()
    {
        var role = User.FindFirstValue(ClaimTypes.Role);
        var orgIdRaw = User.FindFirstValue("organization_id");

        if (role is null || orgIdRaw is null || !Guid.TryParse(orgIdRaw, out var orgId))
        {
            // توكن بلا دور أو منظمة: لا صلاحيات. لا نُرجع خطأً لأن الواجهة
            // يجب أن تبقى صالحة للعرض (قراءة فقط) لا أن تنهار.
            return new MyPermissionsDto(role ?? "", false, new List<string>());
        }

        // super_admin يملك كل شيء دائماً وليس عنصراً في المصفوفة — نفس
        // الاستثناء الموجود في RequirePermissionAttribute حرفياً. تكراره هنا
        // مقصود: لو اختلف الطرفان لظهرت أزرار لا تعمل، أو اختفت أزرار تعمل.
        if (role == "super_admin")
        {
            var all = await _db.Permissions.Select(p => p.Code).ToListAsync();
            return new MyPermissionsDto(role, true, all);
        }

        var codes = await _db.RolePermissions
            .Where(rp => rp.OrganizationId == orgId && rp.Role == role)
            .Select(rp => rp.PermissionCode)
            .ToListAsync();

        return new MyPermissionsDto(role, false, codes);
    }
}
