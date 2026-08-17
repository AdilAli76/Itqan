using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Authorization;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Controllers;

public record PurchaseOrderLineRequest(Guid ProductId, decimal Quantity, decimal UnitCost, decimal? SalePrice);
public record CreatePurchaseOrderRequest(Guid BranchId, Guid? SupplierId, List<PurchaseOrderLineRequest> Lines);

public record ReceiveLineRequest(Guid ProductId, string? BatchNumber, DateTime? ExpiryDate);
public record ReceivePurchaseOrderRequest(List<ReceiveLineRequest> Lines);

public record PurchaseOrderListItemDto(
    Guid Id, Guid BranchId, string BranchName, Guid? SupplierId, string SupplierName,
    string Status, decimal TotalAmount, int ItemCount, DateTime CreatedAt);

public record PurchaseOrderDetailItemDto(
    Guid ProductId, string ProductName, bool TrackExpiry, decimal Quantity, decimal UnitCost, decimal? SalePrice, decimal LineTotal);
public record PurchaseOrderDetailDto(
    Guid Id, Guid BranchId, string BranchName, Guid? SupplierId, string SupplierName,
    string Status, decimal TotalAmount, DateTime CreatedAt, List<PurchaseOrderDetailItemDto> Items);

/// <summary>
/// موديول المشتريات (أوامر الشراء من الموردين) — كان جدولاه purchase_orders
/// وpurchase_order_items موثَّقين في المخطط منذ البداية بلا أي Controller
/// يستعلم عنهما. تسلسل الحالة مطابق تماماً لـ StockTransfersController:
/// draft (مسودة، بلا أثر) ← ordered (أُرسل للمورّد) ← received (وصلت
/// البضاعة فعلياً — هنا فقط تُضاف الكمية لـ stock_levels)، أو cancelled
/// قبل الاستلام فقط.
/// </summary>
[ApiController]
[Route("api/purchase-orders")]
[Authorize]
public class PurchaseOrdersController : ControllerBase
{
    private readonly AppDbContext _db;
    public PurchaseOrdersController(AppDbContext db) => _db = db;

    [HttpGet]
    public async Task<ActionResult<List<PurchaseOrderListItemDto>>> GetAll([FromQuery] string? status)
    {
        var query = _db.PurchaseOrders.Include(o => o.Items).AsQueryable();
        if (!string.IsNullOrWhiteSpace(status)) query = query.Where(o => o.Status == status);

        var orders = await query.OrderByDescending(o => o.CreatedAt).ToListAsync();
        var branchNames = await BranchNamesFor(orders.Select(o => o.BranchId));
        var supplierNames = await SupplierNamesFor(orders.Where(o => o.SupplierId.HasValue).Select(o => o.SupplierId!.Value));

        return orders.Select(o => new PurchaseOrderListItemDto(
            o.Id, o.BranchId, branchNames.GetValueOrDefault(o.BranchId, "-"),
            o.SupplierId, o.SupplierId.HasValue ? supplierNames.GetValueOrDefault(o.SupplierId.Value, "-") : "-",
            o.Status, o.TotalAmount, o.Items.Count, o.CreatedAt)).ToList();
    }

    [HttpGet("{id:guid}")]
    public async Task<ActionResult<PurchaseOrderDetailDto>> GetById(Guid id)
    {
        var order = await _db.PurchaseOrders.Include(o => o.Items).FirstOrDefaultAsync(o => o.Id == id);
        if (order is null) return NotFound();
        return await ToDetailDto(order);
    }

