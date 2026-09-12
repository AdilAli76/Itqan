using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;

namespace KineticEnterprise.Api.Models;

/// <summary>
/// نموذج الدفعة - تتبع كل دفعة من المنتجات
/// </summary>
public class ProductBatch
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OrganizationId { get; set; }
    public Guid ProductId { get; set; }

    [Required, MaxLength(100)]
    public string BatchNumber { get; set; } = "";

    public DateTime ManufacturingDate { get; set; }
    public DateTime? ExpiryDate { get; set; }

    public int QuantityReceived { get; set; }
    public int QuantityAvailable { get; set; }

    public Guid? WarehouseId { get; set; }
    public decimal CostPerUnit { get; set; }
    public Guid? SupplierId { get; set; }

    [MaxLength(MAX_JSON_LENGTH)]
    public string? CertificateOfAnalysisJson { get; set; } // JSON array

    [MaxLength(50)]
    public string QualityStatus { get; set; } = "pending"; // pending, approved, rejected

    public bool IsDeleted { get; set; } = false;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

    // Navigation
    public Product? Product { get; set; }
    public Warehouse? Warehouse { get; set; }
    public ICollection<ProductSerialNumber> SerialNumbers { get; set; } = new List<ProductSerialNumber>();
    public ICollection<BatchMovement> Movements { get; set; } = new List<BatchMovement>();

    private const int MAX_JSON_LENGTH = 2000;
}

/// <summary>
/// نموذج الأرقام التسلسلية - تتبع كل قطعة على حدة
/// </summary>
public class ProductSerialNumber
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid BatchId { get; set; }

    [Required, MaxLength(255)]
    public string SerialNumber { get; set; } = "";

    [MaxLength(255)]
    public string? Barcode { get; set; }

    [MaxLength(50)]
    public string Status { get; set; } = "available"; // available, sold, returned, damaged, recalled

    [MaxLength(255)]
    public string? WarehouseLocation { get; set; } // Shelf, Aisle, Bin

    public DateTime? SoldAt { get; set; }
    public Guid? InvoiceId { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    // Navigation
    public ProductBatch? Batch { get; set; }
}

/// <summary>
/// نموذج حركات الدفعات - تتبع الدخول والخروج
/// </summary>
public class BatchMovement
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid BatchId { get; set; }
    public Guid OrganizationId { get; set; }

    [MaxLength(50)]
    public string MovementType { get; set; } = ""; // receipt, sale, adjustment, transfer, damage, return

    public int Quantity { get; set; }

    [MaxLength(50)]
    public string? ReferenceType { get; set; } // invoice, transfer, adjustment, return

    public Guid? ReferenceId { get; set; }

    public Guid? FromWarehouseId { get; set; }
    public Guid? ToWarehouseId { get; set; }

    [MaxLength(500)]
    public string? Notes { get; set; }

    public Guid? CreatedBy { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    // Navigation
    public ProductBatch? Batch { get; set; }
}

/// <summary>
/// نموذج إعدادات التنبيهات
/// </summary>
public class InventoryAlertRule
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OrganizationId { get; set; }
    public Guid? ProductId { get; set; } // null = لجميع المنتجات

    [MaxLength(50)]
    public string AlertType { get; set; } = ""; // low_stock, expiring, slow_moving, overstocked

    public int? Threshold { get; set; }
    public int? ExpiryWarningDays { get; set; }
    public int? SlowMovingDays { get; set; }

    [MaxLength(50)]
    public string ActionType { get; set; } = "notification"; // email, notification, auto_po

    public bool IsActive { get; set; } = true;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

/// <summary>
/// نموذج سجل التنبيهات
/// </summary>
public class InventoryAlert
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OrganizationId { get; set; }
    public Guid ProductId { get; set; }

    [MaxLength(50)]
    public string AlertType { get; set; } = "";

    [MaxLength(20)]
    public string Severity { get; set; } = "medium"; // low, medium, high, critical

    [MaxLength(1000)]
    public string Message { get; set; } = "";

    [MaxLength(1000)]
    public string? SuggestedAction { get; set; }

    public bool IsResolved { get; set; } = false;
    public DateTime? ResolvedAt { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    // Navigation
    public Product? Product { get; set; }
}

/// <summary>
/// توسيع نموذج المنتج مع تتبع الدفعات
/// </summary>
public partial class Product
{
    public bool EnableBatchTracking { get; set; } = false;
    public bool EnableSerialNumberTracking { get; set; } = false;
    public bool RequireExpiryDate { get; set; } = false;

    // Min/Max levels for alerts
    public int MinimumStockLevel { get; set; } = 0;
    public int ReorderPoint { get; set; } = 0;
    public int MaximumStockLevel { get; set; } = 0;

    // Navigation
    public ICollection<ProductBatch> Batches { get; set; } = new List<ProductBatch>();
    public ICollection<InventoryAlertRule> AlertRules { get; set; } = new List<InventoryAlertRule>();
}

/// <summary>
/// توسيع نموذج المستودع مع الموقع
/// </summary>
public partial class Warehouse
{
    [MaxLength(100)]
    public string? LocationCode { get; set; }

    public int? Latitude { get; set; }
    public int? Longitude { get; set; }

    // Navigation
    public ICollection<ProductBatch> Batches { get; set; } = new List<ProductBatch>();
}


/// <summary>
/// ملخص قيمة الأصول
/// </summary>
public class InventoryValuation
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OrganizationId { get; set; }
    public Guid ProductId { get; set; }

    public int TotalQuantity { get; set; }
    public decimal TotalCost { get; set; }
    public decimal AverageCost { get; set; }
    public decimal CurrentValue { get; set; } // Based on selling price

    public DateTime CalculatedAt { get; set; } = DateTime.UtcNow;

    // Navigation
    public Product? Product { get; set; }
}
