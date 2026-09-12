namespace KineticEnterprise.Api.Models;

/// <summary>
/// طلب إنشاء أصل ثابت جديد.
/// </summary>
public record CreateFixedAssetRequest(
    string AssetName,
    string AssetCode,
    string AssetCategory,
    DateTime AcquisitionDate,
    decimal AcquisitionCost,
    int UsefulLifeYears,
    decimal ResidualValue,
    string DepreciationMethod = "straight_line",
    decimal AnnualDepreciationRate = 0,
    string? CostCenter = null,
    string? Location = null
);

/// <summary>
/// طلب تحديث أصل ثابت.
/// </summary>
public record UpdateFixedAssetRequest(
    string? AssetName = null,
    string? AssetCode = null,
    string? AssetCategory = null,
    DateTime? AcquisitionDate = null,
    decimal? AcquisitionCost = null,
    int? UsefulLifeYears = null,
    decimal? ResidualValue = null,
    string? DepreciationMethod = null,
    decimal? AnnualDepreciationRate = null,
    string? CostCenter = null,
    string? Location = null,
    bool? IsActive = null,
    DateTime? DisposalDate = null,
    decimal? DisposalAmount = null,
    string? Status = null
);

/// <summary>
/// بيانات أصل ثابت — مُعادة من النقطة البرمجية إلى العميل.
/// </summary>
public class FixedAssetDto
{
    public Guid Id { get; set; }
    public string AssetName { get; set; } = "";
    public string AssetCode { get; set; } = "";
    public string AssetCategory { get; set; } = "";
    public DateTime AcquisitionDate { get; set; }
    public decimal AcquisitionCost { get; set; }
    public int UsefulLifeYears { get; set; }
    public decimal ResidualValue { get; set; }
    public string DepreciationMethod { get; set; } = "";
    public decimal AnnualDepreciationRate { get; set; }
    public string? CostCenter { get; set; }
    public string? Location { get; set; }
    public bool IsActive { get; set; }
    public DateTime? DisposalDate { get; set; }
    public decimal? DisposalAmount { get; set; }
    public string Status { get; set; } = "";
    public decimal CurrentBookValue { get; set; }
    public decimal AccumulatedDepreciation { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
}

/// <summary>
/// سجل الاهلاك — قيم الاهلاك الدوري لأصل.
/// </summary>
public class DepreciationRecordDto
{
    public Guid Id { get; set; }
    public int Month { get; set; }
    public int Year { get; set; }
    public decimal BeginningValue { get; set; }
    public decimal DepreciationAmount { get; set; }
    public decimal AccumulatedDepreciation { get; set; }
    public decimal EndingValue { get; set; }
    public bool IsRecorded { get; set; }
    public Guid? JournalEntryId { get; set; }
    public DateTime CreatedAt { get; set; }
}

/// <summary>
/// خيارات حساب الاهلاك للفترة المطلوبة.
/// </summary>
public record CalculateDepreciationRequest(
    int Month,
    int Year
);

/// <summary>
/// نتيجة حساب الاهلاك — المبالغ المحسوبة.
/// </summary>
public class DepreciationCalculationDto
{
    public Guid AssetId { get; set; }
    public string AssetName { get; set; } = "";
    public int Month { get; set; }
    public int Year { get; set; }
    public decimal BeginningValue { get; set; }
    public decimal DepreciationAmount { get; set; }
    public decimal AccumulatedDepreciation { get; set; }
    public decimal EndingValue { get; set; }
}

/// <summary>
/// طلب تسجيل قيد الاهلاك المحاسبي.
/// </summary>
public record RecordDepreciationRequest(
    Guid DepreciationId,
    string? Description = null
);

/// <summary>
/// بيانات الشركة التجارية — للقراءة والكتابة.
/// </summary>
public class CompanyInfoDto
{
    public Guid Id { get; set; }
    public string? CommercialRegistryNumber { get; set; }
    public string? TaxNumber { get; set; }
    public string LegalName { get; set; } = "";
    public string? TradeAddress { get; set; }
    public int? FoundationYear { get; set; }
    public string? CompanyType { get; set; }
    public string? BankAccountNumber { get; set; }
    public string? BankName { get; set; }
    public string? IBAN { get; set; }
    public string? Phone { get; set; }
    public string? Email { get; set; }
    public string? CurrencyCode { get; set; }
    public DateTime UpdatedAt { get; set; }
}

/// <summary>
/// طلب تحديث بيانات الشركة.
/// </summary>
public record UpdateCompanyInfoRequest(
    string? CommercialRegistryNumber = null,
    string? TaxNumber = null,
    string? LegalName = null,
    string? TradeAddress = null,
    int? FoundationYear = null,
    string? CompanyType = null,
    string? BankAccountNumber = null,
    string? BankName = null,
    string? IBAN = null,
    string? Phone = null,
    string? Email = null,
    string? CurrencyCode = null
);

/// <summary>
/// ملخص قيمة الأصول — للتقارير.
/// </summary>
public class AssetsValuationSummaryDto
{
    public decimal TotalAcquisitionCost { get; set; }
    public decimal TotalAccumulatedDepreciation { get; set; }
    public decimal TotalNetBookValue { get; set; }
    public int TotalAssetsCount { get; set; }
    public Dictionary<string, decimal> ByCategory { get; set; } = new();
}
