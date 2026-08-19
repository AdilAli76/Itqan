using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Authorization;

/// <summary>
/// يمنع نقاط وحدةٍ غير مفعَّلة في إصدار المنظمة.
///
/// إخفاء الشاشة من قائمة التنقّل ليس حماية: المسار يُفتح بكتابته، والنقطة
/// تُستدعى بتوكن صالح من أي أداة. ومنظمة على إصدار المحفظة ليس لها كتالوج
/// ولا مخزون أصلاً — فنقاط الأصناف والمشتريات عليها ليست ممنوعة فحسب، بل
/// بلا معنى: تكتب صفوفاً لا تعرضها أي شاشة ولا يراها أحد حتى تُفسد تقريراً.
///
/// الفرق عن [RequirePermissionAttribute]: تلك تسأل «هل يملك هذا الدور
/// الصلاحية؟»، وهذه تسأل «هل هذه الوحدة جزء من النظام الذي اشتراه العميل
/// أصلاً؟». فلا يتجاوزها super_admin — صاحب المنظمة لا يملك تفعيل وحدة لم
/// يشترها، وذلك قرار مالك المنصة عند الإنشاء.
/// </summary>
[AttributeUsage(AttributeTargets.Class | AttributeTargets.Method)]
public class RequireModuleAttribute : Attribute, IAsyncActionFilter
{
    private readonly string _module;
    public RequireModuleAttribute(string module) => _module = module;

    public async Task OnActionExecutionAsync(ActionExecutingContext context, ActionExecutionDelegate next)
    {
        var db = context.HttpContext.RequestServices.GetRequiredService<AppDbContext>();

        // سياسة العزل على القاعدة تُرجع منظمة الطالب وحدها، فلا حاجة لشرط
        // معرّف في الكود — ولا لثقة به.
        var edition = await db.Organizations
            .Select(o => o.Edition)
            .FirstOrDefaultAsync();

        if (edition is null)
        {
            context.Result = new ForbidResult();
            return;
        }

        if (!Editions.ModulesOf(edition).Contains(_module))
        {
            context.Result = new ObjectResult(new
            {
                message = $"وحدة «{_module}» غير مفعَّلة في إصدار هذه المنظمة"
            })
            { StatusCode = StatusCodes.Status403Forbidden };
            return;
        }

        await next();
    }
}
