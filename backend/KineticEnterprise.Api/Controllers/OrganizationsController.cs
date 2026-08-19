using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Data;

namespace KineticEnterprise.Api.Controllers;

public record BrandingResponse(string DisplayName, string? LogoUrl, string PrimaryColor, string SecondaryColor, string CurrencySymbol, string NavLayout, string Edition);
public record UpdateBrandingRequest(string DisplayName, string PrimaryColor, string SecondaryColor, string NavLayout);
public record SetLogoRequest(Guid? AttachmentId);

public record OrganizationSettingsDto(string CurrencyCode, string CurrencySymbol, string Locale, decimal TaxRate, int PasswordMinLength, double ReceiptWidthMm, bool PosAllowOpenProduct);
public record UpdateSettingsRequest(string CurrencyCode, string CurrencySymbol, string Locale, decimal TaxRate, int PasswordMinLength, double ReceiptWidthMm, bool PosAllowOpenProduct);

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

        return new BrandingResponse(org.DisplayName, org.LogoUrl, org.PrimaryColor, org.SecondaryColor, org.CurrencySymbol, org.NavLayout, org.Edition);
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

        return new OrganizationSettingsDto(org.CurrencyCode, org.CurrencySymbol, org.Locale, org.TaxRate, org.PasswordMinLength, org.ReceiptWidthMm, org.PosAllowOpenProduct);
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
}
