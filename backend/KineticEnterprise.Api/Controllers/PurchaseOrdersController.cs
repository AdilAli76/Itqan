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
public record CreatePurchaseOrderRequest(
    Guid BranchId, Guid? SupplierId, List<PurchaseOrderLineRequest> Lines,
    /// أُنشئ من اقتراح إعادة الطلب لا بيد مستخدم — راجع PurchaseOrder.IsAuto.
    bool IsAuto = false);

public record ReceiveLineRequest(
    Guid ProductId, string? BatchNumber, DateTime? ExpiryDate,
    /// المستلَم فعلياً من هذا السطر. NULL = المتبقّي كاملاً (وهو الغالب).
    decimal? Quantity = null);
public record ReceivePurchaseOrderRequest(
    List<ReceiveLineRequest> Lines,
    /// رقم إشعار المورّد — راجع PurchaseReceipt.SupplierNoteNumber.
    string? SupplierNoteNumber = null,
    /// تاريخ الوصول الفعلي. NULL = الآن. راجع PurchaseReceipt.ReceivedOn.
    DateTime? ReceivedOn = null,
    string? Notes = null);

public record PurchaseReceiptItemDto(
    Guid ProductId, string ProductName, decimal Quantity,
    string BatchNumber, DateTime? ExpiryDate, decimal UnitCost);

public record PurchaseReceiptDto(
    Guid Id, Guid PurchaseOrderId, string? SupplierNoteNumber, DateTime ReceivedOn,
    string? ReceivedByName, string? Notes, DateTime CreatedAt,
    List<PurchaseReceiptItemDto> Items);

public record PurchaseOrderListItemDto(
    Guid Id, Guid BranchId, string BranchName, Guid? SupplierId, string SupplierName,
    string Status, decimal TotalAmount, int ItemCount, DateTime CreatedAt, bool IsAuto);

