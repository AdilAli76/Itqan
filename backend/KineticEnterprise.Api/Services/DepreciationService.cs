using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Services;

/// <summary>
/// خدمة حساب الاهلاك — حسابات الاهلاك بطرقه المختلفة وتسجيل المستندات.
/// </summary>
public class DepreciationService
{
    private readonly AppDbContext _db;

    public DepreciationService(AppDbContext db) => _db = db;

    /// <summary>
    /// حساب مبلغ الاهلاك الشهري/السنوي لأصل معين بناءً على الطريقة المستخدمة.
    /// </summary>
    public async Task<DepreciationCalculationDto> CalculateDepreciationAsync(
        Guid assetId,
        int month,
        int year,
        Guid organizationId)
    {
        var asset = await _db.FixedAssets
            .FirstOrDefaultAsync(a => a.Id == assetId && a.OrganizationId == organizationId);

        if (asset is null)
            throw new InvalidOperationException("الأصل المطلوب غير موجود");

        if (asset.IsDeleted || asset.Status == "disposed")
            throw new InvalidOperationException("لا يمكن حساب اهلاك لأصل موقوف أو مستبعد");

        // الحصول على آخر سجل اهلاك
        var lastDepreciation = await _db.AssetDepreciations
            .Where(d => d.FixedAssetId == assetId)
            .OrderByDescending(d => d.Year)
            .ThenByDescending(d => d.Month)
            .FirstOrDefaultAsync();

        // القيمة الدفترية في البداية
        decimal beginningValue = lastDepreciation?.EndingValue ?? asset.AcquisitionCost;

        // حساب مبلغ الاهلاك
        decimal depreciationAmount = asset.DepreciationMethod switch
        {
            "straight_line" => CalculateStraightLineDepreciation(asset, beginningValue),
            "declining_balance" => CalculateDecliningBalanceDepreciation(asset, beginningValue),
            _ => 0m
        };

        // إجمالي الاهلاك المتراكم
        decimal accumulatedDepreciation = (lastDepreciation?.AccumulatedDepreciation ?? 0) + depreciationAmount;

        // القيمة الدفترية في النهاية
        decimal endingValue = asset.AcquisitionCost - accumulatedDepreciation;

        // التأكد من عدم تجاوز القيمة المتبقية
        if (endingValue < asset.ResidualValue)
        {
            depreciationAmount -= (asset.ResidualValue - endingValue);
            endingValue = asset.ResidualValue;
            accumulatedDepreciation = asset.AcquisitionCost - endingValue;
        }

        return new DepreciationCalculationDto
        {
            AssetId = assetId,
            AssetName = asset.AssetName,
            Month = month,
            Year = year,
            BeginningValue = beginningValue,
            DepreciationAmount = depreciationAmount,
            AccumulatedDepreciation = accumulatedDepreciation,
            EndingValue = endingValue
        };
    }

    /// <summary>
    /// حساب الاهلاك بطريقة القسط الثابت (Straight Line).
    /// الصيغة: (قيمة الاستحواذ - القيمة المتبقية) / عدد السنوات
    /// </summary>
    private decimal CalculateStraightLineDepreciation(FixedAsset asset, decimal bookValue)
    {
        // التحقق من أن الأصل لم يصل إلى القيمة المتبقية
        if (bookValue <= asset.ResidualValue)
            return 0m;

        decimal depreciableAmount = asset.AcquisitionCost - asset.ResidualValue;
        decimal annualDepreciation = depreciableAmount / asset.UsefulLifeYears;

        // اهلاك شهري = اهلاك سنوي / 12
        return Math.Round(annualDepreciation / 12, 2);
    }

    /// <summary>
    /// حساب الاهلاك بطريقة التناقص (Declining Balance).
    /// تطبق معدل ثابت على القيمة الدفترية المتناقصة.
    /// </summary>
    private decimal CalculateDecliningBalanceDepreciation(FixedAsset asset, decimal bookValue)
    {
        // التحقق من أن الأصل لم يصل إلى القيمة المتبقية
        if (bookValue <= asset.ResidualValue)
            return 0m;

        // معدل الاهلاك السنوي (إذا لم يُحدَّد يُحسب من العمر الافتراضي)
        decimal rate = asset.AnnualDepreciationRate > 0
            ? asset.AnnualDepreciationRate / 100
            : (2m / asset.UsefulLifeYears);

        // الاهلاك الشهري = القيمة الدفترية × المعدل السنوي / 12
        decimal monthlyDepreciation = Math.Round(bookValue * rate / 12, 2);

        return monthlyDepreciation;
    }

    /// <summary>
    /// تسجيل سجل اهلاك جديد في قاعدة البيانات.
    /// </summary>
    public async Task<AssetDepreciation> RecordDepreciationAsync(
        DepreciationCalculationDto calculation,
        Guid organizationId)
    {
        // التحقق من عدم وجود سجل مكرر للشهر والسنة نفسيهما
        var existingRecord = await _db.AssetDepreciations
            .FirstOrDefaultAsync(d =>
                d.FixedAssetId == calculation.AssetId &&
                d.Month == calculation.Month &&
                d.Year == calculation.Year);

        if (existingRecord is not null)
            throw new InvalidOperationException("سجل اهلاك موجود بالفعل لهذه الفترة");

        var depreciation = new AssetDepreciation
        {
            FixedAssetId = calculation.AssetId,
            OrganizationId = organizationId,
            Month = calculation.Month,
            Year = calculation.Year,
            BeginningValue = calculation.BeginningValue,
            DepreciationAmount = calculation.DepreciationAmount,
            AccumulatedDepreciation = calculation.AccumulatedDepreciation,
            EndingValue = calculation.EndingValue,
            IsRecorded = false,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };

        _db.AssetDepreciations.Add(depreciation);
        await _db.SaveChangesAsync();

        return depreciation;
    }

