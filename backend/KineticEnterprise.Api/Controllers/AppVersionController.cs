using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace KineticEnterprise.Api.Controllers;

public record AppVersionDto(
    string LatestVersion, string? DownloadUrl, string? AndroidDownloadUrl,
    bool Mandatory, string? Notes);

/// <summary>
/// أحدث إصدار متاح من تطبيقات العملاء.
///
/// تطبيق الويب يُحدَّث من تلقائه لأنه يُخدَم من الخادم. أمّا سطح المكتب
/// وأندرويد فنسخة مثبَّتة على جهاز، ولا شيء يخبرها أن أحدث منها صدر —
/// فتبقى أجهزة العملاء على نسخ قديمة شهوراً، وأول ما يُكسر ذلك هو تغيّر
/// عقد الـAPI: الخادم يردّ بشكل جديد وتطبيق قديم لا يفهمه، فتظهر أعطال
/// لا يربطها أحد بقِدَم النسخة.
///
/// مفتوحة بلا توكن عمداً: التطبيق يسألها **قبل** تسجيل الدخول، ومنعها
/// يعني ألّا يعرف بالتحديث إلا من استطاع الدخول — وهو بالضبط ما قد يمنعه
/// إصدار قديم.
///
/// القيم من appsettings فلا تحتاج نشراً جديداً لتغييرها: يكفي تعديل الملف
/// وإعادة تشغيل المجمّع.
/// </summary>
[ApiController]
[Route("api/app-version")]
[AllowAnonymous]
public class AppVersionController : ControllerBase
{
    private readonly IConfiguration _config;
    public AppVersionController(IConfiguration config) => _config = config;

    [HttpGet]
    public ActionResult<AppVersionDto> Get()
    {
        var section = _config.GetSection("AppVersion");
        return new AppVersionDto(
            section["Latest"] ?? "1.0.0",
            section["DownloadUrl"],
            section["AndroidDownloadUrl"],
            bool.TryParse(section["Mandatory"], out var m) && m,
            section["Notes"]);
    }
}