public record PurchaseOrderDetailItemDto(
    Guid ProductId, string ProductName, bool TrackExpiry, decimal Quantity, decimal UnitCost,
    decimal? SalePrice, decimal LineTotal, decimal ReceivedQuantity, decimal RemainingQuantity);
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
[RequireModule("inventory")]
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
            o.Status, o.TotalAmount, o.Items.Count, o.CreatedAt, o.IsAuto)).ToList();
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
            IsAuto = request.IsAuto,
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

        // تحقّق قبل أي كتابة: كمية أكبر من المتبقّي تُدخل مخزوناً لم يصل،
        // وسالبة تُخرج مخزوناً بلا سبب. والفحص كاملاً قبل البدء يمنع أمراً
        // نصفَ مستلَم بسبب سطر خاطئ في آخر القائمة.
        foreach (var item in order.Items)
        {
            if (!receiveLines.TryGetValue(item.ProductId, out var l) || l.Quantity is null) continue;
            if (l.Quantity < 0)
            {
                return BadRequest(new { message = "الكمية المستلَمة لا يمكن أن تكون سالبة" });
            }
            if (l.Quantity > item.RemainingQuantity)
            {
                return BadRequest(new
                {
                    message = $"الكمية المستلَمة أكبر من المتبقّي ({item.RemainingQuantity:0.##}) لأحد الأصناف"
                });
            }
        }

        await using var transaction = await _db.Database.BeginTransactionAsync();

        // مستند الشحنة يُنشأ مع كل استلام — راجع PurchaseReceipt.
        //
        // التاريخ من المستخدم لا من الساعة: الشحنة تصل الخميس ويُدخلها أمين
        // المخزن الأحد. ويُرفض تاريخ في المستقبل — بضاعة لم تصل بعد لا
        // تُستلَم، والخطأ المطبعي في السنة يفسد كل قياس لاحق لمهلة التوريد.
        var receivedOn = request.ReceivedOn ?? DateTime.UtcNow;
        if (receivedOn.Date > DateTime.UtcNow.Date.AddDays(1))
        {
            return BadRequest(new { message = "تاريخ الاستلام في المستقبل" });
        }

        var receipt = new PurchaseReceipt
        {
            OrganizationId = order.OrganizationId,
            BranchId = order.BranchId,
            PurchaseOrderId = order.Id,
            SupplierNoteNumber = string.IsNullOrWhiteSpace(request.SupplierNoteNumber)
                ? null : request.SupplierNoteNumber.Trim(),
            ReceivedOn = receivedOn,
            ReceivedBy = CurrentUserId(),
            Notes = string.IsNullOrWhiteSpace(request.Notes) ? null : request.Notes.Trim(),
        };

        foreach (var item in order.Items)
        {
            var product = await _db.Products.FirstOrDefaultAsync(p => p.Id == item.ProductId);
            receiveLines.TryGetValue(item.ProductId, out var receiveLine);

            // بلا كمية مذكورة يُستلَم المتبقّي كاملاً — سلوك الاستلام الكامل
            // كما كان، فالطلبات القديمة لا تتغيّر نتيجتها.
            var receiving = receiveLine?.Quantity ?? item.RemainingQuantity;
            if (receiving <= 0) continue;

            var batchNumber = product?.TrackExpiry == true ? (receiveLine?.BatchNumber ?? "") : "";
            var expiryDate = product?.TrackExpiry == true ? receiveLine?.ExpiryDate : null;

            // سطر الإدخال في الدفتر يشير إلى **مستند الاستلام** لا إلى أمر
            // الشراء: الأمر قد يصل على ثلاث شحنات، ونسبة البضاعة إليه تجعل
            // «متى وصلت هذه القطعة» بلا جواب. راجع PurchaseReceipt.
            await StockLedger.ReceiveAsync(
                _db, order.OrganizationId, order.BranchId, warehouseId: null,
                productId: item.ProductId,
                quantity: receiving,
                unitCost: item.UnitCost,
                sourceType: StockSourceTypes.PurchaseReceipt, sourceId: receipt.Id,
                userId: CurrentUserId(),
                batchNumber: batchNumber, expiryDate: expiryDate,
                trackExpiry: product?.TrackExpiry == true,
                postedAt: receivedOn);

            item.ReceivedQuantity += receiving;

            receipt.Items.Add(new PurchaseReceiptItem
            {
                PurchaseOrderItemId = item.Id,
                ProductId = item.ProductId,
                Quantity = receiving,
                BatchNumber = batchNumber,
                ExpiryDate = expiryDate,
                UnitCost = item.UnitCost,
            });

            if (product is not null)
            {
                product.CostPrice = item.UnitCost;
                if (item.SalePrice.HasValue) product.SalePrice = item.SalePrice.Value;
            }
        }

        // الأمر يُغلَق حين يصل كل شيء فقط. وما دام سطر واحد ناقصاً يبقى
        // «مُرسَلاً» فيظهر في قائمة المنتظَر من الموردين — وهذا هو الغرض:
        // توريد ناقص يجب أن يبقى مرئياً حتى يكتمل أو يُلغى.
        // استلامٌ لم يصل فيه شيء لا يُنتج مستنداً: أمرٌ ضُغط عليه بالخطأ
        // وكل سطوره مكتملة كان سيولّد مستنداً فارغاً يُفسد عدّ الشحنات
        // ويُشوّه أي قياس لمهلة التوريد.
        if (receipt.Items.Count == 0)
        {
            return BadRequest(new { message = "لا كمية مستلَمة في هذا الطلب" });
        }
        _db.PurchaseReceipts.Add(receipt);

        var fullyReceived = order.Items.All(i => i.RemainingQuantity <= 0);
        if (fullyReceived) order.Status = "received";
        _db.LogAudit(order.OrganizationId, CurrentUserId(),
            fullyReceived ? "purchase_order.received" : "purchase_order.partially_received",
            "purchase_orders", order.Id,
            newValues: new
            {
                ReceiptId = receipt.Id,
                receipt.SupplierNoteNumber,
                receipt.ReceivedOn,
                Lines = order.Items.Select(i => new { i.ProductId, i.Quantity, i.ReceivedQuantity }),
            });
        await _db.SaveChangesAsync();
        await transaction.CommitAsync();
        return NoContent();
    }

    /// <summary>
    /// شحنات هذا الأمر — الأقدم أولاً، كما وصلت.
    ///
    /// <para>هو الجواب عن «متى وصلت البضاعة وبأي إشعار»، وهو ما كان
    /// <c>ReceivedQuantity</c> التراكمي يبتلعه. ومنه تُقاس مهلة التوريد
    /// الحقيقية: الفرق بين تاريخ الأمر وأول شحنة.</para>
    /// </summary>
    [HttpGet("{id:guid}/receipts")]
    public async Task<ActionResult<List<PurchaseReceiptDto>>> Receipts(Guid id)
    {
        var receipts = await _db.PurchaseReceipts
            .Include(r => r.Items)
            .Where(r => r.PurchaseOrderId == id)
            .OrderBy(r => r.ReceivedOn)
            .ToListAsync();

        if (receipts.Count == 0) return new List<PurchaseReceiptDto>();

        var productIds = receipts.SelectMany(r => r.Items).Select(i => i.ProductId).Distinct().ToList();
        var productNames = await _db.Products
            .Where(p => productIds.Contains(p.Id))
            .ToDictionaryAsync(p => p.Id, p => p.Name);

        var userIds = receipts.Where(r => r.ReceivedBy.HasValue).Select(r => r.ReceivedBy!.Value).Distinct().ToList();
        var userNames = userIds.Count == 0
            ? new Dictionary<Guid, string>()
            : await _db.AppUsers.Where(u => userIds.Contains(u.Id)).ToDictionaryAsync(u => u.Id, u => u.FullName);

        return receipts.Select(r => new PurchaseReceiptDto(
            r.Id, r.PurchaseOrderId, r.SupplierNoteNumber, r.ReceivedOn,
            r.ReceivedBy is null ? null : userNames.GetValueOrDefault(r.ReceivedBy.Value),
            r.Notes, r.CreatedAt,
            r.Items.Select(i => new PurchaseReceiptItemDto(
                i.ProductId, productNames.GetValueOrDefault(i.ProductId, "-"),
                i.Quantity, i.BatchNumber, i.ExpiryDate, i.UnitCost)).ToList())).ToList();
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
                    i.Quantity, i.UnitCost, i.SalePrice, i.Quantity * i.UnitCost,
                    i.ReceivedQuantity, i.RemainingQuantity);
            }).ToList());
    }

    private Guid? CurrentUserId()
    {
        var raw = User.FindFirstValue(JwtRegisteredClaimNames.Sub) ?? User.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(raw, out var id) ? id : null;
    }
}
