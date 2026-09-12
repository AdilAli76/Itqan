using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Authorization;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Controllers;

public record SupplierInvoiceLineRequest(Guid PurchaseReceiptItemId, decimal Quantity, decimal UnitCost);

public record NewProductLineRequest(Guid ProductId, decimal Quantity, decimal SupplierCost, decimal? SellingPrice);

public record SupplierInvoiceExpenseRequest(string Name, decimal Amount);

public record CreateSupplierInvoiceRequest(
    Guid BranchId, Guid SupplierId, string InvoiceNumber, DateTime InvoiceDate,
    DateTime? DueDate, decimal TotalAmount, string? Notes,
    List<SupplierInvoiceLineRequest> Lines,
    List<NewProductLineRequest>? NewProductLines,
    List<SupplierInvoiceExpenseRequest>? Expenses);

public record CancelSupplierInvoiceRequest(string Reason);

/// <summary>سطر مطابقة: ما وصل، وما فُوتر، والفرق بينهما.</summary>
public record MatchLineDto(
    Guid PurchaseReceiptItemId, Guid ProductId, string ProductName,
    string? SupplierNoteNumber, DateTime ReceivedOn,
    decimal ReceivedQuantity, decimal ReceivedUnitCost,
    decimal InvoicedQuantity, decimal InvoicedUnitCost,
    decimal QuantityVariance, decimal UnitCostVariance, decimal AmountVariance);

public record SupplierInvoiceDto(
    Guid Id, Guid SupplierId, string SupplierName, string InvoiceNumber,
    DateTime InvoiceDate, DateTime? DueDate, decimal TotalAmount,
    decimal LinesTotal, decimal HeaderVariance,
    string Status, string? Notes, DateTime? PostedAt,
    string? CreatedByName, DateTime CreatedAt,
    List<MatchLineDto> Lines);

/// <summary>سطر في تقرير مقارنة أسعار الشراء.</summary>
public record ProductPriceHistoryDto(
    Guid ProductId, string ProductName, string Sku,
    decimal LatestCost, DateTime LatestOn, string? LatestSupplierName,
    /// السعر قبل الأخير — NULL يعني أن الصنف اشتُري مرّةً واحدة فلا مقارنة.
    decimal? PreviousCost, DateTime? PreviousOn,
    /// نسبة التغيّر مئويةً. موجبٌ يعني ارتفاعاً.
    decimal? ChangePercent,
    string? CheapestSupplierName, decimal CheapestCost,
    int SupplierCount, int PurchaseCount);

/// <summary>سطر استلامٍ لم يُفوتر بعد — ما يُعرَض للاختيار عند إنشاء فاتورة.</summary>
public record UninvoicedReceiptItemDto(
    Guid PurchaseReceiptItemId, Guid PurchaseReceiptId, string? SupplierNoteNumber,
    DateTime ReceivedOn, Guid ProductId, string ProductName,
    decimal Quantity, decimal UnitCost);

/// <summary>
/// فواتير الموردين ومطابقتها بالاستلام.
///
/// <para><b>الفجوة:</b> لم يكن للمورّد فاتورة في النظام. الدَّين يُنشَأ من
/// ورقة أمين المخزن بتكلفة أمر الشراء، فإن فوتر المورّد سعراً أو كميةً
/// مختلفة لم يظهر الفرق في أي موضع — يُدفَع ما تقوله الورقة ويبقى الميزان
/// يقول رقماً آخر.</para>
///
/// <para><b>المطابقة الثلاثية:</b> أمر الشراء (ما اتُّفق عليه) ← الاستلام (ما
/// وصل) ← الفاتورة (ما طُولب به). وثلاثتها تلتقي هنا: كل سطر فاتورة يشير إلى
/// سطر استلام بعينه، فالفرق يُحسَب لا يُقدَّر.</para>
///
/// <para>مقيَّدة بوحدة <c>accounting</c>: الفاتورة هنا مستندٌ محاسبي، ومنظمةٌ
/// بلا دفتر ليس لها ما تُفرغه فيه.</para>
/// </summary>
[RequireModule("accounting")]
// وprocurement معها: منظمةٌ بلا مشتريات لا استلامَ عندها تُفوتره، فكل
// نقطة نهاية هنا تُرجع فارغاً أبداً. وبابٌ مفتوح على لا شيء يُوهم من
// يجده أن الميزة موجودة ومعطوبة.
[RequireModule("procurement")]
[ApiController]
[Route("api/supplier-invoices")]
[Authorize]
public class SupplierInvoicesController : ControllerBase
{
    private readonly AppDbContext _db;
    public SupplierInvoicesController(AppDbContext db) => _db = db;

