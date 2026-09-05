using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Controllers;

/// <summary>
/// ما تحتاجه الواجهة عند الإقلاع لترسم نفسها.
///
/// <para><b>ولماذا <c>Modules</c> إلى جانب <c>Edition</c>:</b> الإصدار يقول
/// **شكل** النظام (محفظة بلا كتالوج، بيع بالقيمة الحرّة)، والوحدات تقول ما
/// اشتراه العميل. كانت قائمة التنقّل تُبنى من الإصدار وحده فتكرّر منطق
/// [Editions.ModulesOf] في Dart — وبعد أن صارت الوحدات تُباع فوق الإصدار،
/// كان ذلك يعني عميلاً يدفع ثمن وحدة يفتحها له الخادم ولا يرى لها
/// شاشة.</para>
/// </summary>
public record BrandingResponse(string DisplayName, string? LogoUrl, string PrimaryColor, string SecondaryColor, string CurrencySymbol, string NavLayout, string Edition, List<string> Modules);
public record UpdateBrandingRequest(string DisplayName, string PrimaryColor, string SecondaryColor, string NavLayout);
public record SetLogoRequest(Guid? AttachmentId);

public record OrganizationSettingsDto(string CurrencyCode, string CurrencySymbol, string Locale, decimal TaxRate, int PasswordMinLength, double ReceiptWidthMm, bool PosAllowOpenProduct, string CardModesAllowed, string CardModeDefault, decimal CardOpenModeDailyCap);
public record UpdateSettingsRequest(string CurrencyCode, string CurrencySymbol, string Locale, decimal TaxRate, int PasswordMinLength, double ReceiptWidthMm, bool PosAllowOpenProduct, string? CardModesAllowed, string? CardModeDefault, decimal? CardOpenModeDailyCap);

/// <summary>
/// قالب الإيصال.
///
/// <para><c>Paper</c> أحد: <c>roll80</c>، <c>roll58</c>، <c>a4</c>،
/// <c>a5</c>. والرقم الضريبي والسجلّ التجاري يُقرآن من المنظمة لا من
/// القالب — القالب يقرّر أيُعرضان، لا ما قيمتهما.</para>
/// </summary>
public record ReceiptTemplateDto(
    string Paper, bool ShowLogo, bool ShowTaxNumber, bool ShowCommercialRegistry,
    bool ShowQr, string? HeaderText, string? FooterText,
    /// <summary>
    /// القالب الجاهز وتفاصيل شكله — راجع ReceiptPresets في الواجهة.
    ///
    /// <para><b>ولماذا داخل نفس الـJSON:</b> هي قيم **عرض** لا يُستعلَم
    /// عنها ولا تُفهرَس، فعمودٌ لكل واحدة يعني هجرةً لكل خيار جديد — وهو
    /// الطريق الذي انتهى بجدولٍ ذي ١٦٥ عموداً في نظامٍ آخر دُرس.</para>
    /// </summary>
    string? Preset = null, string? AccentColor = null, double? FontScale = null,
    string? TableStyle = null, bool ShowPageBorder = false);

/// <summary>القالب ومعه ما يملأه — ردٌّ واحد فتطبع الشاشة بلا نداءين.</summary>
public record ReceiptTemplateResponse(
    ReceiptTemplateDto Template, string? TaxNumber, string? CommercialRegistry,
    string? LogoUrl);

public record UpdateReceiptTemplateRequest(
    string Paper, bool ShowLogo, bool ShowTaxNumber, bool ShowCommercialRegistry,
    bool ShowQr, string? HeaderText, string? FooterText,
    string? TaxNumber, string? CommercialRegistry,
    string? Preset = null, string? AccentColor = null, double? FontScale = null,
    string? TableStyle = null, bool ShowPageBorder = false);

public record BarcodeTemplateDto(double WidthMm, double HeightMm, bool ShowName, bool ShowPrice, bool ShowSku);

[ApiController]
[Route("api/organizations")]
[Authorize]
public class OrganizationsController : ControllerBase
{
    private readonly AppDbContext _db;
    public OrganizationsController(AppDbContext db) => _db = db;

