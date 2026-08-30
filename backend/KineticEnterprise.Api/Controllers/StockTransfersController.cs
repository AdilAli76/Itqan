using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Authorization;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Controllers;

public record TransferLineRequest(Guid ProductId, decimal Quantity);
public record CreateTransferRequest(Guid FromBranchId, Guid ToBranchId, List<TransferLineRequest> Lines);

public record TransferListItemDto(
    Guid Id, Guid FromBranchId, string FromBranchName, Guid ToBranchId, string ToBranchName,
    string Status, int ItemCount, DateTime CreatedAt);

public record TransferDetailItemDto(Guid ProductId, string ProductName, decimal Quantity);
public record TransferDetailDto(
    Guid Id, Guid FromBranchId, string FromBranchName, Guid ToBranchId, string ToBranchName,
    string Status, DateTime CreatedAt, List<TransferDetailItemDto> Items);

/// <summary>
/// stock_transfers بلا عمود branch_id واحد (from/to معاً) — Security Policy
/// تعزل المنظمة فقط (راجع StockTransfersPolicy)، والفلترة "بحسب فرعي أنا"
/// تتم هنا يدوياً: مدير فرع يرى فقط التحويلات التي فرعه طرف فيها (مصدراً
/// أو هدفاً)، مدير عام يرى كل تحويلات المنظمة.
/// </summary>
[RequireModule("inventory")]
[ApiController]
[Route("api/stock-transfers")]
[Authorize]
public class StockTransfersController : ControllerBase
{
    private readonly AppDbContext _db;
    public StockTransfersController(AppDbContext db) => _db = db;

    [HttpGet]
    public async Task<ActionResult<List<TransferListItemDto>>> GetAll([FromQuery] string? status)
    {
        var query = _db.StockTransfers.Include(t => t.Items).AsQueryable();

        if (Guid.TryParse(User.FindFirstValue("branch_id"), out var branchId))
        {
            query = query.Where(t => t.FromBranchId == branchId || t.ToBranchId == branchId);
        }
        if (!string.IsNullOrWhiteSpace(status)) query = query.Where(t => t.Status == status);

        var transfers = await query.OrderByDescending(t => t.CreatedAt).ToListAsync();
        var branchNames = await BranchNamesFor(transfers.SelectMany(t => new[] { t.FromBranchId, t.ToBranchId }));

        return transfers.Select(t => new TransferListItemDto(
            t.Id, t.FromBranchId, branchNames.GetValueOrDefault(t.FromBranchId, "-"),
            t.ToBranchId, branchNames.GetValueOrDefault(t.ToBranchId, "-"),
            t.Status, t.Items.Count, t.CreatedAt)).ToList();
    }

    [HttpGet("{id:guid}")]
    public async Task<ActionResult<TransferDetailDto>> GetById(Guid id)
    {
        var transfer = await _db.StockTransfers.Include(t => t.Items).FirstOrDefaultAsync(t => t.Id == id);
        if (transfer is null) return NotFound();
        return await ToDetailDto(transfer);
    }

    [HttpPost]
    [RequirePermission("stock_transfer.manage")]
    public async Task<ActionResult<TransferDetailDto>> Create(CreateTransferRequest request)
    {
        if (request.FromBranchId == request.ToBranchId)
        {
            return BadRequest(new { message = "لا يمكن التحويل لنفس الفرع" });
        }
        if (request.Lines.Count == 0)
        {
            return BadRequest(new { message = "أضف صنفاً واحداً على الأقل" });
        }

        var transfer = new StockTransfer
        {
            OrganizationId = Guid.Parse(User.FindFirstValue("organization_id")!),
            FromBranchId = request.FromBranchId,
            ToBranchId = request.ToBranchId,
            CreatedBy = CurrentUserId(),
        };
        foreach (var line in request.Lines)
        {
            transfer.Items.Add(new StockTransferItem { ProductId = line.ProductId, Quantity = line.Quantity });
        }

        _db.StockTransfers.Add(transfer);
        _db.LogAudit(transfer.OrganizationId, CurrentUserId(), "stock_transfer.created", "stock_transfers", transfer.Id,
            newValues: new { transfer.FromBranchId, transfer.ToBranchId, ItemCount = transfer.Items.Count });
        await _db.SaveChangesAsync();

        return CreatedAtAction(nameof(GetById), new { id = transfer.Id }, await ToDetailDto(transfer));
    }

