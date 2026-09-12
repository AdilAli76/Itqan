using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Services;

public class InventoryAlertService
{
    private readonly AppDbContext _db;

    public InventoryAlertService(AppDbContext db)
    {
        _db = db;
    }

    public async Task CheckBatchAlertsAsync(Guid organizationId, Guid batchId)
    {
        var batch = await _db.ProductBatches
            .Include(b => b.Product)
            .FirstOrDefaultAsync(b => b.Id == batchId && b.OrganizationId == organizationId);

        if (batch == null)
            return;

        // Get all active alert rules for this product
        var rules = await _db.InventoryAlertRules
            .Where(r => r.OrganizationId == organizationId && r.IsActive &&
                   (r.ProductId == null || r.ProductId == batch.ProductId))
            .ToListAsync();

        foreach (var rule in rules)
        {
            await CheckAndCreateAlertAsync(organizationId, batch, rule);
        }
    }

    public async Task CheckAllAlertsAsync(Guid organizationId)
    {
        var rules = await _db.InventoryAlertRules
            .Where(r => r.OrganizationId == organizationId && r.IsActive)
            .ToListAsync();

        var batches = await _db.ProductBatches
            .Include(b => b.Product)
            .Where(b => b.OrganizationId == organizationId && !b.IsDeleted)
            .ToListAsync();

        foreach (var batch in batches)
        {
            foreach (var rule in rules)
            {
                if (rule.ProductId == null || rule.ProductId == batch.ProductId)
                {
                    await CheckAndCreateAlertAsync(organizationId, batch, rule);
                }
            }
        }
    }

    private async Task CheckAndCreateAlertAsync(Guid organizationId, ProductBatch batch, InventoryAlertRule rule)
    {
        var (message, suggestedAction, severity) = rule.AlertType switch
        {
            "low_stock" => await CheckLowStockAsync(organizationId, batch, rule),
            "expiring" => await CheckExpiringAsync(organizationId, batch, rule),
            "slow_moving" => await CheckSlowMovingAsync(organizationId, batch, rule),
            "overstocked" => await CheckOverstockedAsync(organizationId, batch, rule),
            _ => (null, null, "medium")
        };

        if (!string.IsNullOrEmpty(message))
        {
            // Check if alert already exists and unresolved
            var existing = await _db.InventoryAlerts
                .FirstOrDefaultAsync(a => a.ProductId == batch.ProductId &&
                       a.AlertType == rule.AlertType && !a.IsResolved &&
                       a.OrganizationId == organizationId);

            if (existing == null)
            {
                var alert = new InventoryAlert
                {
                    OrganizationId = organizationId,
                    ProductId = batch.ProductId,
                    AlertType = rule.AlertType,
                    Severity = severity,
                    Message = message,
                    SuggestedAction = suggestedAction,
                    IsResolved = false
                };

                _db.InventoryAlerts.Add(alert);
                await _db.SaveChangesAsync();

                // Execute action if configured
                await ExecuteAlertActionAsync(organizationId, alert, rule);
            }
        }
    }

    private async Task<(string? message, string? suggestedAction, string severity)> CheckLowStockAsync(Guid organizationId, ProductBatch batch, InventoryAlertRule rule)
    {
        var product = await _db.Products.FirstOrDefaultAsync(p => p.Id == batch.ProductId);
        if (product == null)
            return (null, null, "medium");

        if (rule.Threshold.HasValue && batch.QuantityAvailable <= rule.Threshold.Value)
        {
            var severity = batch.QuantityAvailable == 0 ? "critical" : "high";
            var message = $"Low stock alert for {product.Name}: {batch.QuantityAvailable} units remaining (threshold: {rule.Threshold})";
            var suggestedAction = $"Create purchase order for {batch.BatchNumber}. Current: {batch.QuantityAvailable}, Recommended: {product.MinimumStockLevel}";
            return (message, suggestedAction, severity);
        }

        return (null, null, "medium");
    }

    private async Task<(string? message, string? suggestedAction, string severity)> CheckExpiringAsync(Guid organizationId, ProductBatch batch, InventoryAlertRule rule)
    {
        if (!batch.ExpiryDate.HasValue)
            return (null, null, "medium");

        var daysToExpiry = (int)(batch.ExpiryDate.Value - DateTime.UtcNow).TotalDays;
        var warningDays = rule.ExpiryWarningDays ?? 30;

        if (daysToExpiry <= warningDays && daysToExpiry > 0)
        {
            var severity = daysToExpiry <= 7 ? "critical" : daysToExpiry <= 14 ? "high" : "medium";
            var message = $"Expiry warning for {batch.BatchNumber}: expires in {daysToExpiry} days ({batch.ExpiryDate:yyyy-MM-dd})";
            var suggestedAction = daysToExpiry <= 7
                ? "Dispose of or donate this batch immediately"
                : "Plan clearance sales or promotional discounts";
            return (message, suggestedAction, severity);
        }

        if (daysToExpiry <= 0)
        {
            var message = $"EXPIRED: {batch.BatchNumber} expired on {batch.ExpiryDate:yyyy-MM-dd}";
            var suggestedAction = "Immediately remove from inventory and dispose according to regulations";
            return (message, suggestedAction, "critical");
        }

        return (null, null, "medium");
    }