    [HttpPost]
    [RequirePermission("purchasing.manage")]
    public async Task<ActionResult<PurchaseOrderDetailDto>> Create(CreatePurchaseOrderRequest request)
    {
        if (request.Lines.Count == 0)
        {
            return BadRequest(new { message = "أضف صنفاً واحداً على الأقل" });
        }

        var order = new PurchaseOrder
        {
            OrganizationId = Guid.Parse(User.FindFirstValue("organization_id")!),
            BranchId = request.BranchId,
            SupplierId = request.SupplierId,
            CreatedBy = CurrentUserId(),
        };
        foreach (var line in request.Lines)
        {
            order.Items.Add(new PurchaseOrderItem
            {
                ProductId = line.ProductId,
                Quantity = line.Quantity,
                UnitCost = line.UnitCost,
                SalePrice = line.SalePrice,
            });
        }
        order.TotalAmount = order.Items.Sum(i => i.Quantity * i.UnitCost);

        _db.PurchaseOrders.Add(order);
        _db.LogAudit(order.OrganizationId, CurrentUserId(), "purchase_order.created", "purchase_orders", order.Id,
            newValues: new { order.BranchId, order.SupplierId, order.TotalAmount, ItemCount = order.Items.Count });
        await _db.SaveChangesAsync();

        return CreatedAtAction(nameof(GetById), new { id = order.Id }, await ToDetailDto(order));
    }

    // draft -> ordered: لا أثر مخزوني، فقط تثبيت الأمر كمُرسَل للمورّد.
    [HttpPost("{id:guid}/order")]
    [RequirePermission("purchasing.manage")]
    public async Task<IActionResult> MarkOrdered(Guid id)
    {
        var order = await _db.PurchaseOrders.FirstOrDefaultAsync(o => o.Id == id);
        if (order is null) return NotFound();
        if (order.Status != "draft")
        {
            return BadRequest(new { message = "لا يمكن إرسال أمر ليس في حالة مسودة" });
        }

        order.Status = "ordered";
        _db.LogAudit(order.OrganizationId, CurrentUserId(), "purchase_order.ordered", "purchase_orders", order.Id, null);
        await _db.SaveChangesAsync();
        return NoContent();
    }

    /// <summary>
    /// ordered -> received: يضيف الكمية المطلوبة فعلياً لمخزون الفرع، ويحدّث
    /// تكلفة الصنف (CostPrice) لآخر سعر شراء فعلي وسعر البيع إن حُدِّد وقت
    /// الإنشاء. رقم الدفعة وتاريخ الصلاحية لا يُعرَفان فعلياً إلا لحظة
    /// الاستلام الفعلي (المورّد قد يرسل دفعة مختلفة عمّا كان متوقَّعاً وقت
    /// الطلب) — لذا يُطلَبان هنا في request.Lines، لا في CreatePurchaseOrderRequest.
    /// الأصناف التي لا تتتبّع الصلاحية (TrackExpiry=false) تُستقبَل بدفعة
    /// عامة فارغة، نفس نمط StockTransfersController.Receive تماماً.
    /// </summary>
    [HttpPost("{id:guid}/receive")]
    [RequirePermission("purchasing.manage")]
    public async Task<IActionResult> Receive(Guid id, ReceivePurchaseOrderRequest request)
    {
        var order = await _db.PurchaseOrders.Include(o => o.Items).FirstOrDefaultAsync(o => o.Id == id);
        if (order is null) return NotFound();
        if (order.Status != "ordered")
        {
            return BadRequest(new { message = "لا يمكن استلام أمر لم يُرسَل للمورّد بعد" });
        }

        var receiveLines = request.Lines.ToDictionary(l => l.ProductId);

        await using var transaction = await _db.Database.BeginTransactionAsync();

        foreach (var item in order.Items)
        {
            var product = await _db.Products.FirstOrDefaultAsync(p => p.Id == item.ProductId);
            receiveLines.TryGetValue(item.ProductId, out var receiveLine);

            var batchNumber = product?.TrackExpiry == true ? (receiveLine?.BatchNumber ?? "") : "";
            var expiryDate = product?.TrackExpiry == true ? receiveLine?.ExpiryDate : null;

            var stock = await _db.StockLevels.FirstOrDefaultAsync(
                s => s.BranchId == order.BranchId && s.ProductId == item.ProductId && s.BatchNumber == batchNumber);
            if (stock is null)
            {
                _db.StockLevels.Add(new StockLevel
                {
                    OrganizationId = order.OrganizationId,
                    BranchId = order.BranchId,
                    ProductId = item.ProductId,
                    BatchNumber = batchNumber,
                    Quantity = item.Quantity,
                    ExpiryDate = expiryDate,
                });
            }
            else
            {
                stock.Quantity += item.Quantity;
                if (expiryDate.HasValue) stock.ExpiryDate = expiryDate;
            }

            if (product is not null)
            {
                product.CostPrice = item.UnitCost;
                if (item.SalePrice.HasValue) product.SalePrice = item.SalePrice.Value;
            }
        }

        order.Status = "received";
        _db.LogAudit(order.OrganizationId, CurrentUserId(), "purchase_order.received", "purchase_orders", order.Id, null);
        await _db.SaveChangesAsync();
        await transaction.CommitAsync();
        return NoContent();
    }