    /// <summary>
    /// يستدعيها main.dart في Flutter عند الإقلاع لبناء الثيم الديناميكي —
    /// بديل مباشر لاستعلام organizations الذي كان يُنفَّذ عبر Supabase.
    /// الـ Security Policy على قاعدة البيانات تضمن رجوع منظمة المستخدم فقط.
    /// </summary>
    [HttpGet("me")]
    public async Task<ActionResult<BrandingResponse>> GetMyOrganization()
    {
        var org = await _db.Organizations.FirstOrDefaultAsync();
        if (org is null) return NotFound();

        // نفس المخنق الذي يفرضه [RequireModuleAttribute] لا حسابٌ ثانٍ:
        // قائمةٌ تُرسم بمنطقٍ وتُحرَس بمنطقٍ آخر تفترق أوّل مرّة يتغيّر
        // أحدهما، فيرى المستخدم شاشة تُفتح لتُقابله بـ«وحدة غير مفعَّلة».
        var license = await _db.Licenses.FirstOrDefaultAsync(l => l.OrganizationId == org.Id);
        var modules = LicenseLimits.EffectiveModules(org.Edition, license).ToList();

        return new BrandingResponse(org.DisplayName, org.LogoUrl, org.PrimaryColor, org.SecondaryColor, org.CurrencySymbol, org.NavLayout, org.Edition, modules);
    }

    /// <summary>
    /// ربط شعار مرفوع بالمنظمة. الملف يُرفع أولاً عبر POST /api/files ثم
    /// يُمرَّر معرّفه هنا — فصلٌ يبقي منطق التخزين في مكان واحد.
    /// </summary>
    [HttpPut("me/logo")]
    [Authorize(Roles = "super_admin")]
    public async Task<IActionResult> SetLogo([FromBody] SetLogoRequest request)
    {
        var org = await _db.Organizations.FirstOrDefaultAsync();
        if (org is null) return NotFound();

        if (request.AttachmentId is null)
        {
            org.LogoUrl = null;
        }
        else
        {
            // التحقّق من وجود المرفق قبل ربطه: معرّف عشوائي كان سيُخزَّن
            // رابطاً ميتاً يظهر أيقونة مكسورة في كل شاشة.
            var exists = await _db.Attachments.AnyAsync(a => a.Id == request.AttachmentId);
            if (!exists) return BadRequest(new { message = "المرفق غير موجود" });
            org.LogoUrl = $"/api/files/{request.AttachmentId}";
        }

        await _db.SaveChangesAsync();
        return Ok(new { logoUrl = org.LogoUrl });
    }

    [HttpPut("me/branding")]
    [Authorize(Roles = "super_admin")]
    public async Task<IActionResult> UpdateBranding(UpdateBrandingRequest request)
    {
        var org = await _db.Organizations.FirstOrDefaultAsync();
        if (org is null) return NotFound();

        if (request.NavLayout is not ("sidebar" or "navbar"))
        {
            return BadRequest(new { message = "نمط تنقّل غير معروف" });
        }

        org.DisplayName = request.DisplayName;
        org.PrimaryColor = request.PrimaryColor;
        org.SecondaryColor = request.SecondaryColor;
        org.NavLayout = request.NavLayout;
        org.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();

        return NoContent();
    }

    /// <summary>
    /// شاشة "الإعدادات العامة" (ARCHITECTURE.md §2.14) — منفصلة عمداً عن
    /// GetMyOrganization/me: تلك تُستدعى عند إقلاع التطبيق لبناء الثيم (نقطة
    /// حرجة للأداء)، وهذه تُستدعى عند فتح شاشة الإعدادات، *وأيضاً* من نقطة
    /// البيع لأي كاشير قبل طباعة إيصال (يحتاج receipt_width_mm) — لذا القراءة
    /// مفتوحة لأي مستخدم مسجَّل دخول، والتعديل فقط مقصور على super_admin.
    /// </summary>
    [HttpGet("me/settings")]
    public async Task<ActionResult<OrganizationSettingsDto>> GetSettings()
    {
        var org = await _db.Organizations.FirstOrDefaultAsync();
        if (org is null) return NotFound();

        return new OrganizationSettingsDto(org.CurrencyCode, org.CurrencySymbol, org.Locale, org.TaxRate, org.PasswordMinLength, org.ReceiptWidthMm, org.PosAllowOpenProduct,
            string.Join(",", CardModeGate.AllowedModes(org)), org.CardModeDefault, org.CardOpenModeDailyCap);
    }

