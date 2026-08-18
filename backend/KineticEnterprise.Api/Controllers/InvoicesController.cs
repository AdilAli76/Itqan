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
    string? CustomerPin = null,
    // مفتاح يولّده العميل مرّة واحدة لكل عملية بيع، ويُعيد إرساله مع كل
    // محاولة مزامنة. هو ما يجعل إعادة الإرسال آمنة: انقطاع الشبكة بعد وصول
    // الطلب وقبل وصول الرد حالة شائعة جداً في متجر، وبدون هذا المفتاح تُنشأ
    // الفاتورة مرّتين ويُخصَم المخزون مرّتين — وهو أسوأ ما يمكن أن ينتج عن
    // ميزة «العمل دون اتصال».
    string? ClientRequestId = null);

/// صفحة فواتير — نفس شكل CustomerPageDto وAuditLogPageDto.
public record InvoicePageDto(List<InvoiceListItemDto> Items, int TotalCount, int Page, int PageSize);

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
    /// <summary>
    /// قائمة الفواتير مقسَّمة صفحات.
    ///
    /// كانت هذه أخطر نقطة في النظام كله: الاستعلام يجلب كل فاتورة أُنشئت
    /// منذ بداية التشغيل، ومعها كل بنودها وكل دفعاتها عبر Include مزدوج.
    /// متجرٌ بعشرين ألف فاتورة كان يحمّل مئات آلاف الصفوف في كل فتح لشاشة
    /// الفواتير — وهي شاشة تُفتح عشرات المرات يومياً. الترقيم هنا ليس تحسين
    /// تجربة، بل شرط بقاء النظام صالحاً للعمل بعد سنته الأولى.
    /// </summary>
    [HttpGet]
    public async Task<ActionResult<InvoicePageDto>> GetAll(
        [FromQuery] string? search,
        [FromQuery] string? status,
        [FromQuery] string? invoiceType,
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 200);

        var query = _db.Invoices.Include(i => i.Items).Include(i => i.Payments).AsQueryable();

        if (!string.IsNullOrWhiteSpace(status)) query = query.Where(i => i.Status == status);
        if (!string.IsNullOrWhiteSpace(invoiceType)) query = query.Where(i => i.InvoiceType == invoiceType);
        if (from.HasValue) query = query.Where(i => i.CreatedAt >= from.Value);
        if (to.HasValue) query = query.Where(i => i.CreatedAt < to.Value.AddDays(1));

        // البحث كان يُطبَّق في الذاكرة بعد جلب كل الفواتير. مع الترقيم كان
        // ذلك سيصبح خطأً صريحاً: الفلترة تقع على الصفحة الحالية وحدها، فيبحث
        // المستخدم عن رقم فاتورة موجود فلا يجده لأنه في صفحة أخرى. البحث
        // ينتقل هنا إلى الاستعلام قبل العدّ والتقطيع.
        //
        // بلا StringComparison: الترجمة إلى SQL لا تدعمها، وحساسية الأحرف
        // تحسمها لغة ترتيب قاعدة البيانات (غير حسّاسة افتراضياً).
        if (!string.IsNullOrWhiteSpace(search))
        {
            query = query.Where(i =>
                i.InvoiceNumber.Contains(search) ||
                _db.Customers.Any(c => c.Id == i.CustomerId && c.FullName.Contains(search)));
        }

        // العدّ قبل التقطيع ليعكس كل النتائج المطابقة للفلتر لا الصفحة وحدها.
        var totalCount = await query.CountAsync();
        var invoices = await query.OrderByDescending(i => i.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync();

        var customerIds = invoices.Where(i => i.CustomerId.HasValue).Select(i => i.CustomerId!.Value).Distinct().ToList();
        var customerNames = await _db.Customers
            .Where(c => customerIds.Contains(c.Id))
            .ToDictionaryAsync(c => c.Id, c => c.FullName);

        var items = invoices.Select(i =>
        {
            customerNames.TryGetValue(i.CustomerId ?? Guid.Empty, out var customerName);
            var paymentMethod = i.Payments.Count == 0 ? "-" : i.Payments.Count == 1 ? i.Payments[0].Method : "متعدد";
            return new InvoiceListItemDto(
                i.Id, i.InvoiceNumber, i.InvoiceType, i.Status,
                i.CustomerId, customerName, i.Items.Count, i.TotalAmount, paymentMethod, i.CreatedAt);
        }).ToList();

        return new InvoicePageDto(items, totalCount, page, pageSize);
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
        // تعطيل التكرار: إن سبق أن وصلت عملية بهذا المفتاح تُعاد فاتورتها
        // كما هي بدل إنشاء ثانية. يُفحَص قبل كل شيء — قبل الرقم السري وقبل
        // المخزون — لأن إعادة الإرسال يجب ألّا تستهلك محاولة رقم سري ولا
        // تلمس رصيداً.
        if (!string.IsNullOrWhiteSpace(request.ClientRequestId))
        {
            var existing = await _db.Invoices
                .FirstOrDefaultAsync(i => i.ClientRequestId == request.ClientRequestId);
            if (existing is not null) return existing;
        }

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

        // ------------------------------------------------------------------
        // تسعير من جانب السيرفر — لا يُقبل سعر العميل كما هو.
        //
        // كان السطر يُحسَب من request.UnitPrice مباشرة بلا أي مقارنة بسعر
        // الكتالوج، أي أن أي حامل توكن كاشير يستطيع بيع صنف بـ500 دينار
        // مقابل نصف دينار عبر طلب HTTP مباشر. الفاتورة تُسجَّل "سليمة"
        // والمخزون يُخصم صحيحاً فلا يكشفها شيء إلا جرد يقارن الإيراد
        // بالبضاعة المنصرفة. هذه أولى طرق السرقة عبر نقاط البيع.
        //
        // القاعدة الآن: السعر من الكتالوج دائماً، إلا في حالتين صريحتين:
        //   1) صنف مفتوح القيمة (TracksStock = false) وإعداد المنظمة يسمح.
        //   2) حامل صلاحية pos.price_override — ويُسجَّل التجاوز في التدقيق.
        // ------------------------------------------------------------------
        var org = await _db.Organizations.FirstOrDefaultAsync();
        if (org is null) return BadRequest(new { message = "تعذّر تحديد المنظمة" });

        var canOverridePrice = await HasPriceOverrideAsync();
        var resolvedLines = new List<(Product Product, decimal Quantity, decimal UnitPrice, bool Overridden)>();

        foreach (var line in request.Lines)
        {
            if (line.Quantity <= 0)
            {
                return BadRequest(new { message = "الكمية يجب أن تكون أكبر من صفر" });
            }

            // RLS تحصر البحث في منظمة المستخدم، فمعرّف صنف من منظمة أخرى
            // يعود null هنا ولا يتسرّب إلى الفاتورة.
            var product = await _db.Products.FirstOrDefaultAsync(p => p.Id == line.ProductId && !p.IsDeleted);
            if (product is null)
            {
                return BadRequest(new { message = "صنف غير موجود أو محذوف" });
            }

            decimal unitPrice;
            var overridden = false;

            if (!product.TracksStock)
            {
                // البوابة الحقيقية للصنف المفتوح: كانت في واجهة Flutter وحدها،
                // فمن يتجاوز الواجهة كان يبيع بقيمة حرة والإعداد مطفأ.
                if (!org.PosAllowOpenProduct)
                {
                    return BadRequest(new { message = "بيع الأصناف مفتوحة القيمة غير مفعَّل في هذه المنظمة" });
                }
                if (line.UnitPrice <= 0)
                {
                    return BadRequest(new { message = "قيمة الصنف المفتوح يجب أن تكون أكبر من صفر" });
                }
                unitPrice = line.UnitPrice;
            }
            else if (line.UnitPrice == product.SalePrice)
            {
                unitPrice = product.SalePrice;
            }
            else if (canOverridePrice)
            {
                if (line.UnitPrice < 0)
                {
                    return BadRequest(new { message = "السعر لا يمكن أن يكون سالباً" });
                }
                unitPrice = line.UnitPrice;
                overridden = true;
            }
            else
            {
                return BadRequest(new { message = $"سعر «{product.Name}» لا يطابق سعر الكتالوج، وتعديل السعر غير مسموح لك" });
            }

            resolvedLines.Add((product, line.Quantity, unitPrice, overridden));
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
            // من الأسعار المُثبَّتة في السيرفر لا من الطلب.
            Subtotal = resolvedLines.Sum(l => l.Quantity * l.UnitPrice),
            // لم تكن تُضبَط أصلاً — بلا هذا الحقل تعرض "أداء الكاشير" في
            // شاشة التقارير كل الفواتير كـ"غير محدَّد" دائماً.
            CreatedBy = CurrentUserId(),
        };
        invoice.TotalAmount = invoice.Subtotal - invoice.DiscountAmount + invoice.TaxAmount;

        foreach (var (product, quantity, unitPrice, overridden) in resolvedLines)
        {
            invoice.Items.Add(new InvoiceItem
            {
                ProductId = product.Id,
                Quantity = quantity,
                UnitPrice = unitPrice,
                LineTotal = quantity * unitPrice,
            });

            if (overridden)
            {
                // تجاوز السعر يُسجَّل دائماً: صلاحية مشروعة (مساومة، خصم لزبون
                // دائم) لكنها يجب أن تترك أثراً يُراجَع.
                _db.LogAudit(invoice.OrganizationId, CurrentUserId(), "invoice.price_overridden",
                    "invoice_items", product.Id,
                    newValues: new { product.Name, CatalogPrice = product.SalePrice, SoldPrice = unitPrice });
            }

            // الأصناف غير المتتبَّعة مخزنياً (خدمات / قيمة مفتوحة) تُباع بلا
            // رصيد ولا خصم — راجع Product.TracksStock. الفاتورة وسطرها يُسجَّلان
            // كاملين، والمتخطَّى هو حركة المخزون وحدها.
            if (!product.TracksStock) continue;

            // WITH (UPDLOCK) — قفل تحديث على صف الرصيد حتى نهاية المعاملة.
            //
            // بدونه: قراءة ثم فحص ثم كتابة بلا قفل. كاشيران يبيعان آخر قطعة
            // في نفس اللحظة يقرآن كلاهما 1، ويمرّان الفحص كلاهما، فتُباع
            // قطعتان موجودة منهما واحدة ويصبح الرصيد سالباً. لا يظهر هذا في
            // اختبار بمستخدم واحد إطلاقاً — يظهر بعد التسليم عند فرعين
            // نشطين وثلاثة كاشيرات.
            var stock = await _db.StockLevels
                .FromSqlInterpolated($@"
                    SELECT * FROM stock_levels WITH (UPDLOCK, ROWLOCK)
                    WHERE branch_id = {request.BranchId} AND product_id = {product.Id}")
                .FirstOrDefaultAsync();

            if (stock is null || stock.Quantity < quantity)
            {
                return BadRequest(new { message = $"الكمية غير متوفرة في المخزون: {product.Name}" });
            }
            stock.Quantity -= quantity;

            // موديول التنبيهات: دفعة SignalR اللحظية للمتصلين الآن، بالإضافة
            // إلى صف دائم في notifications حتى تظهر لاحقاً في "غرفة
            // الإشعارات" لمن لم يكن متصلاً وقت الحدث (الدفعة وحدها كانت
            // تُفقَد فوراً بلا أي أثر دائم قبل هذا الإصلاح).
            if (stock.Quantity <= product.ReorderLevel)
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
            //
            // القفل ضروري هنا كضرورته على المخزون: الجمع ثم المقارنة ثم
            // الإضافة بلا قفل نطاق يسمح لعمليتَي بيع متزامنتين بأن تمرّا
            // كلتاهما على نفس الرصيد، فيُنفَق مرتين. HOLDLOCK يمنع إدراج
            // حركات جديدة لهذا العميل حتى نهاية المعاملة.
            var balance = await WalletBalances.ComputeLockedAsync(_db, walletCustomer!.Id);
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
        await using var transaction = await _db.Database.BeginTransactionAsync();

        // فحص الاسترجاع المسبق **داخل** المعاملة وبقفل نطاق.
        //
        // كان قبلها بلا معاملة ولا قفل: نقرتان متزامنتان على "استرجاع" (أو
        // نقرة مكرَّرة على شبكة بطيئة) تمرّان كلتاهما، فتُنشأ فاتورتا مرتجع
        // للفاتورة نفسها وتعود البضاعة للمخزون مرتين ويُردّ المبلغ مرتين.
        // HOLDLOCK يمنع إدراج مرتجع ثانٍ لنفس الأصل حتى نهاية هذه المعاملة.
        var alreadyReturned = await _db.Invoices
            .FromSqlInterpolated($@"
                SELECT * FROM invoices WITH (UPDLOCK, HOLDLOCK)
                WHERE original_invoice_id = {id}")
            .AnyAsync();

        if (alreadyReturned)
        {
            return BadRequest(new { message = "تم استرجاع هذه الفاتورة مسبقاً" });
        }

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

    /// <summary>
    /// صلاحية بيع بسعر مخالف لسعر الكتالوج.
    ///
    /// نفس منطق RequirePermissionAttribute (صلاحية من role_permissions،
    /// و super_admin يتجاوز دائماً) — لكنها فحص داخل الإجراء لا سمة عليه،
    /// لأن الأمر ليس منع الوصول إلى نقطة النهاية بل تحديد أي سعر يُقبل.
    /// </summary>
    private async Task<bool> HasPriceOverrideAsync()
    {
        var role = User.FindFirstValue(ClaimTypes.Role);
        if (role is null) return false;
        if (role == "super_admin") return true;

        var orgIdRaw = User.FindFirstValue("organization_id");
        if (!Guid.TryParse(orgIdRaw, out var orgId)) return false;

        return await _db.RolePermissions.AnyAsync(rp =>
            rp.OrganizationId == orgId && rp.Role == role && rp.PermissionCode == "pos.price_override");
    }
}