    /// <summary>
    /// سطور استلامٍ لم تُفوتر بعد — لمورّد بعينه.
    ///
    /// <para>هي ما يُبنى عليه الاختيار: بدل أن يكتب المستخدم أصنافاً من
    /// رأسه، يختار من الوارد فعلاً. فلا تُفوتر بضاعةٌ لم تصل، ولا يُفوتر
    /// سطرٌ مرّتين.</para>
    /// </summary>
    [HttpGet("uninvoiced")]
    public async Task<ActionResult<List<UninvoicedReceiptItemDto>>> Uninvoiced(
        [FromQuery] Guid supplierId)
    {
        var invoiced = _db.SupplierInvoiceLines
            .Where(l => _db.SupplierInvoices
                .Any(i => i.Id == l.SupplierInvoiceId && i.Status != SupplierInvoiceStatuses.Cancelled))
            .Select(l => l.PurchaseReceiptItemId);

        return await (
            from item in _db.PurchaseReceiptItems
            join receipt in _db.PurchaseReceipts on item.PurchaseReceiptId equals receipt.Id
            join order in _db.PurchaseOrders on receipt.PurchaseOrderId equals order.Id
            join product in _db.Products on item.ProductId equals product.Id
            where order.SupplierId == supplierId && !invoiced.Contains(item.Id)
            orderby receipt.ReceivedOn
            select new UninvoicedReceiptItemDto(
                item.Id, receipt.Id, receipt.SupplierNoteNumber, receipt.ReceivedOn,
                item.ProductId, product.Name, item.Quantity, item.UnitCost))
            .ToListAsync();
    }

