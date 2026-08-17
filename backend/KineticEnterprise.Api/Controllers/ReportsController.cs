using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Authorization;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Controllers;

public record DailyRevenuePoint(DateTime Date, decimal Revenue, int InvoiceCount);
public record ProductSalesPoint(Guid ProductId, string ProductName, decimal QuantitySold, decimal Revenue);
public record BranchSalesPoint(Guid BranchId, string BranchName, decimal Revenue, int InvoiceCount);
public record CashierSalesPoint(Guid? CashierId, string CashierName, decimal Revenue, int InvoiceCount);

public record SalesSummaryDto(
    decimal TotalRevenue, int TotalInvoices, decimal AverageInvoiceValue,
    decimal TotalReturns, int ReturnCount,
    List<DailyRevenuePoint> RevenueByDay,
    List<ProductSalesPoint> TopProducts,
    List<BranchSalesPoint> RevenueByBranch,
    List<CashierSalesPoint> RevenueByCashier);

public record LowStockItemDto(Guid ProductId, string ProductName, decimal Quantity, decimal ReorderLevel);
public record ExpiringItemDto(Guid ProductId, string ProductName, decimal Quantity, DateTime ExpiryDate, decimal EstimatedLossValue);

public record InventorySummaryDto(
    decimal TotalInventoryValue, int TotalProducts,
    int LowStockCount, List<LowStockItemDto> LowStockItems,
    int ExpiredCount, decimal ExpiredLossValue, List<ExpiringItemDto> ExpiredItems,
    int NearExpiryCount, List<ExpiringItemDto> NearExpiryItems);

/// <summary>
/// موديول التقارير (ARCHITECTURE.md §2.9): مبيعات، مخزون، فواقد الصلاحية،
/// أداء الفروع، أداء الكاشير. تصدير PDF/Excel مؤجَّل — هذا الإصدار عرض حي
/// داخل التطبيق فقط. لا حاجة لفلترة organization_id/branch_id يدوياً هنا:
/// InvoicesPolicy وStockLevelsPolicy تُطبَّقان تلقائياً (مدير فرع لا يرى إلا
/// أرقام فرعه، بلا أي كود إضافي في هذا الملف).
/// </summary>
[ApiController]
[Route("api/reports")]
[Authorize]
[RequirePermission("reports.view")]
public class ReportsController : ControllerBase
{
    private readonly AppDbContext _db;
    public ReportsController(AppDbContext db) => _db = db;

