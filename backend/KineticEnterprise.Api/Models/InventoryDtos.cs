using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;

namespace KineticEnterprise.Api.Models;

// ============================================================================
// Batch Management
// ============================================================================

public record CreateBatchRequest(
    [Required] Guid ProductId,
    [Required, MaxLength(100)] string BatchNumber,
    [Required] DateTime ManufacturingDate,
    DateTime? ExpiryDate,
    [Required] int QuantityReceived,
    [Required] decimal CostPerUnit,
    Guid? WarehouseId,
    Guid? SupplierId,
    string? CertificateOfAnalysisJson
);

public record UpdateBatchRequest(
    [MaxLength(100)] string? BatchNumber,
    DateTime? ManufacturingDate,
    DateTime? ExpiryDate,
    int? QuantityReceived,
    decimal? CostPerUnit,
    Guid? WarehouseId,
    string? QualityStatus
);

public class ProductBatchDto
{
    public Guid Id { get; set; }
    public Guid ProductId { get; set; }
    [MaxLength(100)]
    public string BatchNumber { get; set; } = "";
    public DateTime ManufacturingDate { get; set; }
    public DateTime? ExpiryDate { get; set; }
    public int QuantityReceived { get; set; }
    public int QuantityAvailable { get; set; }
    public Guid? WarehouseId { get; set; }
    public string? WarehouseName { get; set; }
    public decimal CostPerUnit { get; set; }
    public Guid? SupplierId { get; set; }
    public string QualityStatus { get; set; } = "";
    public bool IsExpiring { get; set; }
    public int DaysToExpiry { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
}

public class BatchDetailsDto : ProductBatchDto
{
    public List<SerialNumberDto> SerialNumbers { get; set; } = new();
    public List<BatchMovementDto> RecentMovements { get; set; } = new();
    public decimal TotalValue { get; set; }
}

// ============================================================================
// Serial Numbers
// ============================================================================

public record AddSerialNumbersRequest(
    [Required] Guid BatchId,
    [Required] List<string> SerialNumbers,
    List<string>? Barcodes
);

public class SerialNumberDto
{
    public Guid Id { get; set; }
    public Guid BatchId { get; set; }
    public string SerialNumber { get; set; } = "";
    public string? Barcode { get; set; }
    public string Status { get; set; } = "";
    public string? WarehouseLocation { get; set; }
    public DateTime? SoldAt { get; set; }
    public Guid? InvoiceId { get; set; }
    public DateTime CreatedAt { get; set; }
}

// ============================================================================
// Batch Movements
// ============================================================================

public record RecordBatchMovementRequest(
    [Required] Guid BatchId,
    [Required] string MovementType,
    [Required] int Quantity,
    string? ReferenceType,
    Guid? ReferenceId,
    Guid? FromWarehouseId,
    Guid? ToWarehouseId,
    string? Notes
);

public class BatchMovementDto
{
    public Guid Id { get; set; }
    public Guid BatchId { get; set; }
    public string MovementType { get; set; } = "";
    public int Quantity { get; set; }
    public string? ReferenceType { get; set; }
    public Guid? ReferenceId { get; set; }
    public string? FromWarehouse { get; set; }
    public string? ToWarehouse { get; set; }
    public string? Notes { get; set; }
    public Guid? CreatedBy { get; set; }
    public string? CreatedByName { get; set; }
    public DateTime CreatedAt { get; set; }
}

// ============================================================================
// Inventory Alerts
// ============================================================================

public record CreateAlertRuleRequest(
    Guid? ProductId,
    [Required] string AlertType,
    int? Threshold,
    int? ExpiryWarningDays,
    int? SlowMovingDays,
    string ActionType = "notification"
);

public class InventoryAlertDto
{
    public Guid Id { get; set; }
    public Guid ProductId { get; set; }
    public string ProductName { get; set; } = "";
    public string AlertType { get; set; } = "";
    public string Severity { get; set; } = "";
    public string Message { get; set; } = "";
    public string? SuggestedAction { get; set; }
    public bool IsResolved { get; set; }
    public DateTime CreatedAt { get; set; }
}

public record QueryAlertsRequest(
    string? AlertType = null,
    string? Severity = null,
    bool? IsResolved = null,
    int Limit = 50,
    int Offset = 0
);

// ============================================================================
// Stock Transfers
// ============================================================================

public record CreateStockTransferRequest(
    [Required] Guid FromWarehouseId,
    [Required] Guid ToWarehouseId,
    [Required] List<TransferItemRequest> Items,
    DateTime? ExpectedDeliveryDate
);

public record TransferItemRequest(
    [Required] Guid ProductId,
    Guid? BatchId,
    [Required] int Quantity,
    string? Notes
);

public class StockTransferDto
{
    public Guid Id { get; set; }
    public string FromWarehouse { get; set; } = "";
    public string ToWarehouse { get; set; } = "";
    public DateTime TransferDate { get; set; }
    public DateTime? ExpectedDeliveryDate { get; set; }
    public DateTime? ActualDeliveryDate { get; set; }
    public string Status { get; set; } = "";
    public int TotalItems { get; set; }
    public int ItemsReceived { get; set; }
    public DateTime CreatedAt { get; set; }
}

public class StockTransferDetailsDto : StockTransferDto
{
    public List<TransferItemDto> Items { get; set; } = new();
}

public class TransferItemDto
{
    public Guid Id { get; set; }
    public Guid ProductId { get; set; }
    public string ProductName { get; set; } = "";
    public string? BatchNumber { get; set; }
    public int Quantity { get; set; }
    public int QuantityReceived { get; set; }
    public string? Notes { get; set; }
}

// ============================================================================
// Inventory Reports & Analytics
// ============================================================================

public class InventoryValuationSummaryDto
{
    public decimal TotalAcquisitionCost { get; set; }
    public decimal TotalCurrentValue { get; set; }
    public int TotalItems { get; set; }
    public Dictionary<string, decimal> ByCategory { get; set; } = new();
    public List<ProductValuationDto> TopProducts { get; set; } = new();
}

public class ProductValuationDto
{
    public Guid ProductId { get; set; }
    public string ProductName { get; set; } = "";
    public string Category { get; set; } = "";
    public int Quantity { get; set; }
    public decimal AverageCost { get; set; }
    public decimal TotalCost { get; set; }
    public decimal CurrentValue { get; set; }
    public int DaysToExpiry { get; set; }
    public bool IsLowStock { get; set; }
    public bool IsExpiring { get; set; }
}

public class ExpiringProductsDto
{
    public Guid Id { get; set; }
    public string ProductName { get; set; } = "";
    public string BatchNumber { get; set; } = "";
    public DateTime ExpiryDate { get; set; }
    public int DaysToExpiry { get; set; }
    public int QuantityAvailable { get; set; }
    public decimal TotalValue { get; set; }
    public string? SuggestedAction { get; set; }
}

public class LowStockProductsDto
{
    public Guid ProductId { get; set; }
    public string ProductName { get; set; } = "";
    public int CurrentStock { get; set; }
    public int MinimumLevel { get; set; }
    public int ReorderPoint { get; set; }
    public decimal EstimatedValue { get; set; }
    public string? LastRestockDate { get; set; }
}

public class SlowMovingProductsDto
{
    public Guid ProductId { get; set; }
    public string ProductName { get; set; } = "";
    public int Quantity { get; set; }
    public decimal TotalValue { get; set; }
    public int DaysSinceLastMovement { get; set; }
    public DateTime? LastMovementDate { get; set; }
    public string? SuggestedAction { get; set; }
}

public class InventoryAccuracyDto
{
    public Guid ProductId { get; set; }
    public string ProductName { get; set; } = "";
    public int TheoreticalQuantity { get; set; }
    public int PhysicalQuantity { get; set; }
    public int Variance { get; set; }
    public decimal AccuracyPercentage { get; set; }
    public DateTime LastCountDate { get; set; }
}

// ============================================================================
// Batch Statistics
// ============================================================================

public class BatchStatisticsDto
{
    public Guid BatchId { get; set; }
    public string BatchNumber { get; set; } = "";
    public int TotalReceived { get; set; }
    public int TotalSold { get; set; }
    public int TotalReturned { get; set; }
    public int TotalDamaged { get; set; }
    public int CurrentAvailable { get; set; }
    public decimal TotalSales { get; set; }
    public decimal AverageSalePrice { get; set; }
    public double ProfitMargin { get; set; }
    public DateTime? FirstSaleDate { get; set; }
    public DateTime? LastSaleDate { get; set; }
}

// ============================================================================
// Dashboard Widget
// ============================================================================

public class InventoryDashboardDto
{
    public int TotalProducts { get; set; }
    public int TotalBatches { get; set; }
    public decimal TotalInventoryValue { get; set; }

    public int LowStockCount { get; set; }
    public int ExpiringCount { get; set; }
    public int DamagedCount { get; set; }

    public List<ProductValuationDto> TopProducts { get; set; } = new();
    public List<ExpiringProductsDto> RecentExpirations { get; set; } = new();
    public List<LowStockProductsDto> LowStockAlert { get; set; } = new();

    public Dictionary<string, int> InventoryByCategory { get; set; } = new();
    public Dictionary<string, decimal> ValueByCategory { get; set; } = new();

    public DateTime LastUpdated { get; set; }
}
