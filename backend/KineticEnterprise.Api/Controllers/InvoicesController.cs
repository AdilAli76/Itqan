using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Authorization;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Hubs;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Controllers;

public record InvoiceLineRequest(Guid ProductId, decimal Quantity, decimal UnitPrice);
public record CreateInvoiceRequest(
    Guid BranchId, Guid? CustomerId, string PaymentMethod, List<InvoiceLineRequest> Lines,
    // يُطلَب فقط عند الدفع من محفظة العميل — البطاقة وحدها لا تكفي للصرف،
    // وإلا كان من يجدها ينفقها.
    string? CustomerPin = null);

public record InvoiceListItemDto(
    Guid Id, string InvoiceNumber, string InvoiceType, string Status,
    Guid? CustomerId, string? CustomerName, int ItemCount, decimal TotalAmount,
    string PaymentMethod, DateTime CreatedAt);

public record InvoiceDetailItemDto(Guid ProductId, string ProductName, decimal Quantity, decimal UnitPrice, decimal LineTotal);
public record InvoicePaymentDto(string Method, decimal Amount);
public record InvoiceDetailDto(
    Guid Id, string InvoiceNumber, string InvoiceType, string Status,
    Guid? CustomerId, string? CustomerName, Guid? OriginalInvoiceId,
    decimal Subtotal, decimal TaxAmount, decimal DiscountAmount, decimal TotalAmount,
    DateTime CreatedAt, List<InvoiceDetailItemDto> Items, List<InvoicePaymentDto> Payments);