    [HttpGet("sales-summary")]
    public async Task<ActionResult<SalesSummaryDto>> SalesSummary([FromQuery] DateTime? from, [FromQuery] DateTime? to)
    {
        var rangeFrom = from ?? DateTime.UtcNow.Date.AddDays(-29);
        var rangeTo = (to ?? DateTime.UtcNow.Date).AddDays(1);

        var invoices = await _db.Invoices
            .Include(i => i.Items)
            .Where(i => i.CreatedAt >= rangeFrom && i.CreatedAt < rangeTo)
            .ToListAsync();

        var sales = invoices.Where(i => i.InvoiceType == "sale").ToList();
        var returns = invoices.Where(i => i.InvoiceType == "return").ToList();
        var totalRevenue = sales.Sum(i => i.TotalAmount);

        var revenueByDay = sales
            .GroupBy(i => i.CreatedAt.Date)
            .Select(g => new DailyRevenuePoint(g.Key, g.Sum(i => i.TotalAmount), g.Count()))
            .OrderBy(p => p.Date)
            .ToList();

        var productIds = sales.SelectMany(i => i.Items).Select(item => item.ProductId).Distinct().ToList();
        var productNames = await _db.Products.Where(p => productIds.Contains(p.Id)).ToDictionaryAsync(p => p.Id, p => p.Name);
        var topProducts = sales.SelectMany(i => i.Items)
            .GroupBy(item => item.ProductId)
            .Select(g => new ProductSalesPoint(g.Key, productNames.GetValueOrDefault(g.Key, "-"), g.Sum(x => x.Quantity), g.Sum(x => x.LineTotal)))
            .OrderByDescending(p => p.Revenue)
            .Take(10)
            .ToList();

        var branchIds = sales.Select(i => i.BranchId).Distinct().ToList();
        var branchNames = await _db.Branches.Where(b => branchIds.Contains(b.Id)).ToDictionaryAsync(b => b.Id, b => b.Name);
        var revenueByBranch = sales
            .GroupBy(i => i.BranchId)
            .Select(g => new BranchSalesPoint(g.Key, branchNames.GetValueOrDefault(g.Key, "-"), g.Sum(i => i.TotalAmount), g.Count()))
            .OrderByDescending(b => b.Revenue)
            .ToList();

        var cashierIds = sales.Where(i => i.CreatedBy.HasValue).Select(i => i.CreatedBy!.Value).Distinct().ToList();
        var cashierNames = await _db.AppUsers.Where(u => cashierIds.Contains(u.Id)).ToDictionaryAsync(u => u.Id, u => u.FullName);
        var revenueByCashier = sales
            .GroupBy(i => i.CreatedBy)
            .Select(g => new CashierSalesPoint(
                g.Key,
                g.Key.HasValue ? cashierNames.GetValueOrDefault(g.Key.Value, "-") : "غير محدَّد",
                g.Sum(i => i.TotalAmount), g.Count()))
            .OrderByDescending(c => c.Revenue)
            .ToList();

        return new SalesSummaryDto(
            totalRevenue, sales.Count, sales.Count == 0 ? 0 : totalRevenue / sales.Count,
            returns.Sum(i => i.TotalAmount), returns.Count,
            revenueByDay, topProducts, revenueByBranch, revenueByCashier);
    }

    [HttpGet("inventory-summary")]
    public async Task<ActionResult<InventorySummaryDto>> InventorySummary()
    {
        var products = await _db.Products.Where(p => !p.IsDeleted).ToListAsync();
        var stockByProduct = (await _db.StockLevels.ToListAsync())
            .GroupBy(s => s.ProductId)
            .ToDictionary(g => g.Key, g => g.ToList());

        decimal totalValue = 0;
        var lowStockItems = new List<LowStockItemDto>();
        var expiredItems = new List<ExpiringItemDto>();
        var nearExpiryItems = new List<ExpiringItemDto>();
        var today = DateTime.UtcNow.Date;

        foreach (var product in products)
        {
            var levels = stockByProduct.GetValueOrDefault(product.Id, new List<StockLevel>());
            var quantity = levels.Sum(l => l.Quantity);
            totalValue += quantity * product.CostPrice;

            if (quantity <= product.ReorderLevel)
            {
                lowStockItems.Add(new LowStockItemDto(product.Id, product.Name, quantity, product.ReorderLevel));
            }

            foreach (var level in levels.Where(l => l.ExpiryDate.HasValue && l.Quantity > 0))
            {
                var expiryDate = level.ExpiryDate!.Value;
                var lossValue = level.Quantity * product.CostPrice;
                if (expiryDate < today)
                {
                    expiredItems.Add(new ExpiringItemDto(product.Id, product.Name, level.Quantity, expiryDate, lossValue));
                }
                else if (expiryDate <= today.AddDays(7))
                {
                    nearExpiryItems.Add(new ExpiringItemDto(product.Id, product.Name, level.Quantity, expiryDate, lossValue));
                }
            }
        }

        return new InventorySummaryDto(
            totalValue, products.Count,
            lowStockItems.Count, lowStockItems.OrderBy(i => i.Quantity).Take(15).ToList(),
            expiredItems.Count, expiredItems.Sum(i => i.EstimatedLossValue), expiredItems.OrderByDescending(i => i.EstimatedLossValue).Take(15).ToList(),
            nearExpiryItems.Count, nearExpiryItems.OrderBy(i => i.ExpiryDate).Take(15).ToList());
    }
}
