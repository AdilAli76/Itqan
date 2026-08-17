using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Authorization;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Controllers;

public record CreateStockCountRequest(Guid BranchId);
public record UpdateCountedQuantityRequest(decimal CountedQuantity);

public record StockCountListItemDto(
    Guid Id, Guid BranchId, string BranchName, string Status,
    int ItemCount, int VarianceCount, DateTime CreatedAt, DateTime? ClosedAt);

public record StockCountItemDto(
    Guid Id, Guid ProductId, string ProductName, decimal SystemQuantity, decimal CountedQuantity, decimal Variance);

public record StockCountDetailDto(
    Guid Id, Guid BranchId, string BranchName, string Status,
    DateTime CreatedAt, DateTime? ClosedAt, List<StockCountItemDto> Items);

/// <summary>
/// راجع DATABASE_TABLES_GUIDE.md §5.7. stock_counts يحمل branch_id واحداً
/// فعلياً (على عكس stock_transfers)، فـ StockCountsPolicy تعزل تلقائياً حسب
/// فرع المستخدم — لا فلترة يدوية مطلوبة هنا.
/// </summary>
[ApiController]
[Route("api/stock-counts")]
[Authorize]
public class StockCountsController : ControllerBase
{
    private readonly AppDbContext _db;
    public StockCountsController(AppDbContext db) => _db = db;

    [HttpGet]
    public async Task<ActionResult<List<StockCountListItemDto>>> GetAll([FromQuery] string? status)
    {
        var query = _db.StockCounts.Include(c => c.Items).AsQueryable();
        if (!string.IsNullOrWhiteSpace(status)) query = query.Where(c => c.Status == status);

        var counts = await query.OrderByDescending(c => c.CreatedAt).ToListAsync();
        var branchIds = counts.Select(c => c.BranchId).Distinct().ToList();
        var branchNames = await _db.Branches.Where(b => branchIds.Contains(b.Id)).ToDictionaryAsync(b => b.Id, b => b.Name);

        return counts.Select(c => new StockCountListItemDto(
            c.Id, c.BranchId, branchNames.GetValueOrDefault(c.BranchId, "-"), c.Status,
            c.Items.Count, c.Items.Count(i => i.Variance != 0), c.CreatedAt, c.ClosedAt)).ToList();
    }

    [HttpGet("{id:guid}")]
    public async Task<ActionResult<StockCountDetailDto>> GetById(Guid id)
    {
        var count = await _db.StockCounts.Include(c => c.Items).FirstOrDefaultAsync(c => c.Id == id);
        if (count is null) return NotFound();
        return await ToDetailDto(count);
    }

    /// <summary>
    /// ينشئ جرداً جديداً ويُثبِّت الكمية النظامية الحالية (مجموع كل الدفعات)
    /// لكل صنف في الكتالوج كنقطة بداية — الكمية المعدودة تبدأ مساوية لها،
    /// فيُعدِّل الموظف فقط الأصناف التي يجد فرقاً فيها بدل إعادة إدخال الكل.
    /// </summary>
    [HttpPost]
    [RequirePermission("stock_count.manage")]
    public async Task<ActionResult<StockCountDetailDto>> Create(CreateStockCountRequest request)
    {
        var products = await _db.Products.Where(p => !p.IsDeleted).ToListAsync();
        var stockByProduct = (await _db.StockLevels.Where(s => s.BranchId == request.BranchId).ToListAsync())
            .GroupBy(s => s.ProductId)
            .ToDictionary(g => g.Key, g => g.Sum(s => s.Quantity));

        var count = new StockCount
        {
            OrganizationId = Guid.Parse(User.FindFirstValue("organization_id")!),
            BranchId = request.BranchId,
            CreatedBy = CurrentUserId(),
        };
        foreach (var product in products)
        {
            var systemQuantity = stockByProduct.GetValueOrDefault(product.Id, 0);
            count.Items.Add(new StockCountItem
            {
                ProductId = product.Id,
                SystemQuantity = systemQuantity,
                CountedQuantity = systemQuantity,
            });
        }

        _db.StockCounts.Add(count);
        _db.LogAudit(count.OrganizationId, CurrentUserId(), "stock_count.created", "stock_counts", count.Id,
            newValues: new { count.BranchId, ItemCount = count.Items.Count });
        await _db.SaveChangesAsync();

        return CreatedAtAction(nameof(GetById), new { id = count.Id }, await ToDetailDto(count));
    }