    [HttpPut("me/settings")]
    [Authorize(Roles = "super_admin")]
    public async Task<IActionResult> UpdateSettings(UpdateSettingsRequest request)
    {
        var org = await _db.Organizations.FirstOrDefaultAsync();
        if (org is null) return NotFound();

        if (request.PasswordMinLength < 4)
        {
            return BadRequest(new { message = "الحد الأدنى لطول كلمة المرور 4 أحرف على الأقل" });
        }
        if (request.TaxRate < 0 || request.TaxRate > 100)
        {
            return BadRequest(new { message = "نسبة الضريبة يجب أن تكون بين 0 و100" });
        }
        if (request.ReceiptWidthMm < 40 || request.ReceiptWidthMm > 120)
        {
            return BadRequest(new { message = "عرض إيصال الطباعة يجب أن يكون بين 40 و120 ملم" });
        }

        org.CurrencyCode = request.CurrencyCode;
        org.CurrencySymbol = request.CurrencySymbol;
        org.Locale = request.Locale;
        org.TaxRate = request.TaxRate;
        org.PasswordMinLength = request.PasswordMinLength;
        org.ReceiptWidthMm = request.ReceiptWidthMm;
        // بيع بقيمة يكتبها الكاشير هو أوسع باب لسحب نقدية بلا بضاعة مقابلة،
        // فتغييره محصور بـ super_admin مثل بقية هذه الشاشة.
        org.PosAllowOpenProduct = request.PosAllowOpenProduct;

        // أنماط البطاقة — تُحدَّث فقط إن أُرسلت: عميل قديم لا يعرف هذه الحقول
        // يجب ألّا يمحو إعداداً بحفظه شاشة العملة.
        if (request.CardModesAllowed is { } modesRaw)
        {
            var modes = modesRaw
                .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .Where(CardModes.IsSelectable)
                .Distinct()
                .ToArray();
            if (modes.Length == 0)
            {
                return BadRequest(new { message = "يجب السماح بنمط تحقّق واحد على الأقل" });
            }
            org.CardModesAllowed = string.Join(",", modes);

            var fallbackDefault = request.CardModeDefault ?? org.CardModeDefault;
            if (!modes.Contains(fallbackDefault))
            {
                // النمط الافتراضي يجب أن يكون من المسموح، وإلا فكل حساب جديد
                // يسقط إلى مسارٍ لم يقصده المدير.
                return BadRequest(new { message = "النمط الافتراضي يجب أن يكون ضمن الأنماط المسموحة" });
            }
            org.CardModeDefault = fallbackDefault;
        }

        if (request.CardOpenModeDailyCap is { } cap)
        {
            if (cap < 0)
            {
                return BadRequest(new { message = "السقف اليومي لا يكون سالباً" });
            }
            org.CardOpenModeDailyCap = cap;
        }

        org.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();

        return NoContent();
    }

