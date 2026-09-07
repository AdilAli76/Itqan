using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace KineticEnterprise.Api.Controllers;

/// <summary>
/// ملفّات <c>/.well-known/</c> التي تقرأها المنصّات لا الناس.
///
/// <para><b>سبب وجوده:</b> مفتاح المرور على أندرويد لا يعمل ما لم يُثبت
/// النطاق أن هذا التطبيق يمثّله — ونظام أندرويد يطلب هذا الإثبات من
/// <c>https://&lt;النطاق&gt;/.well-known/assetlinks.json</c> قبل أن يعرض
/// نافذة المفتاح أصلاً. وغيابُه لا يُخرج خطأً مفهوماً: تُغلق النافذة فوراً
/// وكأن المستخدم ألغى.</para>
///
/// <para><b>ولماذا يُولَّد من الإعدادات لا يُرفع ملفاً ثابتاً:</b> فيه بصمة
/// توقيع التطبيق، وهي تختلف بين مفتاح الإصدار ومفتاح التصحيح، وتتغيّر إن
/// وُقِّع التطبيق من جديد. وملفٌّ ثابت في المستودع يعني بصمةً تُنسى في
/// نسخةٍ لا يعمل عليها المفتاح، ولا أحد يعرف لماذا.</para>
///
/// <para>وفراغُ الإعدادات يعني أن أندرويد غير مُهيَّأ بعد، فيُردّ 404 —
/// وهو ما يقوله أندرويد نفسه لصاحبه: لا ربط بين النطاق والتطبيق.</para>
/// </summary>
[ApiController]
[AllowAnonymous]
public class WellKnownController : ControllerBase
{
    private readonly IConfiguration _config;
    public WellKnownController(IConfiguration config) => _config = config;

    [HttpGet("/.well-known/assetlinks.json")]
    [Produces("application/json")]
    public IActionResult AssetLinks()
    {
        var package = _config["Passkeys:AndroidPackageName"];
        var fingerprints = _config.GetSection("Passkeys:AndroidCertFingerprints").Get<string[]>()
                           ?? Array.Empty<string>();

        if (string.IsNullOrWhiteSpace(package) || fingerprints.Length == 0)
            return NotFound();

        return Ok(new[]
        {
            new
            {
                relation = new[]
                {
                    "delegate_permission/common.handle_all_urls",
                    "delegate_permission/common.get_login_creds",
                },
                target = new
                {
                    @namespace = "android_app",
                    package_name = package,
                    sha256_cert_fingerprints = fingerprints,
                },
            },
        });
    }
}