    /// <summary>
    /// مقارنة أسعار الشراء — آخر سعر لكل صنف، والسعر قبله، والتغيّر.
    ///
    /// <para><b>العطب الذي يسدّه:</b> المشتري لا يعرف بكم اشترى هذا الصنف
    /// آخر مرّة. تصله فاتورة المورّد بسعرٍ أعلى فيدفعها، لأن الرقم القديم ليس
    /// أمامه. وفرقُ الفاتورة عن أمر الشراء
    /// (<see cref="AccountRoles.PurchasePriceVariance"/>) يُظهر الفرق **داخل
    /// الصفقة الواحدة** فقط؛ أمّا الارتفاع التدريجي عبر الصفقات فلا يُرى
    /// إطلاقاً — وهو ما يأكل الهامش فعلاً.</para>
    ///
    /// <para><b>ولا عمود واحد جديد:</b> كل سعرٍ دُفع محفوظٌ أصلاً في
    /// <c>purchase_receipt_items</c> مؤرَّخاً ومنسوباً إلى مورّده. التقرير
    /// محسوبٌ لا مخزَّن — وعمودان يحملان «آخر سعر» و«السعر السابق» يفقدان ما
    /// قبلهما، ويحتاجان تحديثاً في كل استلام فينحرفان.</para>
    /// </summary>
    [HttpGet("price-history")]
    public async Task<ActionResult<List<ProductPriceHistoryDto>>> PriceHistory(
        [FromQuery] Guid? supplierId, [FromQuery] Guid? productId)
    {
        // كل استلام كواقعة سعر: الكمية والسعر والتاريخ والمورّد.
        var query =
            from item in _db.PurchaseReceiptItems
            join receipt in _db.PurchaseReceipts on item.PurchaseReceiptId equals receipt.Id
            join order in _db.PurchaseOrders on receipt.PurchaseOrderId equals order.Id
            join product in _db.Products on item.ProductId equals product.Id
            select new
            {
                item.ProductId,
                ProductName = product.Name,
                product.Sku,
                order.SupplierId,
                receipt.ReceivedOn,
                item.UnitCost,
            };

        if (productId is { } pid) query = query.Where(x => x.ProductId == pid);
        if (supplierId is { } sid) query = query.Where(x => x.SupplierId == sid);

        var facts = await query.ToListAsync();
        if (facts.Count == 0) return new List<ProductPriceHistoryDto>();

        var supplierNames = await _db.Suppliers
            .ToDictionaryAsync(x => x.Id, x => x.Name);

        var result = new List<ProductPriceHistoryDto>();

        foreach (var group in facts.GroupBy(f => f.ProductId))
        {
            // الأحدث أولاً — والمقارنة بين آخر شرائين لا بين أعلى وأدنى:
            // الاتجاه هو ما يقرّر، لا المدى.
            var ordered = group.OrderByDescending(f => f.ReceivedOn).ToList();
            var latest = ordered[0];
            var previous = ordered.Skip(1).FirstOrDefault(f => f.UnitCost != latest.UnitCost)
                           ?? ordered.Skip(1).FirstOrDefault();

            decimal? change = previous is null || previous.UnitCost == 0
                ? null
                : Math.Round(((latest.UnitCost - previous.UnitCost) / previous.UnitCost) * 100, 1);

            // أرخص مورّد لهذا الصنف — بآخر سعرٍ لكلٍّ منهم لا بأقدمه.
            var perSupplier = group
                .GroupBy(f => f.SupplierId)
                .Select(g => g.OrderByDescending(f => f.ReceivedOn).First())
                .OrderBy(f => f.UnitCost)
                .ToList();
            var cheapest = perSupplier[0];

            result.Add(new ProductPriceHistoryDto(
                latest.ProductId, latest.ProductName, latest.Sku,
                latest.UnitCost, latest.ReceivedOn,
                latest.SupplierId is null ? null : supplierNames.GetValueOrDefault(latest.SupplierId.Value),
                previous?.UnitCost, previous?.ReceivedOn,
                change,
                cheapest.SupplierId is null ? null : supplierNames.GetValueOrDefault(cheapest.SupplierId.Value),
                cheapest.UnitCost,
                perSupplier.Count,
                group.Count()));
        }

        // الأعلى ارتفاعاً أولاً: من يفتح التقرير يريد ما ارتفع لا ما استقرّ.
        return result
            .OrderByDescending(r => r.ChangePercent ?? decimal.MinValue)
            .ThenBy(r => r.ProductName)
            .ToList();
    }

    [HttpGet]
    public async Task<ActionResult<List<SupplierInvoiceDto>>> GetAll(
        [FromQuery] Guid? supplierId, [FromQuery] string? status)
    {
        var query = _db.SupplierInvoices.AsQueryable();
        if (supplierId is { } sid) query = query.Where(i => i.SupplierId == sid);
        if (!string.IsNullOrWhiteSpace(status)) query = query.Where(i => i.Status == status);

        var invoices = await query.OrderByDescending(i => i.InvoiceDate).Take(200).ToListAsync();

        var result = new List<SupplierInvoiceDto>();
        foreach (var invoice in invoices) result.Add(await ToDtoAsync(invoice));
        return result;
    }

    [HttpGet("{id:guid}")]
    public async Task<ActionResult<SupplierInvoiceDto>> GetOne(Guid id)
    {
        var invoice = await _db.SupplierInvoices.FirstOrDefaultAsync(i => i.Id == id);
        if (invoice is null) return NotFound();
        return await ToDtoAsync(invoice);
    }