[ApiController]
[Route("api/invoices")]
[Authorize]
public class InvoicesController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly IHubContext<NotificationsHub> _hub;

    public InvoicesController(AppDbContext db, IHubContext<NotificationsHub> hub)
    {
        _db = db;
        _hub = hub;
    }

    /// <summary>
    /// شاشة "الفواتير" في Flutter — فلترة بالحالة/النوع/المدى الزمني تُنفَّذ
    /// في قاعدة البيانات، وبحث النص الحر (رقم الفاتورة أو اسم العميل) في
    /// الذاكرة بعدها لأنه يحتاج ربط جدول customers الذي لا تربطه Invoice
    /// بعلاقة EF مباشرة (تعمّدنا عدم إضافة Navigation Property لعميل حتى لا
    /// نحمّل بيانات العميل الكاملة مع كل استعلام فواتير غير ضروري).
    /// </summary>
    [HttpGet]
    public async Task<ActionResult<List<InvoiceListItemDto>>> GetAll(
        [FromQuery] string? search,
        [FromQuery] string? status,
        [FromQuery] string? invoiceType,
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to)
    {
        var query = _db.Invoices.Include(i => i.Items).Include(i => i.Payments).AsQueryable();

        if (!string.IsNullOrWhiteSpace(status)) query = query.Where(i => i.Status == status);
        if (!string.IsNullOrWhiteSpace(invoiceType)) query = query.Where(i => i.InvoiceType == invoiceType);
        if (from.HasValue) query = query.Where(i => i.CreatedAt >= from.Value);
        if (to.HasValue) query = query.Where(i => i.CreatedAt < to.Value.AddDays(1));

        var invoices = await query.OrderByDescending(i => i.CreatedAt).ToListAsync();

        var customerIds = invoices.Where(i => i.CustomerId.HasValue).Select(i => i.CustomerId!.Value).Distinct().ToList();
        var customerNames = await _db.Customers
            .Where(c => customerIds.Contains(c.Id))
            .ToDictionaryAsync(c => c.Id, c => c.FullName);

        var result = invoices.Select(i =>
        {
            customerNames.TryGetValue(i.CustomerId ?? Guid.Empty, out var customerName);
            var paymentMethod = i.Payments.Count == 0 ? "-" : i.Payments.Count == 1 ? i.Payments[0].Method : "متعدد";
            return new InvoiceListItemDto(
                i.Id, i.InvoiceNumber, i.InvoiceType, i.Status,
                i.CustomerId, customerName, i.Items.Count, i.TotalAmount, paymentMethod, i.CreatedAt);
        });

        if (!string.IsNullOrWhiteSpace(search))
        {
            result = result.Where(r =>
                r.InvoiceNumber.Contains(search, StringComparison.OrdinalIgnoreCase) ||
                (r.CustomerName != null && r.CustomerName.Contains(search, StringComparison.OrdinalIgnoreCase)));
        }

        return result.ToList();
    }

    [HttpGet("{id:guid}")]
    public async Task<ActionResult<InvoiceDetailDto>> GetById(Guid id)
    {
        var invoice = await _db.Invoices.Include(i => i.Items).Include(i => i.Payments)
            .FirstOrDefaultAsync(i => i.Id == id);
        if (invoice is null) return NotFound();

        var productIds = invoice.Items.Select(i => i.ProductId).ToList();
        var productNames = await _db.Products
            .Where(p => productIds.Contains(p.Id))
            .ToDictionaryAsync(p => p.Id, p => p.Name);

        string? customerName = null;
        if (invoice.CustomerId.HasValue)
        {
            customerName = await _db.Customers
                .Where(c => c.Id == invoice.CustomerId.Value)
                .Select(c => c.FullName)
                .FirstOrDefaultAsync();
        }

        return new InvoiceDetailDto(
            invoice.Id, invoice.InvoiceNumber, invoice.InvoiceType, invoice.Status,
            invoice.CustomerId, customerName, invoice.OriginalInvoiceId,
            invoice.Subtotal, invoice.TaxAmount, invoice.DiscountAmount, invoice.TotalAmount,
            invoice.CreatedAt,
            invoice.Items.Select(i => new InvoiceDetailItemDto(
                i.ProductId, productNames.GetValueOrDefault(i.ProductId, "-"), i.Quantity, i.UnitPrice, i.LineTotal)).ToList(),
            invoice.Payments.Select(p => new InvoicePaymentDto(p.Method, p.Amount)).ToList());
    }

    /// <summary>
    /// يقابل زر "خصم من رصيد العميل" / "نقداً" في شاشة POS في Flutter.
    /// العملية بأكملها ضمن Transaction واحدة: خصم مخزون + خصم رصيد + إنشاء
    /// فاتورة، حتى لا يحدث نقص مخزون بدون فاتورة مطابقة (وهي بالضبط الثغرة
    /// المالية الأخطر في أي نظام POS مبني على استعلامات منفصلة).
    /// </summary>
    [HttpPost]
    public async Task<ActionResult<Invoice>> Create(CreateInvoiceRequest request)
    {
        var payingFromWallet = request.PaymentMethod == "customer_wallet" && request.CustomerId.HasValue;
        Customer? walletCustomer = null;

        // الرقم السري يُتحقَّق منه *قبل* فتح المعاملة وقبل لمس المخزون.
        //
        // ترتيبه هنا مقصود لسببين: محاولة فاشلة يجب أن تُحفَظ دائماً وإلا لم
        // يتقدّم عدّاد القفل وصار التخمين بلا حد — ولو حُفظت بعد بدء المعاملة
        // لألغاها التراجع معها. وفحص الرصيد يأتي بعده لا قبله، وإلا أمكن
        // استكشاف أرصدة العملاء برموز بطاقات وحدها بلا رقم سري.
        if (payingFromWallet)
        {
            walletCustomer = await _db.Customers.FindAsync(request.CustomerId!.Value);
            if (walletCustomer is null) return BadRequest(new { message = "العميل غير موجود" });

            var pinResult = await CustomerPinGate.VerifyAsync(
                _db, walletCustomer, request.CustomerPin, HttpContext.Connection.RemoteIpAddress?.ToString());
            await _db.SaveChangesAsync();

            if (pinResult.Result != PinCheck.Ok)
            {
                return pinResult.Result == PinCheck.Locked
                    ? StatusCode(429, new { message = pinResult.Message })
                    : BadRequest(new { message = pinResult.Message });
            }
        }

        await using var transaction = await _db.Database.BeginTransactionAsync();

        var invoice = new Invoice
        {
            // organization_id يُشتق من التوكن دائماً — وإلا ترفضه BLOCK
            // PREDICATE الخاصة بـ InvoicesPolicy بصمت (نفس الإصلاح المطبَّق
            // في ProductsController/SuppliersController/CategoriesController).
            OrganizationId = Guid.Parse(User.FindFirstValue("organization_id")!),
            BranchId = request.BranchId,
            CustomerId = request.CustomerId,
            InvoiceNumber = $"INV-{DateTime.UtcNow:yyyyMMddHHmmssfff}",
            Subtotal = request.Lines.Sum(l => l.Quantity * l.UnitPrice),
            // لم تكن تُضبَط أصلاً — بلا هذا الحقل تعرض "أداء الكاشير" في
            // شاشة التقارير كل الفواتير كـ"غير محدَّد" دائماً.
            CreatedBy = CurrentUserId(),
        };
        invoice.TotalAmount = invoice.Subtotal - invoice.DiscountAmount + invoice.TaxAmount;

        foreach (var line in request.Lines)
        {
            invoice.Items.Add(new InvoiceItem
            {
                ProductId = line.ProductId,
                Quantity = line.Quantity,
                UnitPrice = line.UnitPrice,
                LineTotal = line.Quantity * line.UnitPrice,
            });

            var product = await _db.Products.FindAsync(line.ProductId);

            // الأصناف غير المتتبَّعة مخزنياً (خدمات / قيمة مفتوحة) تُباع بلا
            // رصيد ولا خصم — راجع Product.TracksStock. الفاتورة وسطرها يُسجَّلان
            // كاملين، والمتخطَّى هو حركة المخزون وحدها.
            if (product is not null && !product.TracksStock) continue;

            var stock = await _db.StockLevels.FirstOrDefaultAsync(
                s => s.BranchId == request.BranchId && s.ProductId == line.ProductId);
            if (stock is null || stock.Quantity < line.Quantity)
            {
                return BadRequest(new { message = "الكمية غير متوفرة في المخزون" });
            }
            stock.Quantity -= line.Quantity;

            // موديول التنبيهات: دفعة SignalR اللحظية للمتصلين الآن، بالإضافة
            // إلى صف دائم في notifications حتى تظهر لاحقاً في "غرفة
            // الإشعارات" لمن لم يكن متصلاً وقت الحدث (الدفعة وحدها كانت
            // تُفقَد فوراً بلا أي أثر دائم قبل هذا الإصلاح).
            if (product is not null && stock.Quantity <= product.ReorderLevel)
            {
                await _hub.Clients.Group(invoice.OrganizationId.ToString())
                    .SendAsync("LowStockAlert", new { product.Name, stock.Quantity });

                _db.Notifications.Add(new NotificationItem
                {
                    OrganizationId = invoice.OrganizationId,
                    BranchId = request.BranchId,
                    Type = "low_stock",
                    Title = $"نقص مخزون: {product.Name}",
                    Body = $"الكمية المتبقية: {stock.Quantity}",
                });
            }
        }

        if (payingFromWallet)
        {
            // الرصيد مجموع الدفتر لا عمود مخزَّن — راجع WalletBalances.
            var balance = await WalletBalances.ComputeAsync(_db, walletCustomer!.Id);
            if (balance < invoice.TotalAmount)
            {
                return BadRequest(new { message = "رصيد العميل غير كافٍ" });
            }
        }

        // invoice_payments كانت جدولاً معرَّفاً في المخطط بلا أي كود يكتب
        // إليه — الفاتورة كانت تُنشأ بلا سجل دفع مطابق أصلاً. صف واحد بكامل
        // المبلغ يكفي الآن (دفع مقسّم فعلي مرحلة لاحقة على شاشة POS ذاتها).
        invoice.Payments.Add(new InvoicePayment { Method = request.PaymentMethod, Amount = invoice.TotalAmount });

        _db.Invoices.Add(invoice);
        await _db.SaveChangesAsync();

        // حركة المحفظة تُحفَظ *بعد* الفاتورة عمداً: customer_wallet_transactions
        // يحمل مفتاحاً خارجياً على invoices، وEF لا يعرف هذا الاعتماد (لا
        // Navigation property بينهما) فيُدرج الحركة قبل الفاتورة لو حُفظا معاً
        // فيرفضها القيد. كلاهما داخل نفس المعاملة الصريحة، فإما يمرّان معاً
        // أو يُلغيان معاً.
        if (payingFromWallet)
        {
            _db.CustomerWalletTransactions.Add(new CustomerWalletTransaction
            {
                OrganizationId = invoice.OrganizationId,
                CustomerId = request.CustomerId!.Value,
                InvoiceId = invoice.Id,
                Kind = WalletKinds.Spend,
                Amount = invoice.TotalAmount,
                Note = $"سداد فاتورة {invoice.InvoiceNumber}",
                CreatedBy = CurrentUserId(),
            });
            await _db.SaveChangesAsync();
        }

        await transaction.CommitAsync();

        return CreatedAtAction(nameof(GetById), new { id = invoice.Id }, invoice);
    }

    /// <summary>
    /// استرجاع فاتورة بيع كاملة: يُنشئ فاتورة مرتجع مرتبطة بالأصل، يعيد
    /// الكمية للمخزون، ويردّ المبلغ لمحفظة العميل إن كان الدفع منها. رد
    /// الكاش/البطاقة يبقى إجراءً يدوياً خارج النظام (لا حساب بنكي مربوط).
    /// </summary>
    [HttpPost("{id:guid}/refund")]
    [RequirePermission("invoices.refund")]
    public async Task<ActionResult<Invoice>> Refund(Guid id)
    {
        var original = await _db.Invoices.Include(i => i.Items).Include(i => i.Payments)
            .FirstOrDefaultAsync(i => i.Id == id);
        if (original is null) return NotFound();
        if (original.InvoiceType != "sale")
        {
            return BadRequest(new { message = "لا يمكن استرجاع فاتورة مرتجعة أصلاً" });
        }
        var alreadyReturned = await _db.Invoices.AnyAsync(i => i.OriginalInvoiceId == id);
        if (alreadyReturned)
        {
            return BadRequest(new { message = "تم استرجاع هذه الفاتورة مسبقاً" });
        }

        await using var transaction = await _db.Database.BeginTransactionAsync();

        var refund = new Invoice
        {
            OrganizationId = original.OrganizationId,
            BranchId = original.BranchId,
            CustomerId = original.CustomerId,
            InvoiceNumber = $"RET-{DateTime.UtcNow:yyyyMMddHHmmssfff}",
            InvoiceType = "return",
            OriginalInvoiceId = original.Id,
            Subtotal = original.Subtotal,
            TaxAmount = original.TaxAmount,
            DiscountAmount = original.DiscountAmount,
            TotalAmount = original.TotalAmount,
        };

        foreach (var item in original.Items)
        {
            refund.Items.Add(new InvoiceItem
            {
                ProductId = item.ProductId,
                Quantity = item.Quantity,
                UnitPrice = item.UnitPrice,
                LineTotal = item.LineTotal,
            });

            // الصنف غير المتتبَّع مخزنياً لم يُخصَم عند البيع، فإرجاعه للمخزون
            // كان سيخلق كمية من عدم — راجع Product.TracksStock.
            var refundedProduct = await _db.Products.FindAsync(item.ProductId);
            if (refundedProduct is not null && !refundedProduct.TracksStock) continue;

            // إعادة الكمية إلى دفعة عامة بلا رقم دفعة محدَّد — invoice_items
            // لا تخزّن batch_number أصلاً، فلا سبيل لمعرفة الدفعة الأصلية بدقة.
            var stock = await _db.StockLevels.FirstOrDefaultAsync(
                s => s.BranchId == original.BranchId && s.ProductId == item.ProductId && s.BatchNumber == "");
            if (stock is null)
            {
                _db.StockLevels.Add(new StockLevel
                {
                    OrganizationId = original.OrganizationId,
                    BranchId = original.BranchId,
                    ProductId = item.ProductId,
                    BatchNumber = "",
                    Quantity = item.Quantity,
                });
            }
            else
            {
                stock.Quantity += item.Quantity;
            }
        }

        var walletRefundAmount = 0m;
        foreach (var payment in original.Payments)
        {
            refund.Payments.Add(new InvoicePayment { Method = payment.Method, Amount = payment.Amount });
            if (payment.Method == "customer_wallet" && original.CustomerId.HasValue)
            {
                walletRefundAmount += payment.Amount;
            }
        }

        original.Status = "refunded";
        _db.Invoices.Add(refund);
        _db.LogAudit(original.OrganizationId, CurrentUserId(), "invoice.refunded", "invoices", original.Id,
            newValues: new { original.InvoiceNumber, RefundInvoiceNumber = refund.InvoiceNumber, refund.TotalAmount });
        await _db.SaveChangesAsync();

        // بعد حفظ فاتورة المرتجع لأن الحركة تشير إليها بمفتاح خارجي — نفس
        // سبب الترتيب في Create أعلاه. وهي حركة معاكسة *جديدة*، لا تعديل على
        // حركة الصرف الأصلية (حرمة القيد: التصحيح بعكسه لا بمحو الماضي).
        if (walletRefundAmount > 0)
        {
            _db.CustomerWalletTransactions.Add(new CustomerWalletTransaction
            {
                OrganizationId = original.OrganizationId,
                CustomerId = original.CustomerId!.Value,
                InvoiceId = refund.Id,
                Kind = WalletKinds.InvoiceRefund,
                Amount = walletRefundAmount,
                Note = $"استرجاع فاتورة {original.InvoiceNumber}",
                CreatedBy = CurrentUserId(),
            });
            await _db.SaveChangesAsync();
        }

        await transaction.CommitAsync();

        return CreatedAtAction(nameof(GetById), new { id = refund.Id }, refund);
    }

    private Guid? CurrentUserId()
    {
        var raw = User.FindFirstValue(JwtRegisteredClaimNames.Sub) ?? User.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(raw, out var id) ? id : null;
    }
}
