using System.Security.Claims;
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
        // مالك المنصّة مشغّل النظام لا مستأجر فيه: منظمته الخاصة قد تكون
        // بإصدار قياسي بينما يدير محتوى يخصّ عملاء بإصدارات أخرى (نشرة
        // الدواء مثلاً — جدول على مستوى المنصّة يُدار من حساب واحد ويقرأه كل
        // عملاء إصدار الصيدليات). قياسه بإصدار منظمته كان يمنعه من إدارة ما
        // يبيعه هو نفسه.
        //
        // ولا يوسّع هذا صلاحيته على بيانات العملاء: سياسات العزل على قاعدة
        // البيانات تبقى كما هي، وهي التي تحكم أي صفوف يراها.
        if (string.Equals(
                context.HttpContext.User.FindFirstValue("is_platform_admin"),
                "True", StringComparison.OrdinalIgnoreCase))
        {
            await next();
            return;
        }

        var db = context.HttpContext.RequestServices.GetRequiredService<AppDbContext>();

        // سياسة العزل على القاعدة تُرجع منظمة الطالب وحدها، فلا حاجة لشرط
        // معرّف في الكود — ولا لثقة به.
        var org = await db.Organizations
            .Select(o => new { o.Id, o.Edition })
            .FirstOrDefaultAsync();

        if (org is null)
        {
            context.Result = new ForbidResult();
            return;
        }

        // الإصدار **والترخيص** معاً: الأول يقول ما شكل النظام، والثاني ما
        // دُفع ثمنه. الاكتفاء بالأول — وهو ما كان — يجعل قائمة وحدات
        // الترخيص زينةً، فيحصل من اشترى الأدنى على ما لم يشترِه.
        // راجع [LicenseLimits.EffectiveModules].
        var licenseModules = await db.Licenses
            .Where(l => l.OrganizationId == org.Id)
            .Select(l => l.EnabledModulesJson)
            .FirstOrDefaultAsync();

        if (!LicenseLimits.EffectiveModules(org.Edition, licenseModules).Contains(_module))
        {
            context.Result = new ObjectResult(new
            {
                message = $"وحدة «{_module}» غير مفعَّلة في ترخيص هذه المنظمة"
            })
            { StatusCode = StatusCodes.Status403Forbidden };
            return;
        }

        await next();
    }
}