    /// <summary>
    /// فاتورة مورّد جديدة — مسوّدة، ثم تُرحَّل صراحةً.
    ///
    /// <para><b>ولماذا خطوتان:</b> الفاتورة تُدخَل عن ورقة، والورقة تُقرأ
    /// خطأً. مسوّدةٌ تُراجَع وتُصحَّح أهون من قيدٍ يلزمه عكس. والترحيل
    /// اختيارٌ صريح فيعرف من يضغطه أنه يُثبت دَيناً.</para>
    /// </summary>
    [HttpPost]
    public async Task<ActionResult<SupplierInvoiceDto>> Create(CreateSupplierInvoiceRequest request)
    {
        var number = (request.InvoiceNumber ?? "").Trim();
        if (number.Length == 0) return BadRequest(new { message = "رقم الفاتورة إلزامي" });

        var hasLines = request.Lines?.Count > 0;
        var hasNewProducts = request.NewProductLines?.Count > 0;
        if (!hasLines && !hasNewProducts)
            return BadRequest(new { message = "الفاتورة بلا سطور — اختر ما تُفوتره أو أضف منتجات" });

        if (request.TotalAmount <= 0)
            return BadRequest(new { message = "إجمالي الفاتورة يجب أن يكون أكبر من صفر" });

        var supplier = await _db.Suppliers.FirstOrDefaultAsync(s => s.Id == request.SupplierId);
        if (supplier is null) return BadRequest(new { message = "المورّد غير موجود" });

        // معالجة سطور الاستلام (الموجودة)
        var receiptProducts = new Dictionary<Guid, Guid>();
        if (hasLines && request.Lines != null)
        {
            var itemIds = request.Lines!.Select(l => l.PurchaseReceiptItemId).ToList();
            if (itemIds.Distinct().Count() != itemIds.Count)
                return BadRequest(new { message = "سطر استلامٍ مكرَّر في الفاتورة" });

            var owned = await (
                from item in _db.PurchaseReceiptItems
                join receipt in _db.PurchaseReceipts on item.PurchaseReceiptId equals receipt.Id
                join order in _db.PurchaseOrders on receipt.PurchaseOrderId equals order.Id
                where itemIds.Contains(item.Id) && order.SupplierId == request.SupplierId
                select item.Id).ToListAsync();
            if (owned.Count != itemIds.Count)
                return BadRequest(new { message = "سطرٌ لا يخصّ استلاماً من هذا المورّد" });

            var alreadyInvoiced = await _db.SupplierInvoiceLines
                .Where(l => l.PurchaseReceiptItemId.HasValue && itemIds.Contains(l.PurchaseReceiptItemId.Value))
                .Where(l => _db.SupplierInvoices
                    .Any(i => i.Id == l.SupplierInvoiceId && i.Status != SupplierInvoiceStatuses.Cancelled))
                .AnyAsync();
            if (alreadyInvoiced)
                return BadRequest(new { message = "أحد السطور مُفوتَر في فاتورة أخرى" });

            receiptProducts = await _db.PurchaseReceiptItems
                .Where(i => itemIds.Contains(i.Id))
                .ToDictionaryAsync(i => i.Id, i => i.ProductId);
        }

        // التحقق من المنتجات الجديدة
        if (hasNewProducts && request.NewProductLines != null)
        {
            var newProductIds = request.NewProductLines!.Select(p => p.ProductId).ToList();
            var existingProducts = await _db.Products
                .Where(p => newProductIds.Contains(p.Id))
                .Select(p => p.Id)
                .ToListAsync();
            if (existingProducts.Count != newProductIds.Count)
                return BadRequest(new { message = "أحد المنتجات الجديدة غير موجود" });
        }

        var orgId = Guid.Parse(User.FindFirstValue("organization_id")!);

        var invoice = new SupplierInvoice
        {
            OrganizationId = orgId,
            BranchId = request.BranchId,
            SupplierId = request.SupplierId,
            InvoiceNumber = number,
            InvoiceDate = request.InvoiceDate.Date,
            DueDate = request.DueDate?.Date,
            TotalAmount = request.TotalAmount,
            Notes = string.IsNullOrWhiteSpace(request.Notes) ? null : request.Notes.Trim(),
            CreatedBy = CurrentUserId(),
        };

        // إضافة سطور الاستلام
        if (hasLines && request.Lines != null)
        {
            foreach (var line in request.Lines!)
            {
                if (line.Quantity <= 0)
                    return BadRequest(new { message = "كمية السطر يجب أن تكون أكبر من صفر" });
                if (line.UnitCost < 0)
                    return BadRequest(new { message = "سعر الوحدة لا يكون سالباً" });

                invoice.Lines.Add(new SupplierInvoiceLine
                {
                    PurchaseReceiptItemId = line.PurchaseReceiptItemId,
                    ProductId = receiptProducts[line.PurchaseReceiptItemId],
                    Quantity = line.Quantity,
                    UnitCost = line.UnitCost,
                });
            }
        }

        // إضافة المنتجات الجديدة
        if (hasNewProducts && request.NewProductLines != null)
        {
            foreach (var line in request.NewProductLines!)
            {
                if (line.Quantity <= 0)
                    return BadRequest(new { message = "كمية المنتج يجب أن تكون أكبر من صفر" });
                if (line.SupplierCost < 0)
                    return BadRequest(new { message = "سعر المورد لا يكون سالباً" });
                if (line.SellingPrice is { } sp && sp < 0)
                    return BadRequest(new { message = "سعر البيع لا يكون سالباً" });

                invoice.Lines.Add(new SupplierInvoiceLine
                {
                    ProductId = line.ProductId,
                    Quantity = line.Quantity,
                    UnitCost = line.SupplierCost,
                    SellingPrice = line.SellingPrice,
                });
            }
        }

        // إضافة المصاريف
        if (request.Expenses?.Count > 0)
        {
            foreach (var expense in request.Expenses)
            {
                var name = (expense.Name ?? "").Trim();
                if (name.Length == 0) continue;
                if (expense.Amount < 0)
                    return BadRequest(new { message = "مبلغ المصروف لا يكون سالباً" });

                invoice.Expenses.Add(new SupplierInvoiceExpense
                {
                    Name = name,
                    Amount = expense.Amount,
                });
            }
        }

        _db.SupplierInvoices.Add(invoice);
        _db.LogAudit(orgId, CurrentUserId(), "supplier_invoice.created", "supplier_invoices", invoice.Id,
            newValues: new { invoice.InvoiceNumber, invoice.TotalAmount, Lines = invoice.Lines.Count, Expenses = invoice.Expenses.Count });
        await _db.SaveChangesAsync();

        return await ToDtoAsync(invoice);
    }