    private async Task<(string? message, string? suggestedAction, string severity)> CheckSlowMovingAsync(Guid organizationId, ProductBatch batch, InventoryAlertRule rule)
    {
        var slowMovingDays = rule.SlowMovingDays ?? 90;
        var lastMovement = await _db.BatchMovements
            .Where(m => m.BatchId == batch.Id)
            .OrderByDescending(m => m.CreatedAt)
            .FirstOrDefaultAsync();

        if (lastMovement == null)
        {
            var daysIdle = (int)(DateTime.UtcNow - batch.CreatedAt).TotalDays;
            if (daysIdle > slowMovingDays)
            {
                var message = $"Slow-moving inventory: {batch.BatchNumber} has not moved in {daysIdle} days";
                var suggestedAction = "Consider running promotions, bundling with other products, or disposing";
                return (message, suggestedAction, "low");
            }
        }
        else
        {
            var daysSinceMove = (int)(DateTime.UtcNow - lastMovement.CreatedAt).TotalDays;
            if (daysSinceMove > slowMovingDays)
            {
                var message = $"Slow-moving inventory: {batch.BatchNumber} hasn't moved in {daysSinceMove} days";
                var suggestedAction = "Evaluate market demand and consider adjusting pricing or marketing";
                return (message, suggestedAction, "low");
            }
        }

        return (null, null, "low");
    }

    private async Task<(string? message, string? suggestedAction, string severity)> CheckOverstockedAsync(Guid organizationId, ProductBatch batch, InventoryAlertRule rule)
    {
        var product = await _db.Products.FirstOrDefaultAsync(p => p.Id == batch.ProductId);
        if (product == null || product.MaximumStockLevel <= 0)
            return (null, null, "low");

        if (batch.QuantityAvailable > product.MaximumStockLevel)
        {
            var excess = batch.QuantityAvailable - product.MaximumStockLevel;
            var message = $"Overstocked: {batch.BatchNumber} has {excess} units above maximum level ({product.MaximumStockLevel})";
            var suggestedAction = $"Increase sales efforts or consider returning {excess} units to supplier";
            return (message, suggestedAction, "medium");
        }

        return (null, null, "low");
    }

    private async Task ExecuteAlertActionAsync(Guid organizationId, InventoryAlert alert, InventoryAlertRule rule)
    {
        switch (rule.ActionType)
        {
            case "email":
                // In production: Send email notification
                // await _emailService.SendAsync(...);
                break;

            case "notification":
                // Notification already created, could send via SignalR/WebSocket
                break;

            case "auto_po":
                // In production: Auto-create purchase order
                // await _poService.CreateAutoPoAsync(...);
                break;
        }

        await Task.CompletedTask;
    }

    public async Task<List<InventoryAlertDto>> GetUnresolvedAlertsAsync(Guid organizationId, int limit = 50)
    {
        var alerts = await _db.InventoryAlerts
            .Where(a => a.OrganizationId == organizationId && !a.IsResolved)
            .OrderByDescending(a => a.CreatedAt)
            .Take(limit)
            .Select(a => new InventoryAlertDto
            {
                Id = a.Id,
                ProductId = a.ProductId,
                ProductName = a.Product.Name,
                AlertType = a.AlertType,
                Severity = a.Severity,
                Message = a.Message,
                SuggestedAction = a.SuggestedAction,
                IsResolved = a.IsResolved,
                CreatedAt = a.CreatedAt
            })
            .ToListAsync();

        return alerts;
    }

    public async Task<List<InventoryAlertDto>> QueryAlertsAsync(Guid organizationId, QueryAlertsRequest request)
    {
        var query = _db.InventoryAlerts
            .Where(a => a.OrganizationId == organizationId);

        if (!string.IsNullOrEmpty(request.AlertType))
            query = query.Where(a => a.AlertType == request.AlertType);

        if (!string.IsNullOrEmpty(request.Severity))
            query = query.Where(a => a.Severity == request.Severity);

        if (request.IsResolved.HasValue)
            query = query.Where(a => a.IsResolved == request.IsResolved.Value);

        var alerts = await query
            .OrderByDescending(a => a.CreatedAt)
            .Skip(request.Offset)
            .Take(request.Limit)
            .Select(a => new InventoryAlertDto
            {
                Id = a.Id,
                ProductId = a.ProductId,
                ProductName = a.Product.Name,
                AlertType = a.AlertType,
                Severity = a.Severity,
                Message = a.Message,
                SuggestedAction = a.SuggestedAction,
                IsResolved = a.IsResolved,
                CreatedAt = a.CreatedAt
            })
            .ToListAsync();

        return alerts;
    }

