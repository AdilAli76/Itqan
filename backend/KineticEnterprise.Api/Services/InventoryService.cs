using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Services;

public class InventoryService
{
    private readonly AppDbContext _db;
    private readonly InventoryAlertService _alertService;

    public InventoryService(AppDbContext db, InventoryAlertService alertService)
    {
        _db = db;
        _alertService = alertService;
    }

    // ============================================================================
    // Batch Operations
    // ============================================================================

    public async Task<ProductBatch> CreateBatchAsync(Guid organizationId, CreateBatchRequest request)
    {
        var batch = new ProductBatch
        {
            OrganizationId = organizationId,
            ProductId = request.ProductId,
            BatchNumber = request.BatchNumber,
            ManufacturingDate = request.ManufacturingDate,
            ExpiryDate = request.ExpiryDate,
            QuantityReceived = request.QuantityReceived,
            QuantityAvailable = request.QuantityReceived,
            WarehouseId = request.WarehouseId,
            CostPerUnit = request.CostPerUnit,
            SupplierId = request.SupplierId,
            CertificateOfAnalysisJson = request.CertificateOfAnalysisJson,
            QualityStatus = "pending"
        };

        _db.ProductBatches.Add(batch);
        await _db.SaveChangesAsync();

        await RecordBatchMovementAsync(organizationId, batch.Id, "receipt", request.QuantityReceived,
            referenceType: null, referenceId: null);

        return batch;
    }

    public async Task<ProductBatch?> GetBatchAsync(Guid batchId, Guid organizationId)
    {
        return await _db.ProductBatches
            .Include(b => b.SerialNumbers)
            .Include(b => b.Movements)
            .FirstOrDefaultAsync(b => b.Id == batchId && b.OrganizationId == organizationId && !b.IsDeleted);
    }

    public async Task<List<ProductBatchDto>> GetBatchesByProductAsync(Guid productId, Guid organizationId)
    {
        var batches = await _db.ProductBatches
            .Where(b => b.ProductId == productId && b.OrganizationId == organizationId && !b.IsDeleted)
            .OrderByDescending(b => b.CreatedAt)
            .ToListAsync();

        return batches.Select(b => MapToBatchDto(b)).ToList();
    }

    public async Task<ProductBatch> UpdateBatchAsync(Guid batchId, Guid organizationId, UpdateBatchRequest request)
    {
        var batch = await GetBatchAsync(batchId, organizationId);
        if (batch == null)
            throw new InvalidOperationException("Batch not found");

        if (!string.IsNullOrEmpty(request.BatchNumber))
            batch.BatchNumber = request.BatchNumber;

        if (request.ManufacturingDate.HasValue)
            batch.ManufacturingDate = request.ManufacturingDate.Value;

        if (request.ExpiryDate.HasValue)
            batch.ExpiryDate = request.ExpiryDate;

        if (request.CostPerUnit.HasValue)
            batch.CostPerUnit = request.CostPerUnit.Value;

        if (request.WarehouseId.HasValue)
            batch.WarehouseId = request.WarehouseId;

        if (!string.IsNullOrEmpty(request.QualityStatus))
            batch.QualityStatus = request.QualityStatus;

        batch.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();

        return batch;
    }

    public async Task DeleteBatchAsync(Guid batchId, Guid organizationId)
    {
        var batch = await GetBatchAsync(batchId, organizationId);
        if (batch == null)
            throw new InvalidOperationException("Batch not found");

        batch.IsDeleted = true;
        batch.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();
    }

    // ============================================================================
    // Serial Numbers
    // ============================================================================

    public async Task AddSerialNumbersAsync(Guid organizationId, Guid batchId, List<string> serialNumbers, List<string>? barcodes)
    {
        var batch = await GetBatchAsync(batchId, organizationId);
        if (batch == null)
            throw new InvalidOperationException("Batch not found");

        var serials = new List<ProductSerialNumber>();
        for (int i = 0; i < serialNumbers.Count; i++)
        {
            serials.Add(new ProductSerialNumber
            {
                BatchId = batchId,
                SerialNumber = serialNumbers[i],
                Barcode = barcodes?.ElementAtOrDefault(i),
                Status = "available"
            });
        }

        _db.ProductSerialNumbers.AddRange(serials);
        await _db.SaveChangesAsync();

        await _alertService.CheckBatchAlertsAsync(organizationId, batchId);
    }