    /// <summary>
    /// ترحيل الفاتورة.
    ///
    /// <code>
    ///   من ح/ بضاعة وردت ولم تُفوتَر   (بقيمة ما وصل)
    ///   من ح/ فروق أسعار المشتريات      (الفرق، إن كانت الفاتورة أعلى)
    ///       إلى ح/ الموردون             (بإجمالي الفاتورة)
    /// </code>
    ///
    /// <para><b>والفرق يُقيَّد ولا يُرفض:</b> فاتورةٌ تُردّ لأن فيها فرق
    /// دينارين تُدفَع خارج النظام، فيضيع أثرها كله. فتُقبَل ويقف الفرق في
    /// حسابٍ ظاهر للمراجعة. ورصيدُه المتراكم يقول كم يُكلّف المورّد الذي
    /// يرفع سعره بعد الاتفاق.</para>
    ///
    /// <para>وبتاريخ الفاتورة لا تاريخ الإدخال — فاتورةُ الشهر الماضي تنتمي
    /// محاسبياً إلى الشهر الماضي.</para>
    /// </summary>
    [HttpPost("{id:guid}/post")]
    public async Task<ActionResult<SupplierInvoiceDto>> PostInvoice(Guid id)
    {
        var invoice = await _db.SupplierInvoices
            .Include(i => i.Lines)
            .FirstOrDefaultAsync(i => i.Id == id);
        if (invoice is null) return NotFound();

        if (invoice.Status == SupplierInvoiceStatuses.Posted)
            return BadRequest(new { message = "الفاتورة مُرحَّلة أصلاً" });
        if (invoice.Status == SupplierInvoiceStatuses.Cancelled)
            return BadRequest(new { message = "الفاتورة مُلغاة — لا تُرحَّل" });

        var org = await _db.Organizations.FirstOrDefaultAsync();
        var license = await _db.Licenses.FirstOrDefaultAsync();
        if (org is null || !Ledger.IsEnabled(org, license))
            return BadRequest(new { message = "وحدة المحاسبة غير مفعَّلة" });

        var supplier = await _db.Suppliers.FirstOrDefaultAsync(s => s.Id == invoice.SupplierId);

        // قيمة ما وصل فعلاً — هي ما وقف في «وردت ولم تُفوتَر» عند الاستلام،
        // فبها بالضبط يُفرَّغ. وأي رقم آخر يترك فيه رصيداً وهمياً لا يُصفَّر.
        var itemIds = invoice.Lines.Select(l => l.PurchaseReceiptItemId).ToList();
        var receivedAmount = await _db.PurchaseReceiptItems
            .Where(i => itemIds.Contains(i.Id))
            .SumAsync(i => i.Quantity * i.UnitCost);

        var variance = invoice.TotalAmount - receivedAmount;

        await using var transaction = await _db.Database.BeginTransactionAsync();

        var lines = new List<PostingLine>
        {
            new(AccountRoles.GoodsReceivedNotInvoiced, receivedAmount, 0),
            new(AccountRoles.Payables, 0, invoice.TotalAmount),
        };

        if (variance != 0)
        {
            // الفاتورة أعلى ⇒ الفرق مدين (تكلفة إضافية). أقلّ ⇒ دائن (وفر).
            lines.Add(variance > 0
                ? new PostingLine(AccountRoles.PurchasePriceVariance, variance, 0, "فرق سعر")
                : new PostingLine(AccountRoles.PurchasePriceVariance, 0, -variance, "فرق سعر"));
        }

        await Ledger.PostAsync(_db, invoice.OrganizationId, invoice.BranchId,
            JournalSources.SupplierInvoice, invoice.Id,
            $"فاتورة مورّد {invoice.InvoiceNumber} — {supplier?.Name ?? "غير معروف"}",
            lines, CurrentUserId(), invoice.InvoiceDate);

        invoice.Status = SupplierInvoiceStatuses.Posted;
        invoice.PostedAt = DateTime.UtcNow;

        _db.LogAudit(invoice.OrganizationId, CurrentUserId(), "supplier_invoice.posted",
            "supplier_invoices", invoice.Id,
            newValues: new { invoice.TotalAmount, ReceivedAmount = receivedAmount, Variance = variance });
        await _db.SaveChangesAsync();
        await transaction.CommitAsync();

        return await ToDtoAsync(invoice);
    }