    /// <summary>
    /// شاشة "تخصيص ملصق الباركود" (ARCHITECTURE.md §2.12) — إعداد تصميم
    /// الملصق (أبعاد + حقول ظاهرة) على مستوى المنظمة كلها، لتوليد نفس الشكل
    /// من أي جهاز يطبع منه أي مستخدم. توليد PDF الملصقات نفسه يتم في
    /// الفرونت إند مباشرة من بيانات المنتجات الموجودة أصلاً عبر /products.
    /// </summary>
    [HttpGet("me/barcode-template")]
    public async Task<ActionResult<BarcodeTemplateDto>> GetBarcodeTemplate()
    {
        var org = await _db.Organizations.FirstOrDefaultAsync();
        if (org is null) return NotFound();

        try
        {
            var dto = JsonSerializer.Deserialize<BarcodeTemplateDto>(
                org.BarcodeTemplateJson, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
            if (dto is not null) return dto;
        }
        catch (JsonException)
        {
            // نص غير صالح (حالة غير متوقَّعة) — يُستخدَم القالب الافتراضي أدناه.
        }
        return new BarcodeTemplateDto(40, 25, true, true, false);
    }

    [HttpPut("me/barcode-template")]
    [Authorize(Roles = "super_admin")]
    public async Task<IActionResult> UpdateBarcodeTemplate(BarcodeTemplateDto request)
    {
        var org = await _db.Organizations.FirstOrDefaultAsync();
        if (org is null) return NotFound();

        if (request.WidthMm < 15 || request.WidthMm > 200 || request.HeightMm < 10 || request.HeightMm > 200)
        {
            return BadRequest(new { message = "أبعاد الملصق يجب أن تكون بين 10 و200 ملم" });
        }

        org.BarcodeTemplateJson = JsonSerializer.Serialize(request);
        org.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();

        return NoContent();
    }

    /// <summary>
    /// قالب الإيصال — الشكل الذي يُطبع به كل إيصال في المنظمة.
    ///
    /// <para>مفتوح لأي مستخدم مسجَّل: نقطة البيع تحتاجه لتطبع، وقصرُه على
    /// المدير يجعل الكاشير عاجزاً عن الطباعة. والتعديل وحده محصور
    /// (راجع <see cref="UpdateReceiptTemplate"/>).</para>
    /// </summary>
    [HttpGet("me/receipt-template")]
    public async Task<ActionResult<ReceiptTemplateResponse>> GetReceiptTemplate()
    {
        var org = await _db.Organizations.FirstOrDefaultAsync();
        if (org is null) return NotFound();

        return new ReceiptTemplateResponse(
            ParseReceiptTemplate(org), org.TaxNumber, org.CommercialRegistry, org.LogoUrl);
    }

    [HttpPut("me/receipt-template")]
    [Authorize(Roles = "super_admin")]
    public async Task<IActionResult> UpdateReceiptTemplate(UpdateReceiptTemplateRequest request)
    {
        var org = await _db.Organizations.FirstOrDefaultAsync();
        if (org is null) return NotFound();

        if (!ReceiptPapers.All.Contains(request.Paper))
        {
            // مقاسٌ مجهول يُنتج PDF بأبعادٍ غير متوقَّعة عند كل طباعة، ولا
            // يكتشفه أحد إلا والورق يخرج مقصوصاً.
            return BadRequest(new
            {
                message = $"مقاس غير معروف: {request.Paper} — المتاح: {string.Join(", ", ReceiptPapers.All)}",
            });
        }

        org.TaxNumber = Trimmed(request.TaxNumber);
        org.CommercialRegistry = Trimmed(request.CommercialRegistry);
        // اللون يُفحَص لا يُخزَّن كما جاء: نصٌّ حرّ في حقل لونٍ يُقرأ
        // لاحقاً في محرِّك PDF، ولا يجوز أن يصل إليه ما لم يُتحقّق منه.
        var accent = request.AccentColor;
        if (accent is not null && !System.Text.RegularExpressions.Regex.IsMatch(accent, "^#[0-9a-fA-F]{6}$"))
        {
            return BadRequest(new { message = $"لون غير صالح: {accent}" });
        }

        org.ReceiptTemplateJson = JsonSerializer.Serialize(new ReceiptTemplateDto(
            request.Paper, request.ShowLogo, request.ShowTaxNumber,
            request.ShowCommercialRegistry, request.ShowQr,
            Trimmed(request.HeaderText), Trimmed(request.FooterText),
            Trimmed(request.Preset), accent,
            // يُقيَّد هنا لا في الواجهة وحدها: نداءٌ مباشر بقيمة ٩٩ يُنتج
            // إيصالاً بسطرٍ واحد على الصفحة.
            request.FontScale is null ? null : Math.Clamp(request.FontScale.Value, 0.8, 1.4),
            Trimmed(request.TableStyle), request.ShowPageBorder));

        // العرض القديم يتبع المقاس فلا يفترق مصدرا الحقيقة: شاشةٌ تقرأ
        // receiptWidthMm وأخرى تقرأ القالب كانتا ستطبعان بعرضين.
        org.ReceiptWidthMm = request.Paper == ReceiptPapers.Roll58 ? 58 : 80;
        org.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();

        return NoContent();
    }

    private static string? Trimmed(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    /// <summary>القالب المحفوظ، أو الافتراضي إن كان النصّ تالفاً.</summary>
    private static ReceiptTemplateDto ParseReceiptTemplate(Organization org)
    {
        try
        {
            var dto = JsonSerializer.Deserialize<ReceiptTemplateDto>(
                org.ReceiptTemplateJson, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
            if (dto is not null && ReceiptPapers.All.Contains(dto.Paper)) return dto;
        }
        catch (JsonException)
        {
            // نصّ غير صالح — يُستعمل الافتراضي أدناه بدل أن تتوقّف الطباعة.
        }

        return new ReceiptTemplateDto(
            ReceiptPapers.Roll80, true, true, false, false, null, "شكراً لتعاملكم معنا");
    }
}