    /// <summary>
    /// pending -> in_transit: يخصم الكمية من مخزون الفرع المصدر فوراً — هذه
    /// اللحظة تمثّل خروج البضاعة فعلياً. الخصم يبدأ من الدفعة الأقرب انتهاءً
    /// (FIFO حسب تاريخ الصلاحية) بدل دفعة واحدة ثابتة، حتى يعمل بشكل صحيح
    /// مع الأصناف التي دخلت المخزون بدفعات متعددة عبر شاشة المخزون.
    /// </summary>
    [HttpPost("{id:guid}/ship")]
    [RequirePermission("stock_transfer.manage")]
    public async Task<IActionResult> Ship(Guid id)
    {
        var transfer = await _db.StockTransfers.Include(t => t.Items).FirstOrDefaultAsync(t => t.Id == id);
        if (transfer is null) return NotFound();
        if (transfer.Status != "pending")
        {
            return BadRequest(new { message = "لا يمكن شحن تحويل ليس في حالة الانتظار" });
        }

        await using var transaction = await _db.Database.BeginTransactionAsync();

        // مستودع العبور: البضاعة تغادر الفرع المصدر وتدخل موضعاً وسيطاً
        // **مرئياً**، بدل أن تختفي من كل تقرير طوال الترحيل. راجع [Warehouse].
        var transit = await TransitWarehouseAsync(transfer.OrganizationId, transfer.FromBranchId);

        foreach (var item in transfer.Items)
        {
            // الموقوف لا يُشحن: قفلُه قرارٌ بأنه لا يُصرَف، وشحنُه إلى فرع آخر
            // تحايلٌ على القرار — البضاعة تصل هناك بلا قفل ولا سبب، لأن
            // stock_transfer_items لا يحمل رقم دفعة أصلاً فيضيع القفل معها.
            // والاستبعاد يقع داخل StockLedger.IssueAsync لكل المسارات معاً.
            List<IssuedLot> issued;
            try
            {
                issued = await StockLedger.IssueAsync(
                    _db, transfer.OrganizationId, transfer.FromBranchId, warehouseId: null,
                    productId: item.ProductId, quantity: item.Quantity,
                    sourceType: StockSourceTypes.TransferOut, sourceId: transfer.Id,
                    userId: CurrentUserId());
            }
            catch (InvalidOperationException ex)
            {
                return BadRequest(new { message = $"{ex.Message} — والموقوف لا يُشحن" });
            }

            // كل دفعة تدخل العبور بتكلفتها ورقمها وصلاحيتها كما خرجت: العبور
            // موضع لا نوع بضاعة، وتجريدها من دفعاتها هنا كان سيُفقدها هويتها
            // قبل أن تصل — فتصل بلا صلاحية ولا تكلفة.
            foreach (var lot in issued)
            {
                await StockLedger.ReceiveAsync(
                    _db, transfer.OrganizationId, transfer.FromBranchId, warehouseId: transit?.Id,
                    productId: item.ProductId, quantity: lot.Quantity, unitCost: lot.UnitCost,
                    sourceType: StockSourceTypes.TransferOut, sourceId: transfer.Id,
                    userId: CurrentUserId(),
                    batchNumber: lot.BatchNumber, expiryDate: lot.ExpiryDate,
                    trackExpiry: lot.ExpiryDate.HasValue);
            }
        }

        transfer.Status = "in_transit";
        _db.LogAudit(transfer.OrganizationId, CurrentUserId(), "stock_transfer.shipped", "stock_transfers", transfer.Id, null);
        await _db.SaveChangesAsync();
        await transaction.CommitAsync();
        return NoContent();
    }

    /// <summary>
    /// in_transit -> received: يضيف الكمية لمخزون الفرع الهدف (دفعة عامة
    /// بلا رقم دفعة/صلاحية — stock_transfer_items لا يخزّن هذه التفاصيل
    /// أصلاً، نفس القيد الموجود في استرجاع الفواتير).
    /// </summary>
    [HttpPost("{id:guid}/receive")]
    [RequirePermission("stock_transfer.manage")]
    public async Task<IActionResult> Receive(Guid id)
    {
        var transfer = await _db.StockTransfers.Include(t => t.Items).FirstOrDefaultAsync(t => t.Id == id);
        if (transfer is null) return NotFound();
        if (transfer.Status != "in_transit")
        {
            return BadRequest(new { message = "لا يمكن استلام تحويل لم يُشحَن بعد" });
        }

        await using var transaction = await _db.Database.BeginTransactionAsync();

        // نفس مستودع عبور الفرع المصدر الذي دخلته البضاعة عند الشحن.
        var transit = await TransitWarehouseAsync(transfer.OrganizationId, transfer.FromBranchId);

        foreach (var item in transfer.Items)
        {
            // يخرج من العبور بدفعاته كما دخل، ثم يدخل الفرع الهدف بها —
            // فتصل البضاعة بصلاحيتها وتكلفتها لا كدفعة عامة مجهولة كما كان.
            List<IssuedLot> arriving;
            try
            {
                arriving = await StockLedger.IssueAsync(
                    _db, transfer.OrganizationId, transfer.FromBranchId, warehouseId: transit?.Id,
                    productId: item.ProductId, quantity: item.Quantity,
                    sourceType: StockSourceTypes.TransferIn, sourceId: transfer.Id,
                    userId: CurrentUserId());
            }
            catch (InvalidOperationException ex)
            {
                return BadRequest(new { message = $"تعذّر إخراج البضاعة من مستودع العبور: {ex.Message}" });
            }

            foreach (var lot in arriving)
            {
                await StockLedger.ReceiveAsync(
                    _db, transfer.OrganizationId, transfer.ToBranchId, warehouseId: null,
                    productId: item.ProductId, quantity: lot.Quantity, unitCost: lot.UnitCost,
                    sourceType: StockSourceTypes.TransferIn, sourceId: transfer.Id,
                    userId: CurrentUserId(),
                    batchNumber: lot.BatchNumber, expiryDate: lot.ExpiryDate,
                    trackExpiry: lot.ExpiryDate.HasValue);
            }
        }

        transfer.Status = "received";
        _db.LogAudit(transfer.OrganizationId, CurrentUserId(), "stock_transfer.received", "stock_transfers", transfer.Id, null);
        await _db.SaveChangesAsync();
        await transaction.CommitAsync();
        return NoContent();
    }