    /// <summary>
    /// إلغاء الفاتورة — بقيدٍ عكسي إن كانت مُرحَّلة.
    ///
    /// <para>لا تُحذف: سطورُها تحجز سطور الاستلام من التفويتر مرّتين، وحذفُها
    /// يُطلقها بلا أثر يشرح لماذا. والإلغاء يُطلقها **وهو مسجَّل**.</para>
    /// </summary>
    [HttpPost("{id:guid}/cancel")]
    public async Task<IActionResult> Cancel(Guid id, CancelSupplierInvoiceRequest request)
    {
        var reason = (request?.Reason ?? "").Trim();
        if (reason.Length == 0) return BadRequest(new { message = "سبب الإلغاء إلزامي" });

        var invoice = await _db.SupplierInvoices.FirstOrDefaultAsync(i => i.Id == id);
        if (invoice is null) return NotFound();
        if (invoice.Status == SupplierInvoiceStatuses.Cancelled)
            return BadRequest(new { message = "الفاتورة مُلغاة أصلاً" });

        await using var transaction = await _db.Database.BeginTransactionAsync();

        if (invoice.Status == SupplierInvoiceStatuses.Posted)
        {
            var entry = await _db.JournalEntries.FirstOrDefaultAsync(e =>
                e.Source == JournalSources.SupplierInvoice && e.SourceId == invoice.Id);
            if (entry is not null)
            {
                await Ledger.ReverseAsync(_db, entry.Id, reason, CurrentUserId());
            }
        }

        invoice.Status = SupplierInvoiceStatuses.Cancelled;
        _db.LogAudit(invoice.OrganizationId, CurrentUserId(), "supplier_invoice.cancelled",
            "supplier_invoices", invoice.Id, newValues: new { Reason = reason });
        await _db.SaveChangesAsync();
        await transaction.CommitAsync();

        return NoContent();
    }