    [HttpPut("{id:guid}/items/{itemId:guid}")]
    [RequirePermission("stock_count.manage")]
    public async Task<IActionResult> UpdateCountedQuantity(Guid id, Guid itemId, UpdateCountedQuantityRequest request)
    {
        var count = await _db.StockCounts.FirstOrDefaultAsync(c => c.Id == id);
        if (count is null) return NotFound();
        if (count.Status != "open")
        {
            return BadRequest(new { message = "لا يمكن تعديل جرد ليس قيد العد" });
        }

        var item = await _db.StockCountItems.FirstOrDefaultAsync(i => i.Id == itemId && i.StockCountId == id);
        if (item is null) return NotFound();

        item.CountedQuantity = request.CountedQuantity;
        await _db.SaveChangesAsync();
        return NoContent();
    }

    /// <summary>
    /// يعتمد الجرد: يطبّق الفرق (Variance) فعلياً على stock_levels لكل صنف
    /// مختلف — دفعة عامة بلا رقم دفعة (نفس القيد المتّبع في تعديل المخزون
    /// اليدوي واسترجاع الفواتير)، لأن الجرد على مستوى الصنف لا الدفعة.
    /// </summary>
    [HttpPost("{id:guid}/reconcile")]
    [RequirePermission("stock_count.manage")]
    public async Task<IActionResult> Reconcile(Guid id)
    {
        var count = await _db.StockCounts.Include(c => c.Items).FirstOrDefaultAsync(c => c.Id == id);
        if (count is null) return NotFound();
        if (count.Status != "open")
        {
            return BadRequest(new { message = "لا يمكن اعتماد جرد ليس قيد العد" });
        }

        await using var transaction = await _db.Database.BeginTransactionAsync();

        foreach (var item in count.Items.Where(i => i.Variance != 0))
        {
            var stock = await _db.StockLevels.FirstOrDefaultAsync(
                s => s.BranchId == count.BranchId && s.ProductId == item.ProductId && s.BatchNumber == "");
            if (stock is null)
            {
                _db.StockLevels.Add(new StockLevel
                {
                    OrganizationId = count.OrganizationId,
                    BranchId = count.BranchId,
                    ProductId = item.ProductId,
                    BatchNumber = "",
                    Quantity = Math.Max(0, item.Variance),
                });
            }
            else
            {
                stock.Quantity = Math.Max(0, stock.Quantity + item.Variance);
            }
        }

        count.Status = "reconciled";
        count.ClosedAt = DateTime.UtcNow;
        _db.LogAudit(count.OrganizationId, CurrentUserId(), "stock_count.reconciled", "stock_counts", count.Id,
            newValues: new { AdjustedItems = count.Items.Count(i => i.Variance != 0) });
        await _db.SaveChangesAsync();
        await transaction.CommitAsync();
        return NoContent();
    }

    [HttpPost("{id:guid}/cancel")]
    [RequirePermission("stock_count.manage")]
    public async Task<IActionResult> Cancel(Guid id)
    {
        var count = await _db.StockCounts.FirstOrDefaultAsync(c => c.Id == id);
        if (count is null) return NotFound();
        if (count.Status != "open")
        {
            return BadRequest(new { message = "لا يمكن إلغاء جرد ليس قيد العد" });
        }

        count.Status = "cancelled";
        count.ClosedAt = DateTime.UtcNow;
        _db.LogAudit(count.OrganizationId, CurrentUserId(), "stock_count.cancelled", "stock_counts", count.Id, null);
        await _db.SaveChangesAsync();
        return NoContent();
    }

    private async Task<StockCountDetailDto> ToDetailDto(StockCount count)
    {
        var branchName = await _db.Branches.Where(b => b.Id == count.BranchId).Select(b => b.Name).FirstOrDefaultAsync() ?? "-";
        var productIds = count.Items.Select(i => i.ProductId).ToList();
        var productNames = await _db.Products.Where(p => productIds.Contains(p.Id)).ToDictionaryAsync(p => p.Id, p => p.Name);

        return new StockCountDetailDto(
            count.Id, count.BranchId, branchName, count.Status, count.CreatedAt, count.ClosedAt,
            count.Items
                .Select(i => new StockCountItemDto(i.Id, i.ProductId, productNames.GetValueOrDefault(i.ProductId, "-"), i.SystemQuantity, i.CountedQuantity, i.Variance))
                .OrderBy(i => i.ProductName)
                .ToList());
    }

    private Guid? CurrentUserId()
    {
        var raw = User.FindFirstValue(JwtRegisteredClaimNames.Sub) ?? User.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(raw, out var id) ? id : null;
    }
}