    // إلغاء مسموح فقط قبل الشحن (بلا أثر مخزوني بعد) — بعد in_transit تكون
    // البضاعة قد غادرت الفرع المصدر فعلياً، فالتصحيح عندها تعديل مخزون يدوي
    // (شاشة المخزون) وليس مجرد تغيير حالة نصي على هذا التحويل.
    [HttpPost("{id:guid}/cancel")]
    [RequirePermission("stock_transfer.manage")]
    public async Task<IActionResult> Cancel(Guid id)
    {
        var transfer = await _db.StockTransfers.FirstOrDefaultAsync(t => t.Id == id);
        if (transfer is null) return NotFound();
        if (transfer.Status != "pending")
        {
            return BadRequest(new { message = "لا يمكن إلغاء تحويل بعد شحنه" });
        }

        transfer.Status = "cancelled";
        _db.LogAudit(transfer.OrganizationId, CurrentUserId(), "stock_transfer.cancelled", "stock_transfers", transfer.Id, null);
        await _db.SaveChangesAsync();
        return NoContent();
    }

    private async Task<Dictionary<Guid, string>> BranchNamesFor(IEnumerable<Guid> ids)
    {
        var distinct = ids.Distinct().ToList();
        return await _db.Branches.Where(b => distinct.Contains(b.Id)).ToDictionaryAsync(b => b.Id, b => b.Name);
    }

    private async Task<TransferDetailDto> ToDetailDto(StockTransfer transfer)
    {
        var branchNames = await BranchNamesFor(new[] { transfer.FromBranchId, transfer.ToBranchId });
        var productIds = transfer.Items.Select(i => i.ProductId).ToList();
        var productNames = await _db.Products.Where(p => productIds.Contains(p.Id)).ToDictionaryAsync(p => p.Id, p => p.Name);

        return new TransferDetailDto(
            transfer.Id, transfer.FromBranchId, branchNames.GetValueOrDefault(transfer.FromBranchId, "-"),
            transfer.ToBranchId, branchNames.GetValueOrDefault(transfer.ToBranchId, "-"),
            transfer.Status, transfer.CreatedAt,
            transfer.Items.Select(i => new TransferDetailItemDto(i.ProductId, productNames.GetValueOrDefault(i.ProductId, "-"), i.Quantity)).ToList());
    }

    /// <summary>
    /// مستودع العبور للفرع، ويُنشأ عند أول حاجة إليه.
    ///
    /// <para>الإنشاء الكسول لا الإلزام المسبق: مطالبة كل زبون قائم بإنشاء
    /// مستودع قبل أن يُحوّل كانت ستكسر التحويل لكل من رقّى نظامه، ومستودعٌ
    /// يُنشأ ولا يُستعمل ضوضاء في شجرة فارغة.</para>
    /// </summary>
    private async Task<Warehouse?> TransitWarehouseAsync(Guid organizationId, Guid branchId)
    {
        var transit = await _db.Warehouses.FirstOrDefaultAsync(
            w => w.BranchId == branchId && w.Kind == WarehouseKinds.Transit && w.IsActive);
        if (transit is not null) return transit;

        transit = new Warehouse
        {
            OrganizationId = organizationId,
            BranchId = branchId,
            Name = "بضاعة في الطريق",
            Code = "TRANSIT",
            Kind = WarehouseKinds.Transit,
        };
        _db.Warehouses.Add(transit);
        return transit;
    }

    private Guid? CurrentUserId()
    {
        var raw = User.FindFirstValue(JwtRegisteredClaimNames.Sub) ?? User.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(raw, out var id) ? id : null;
    }
}