    /// <summary>
    /// يبني المطابقة: لكل سطر، ما وصل وما فُوتر والفرق.
    ///
    /// <para>محسوبةً لا مخزَّنة — تكلفة سطر الاستلام قد تتغيّر، والمطابقة
    /// يجب أن تعكس الحال لا لقطةً قديمة منها.</para>
    /// </summary>
    private async Task<SupplierInvoiceDto> ToDtoAsync(SupplierInvoice invoice)
    {
        var lines = invoice.Lines.Count > 0
            ? invoice.Lines
            : await _db.SupplierInvoiceLines.Where(l => l.SupplierInvoiceId == invoice.Id).ToListAsync();

        var itemIds = lines.Select(l => l.PurchaseReceiptItemId).ToList();
        var received = await (
            from item in _db.PurchaseReceiptItems
            join receipt in _db.PurchaseReceipts on item.PurchaseReceiptId equals receipt.Id
            join product in _db.Products on item.ProductId equals product.Id
            where itemIds.Contains(item.Id)
            select new
            {
                item.Id,
                ProductName = product.Name,
                receipt.SupplierNoteNumber,
                receipt.ReceivedOn,
                item.Quantity,
                item.UnitCost,
            }).ToDictionaryAsync(x => x.Id, x => x);

        var supplierName = await _db.Suppliers
            .Where(s => s.Id == invoice.SupplierId).Select(s => s.Name).FirstOrDefaultAsync();
        var createdByName = invoice.CreatedBy is null ? null : await _db.AppUsers
            .Where(u => u.Id == invoice.CreatedBy).Select(u => u.FullName).FirstOrDefaultAsync();

        var matchLines = lines.Select(l =>
        {
            var r = l.PurchaseReceiptItemId.HasValue ? received.GetValueOrDefault(l.PurchaseReceiptItemId.Value) : null;
            var receivedQuantity = r?.Quantity ?? 0;
            var receivedUnitCost = r?.UnitCost ?? 0;
            return new MatchLineDto(
                l.PurchaseReceiptItemId ?? Guid.Empty, l.ProductId, r?.ProductName ?? "—",
                r?.SupplierNoteNumber, r?.ReceivedOn ?? invoice.InvoiceDate,
                receivedQuantity, receivedUnitCost, l.Quantity, l.UnitCost,
                l.Quantity - receivedQuantity,
                l.UnitCost - receivedUnitCost,
                (l.Quantity * l.UnitCost) - (receivedQuantity * receivedUnitCost));
        }).ToList();

        var linesTotal = matchLines.Sum(l => l.InvoicedQuantity * l.InvoicedUnitCost);

        return new SupplierInvoiceDto(
            invoice.Id, invoice.SupplierId, supplierName ?? "—", invoice.InvoiceNumber,
            invoice.InvoiceDate, invoice.DueDate, invoice.TotalAmount,
            linesTotal,
            // فرق الرأس عن مجموع السطور: نقلٌ أو رسمٌ لم يُنسَب إلى صنف، أو
            // خطأ إدخال. ظاهرٌ في الحالين — من يراه يعرف أيّهما.
            invoice.TotalAmount - linesTotal,
            invoice.Status, invoice.Notes, invoice.PostedAt,
            createdByName, invoice.CreatedAt, matchLines);
    }

    private Guid? CurrentUserId()
    {
        var raw = User.FindFirstValue(JwtRegisteredClaimNames.Sub) ?? User.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(raw, out var id) ? id : null;
    }
}