    public async Task<List<SerialNumberDto>> GetSerialNumbersAsync(Guid batchId, Guid organizationId)
    {
        var batch = await GetBatchAsync(batchId, organizationId);
        if (batch == null)
            throw new InvalidOperationException("Batch not found");

        var serials = await _db.ProductSerialNumbers
            .Where(s => s.BatchId == batchId)
            .OrderBy(s => s.SerialNumber)
            .ToListAsync();

        return serials.Select(s => new SerialNumberDto
        {
            Id = s.Id,
            BatchId = s.BatchId,
            SerialNumber = s.SerialNumber,
            Barcode = s.Barcode,
            Status = s.Status,
            WarehouseLocation = s.WarehouseLocation,
            SoldAt = s.SoldAt,
            InvoiceId = s.InvoiceId,
            CreatedAt = s.CreatedAt
        }).ToList();
    }

    // ============================================================================
    // Batch Movements
    // ============================================================================

    public async Task RecordBatchMovementAsync(Guid organizationId, Guid batchId, string movementType,
        int quantity, string? referenceType, Guid? referenceId, Guid? fromWarehouseId = null,
        Guid? toWarehouseId = null, string? notes = null, Guid? createdBy = null)
    {
        var batch = await GetBatchAsync(batchId, organizationId);
        if (batch == null)
            throw new InvalidOperationException("Batch not found");

        // Update quantity based on movement type
        switch (movementType)
        {
            case "receipt":
                batch.QuantityAvailable += quantity;
                break;
            case "sale":
                if (batch.QuantityAvailable < quantity)
                    throw new InvalidOperationException("Insufficient quantity available");
                batch.QuantityAvailable -= quantity;
                break;
            case "transfer":
                if (batch.QuantityAvailable < quantity)
                    throw new InvalidOperationException("Insufficient quantity for transfer");
                batch.QuantityAvailable -= quantity;
                break;
            case "damage":
                batch.QuantityAvailable -= quantity;
                break;
            case "return":
                batch.QuantityAvailable += quantity;
                break;
        }

        var movement = new BatchMovement
        {
            BatchId = batchId,
            OrganizationId = organizationId,
            MovementType = movementType,
            Quantity = quantity,
            ReferenceType = referenceType,
            ReferenceId = referenceId,
            FromWarehouseId = fromWarehouseId,
            ToWarehouseId = toWarehouseId,
            Notes = notes,
            CreatedBy = createdBy,
            CreatedAt = DateTime.UtcNow
        };

        batch.UpdatedAt = DateTime.UtcNow;
        _db.BatchMovements.Add(movement);
        await _db.SaveChangesAsync();

        await _alertService.CheckBatchAlertsAsync(organizationId, batchId);
    }

    public async Task<List<BatchMovementDto>> GetBatchMovementsAsync(Guid batchId, Guid organizationId, int limit = 50)
    {
        var batch = await GetBatchAsync(batchId, organizationId);
        if (batch == null)
            throw new InvalidOperationException("Batch not found");

        var movements = await _db.BatchMovements
            .Where(m => m.BatchId == batchId)
            .OrderByDescending(m => m.CreatedAt)
            .Take(limit)
            .ToListAsync();

        return movements.Select(m => new BatchMovementDto
        {
            Id = m.Id,
            BatchId = m.BatchId,
            MovementType = m.MovementType,
            Quantity = m.Quantity,
            ReferenceType = m.ReferenceType,
            ReferenceId = m.ReferenceId,
            FromWarehouse = m.FromWarehouseId.HasValue
                ? _db.Warehouses.FirstOrDefault(w => w.Id == m.FromWarehouseId)?.Name
                : null,
            ToWarehouse = m.ToWarehouseId.HasValue
                ? _db.Warehouses.FirstOrDefault(w => w.Id == m.ToWarehouseId)?.Name
                : null,
            Notes = m.Notes,
            CreatedBy = m.CreatedBy,
            CreatedAt = m.CreatedAt
        }).ToList();
    }

    // ============================================================================
    // Stock Transfers
    // ============================================================================

    public async Task<StockTransfer> CreateTransferAsync(Guid organizationId, CreateStockTransferRequest request, Guid? createdBy)
    {
        // StockTransfer uses branches, not warehouses in current schema
        // For now, simulate with warehouse data
        var transfer = new StockTransfer
        {
            OrganizationId = organizationId,
            FromBranchId = Guid.Empty, // Would be FromWarehouseId in v2
            ToBranchId = Guid.Empty,   // Would be ToWarehouseId in v2
            Status = "pending",
            CreatedBy = createdBy
        };

        _db.StockTransfers.Add(transfer);
        await _db.SaveChangesAsync();

        foreach (var item in request.Items)
        {
            var batch = await GetBatchAsync(item.BatchId ?? Guid.Empty, organizationId);
            if (batch == null)
                throw new InvalidOperationException("Product/batch not found");

            if (batch.QuantityAvailable < item.Quantity)
                throw new InvalidOperationException($"Insufficient quantity for product {batch.ProductId}");

            var transferItem = new StockTransferItem
            {
                TransferId = transfer.Id,
                ProductId = item.ProductId,
                Quantity = item.Quantity
            };

            _db.StockTransferItems.Add(transferItem);

            await RecordBatchMovementAsync(organizationId, batch.Id, "transfer", item.Quantity,
                referenceType: "transfer", referenceId: transfer.Id,
                fromWarehouseId: request.FromWarehouseId, toWarehouseId: request.ToWarehouseId);
        }

        await _db.SaveChangesAsync();
        return transfer;
    }