    public async Task ResolveAlertAsync(Guid alertId, Guid organizationId)
    {
        var alert = await _db.InventoryAlerts
            .FirstOrDefaultAsync(a => a.Id == alertId && a.OrganizationId == organizationId);

        if (alert == null)
            throw new InvalidOperationException("Alert not found");

        alert.IsResolved = true;
        alert.ResolvedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();
    }

    public async Task CreateAlertRuleAsync(Guid organizationId, CreateAlertRuleRequest request)
    {
        var rule = new InventoryAlertRule
        {
            OrganizationId = organizationId,
            ProductId = request.ProductId,
            AlertType = request.AlertType,
            Threshold = request.Threshold,
            ExpiryWarningDays = request.ExpiryWarningDays,
            SlowMovingDays = request.SlowMovingDays,
            ActionType = request.ActionType,
            IsActive = true
        };

        _db.InventoryAlertRules.Add(rule);
        await _db.SaveChangesAsync();
    }

    public async Task<List<InventoryAlertRule>> GetAlertRulesAsync(Guid organizationId)
    {
        return await _db.InventoryAlertRules
            .Where(r => r.OrganizationId == organizationId)
            .OrderBy(r => r.AlertType)
            .ToListAsync();
    }

    public async Task DisableAlertRuleAsync(Guid ruleId, Guid organizationId)
    {
        var rule = await _db.InventoryAlertRules
            .FirstOrDefaultAsync(r => r.Id == ruleId && r.OrganizationId == organizationId);

        if (rule == null)
            throw new InvalidOperationException("Alert rule not found");

        rule.IsActive = false;
        await _db.SaveChangesAsync();
    }

    public async Task<InventoryDashboardDto> GetInventoryDashboardAsync(Guid organizationId)
    {
        var batches = await _db.ProductBatches
            .Where(b => b.OrganizationId == organizationId && !b.IsDeleted)
            .ToListAsync();

        var lowStockCount = 0;
        var expiringCount = 0;
        var damagedCount = 0;

        foreach (var batch in batches)
        {
            var product = await _db.Products.FirstOrDefaultAsync(p => p.Id == batch.ProductId);
            if (product?.MinimumStockLevel > 0 && batch.QuantityAvailable <= product.MinimumStockLevel)
                lowStockCount++;

            if (batch.ExpiryDate.HasValue && (batch.ExpiryDate.Value - DateTime.UtcNow).TotalDays < 30)
                expiringCount++;

            // Check for damage status
            var damagedSerials = await _db.ProductSerialNumbers
                .CountAsync(s => s.BatchId == batch.Id && s.Status == "damaged");
            if (damagedSerials > 0)
                damagedCount += damagedSerials;
        }

        var totalValue = batches.Sum(b => b.QuantityAvailable * b.CostPerUnit);

        var recentExpirations = await _db.ProductBatches
            .Where(b => b.OrganizationId == organizationId && !b.IsDeleted &&
                   b.ExpiryDate.HasValue && (b.ExpiryDate.Value - DateTime.UtcNow).TotalDays < 30 &&
                   b.QuantityAvailable > 0)
            .OrderBy(b => b.ExpiryDate)
            .Take(5)
            .Select(b => new ExpiringProductsDto
            {
                Id = b.Id,
                ProductName = b.Product.Name,
                BatchNumber = b.BatchNumber,
                ExpiryDate = b.ExpiryDate.Value,
                DaysToExpiry = (int)(b.ExpiryDate.Value - DateTime.UtcNow).TotalDays,
                QuantityAvailable = b.QuantityAvailable,
                TotalValue = b.QuantityAvailable * b.CostPerUnit
            })
            .ToListAsync();

        var topProducts = batches
            .GroupBy(b => b.ProductId)
            .Select(g => new ProductValuationDto
            {
                ProductId = g.Key,
                ProductName = _db.Products.FirstOrDefault(p => p.Id == g.Key)?.Name ?? "",
                Quantity = g.Sum(b => b.QuantityAvailable),
                TotalCost = g.Sum(b => b.QuantityAvailable * b.CostPerUnit),
                CurrentValue = g.Sum(b => b.QuantityAvailable * b.CostPerUnit)
            })
            .OrderByDescending(p => p.CurrentValue)
            .Take(5)
            .ToList();

        return new InventoryDashboardDto
        {
            TotalProducts = batches.Select(b => b.ProductId).Distinct().Count(),
            TotalBatches = batches.Count,
            TotalInventoryValue = totalValue,
            LowStockCount = lowStockCount,
            ExpiringCount = expiringCount,
            DamagedCount = damagedCount,
            TopProducts = topProducts,
            RecentExpirations = recentExpirations,
            LastUpdated = DateTime.UtcNow
        };
    }
}
