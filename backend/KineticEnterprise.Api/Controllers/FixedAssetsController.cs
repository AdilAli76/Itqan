using System.Security.Claims;
using System.IdentityModel.Tokens.Jwt;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;
using KineticEnterprise.Api.Services;
using KineticEnterprise.Api.Authorization;

namespace KineticEnterprise.Api.Controllers;

[ApiController]
[Route("api/fixed-assets")]
[Authorize]
[RequireModule("accounting")]
public class FixedAssetsController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly DepreciationService _depreciationService;

    public FixedAssetsController(AppDbContext db, DepreciationService depreciationService)
    {
        _db = db;
        _depreciationService = depreciationService;
    }

    private Guid GetOrganizationId() =>
        Guid.Parse(User.FindFirstValue("organization_id")!);

    private Guid GetUserId() =>
        Guid.Parse(User.FindFirstValue("sub")!);

    /// <summary>
    /// GET /api/fixed-assets
    /// الحصول على قائمة جميع الأصول الثابتة للمنظمة.
    /// </summary>
    [HttpGet]
    public async Task<ActionResult<List<FixedAssetDto>>> GetAll()
    {
        var orgId = GetOrganizationId();

        var assets = await _db.FixedAssets
            .Where(a => a.OrganizationId == orgId && !a.IsDeleted)
            .OrderByDescending(a => a.CreatedAt)
            .ToListAsync();

        var result = new List<FixedAssetDto>();

        foreach (var asset in assets)
        {
            var accumulatedDep = await _db.AssetDepreciations
                .Where(d => d.FixedAssetId == asset.Id)
                .OrderByDescending(d => d.Year)
                .ThenByDescending(d => d.Month)
                .Select(d => d.AccumulatedDepreciation)
                .FirstOrDefaultAsync();

            result.Add(new FixedAssetDto
            {
                Id = asset.Id,
                AssetName = asset.AssetName,
                AssetCode = asset.AssetCode,
                AssetCategory = asset.AssetCategory,
                AcquisitionDate = asset.AcquisitionDate,
                AcquisitionCost = asset.AcquisitionCost,
                UsefulLifeYears = asset.UsefulLifeYears,
                ResidualValue = asset.ResidualValue,
                DepreciationMethod = asset.DepreciationMethod,
                AnnualDepreciationRate = asset.AnnualDepreciationRate,
                CostCenter = asset.CostCenter,
                Location = asset.Location,
                IsActive = asset.IsActive,
                DisposalDate = asset.DisposalDate,
                DisposalAmount = asset.DisposalAmount,
                Status = asset.Status,
                AccumulatedDepreciation = accumulatedDep,
                CurrentBookValue = asset.AcquisitionCost - accumulatedDep,
                CreatedAt = asset.CreatedAt,
                UpdatedAt = asset.UpdatedAt
            });
        }

        return result;
    }

    /// <summary>
    /// GET /api/fixed-assets/{id}
    /// الحصول على تفاصيل أصل ثابت محدد.
    /// </summary>
    [HttpGet("{id:guid}")]
    public async Task<ActionResult<FixedAssetDto>> GetById(Guid id)
    {
        var orgId = GetOrganizationId();

        var asset = await _db.FixedAssets
            .FirstOrDefaultAsync(a => a.Id == id && a.OrganizationId == orgId && !a.IsDeleted);

        if (asset is null)
            return NotFound(new { message = "الأصل المطلوب غير موجود" });

        var accumulatedDep = await _db.AssetDepreciations
            .Where(d => d.FixedAssetId == asset.Id)
            .OrderByDescending(d => d.Year)
            .ThenByDescending(d => d.Month)
            .Select(d => d.AccumulatedDepreciation)
            .FirstOrDefaultAsync();

        return new FixedAssetDto
        {
            Id = asset.Id,
            AssetName = asset.AssetName,
            AssetCode = asset.AssetCode,
            AssetCategory = asset.AssetCategory,
            AcquisitionDate = asset.AcquisitionDate,
            AcquisitionCost = asset.AcquisitionCost,
            UsefulLifeYears = asset.UsefulLifeYears,
            ResidualValue = asset.ResidualValue,
            DepreciationMethod = asset.DepreciationMethod,
            AnnualDepreciationRate = asset.AnnualDepreciationRate,
            CostCenter = asset.CostCenter,
            Location = asset.Location,
            IsActive = asset.IsActive,
            DisposalDate = asset.DisposalDate,
            DisposalAmount = asset.DisposalAmount,
            Status = asset.Status,
            AccumulatedDepreciation = accumulatedDep,
            CurrentBookValue = asset.AcquisitionCost - accumulatedDep,
            CreatedAt = asset.CreatedAt,
            UpdatedAt = asset.UpdatedAt
        };
    }

    /// <summary>
    /// POST /api/fixed-assets
    /// إنشاء أصل ثابت جديد.
    /// </summary>
    [HttpPost]
    [RequirePermission("fixed_assets.manage")]
    public async Task<ActionResult<FixedAssetDto>> Create(CreateFixedAssetRequest request)
    {
        // التحقق من صحة البيانات
        if (string.IsNullOrWhiteSpace(request.AssetName))
            return BadRequest(new { message = "اسم الأصل إلزامي" });

        if (string.IsNullOrWhiteSpace(request.AssetCode))
            return BadRequest(new { message = "رمز الأصل إلزامي" });

        if (request.AcquisitionCost <= 0)
            return BadRequest(new { message = "قيمة الاستحواذ يجب أن تكون موجبة" });

        if (request.UsefulLifeYears <= 0)
            return BadRequest(new { message = "العمر الافتراضي يجب أن يكون موجب السنوات" });

        var orgId = GetOrganizationId();
        var userId = GetUserId();

        // التحقق من عدم تكرار رمز الأصل
        var existingAsset = await _db.FixedAssets
            .FirstOrDefaultAsync(a => a.AssetCode == request.AssetCode && a.OrganizationId == orgId);

        if (existingAsset is not null)
            return BadRequest(new { message = "رمز الأصل موجود بالفعل" });

        var asset = new FixedAsset
        {
            OrganizationId = orgId,
            AssetName = request.AssetName.Trim(),
            AssetCode = request.AssetCode.Trim(),
            AssetCategory = request.AssetCategory.Trim(),
            AcquisitionDate = request.AcquisitionDate,
            AcquisitionCost = request.AcquisitionCost,
            UsefulLifeYears = request.UsefulLifeYears,
            ResidualValue = request.ResidualValue,
            DepreciationMethod = request.DepreciationMethod,
            AnnualDepreciationRate = request.AnnualDepreciationRate,
            CostCenter = request.CostCenter?.Trim(),
            Location = request.Location?.Trim(),
            IsActive = true,
            Status = "active",
            CreatedBy = userId,
            UpdatedBy = userId,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };

        _db.FixedAssets.Add(asset);
        await _db.SaveChangesAsync();

        return CreatedAtAction(nameof(GetById), new { id = asset.Id }, new FixedAssetDto
        {
            Id = asset.Id,
            AssetName = asset.AssetName,
            AssetCode = asset.AssetCode,
            AssetCategory = asset.AssetCategory,
            AcquisitionDate = asset.AcquisitionDate,
            AcquisitionCost = asset.AcquisitionCost,
            UsefulLifeYears = asset.UsefulLifeYears,
            ResidualValue = asset.ResidualValue,
            DepreciationMethod = asset.DepreciationMethod,
            AnnualDepreciationRate = asset.AnnualDepreciationRate,
            CostCenter = asset.CostCenter,
            Location = asset.Location,
            IsActive = asset.IsActive,
            Status = asset.Status,
            AccumulatedDepreciation = 0,
            CurrentBookValue = asset.AcquisitionCost,
            CreatedAt = asset.CreatedAt,
            UpdatedAt = asset.UpdatedAt
        });
    }

    /// <summary>
    /// PUT /api/fixed-assets/{id}
    /// تحديث أصل ثابت.
    /// </summary>
    [HttpPut("{id:guid}")]
    [RequirePermission("fixed_assets.manage")]
    public async Task<IActionResult> Update(Guid id, UpdateFixedAssetRequest request)
    {
        var orgId = GetOrganizationId();
        var userId = GetUserId();

        var asset = await _db.FixedAssets
            .FirstOrDefaultAsync(a => a.Id == id && a.OrganizationId == orgId && !a.IsDeleted);

        if (asset is null)
            return NotFound(new { message = "الأصل المطلوب غير موجود" });

        // تحديث الحقول المطلوبة فقط
        if (!string.IsNullOrWhiteSpace(request.AssetName))
            asset.AssetName = request.AssetName.Trim();

        if (!string.IsNullOrWhiteSpace(request.AssetCode))
        {
            // التحقق من عدم تكرار الرمز الجديد
            var other = await _db.FixedAssets
                .FirstOrDefaultAsync(a => a.AssetCode == request.AssetCode &&
                    a.OrganizationId == orgId && a.Id != id);

            if (other is not null)
                return BadRequest(new { message = "رمز الأصل موجود بالفعل" });

            asset.AssetCode = request.AssetCode.Trim();
        }

        if (!string.IsNullOrWhiteSpace(request.AssetCategory))
            asset.AssetCategory = request.AssetCategory.Trim();

        if (request.AcquisitionDate.HasValue)
            asset.AcquisitionDate = request.AcquisitionDate.Value;

        if (request.AcquisitionCost.HasValue && request.AcquisitionCost > 0)
            asset.AcquisitionCost = request.AcquisitionCost.Value;

        if (request.UsefulLifeYears.HasValue && request.UsefulLifeYears > 0)
            asset.UsefulLifeYears = request.UsefulLifeYears.Value;

        if (request.ResidualValue.HasValue)
            asset.ResidualValue = request.ResidualValue.Value;

        if (!string.IsNullOrWhiteSpace(request.DepreciationMethod))
            asset.DepreciationMethod = request.DepreciationMethod;

        if (request.AnnualDepreciationRate.HasValue)
            asset.AnnualDepreciationRate = request.AnnualDepreciationRate.Value;

        if (request.CostCenter is not null)
            asset.CostCenter = request.CostCenter.Trim();

        if (request.Location is not null)
            asset.Location = request.Location.Trim();

        if (request.IsActive.HasValue)
            asset.IsActive = request.IsActive.Value;

        if (request.DisposalDate.HasValue)
            asset.DisposalDate = request.DisposalDate.Value;

        if (request.DisposalAmount.HasValue)
            asset.DisposalAmount = request.DisposalAmount.Value;

        if (!string.IsNullOrWhiteSpace(request.Status))
            asset.Status = request.Status;

        asset.UpdatedBy = userId;
        asset.UpdatedAt = DateTime.UtcNow;

        await _db.SaveChangesAsync();
        return NoContent();
    }

    /// <summary>
    /// DELETE /api/fixed-assets/{id}
    /// حذف أصل ثابت (soft delete).
    /// </summary>
    [HttpDelete("{id:guid}")]
    [RequirePermission("fixed_assets.manage")]
    public async Task<IActionResult> Delete(Guid id)
    {
        var orgId = GetOrganizationId();

        var asset = await _db.FixedAssets
            .FirstOrDefaultAsync(a => a.Id == id && a.OrganizationId == orgId && !a.IsDeleted);

        if (asset is null)
            return NotFound(new { message = "الأصل المطلوب غير موجود" });

        asset.IsDeleted = true;
        asset.UpdatedAt = DateTime.UtcNow;

        await _db.SaveChangesAsync();
        return NoContent();
    }

    /// <summary>
    /// GET /api/fixed-assets/{id}/depreciation
    /// الحصول على سجل الاهلاك الكامل لأصل معين.
    /// </summary>
    [HttpGet("{id:guid}/depreciation")]
    public async Task<ActionResult<List<DepreciationRecordDto>>> GetDepreciation(Guid id)
    {
        var orgId = GetOrganizationId();

        // تحقق من وجود الأصل
        var asset = await _db.FixedAssets
            .FirstOrDefaultAsync(a => a.Id == id && a.OrganizationId == orgId && !a.IsDeleted);

        if (asset is null)
            return NotFound(new { message = "الأصل المطلوب غير موجود" });

        var records = await _depreciationService.GetAssetDepreciationHistoryAsync(id, orgId);
        return records;
    }

    /// <summary>
    /// POST /api/fixed-assets/{id}/calculate-depreciation
    /// حساب الاهلاك للفترة المطلوبة.
    /// </summary>
    [HttpPost("{id:guid}/calculate-depreciation")]
    [RequirePermission("fixed_assets.manage")]
    public async Task<ActionResult<DepreciationCalculationDto>> CalculateDepreciation(
        Guid id,
        CalculateDepreciationRequest request)
    {
        if (request.Month < 1 || request.Month > 12)
            return BadRequest(new { message = "رقم الشهر يجب أن يكون بين 1 و 12" });

        if (request.Year < 2000 || request.Year > DateTime.UtcNow.Year + 1)
            return BadRequest(new { message = "السنة غير صحيحة" });

        try
        {
            var orgId = GetOrganizationId();
            var calculation = await _depreciationService.CalculateDepreciationAsync(id, request.Month, request.Year, orgId);
            return Ok(calculation);
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }

    /// <summary>
    /// POST /api/fixed-assets/{id}/record-depreciation
    /// تسجيل سجل الاهلاك في قاعدة البيانات.
    /// </summary>
    [HttpPost("{id:guid}/record-depreciation")]
    [RequirePermission("fixed_assets.manage")]
    public async Task<ActionResult<DepreciationRecordDto>> RecordDepreciation(
        Guid id,
        CalculateDepreciationRequest request)
    {
        try
        {
            var orgId = GetOrganizationId();

            // حساب الاهلاك أولاً
            var calculation = await _depreciationService.CalculateDepreciationAsync(id, request.Month, request.Year, orgId);

            // تسجيل السجل
            var depreciation = await _depreciationService.RecordDepreciationAsync(calculation, orgId);

            return CreatedAtAction(nameof(GetById), new { id = id }, new DepreciationRecordDto
            {
                Id = depreciation.Id,
                Month = depreciation.Month,
                Year = depreciation.Year,
                BeginningValue = depreciation.BeginningValue,
                DepreciationAmount = depreciation.DepreciationAmount,
                AccumulatedDepreciation = depreciation.AccumulatedDepreciation,
                EndingValue = depreciation.EndingValue,
                IsRecorded = depreciation.IsRecorded,
                JournalEntryId = depreciation.JournalEntryId,
                CreatedAt = depreciation.CreatedAt
            });
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }

    /// <summary>
    /// GET /api/fixed-assets/summary/valuation
    /// ملخص قيمة الأصول — إجمالي التكلفة والاهلاك والقيمة الدفترية.
    /// </summary>
    [HttpGet("summary/valuation")]
    public async Task<ActionResult<AssetsValuationSummaryDto>> GetValuationSummary()
    {
        var orgId = GetOrganizationId();
        var summary = await _depreciationService.GetAssetsValuationSummaryAsync(orgId);
        return Ok(summary);
    }

    /// <summary>
    /// GET /api/fixed-assets/pending-depreciation
    /// الحصول على الأصول المستحقة الاهلاك للفترة المطلوبة.
    /// </summary>
    [HttpGet("pending-depreciation")]
    [RequirePermission("fixed_assets.manage")]
    public async Task<ActionResult<List<FixedAssetDto>>> GetPendingDepreciation(
        [FromQuery] int month,
        [FromQuery] int year)
    {
        if (month < 1 || month > 12)
            return BadRequest(new { message = "رقم الشهر يجب أن يكون بين 1 و 12" });

        var orgId = GetOrganizationId();
        var assets = await _depreciationService.GetAssetsRequiringDepreciationAsync(month, year, orgId);
        return Ok(assets);
    }
}
