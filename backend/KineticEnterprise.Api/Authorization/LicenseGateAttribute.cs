using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Data;

namespace KineticEnterprise.Api.Authorization;

/// <summary>
/// بوّابة حالة الترخيص — تمنع الكتابة على منظمة مجمَّدة أو منتهية أو مُنهاة.
///
/// <para><b>العطب الذي تصلحه:</b> حالات الترخيص الأربع
/// (<c>active</c>، <c>grace_period</c>، <c>expired</c>، <c>revoked</c>)
/// كانت معرَّفة في المخطّط منذ اليوم الأول **ولا يقرأها سطر واحد**. أي أن
/// ترخيصاً انتهى أو أُلغي كان يعمل كالجديد تماماً — والترخيص كلّه وثيقة
/// لا حاجز.</para>
///
/// <para><b>لماذا القراءة تبقى مسموحة دائماً:</b> قطع الوصول عن عميل متأخّر
/// في السداد يحجب عنه **دفاتره هو** — فواتيره وأرصدة عملائه وسجلّ مبيعاته.
/// هذا لا يضغط عليه للدفع بل يدفعه إلى إنكار الخدمة كلّها، ويضعنا في موقف
/// من يحتجز بيانات لا من يطالب بحقّ. الحجب عن الكتابة يُوقف العمل الجديد
/// ويُبقي الماضي مرئياً — وهو ما يقوله <c>ARCHITECTURE.md</c> §2.2 صراحةً.
/// </para>
///
/// <para>تُطبَّق عامّةً في <c>Program.cs</c> لا على كل وحدة تحكّم: بوّابة
/// تُضاف يدوياً تُنسى في أول وحدة جديدة، وحاجزٌ به ثغرة واحدة ليس حاجزاً —
/// نفس درس [LicenseLimits] و[StockLedger].</para>
/// </summary>
public class LicenseGateAttribute : Attribute, IAsyncActionFilter
{
    /// <summary>
    /// مسارات تُستثنى دائماً: بلا استثناء الدخول لا يستطيع العميل المجمَّد
    /// أن يدخل ليقرأ حتى، ولا أن يرى رسالة سبب التجميد.
    /// </summary>
    private static readonly string[] AlwaysAllowed =
    {
        "/api/auth", "/api/platform", "/api/license", "/api/app-version",
        "/api/permissions/me", "/api/support",
    };

    public async Task OnActionExecutionAsync(ActionExecutingContext context, ActionExecutionDelegate next)
    {
        var http = context.HttpContext;

        // القراءة مسموحة دائماً — راجع سبب ذلك أعلاه.
        var method = http.Request.Method;
        if (HttpMethods.IsGet(method) || HttpMethods.IsHead(method) || HttpMethods.IsOptions(method))
        {
            await next();
            return;
        }

        var path = http.Request.Path.Value ?? "";
        if (AlwaysAllowed.Any(p => path.StartsWith(p, StringComparison.OrdinalIgnoreCase)))
        {
            await next();
            return;
        }

        // مالك المنصّة يمرّ: هو من يجمّد ويُفرِج، ومنعه من الكتابة يمنعه من
        // رفع التجميد أصلاً.
        if (string.Equals(http.User.FindFirstValue("is_platform_admin"), "True",
                StringComparison.OrdinalIgnoreCase))
        {
            await next();
            return;
        }

        if (http.User.Identity?.IsAuthenticated != true)
        {
            await next();
            return;
        }

        var db = http.RequestServices.GetRequiredService<AppDbContext>();

        // سياسة العزل تُرجع ترخيص منظمة الطالب وحده.
        var license = await db.Licenses
            .Select(l => new { l.Status, l.IsReadOnly, l.StatusReason, l.ExpiresAt })
            .FirstOrDefaultAsync();

        // بلا ترخيص = بلا حاجز: تركيب لم يُرخَّص بعد يجب ألّا يتوقّف.
        if (license is null)
        {
            await next();
            return;
        }

        var expired = license.ExpiresAt != default && license.ExpiresAt < DateTime.UtcNow;

        string? message = license.Status switch
        {
            "revoked" => "أُنهيت خدمة هذا الاشتراك. بياناتك محفوظة وقابلة للقراءة والتصدير — للاستئناف تواصل مع الدعم.",
            "expired" => "انتهى ترخيصك. النظام في وضع القراءة فقط حتى التجديد — بياناتك كما هي.",
            "grace_period" => "حسابك في وضع القراءة فقط مؤقّتاً. بياناتك كاملة ولم يُحذف شيء.",
            _ when license.IsReadOnly => "هذه نسخة للعرض — تُقرأ ولا تُعدَّل.",
            // الانتهاء بالتاريخ حتى لو بقيت الحالة active: التاريخ حقيقة
            // والحالة حقل قد يتأخّر تحديثه، فيُقاس الاثنان.
            _ when expired => "انتهى ترخيصك. النظام في وضع القراءة فقط حتى التجديد.",
            _ => null,
        };

        if (message is null)
        {
            await next();
            return;
        }

        // السبب المكتوب يُضاف إن وُجد: «قراءة فقط» بلا سبب تجعل العميل
        // يتّصل ليسأل، ونحن نعرف السبب سلفاً.
        if (!string.IsNullOrWhiteSpace(license.StatusReason))
        {
            message += $" — {license.StatusReason}";
        }

        context.Result = new ObjectResult(new { message })
        {
            // 403 لا 402: الأخيرة (Payment Required) غير مستقرّة الدلالة في
            // العملاء، وواجهتنا تعرض رسالة الخادم كما هي على أي حال.
            StatusCode = StatusCodes.Status403Forbidden,
        };
    }
}