    public async Task<StockTransfer?> GetTransferAsync(Guid transferId, Guid organizationId)
    {
        return await _db.StockTransfers
            .Include(t => t.Items)
            .FirstOrDefaultAsync(t => t.Id == transferId && t.OrganizationId == organizationId);
    }

    public async Task ReceiveTransferAsync(Guid transferId, Guid organizationId, Guid? receivedBy)
    {
        var transfer = await GetTransferAsync(transferId, organizationId);
        if (transfer == null)
            throw new InvalidOperationException("Transfer not found");

        if (transfer.Status != "pending" && transfer.Status != "in_transit")
            throw new InvalidOperationException("Transfer cannot be received in current status");

        transfer.Status = "received";

        foreach (var item in transfer.Items)
        {
            // In current schema, we don't track batch by transfer
            // This is a placeholder for v2 enhancement
        }

        await _db.SaveChangesAsync();
    }

    // ============================================================================
    // Inventory Valuation
    // ============================================================================

    public async Task<InventoryValuationSummaryDto> GetInventoryValuationAsync(Guid organizationId)
    {
        var batches = await _db.ProductBatches
            .Where(b => b.OrganizationId == organizationId && !b.IsDeleted && b.QuantityAvailable > 0)
            .ToListAsync();

        var totalCost = batches.Sum(b => b.QuantityAvailable * b.CostPerUnit);
        var products = batches.GroupBy(b => b.ProductId).Count();

        var topProducts = batches
            .GroupBy(b => b.ProductId)
            .Select(g => new ProductValuationDto
            {
                ProductId = g.Key,
                ProductName = _db.Products.FirstOrDefault(p => p.Id == g.Key)?.Name ?? "",
                Category = "", // Product doesn't have Category property
                Quantity = g.Sum(b => b.QuantityAvailable),
                AverageCost = g.Count() > 0 ? g.Sum(b => b.CostPerUnit) / g.Count() : 0,
                TotalCost = g.Sum(b => b.QuantityAvailable * b.CostPerUnit),
                CurrentValue = g.Sum(b => b.QuantityAvailable * b.CostPerUnit),
                DaysToExpiry = g.Any(b => b.ExpiryDate.HasValue)
                    ? (int)(g.Where(b => b.ExpiryDate.HasValue).Min(b => b.ExpiryDate.Value) - DateTime.UtcNow).TotalDays
                    : int.MaxValue,
                IsLowStock = false,
                IsExpiring = g.Any(b => b.ExpiryDate.HasValue && (b.ExpiryDate.Value - DateTime.UtcNow).TotalDays < 30)
            })
            .OrderByDescending(p => p.TotalCost)
            .Take(10)
            .ToList();

        return new InventoryValuationSummaryDto
        {
            TotalAcquisitionCost = totalCost,
            TotalCurrentValue = totalCost,
            TotalItems = batches.Sum(b => b.QuantityAvailable),
            TopProducts = topProducts
        };
    }

    // ============================================================================
    // Expiring Products
    // ============================================================================

    public async Task<List<ExpiringProductsDto>> GetExpiringProductsAsync(Guid organizationId, int daysWarning = 30)
    {
        var expiryThreshold = DateTime.UtcNow.AddDays(daysWarning);

        var expiring = await _db.ProductBatches
            .Where(b => b.OrganizationId == organizationId && !b.IsDeleted &&
                   b.ExpiryDate.HasValue && b.ExpiryDate.Value <= expiryThreshold &&
                   b.QuantityAvailable > 0)
            .Select(b => new ExpiringProductsDto
            {
                Id = b.Id,
                ProductName = b.Product.Name,
                BatchNumber = b.BatchNumber,
                ExpiryDate = b.ExpiryDate.Value,
                DaysToExpiry = (int)(b.ExpiryDate.Value - DateTime.UtcNow).TotalDays,
                QuantityAvailable = b.QuantityAvailable,
                TotalValue = b.QuantityAvailable * b.CostPerUnit,
                SuggestedAction = (int)(b.ExpiryDate.Value - DateTime.UtcNow).TotalDays < 7
                    ? "Consider disposal or donation"
                    : "Plan clearance sales"
            })
            .OrderBy(e => e.ExpiryDate)
            .ToListAsync();

        return expiring;
    }

