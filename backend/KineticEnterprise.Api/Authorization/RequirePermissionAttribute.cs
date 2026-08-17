using System.Security.Claims;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Data;

namespace KineticEnterprise.Api.Authorization;

/// <summary>
/// بديل حقيقي عن [Authorize(Roles = "...")] المُبرمَج مباشرة في الكود —
/// يقرأ الصلاحية من جدول role_permissions (منظمة + دور ← كود صلاحية) بدل
/// قائمة أدوار ثابتة، فيصبح مالك المنظمة قادراً فعلياً على تخصيص ما يستطيع
/// كل دور فعله (مثال: منح الكاشير صلاحيات محاسب وأمين مخزن معاً) من شاشة
/// "مصفوفة الصلاحيات" دون أي تعديل كود. super_admin يتجاوز الفحص دائماً —
/// هو صاحب المنظمة، صلاحياته ليست عنصراً قابلاً للتعديل في المصفوفة.
/// يتطلب وجود [Authorize] (توثيق الهوية) على نفس الكنترولر أو الإجراء.
/// </summary>
[AttributeUsage(AttributeTargets.Class | AttributeTargets.Method)]
public class RequirePermissionAttribute : Attribute, IAsyncActionFilter
{
    private readonly string _code;
    public RequirePermissionAttribute(string code) => _code = code;

    public async Task OnActionExecutionAsync(ActionExecutingContext context, ActionExecutionDelegate next)
    {
        var user = context.HttpContext.User;
        var role = user.FindFirstValue(ClaimTypes.Role);
        var orgIdRaw = user.FindFirstValue("organization_id");

        if (role is null || orgIdRaw is null || !Guid.TryParse(orgIdRaw, out var orgId))
        {
            context.Result = new Microsoft.AspNetCore.Mvc.ForbidResult();
            return;
        }

        if (role == "super_admin")
        {
            await next();
            return;
        }

        var db = context.HttpContext.RequestServices.GetRequiredService<AppDbContext>();
        var allowed = await db.RolePermissions.AnyAsync(rp =>
            rp.OrganizationId == orgId && rp.Role == role && rp.PermissionCode == _code);

        if (!allowed)
        {
            context.Result = new Microsoft.AspNetCore.Mvc.ForbidResult();
            return;
        }

        await next();
    }
}