    // إلغاء مسموح فقط قبل الاستلام (بلا أثر مخزوني بعد) — نفس قيد
    // StockTransfersController.Cancel.
    [HttpPost("{id:guid}/cancel")]
    [RequirePermission("purchasing.manage")]
    public async Task<IActionResult> Cancel(Guid id)
    {
        var order = await _db.PurchaseOrders.FirstOrDefaultAsync(o => o.Id == id);
        if (order is null) return NotFound();
        if (order.Status is not ("draft" or "ordered"))
        {
            return BadRequest(new { message = "لا يمكن إلغاء أمر بعد استلامه" });
        }

        order.Status = "cancelled";
        _db.LogAudit(order.OrganizationId, CurrentUserId(), "purchase_order.cancelled", "purchase_orders", order.Id, null);
        await _db.SaveChangesAsync();
        return NoContent();
    }

    private async Task<Dictionary<Guid, string>> BranchNamesFor(IEnumerable<Guid> ids)
    {
        var distinct = ids.Distinct().ToList();
        return await _db.Branches.Where(b => distinct.Contains(b.Id)).ToDictionaryAsync(b => b.Id, b => b.Name);
    }

    private async Task<Dictionary<Guid, string>> SupplierNamesFor(IEnumerable<Guid> ids)
    {
        var distinct = ids.Distinct().ToList();
        return await _db.Suppliers.Where(s => distinct.Contains(s.Id)).ToDictionaryAsync(s => s.Id, s => s.Name);
    }

    private async Task<PurchaseOrderDetailDto> ToDetailDto(PurchaseOrder order)
    {
        var branchNames = await BranchNamesFor(new[] { order.BranchId });
        var supplierName = order.SupplierId.HasValue
            ? (await SupplierNamesFor(new[] { order.SupplierId.Value })).GetValueOrDefault(order.SupplierId.Value, "-")
            : "-";
        var productIds = order.Items.Select(i => i.ProductId).ToList();
        var products = await _db.Products.Where(p => productIds.Contains(p.Id)).ToDictionaryAsync(p => p.Id, p => p);

        return new PurchaseOrderDetailDto(
            order.Id, order.BranchId, branchNames.GetValueOrDefault(order.BranchId, "-"),
            order.SupplierId, supplierName, order.Status, order.TotalAmount, order.CreatedAt,
            order.Items.Select(i =>
            {
                products.TryGetValue(i.ProductId, out var product);
                return new PurchaseOrderDetailItemDto(
                    i.ProductId, product?.Name ?? "-", product?.TrackExpiry ?? false,
                    i.Quantity, i.UnitCost, i.SalePrice, i.Quantity * i.UnitCost);
            }).ToList());
    }

    private Guid? CurrentUserId()
    {
        var raw = User.FindFirstValue(JwtRegisteredClaimNames.Sub) ?? User.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(raw, out var id) ? id : null;
    }
}
