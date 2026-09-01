using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Data;

namespace KineticEnterprise.Api.Authorization;

/// <summary>
/// يمنع كل شيء على حسابٍ يحمل كلمةً مؤقّتة حتى يغيّرها صاحبه.
///
/// <para><b>الفرض على الخادم لا في الشاشة.</b> شاشةٌ تُلحّ على المستخدم
/// تُتجاوَز بفتح مسارٍ آخر أو بإغلاق نافذة، والتوكن يبقى صالحاً ثماني
/// ساعات — فيعمل صاحب الكلمة المؤقّتة يوم عملٍ كاملاً بها. وكلمةٌ أملاها
/// مشغّل النظام هاتفياً يعرفها اثنان: من أملاها ومن سمعها.</para>
///
/// <para><b>ومُرشِّح عامّ لا سمة تُوضع على وحدات التحكّم:</b> نفس درس
/// [LicenseLimits] و[PlatformScope]. أربعون وحدة تحكّم في هذا النظام، وسمةٌ
/// تُنسى على واحدة تترك باباً مفتوحاً — والوحدة المنسيّة هي الوحدة التي
/// تُكتشف عند العميل. والمُعفَون قائمة قصيرة صريحة أدناه.</para>
///
/// <para><b>ويُقرأ العلم من القاعدة لا من التوكن:</b> دعوى في التوكن تبقى
/// مرفوعةً بعد تغيير الكلمة حتى ينتهي، فيُقفَل الحساب على صاحبه بعد أن
/// فعل ما طُلب منه. والقراءة استعلامٌ واحد بمفتاح أساسي.</para>
/// </summary>
public class MustChangePasswordFilter : IAsyncActionFilter
{
    /// <summary>
    /// ما يبقى مفتوحاً: الدخول (لا توكن بعد)، وتغيير الكلمة نفسه — وإلا
    /// صار من يجب أن يغيّرها عاجزاً عن تغييرها، وهو قفلٌ لا مخرج منه.
    ///
    /// <para>والمقارنة على المسار كاملاً لا على بادئته: <c>api/auth</c>
    /// بادئةً كانت ستُعفي أي نقطة تُضاف تحتها لاحقاً بلا أن ينتبه من
    /// أضافها.</para>
    /// </summary>
    private static readonly HashSet<string> Exempt = new(StringComparer.OrdinalIgnoreCase)
    {
        "/api/auth/login",
        "/api/auth/change-password",
    };

    public async Task OnActionExecutionAsync(ActionExecutingContext context, ActionExecutionDelegate next)
    {
        var path = context.HttpContext.Request.Path.Value ?? "";
        if (Exempt.Contains(path.TrimEnd('/')))
        {
            await next();
            return;
        }

        // غير مصادَق = ليس شأن هذا المُرشِّح: المصادقة تردّه قبل أن يصل
        // إلى هنا أو تسمح له، وفحصه هنا استعلامٌ بلا داعٍ على كل نداء عامّ.
        if (context.HttpContext.User.Identity?.IsAuthenticated != true)
        {
            await next();
            return;
        }

        var raw = context.HttpContext.User.FindFirstValue(JwtRegisteredClaimNames.Sub)
                  ?? context.HttpContext.User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (!Guid.TryParse(raw, out var userId))
        {
            await next();
            return;
        }

        var db = context.HttpContext.RequestServices.GetRequiredService<AppDbContext>();
        var mustChange = await db.AppUsers
            .Where(u => u.Id == userId)
            .Select(u => u.MustChangePassword)
            .FirstOrDefaultAsync();

        if (mustChange)
        {
            // 403 برمزٍ تقرؤه الواجهة لا 401: الأخيرة تُفهَم «انتهت جلستك»
            // فيُمحى التوكن ويُعاد إلى الدخول، فيدخل بالكلمة المؤقّتة
            // نفسها ويدور في حلقة لا تنتهي.
            context.Result = new ObjectResult(new
            {
                code = "must_change_password",
                message = "كلمة المرور مؤقّتة — غيّرها قبل استعمال النظام.",
            })
            { StatusCode = StatusCodes.Status403Forbidden };
            return;
        }

        await next();
    }
}