    // ============================================================================
    // Low Stock Products
    // ============================================================================

    public async Task<List<LowStockProductsDto>> GetLowStockProductsAsync(Guid organizationId)
    {
        var products = await _db.Products
            .Where(p => p.OrganizationId == organizationId && !p.IsDeleted)
            .ToListAsync();

        var lowStock = new List<LowStockProductsDto>();

        foreach (var product in products)
        {
            if (product.MinimumStockLevel <= 0)
                continue;

            var currentStock = await _db.ProductBatches
                .Where(b => b.ProductId == product.Id && b.OrganizationId == organizationId && !b.IsDeleted)
                .SumAsync(b => b.QuantityAvailable);

            if (currentStock < product.MinimumStockLevel)
            {
                var value = await _db.ProductBatches
                    .Where(b => b.ProductId == product.Id && b.OrganizationId == organizationId && !b.IsDeleted)
                    .SumAsync(b => b.QuantityAvailable * b.CostPerUnit);

                lowStock.Add(new LowStockProductsDto
                {
                    ProductId = product.Id,
                    ProductName = product.Name,
                    CurrentStock = currentStock,
                    MinimumLevel = product.MinimumStockLevel,
                    ReorderPoint = product.ReorderPoint,
                    EstimatedValue = value
                });
            }
        }

        return lowStock;
    }

    // ============================================================================
    // Slow Moving Products
    // ============================================================================

    public async Task<List<SlowMovingProductsDto>> GetSlowMovingProductsAsync(Guid organizationId, int daysNoMovement = 90)
    {
        var threshold = DateTime.UtcNow.AddDays(-daysNoMovement);

        var batchesWithMovements = await _db.ProductBatches
            .Where(b => b.OrganizationId == organizationId && !b.IsDeleted && b.QuantityAvailable > 0)
            .Include(b => b.Movements)
            .Include(b => b.Product)
            .ToListAsync();

        var slowMoving = batchesWithMovements
            .Select(b => new
            {
                Batch = b,
                LastMovement = b.Movements.OrderByDescending(m => m.CreatedAt).FirstOrDefault()
            })
            .Where(x => x.LastMovement == null || x.LastMovement.CreatedAt < threshold)
            .Select(x => new SlowMovingProductsDto
            {
                ProductId = x.Batch.ProductId,
                ProductName = x.Batch.Product?.Name ?? "",
                Quantity = x.Batch.QuantityAvailable,
                TotalValue = x.Batch.QuantityAvailable * x.Batch.CostPerUnit,
                DaysSinceLastMovement = x.LastMovement == null
                    ? (int)(DateTime.UtcNow - x.Batch.CreatedAt).TotalDays
                    : (int)(DateTime.UtcNow - x.LastMovement.CreatedAt).TotalDays,
                LastMovementDate = x.LastMovement?.CreatedAt,
                SuggestedAction = "Consider promotion or clearance"
            })
            .OrderByDescending(s => s.DaysSinceLastMovement)
            .ToList();

        return slowMoving;
    }

    // ============================================================================
    // Helpers
    // ============================================================================

    private ProductBatchDto MapToBatchDto(ProductBatch batch)
    {
        var warehouse = _db.Warehouses.FirstOrDefault(w => w.Id == batch.WarehouseId);
        var daysToExpiry = batch.ExpiryDate.HasValue
            ? (int)(batch.ExpiryDate.Value - DateTime.UtcNow).TotalDays
            : int.MaxValue;

        return new ProductBatchDto
        {
            Id = batch.Id,
            ProductId = batch.ProductId,
            BatchNumber = batch.BatchNumber,
            ManufacturingDate = batch.ManufacturingDate,
            ExpiryDate = batch.ExpiryDate,
            QuantityReceived = batch.QuantityReceived,
            QuantityAvailable = batch.QuantityAvailable,
            WarehouseId = batch.WarehouseId,
            WarehouseName = warehouse?.Name,
            CostPerUnit = batch.CostPerUnit,
            SupplierId = batch.SupplierId,
            QualityStatus = batch.QualityStatus,
            IsExpiring = batch.ExpiryDate.HasValue && daysToExpiry < 30,
            DaysToExpiry = daysToExpiry,
            CreatedAt = batch.CreatedAt,
            UpdatedAt = batch.UpdatedAt
        };
    }
}
