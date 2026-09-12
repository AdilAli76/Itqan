using System.Security.Claims;
using System.IdentityModel.Tokens.Jwt;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;
using KineticEnterprise.Api.Authorization;

namespace KineticEnterprise.Api.Controllers;

[ApiController]
[Route("api/company-info")]
[Authorize]
[RequireModule("accounting")]
public class CompanyInfoController : ControllerBase
{
    private readonly AppDbContext _db;

    public CompanyInfoController(AppDbContext db) => _db = db;

    private Guid GetOrganizationId() =>
        Guid.Parse(User.FindFirstValue("organization_id")!);

    private Guid GetUserId() =>
        Guid.Parse(User.FindFirstValue("sub")!);

    /// <summary>
    /// GET /api/company-info
    /// الحصول على بيانات الشركة التجارية.
    /// </summary>
    [HttpGet]
    public async Task<ActionResult<CompanyInfoDto>> GetCompanyInfo()
    {
        var orgId = GetOrganizationId();

        var companyInfo = await _db.CompanyInfos
            .FirstOrDefaultAsync(c => c.OrganizationId == orgId);

        if (companyInfo is null)
            return NotFound(new { message = "بيانات الشركة لم تُسجَّل بعد" });

        return new CompanyInfoDto
        {
            Id = companyInfo.Id,
            CommercialRegistryNumber = companyInfo.CommercialRegistryNumber,
            TaxNumber = companyInfo.TaxNumber,
            LegalName = companyInfo.LegalName,
            TradeAddress = companyInfo.TradeAddress,
            FoundationYear = companyInfo.FoundationYear,
            CompanyType = companyInfo.CompanyType,
            BankAccountNumber = companyInfo.BankAccountNumber,
            BankName = companyInfo.BankName,
            IBAN = companyInfo.IBAN,
            Phone = companyInfo.Phone,
            Email = companyInfo.Email,
            CurrencyCode = companyInfo.CurrencyCode,
            UpdatedAt = companyInfo.UpdatedAt
        };
    }

    /// <summary>
    /// PUT /api/company-info
    /// تحديث بيانات الشركة التجارية.
    /// </summary>
    [HttpPut]
    [RequirePermission("company_info.manage")]
    public async Task<ActionResult<CompanyInfoDto>> UpdateCompanyInfo(UpdateCompanyInfoRequest request)
    {
        // التحقق من أن لدينا على الأقل اسم قانوني
        if (!string.IsNullOrWhiteSpace(request.LegalName) &&
            string.IsNullOrWhiteSpace(request.LegalName.Trim()))
            return BadRequest(new { message = "الاسم القانوني لا يمكن أن يكون فارغاً" });

        var orgId = GetOrganizationId();
        var userId = GetUserId();

        var companyInfo = await _db.CompanyInfos
            .FirstOrDefaultAsync(c => c.OrganizationId == orgId);

        // إنشاء سجل جديد إذا لم يكن موجوداً
        if (companyInfo is null)
        {
            companyInfo = new CompanyInfo
            {
                OrganizationId = orgId,
                LegalName = request.LegalName ?? ""
            };

            _db.CompanyInfos.Add(companyInfo);
        }

        // تحديث الحقول المطلوبة
        if (!string.IsNullOrWhiteSpace(request.CommercialRegistryNumber))
            companyInfo.CommercialRegistryNumber = request.CommercialRegistryNumber.Trim();

        if (!string.IsNullOrWhiteSpace(request.TaxNumber))
            companyInfo.TaxNumber = request.TaxNumber.Trim();

        if (!string.IsNullOrWhiteSpace(request.LegalName))
            companyInfo.LegalName = request.LegalName.Trim();

        if (!string.IsNullOrWhiteSpace(request.TradeAddress))
            companyInfo.TradeAddress = request.TradeAddress.Trim();

        if (request.FoundationYear.HasValue && request.FoundationYear > 0)
            companyInfo.FoundationYear = request.FoundationYear.Value;

        if (!string.IsNullOrWhiteSpace(request.CompanyType))
            companyInfo.CompanyType = request.CompanyType.Trim();

        if (!string.IsNullOrWhiteSpace(request.BankAccountNumber))
            companyInfo.BankAccountNumber = request.BankAccountNumber.Trim();

        if (!string.IsNullOrWhiteSpace(request.BankName))
            companyInfo.BankName = request.BankName.Trim();

        if (!string.IsNullOrWhiteSpace(request.IBAN))
            companyInfo.IBAN = request.IBAN.Trim();

        if (!string.IsNullOrWhiteSpace(request.Phone))
            companyInfo.Phone = request.Phone.Trim();

        if (!string.IsNullOrWhiteSpace(request.Email))
            companyInfo.Email = request.Email.Trim();

        if (!string.IsNullOrWhiteSpace(request.CurrencyCode))
            companyInfo.CurrencyCode = request.CurrencyCode.Trim();

        companyInfo.UpdatedAt = DateTime.UtcNow;
        companyInfo.UpdatedBy = userId;

        await _db.SaveChangesAsync();

        return Ok(new CompanyInfoDto
        {
            Id = companyInfo.Id,
            CommercialRegistryNumber = companyInfo.CommercialRegistryNumber,
            TaxNumber = companyInfo.TaxNumber,
            LegalName = companyInfo.LegalName,
            TradeAddress = companyInfo.TradeAddress,
            FoundationYear = companyInfo.FoundationYear,
            CompanyType = companyInfo.CompanyType,
            BankAccountNumber = companyInfo.BankAccountNumber,
            BankName = companyInfo.BankName,
            IBAN = companyInfo.IBAN,
            Phone = companyInfo.Phone,
            Email = companyInfo.Email,
            CurrencyCode = companyInfo.CurrencyCode,
            UpdatedAt = companyInfo.UpdatedAt
        });
    }
}