    /// <summary>
    /// الحصول على جميع سجلات الاهلاك لأصل معين.
    /// </summary>
    public async Task<List<DepreciationRecordDto>> GetAssetDepreciationHistoryAsync(
        Guid assetId,
        Guid organizationId)
    {
        return await _db.AssetDepreciations
            .Where(d => d.FixedAssetId == assetId && d.OrganizationId == organizationId)
            .OrderBy(d => d.Year)
            .ThenBy(d => d.Month)
            .Select(d => new DepreciationRecordDto
            {
                Id = d.Id,
                Month = d.Month,
                Year = d.Year,
                BeginningValue = d.BeginningValue,
                DepreciationAmount = d.DepreciationAmount,
                AccumulatedDepreciation = d.AccumulatedDepreciation,
                EndingValue = d.EndingValue,
                IsRecorded = d.IsRecorded,
                JournalEntryId = d.JournalEntryId,
                CreatedAt = d.CreatedAt
            })
            .ToListAsync();
    }

    /// <summary>
    /// حساب ملخص قيمة الأصول — إجمالي التكلفة والاهلاك والقيمة الدفترية.
    /// </summary>
    public async Task<AssetsValuationSummaryDto> GetAssetsValuationSummaryAsync(Guid organizationId)
    {
        var assets = await _db.FixedAssets
            .Where(a => a.OrganizationId == organizationId && !a.IsDeleted && a.Status != "disposed")
            .ToListAsync();

        if (assets.Count == 0)
            return new AssetsValuationSummaryDto();

        var depreciationsRaw = await _db.AssetDepreciations
            .Where(d => assets.Select(a => a.Id).Contains(d.FixedAssetId))
            .ToListAsync();

        var depreciations = depreciationsRaw
            .GroupBy(d => d.FixedAssetId)
            .Select(g => new
            {
                AssetId = g.Key,
                AccumulatedDepreciation = g.OrderByDescending(d => d.Year).ThenByDescending(d => d.Month)
                    .FirstOrDefault()?.AccumulatedDepreciation ?? 0m
            })
            .ToList();

        var summary = new AssetsValuationSummaryDto
        {
            TotalAssetsCount = assets.Count,
            TotalAcquisitionCost = assets.Sum(a => a.AcquisitionCost),
            TotalAccumulatedDepreciation = depreciations.Sum(d => d.AccumulatedDepreciation)
        };

        summary.TotalNetBookValue = summary.TotalAcquisitionCost - summary.TotalAccumulatedDepreciation;

        // التفصيل حسب التصنيف
        var byCategory = assets.GroupBy(a => a.AssetCategory)
            .ToDictionary(
                g => g.Key,
                g => g.Sum(a => a.AcquisitionCost)
            );

        summary.ByCategory = byCategory;

        return summary;
    }

    /// <summary>
    /// وسم سجل اهلاك كمسجل محاسبياً.
    /// </summary>
    public async Task MarkDepreciationAsRecordedAsync(
        Guid depreciationId,
        Guid journalEntryId,
        Guid organizationId)
    {
        var depreciation = await _db.AssetDepreciations
            .FirstOrDefaultAsync(d => d.Id == depreciationId && d.OrganizationId == organizationId);

        if (depreciation is null)
            throw new InvalidOperationException("سجل الاهلاك غير موجود");

        depreciation.IsRecorded = true;
        depreciation.JournalEntryId = journalEntryId;
        depreciation.UpdatedAt = DateTime.UtcNow;

        await _db.SaveChangesAsync();
    }

    /// <summary>
    /// الحصول على الأصول المستحقة الاهلاك للفترة المعطاة.
    /// </summary>
    public async Task<List<FixedAssetDto>> GetAssetsRequiringDepreciationAsync(
        int month,
        int year,
        Guid organizationId)
    {
        var assets = await _db.FixedAssets
            .Where(a => a.OrganizationId == organizationId &&
                        !a.IsDeleted &&
                        a.Status == "active" &&
                        a.AcquisitionDate <= new DateTime(year, month, DateTime.DaysInMonth(year, month)))
            .ToListAsync();

        var result = new List<FixedAssetDto>();

        foreach (var asset in assets)
        {
            // تحقق من عدم وجود سجل اهلاك للفترة نفسها
            var hasRecord = await _db.AssetDepreciations
                .AnyAsync(d => d.FixedAssetId == asset.Id && d.Month == month && d.Year == year);

            if (!hasRecord)
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
                    Status = asset.Status,
                    AccumulatedDepreciation = accumulatedDep,
                    CurrentBookValue = asset.AcquisitionCost - accumulatedDep,
                    CreatedAt = asset.CreatedAt,
                    UpdatedAt = asset.UpdatedAt
                });
            }
        }

        return result;
    }
}
