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

public record InvoiceLineRequest(
    Guid ProductId, decimal Quantity,
    /// <summary>
    /// السعر المطلوب. **NULL = سعر الكتالوج** — وهو الغالب.
    ///
    /// <para><b>لماذا يقبل NULL:</b> كان <c>decimal</c> غير قابل للإفراغ،
    /// فطلبٌ لا يذكر السعر يصل بقيمة صفر. ومن يملك <c>pos.price_override</c>
    /// — و<c>super_admin</c> يملكها دائماً — كان الصفر يمرّ عنده **تجاوزاً
    /// متعمّداً**: أي أن طلب HTTP مباشراً بلا حقل سعر يبيع كل شيء مجاناً،
    /// ويُسجَّل في التدقيق «تجاوز سعر» لا خطأً.</para>
    ///
    /// <para>وهذا نقض للغرض الذي بُنيت له كتلة التسعير أصلاً: منع من يتجاوز
    /// الواجهة من فرض سعره. والفرق بين «لم يقل» و«قال صفراً» لا يُلتقط إلا
    /// بحقل قابل للإفراغ. والصفر الصريح يبقى مسموحاً لصاحب الصلاحية —
    /// الهدية تقع فعلاً — لكنه يصير قراراً مكتوباً لا سهواً.</para>
    /// </summary>
    decimal? UnitPrice,
    /// بيع بالوحدة الجزئية (حبّة من شريط). الكمية والسعر حينها بالوحدة
    /// الجزئية، والخصم من المخزون وحده هو ما يُحوَّل إلى الوحدة الأساسية.
    bool SoldAsSubUnit = false);
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
    string? ClientRequestId = null,
    /// المدفوع الآن من الإجمالي. NULL = دفع كامل (وهو الغالب).
    /// أقلّ من الإجمالي = دفع جزئي، والفرق يُقيَّد دَيناً على محفظة العميل
    /// — فيلزم عميل محدَّد وحدّ ائتمان يتّسع للفرق.
    decimal? PaidAmount = null,
    /// النقد الذي سلّمه الزبون، والباقي يُشتقّ منه. للتدقيق وتسوية الدرج.
    decimal? TenderedAmount = null,
    /// بيانات الوصفة — إلزامية إن كان في الفاتورة دواء مقيَّد بوصفة.
    /// راجع [PrescriptionRequest] وقاعدة الرفض في Create.
    PrescriptionRequest? Prescription = null);

/// <summary>
/// بيانات الوصفة كما يُدخلها الكاشير لحظة الصرف.
///
/// الطبيب والمريض مطلوبان لأنهما ما يجعل القيد مستنداً: دفتر فيه «صُرف دواء
/// مقيَّد» بلا اسم طبيب ولا مريض لا يجيب عن أي سؤال تفتيش.
/// </summary>
public record PrescriptionRequest(
    string DoctorName, string PatientName,
    string? PrescriptionNumber = null, string? DoctorLicense = null,
    string? PatientPhone = null, DateOnly? IssuedOn = null, string? Notes = null);

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

        // تُقرأ المنظمة هنا لا بعد التسعير: نمط التحقّق من البطاقة من
        // إعداداتها، ويلزم معرفته **قبل** أن نقرّر هل يُطلب رقم سرّي.
        var org = await _db.Organizations.FirstOrDefaultAsync();
        if (org is null) return BadRequest(new { message = "تعذّر تحديد المنظمة" });

        var payingFromWallet = request.PaymentMethod == "customer_wallet" && request.CustomerId.HasValue;
        Customer? walletCustomer = null;
        var cardMode = CardModes.Pin;

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

            // النمط من إعدادات المنظمة واختيار الزبون — **لا من الطلب**.
            // لو أرسله العميل لاختار السارق «بطاقة فقط» لكل عملية فسقطت
            // الحماية كلّها بحقل في JSON.
            cardMode = CardModeGate.EffectiveMode(org, walletCustomer);

            if (cardMode == CardModes.Pin)
            {
                var pinResult = await CustomerPinGate.VerifyAsync(
                    _db, walletCustomer, request.CustomerPin,
                    HttpContext.Connection.RemoteIpAddress?.ToString());
                await _db.SaveChangesAsync();

                if (pinResult.Result != PinCheck.Ok)
                {
                    return pinResult.Result == PinCheck.Locked
                        ? StatusCode(429, new { message = pinResult.Message })
                        : BadRequest(new { message = pinResult.Message });
                }
            }
            // نمط «بطاقة فقط»: لا رقم يُطلب هنا — الحدّ سقفٌ يوميّ يُفحَص بعد
            // التسعير داخل المعاملة، لأن المبلغ لا يُعرف قبله ولا يُؤخذ من
            // الطلب.
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
        var canOverridePrice = await HasPriceOverrideAsync();
        // تكلفة البضاعة المباعة — تُجمَع من الدفتر أثناء الصرف ويُرحَّل بها
        // قيد التكلفة بعد الحفظ (راجع PostInvoiceAsync).
        decimal costOfGoodsSold = 0;
        var resolvedLines = new List<(Product Product, decimal Quantity, decimal UnitPrice, bool Overridden, bool SoldAsSubUnit)>();

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
                if (line.UnitPrice is not { } openPrice || openPrice <= 0)
                {
                    return BadRequest(new { message = "قيمة الصنف المفتوح يجب أن تكون أكبر من صفر" });
                }
                unitPrice = openPrice;
            }
            else if (line.SoldAsSubUnit)
            {
                // سعر الوحدة الجزئية يُقارَن بـ SubUnitPrice لا بـ SalePrice:
                // مقارنته بسعر الشريط كانت ترفض كل بيع جزئي مشروع، أو تمرّره
                // كتجاوز سعر فيُسجَّل تجاوزاً في التدقيق بلا سبب.
                if (!product.AllowsSubUnitSale)
                {
                    return BadRequest(new
                    {
                        message = $"«{product.Name}» غير مهيَّأ للبيع بالوحدة الجزئية"
                    });
                }
                // NULL = سعر الكتالوج، لا تجاوزاً بصفر.
                if (line.UnitPrice is null || line.UnitPrice == product.SubUnitPrice)
                {
                    unitPrice = product.SubUnitPrice;
                }
                else if (canOverridePrice)
                {
                    if (line.UnitPrice < 0)
                    {
                        return BadRequest(new { message = "السعر لا يمكن أن يكون سالباً" });
                    }
                    unitPrice = line.UnitPrice.Value;
                    overridden = true;
                }
                else
                {
                    return BadRequest(new
                    {
                        message = $"سعر الوحدة الجزئية لـ«{product.Name}» لا يطابق الكتالوج، وتعديل السعر غير مسموح لك"
                    });
                }
            }
            else if (line.UnitPrice is null || line.UnitPrice == product.SalePrice)
            {
                unitPrice = product.SalePrice;
            }
            else if (canOverridePrice)
            {
                if (line.UnitPrice < 0)
                {
                    return BadRequest(new { message = "السعر لا يمكن أن يكون سالباً" });
                }
                unitPrice = line.UnitPrice.Value;
                overridden = true;
            }
            else
            {
                return BadRequest(new { message = $"سعر «{product.Name}» لا يطابق سعر الكتالوج، وتعديل السعر غير مسموح لك" });
            }

            // ── الحدّ الأدنى: نقطة تحقّقٍ واحدة بعد الفروع الثلاثة ──
            //
            // موضعها هنا لا داخل كل فرع: الفروع ثلاثة (صنف مفتوح، وحدة
            // جزئية، وحدة أساسية) وثلاثةُ فحوصٍ متطابقة تفترق أوّل مرّة
            // يُعدَّل أحدها. وهو نفس مبدأ [StockLedger] و[Ledger] — بوابةٌ
            // واحدة يستحيل الالتفاف عليها.
            //
            // ولا يُستثنى منها حامل pos.price_override: حدٌّ له استثناء ليس
            // حدّاً، ومدير المنظمة يملك الصلاحية دائماً فيصير الحدّ زينة.
            if (product.MinSalePrice > 0)
            {
                // الحدّ بالوحدة الأساسية، والبيع الجزئي يقيسه بالنسبة.
                var floor = line.SoldAsSubUnit && product.SubUnitsPerBase > 0
                    ? product.MinSalePrice / product.SubUnitsPerBase
                    : product.MinSalePrice;

                if (unitPrice < floor)
                {
                    return BadRequest(new
                    {
                        // يُسمّى الحدّ صراحةً: «السعر منخفض» تترك الكاشير
                        // يجرّب أرقاماً أمام زبونٍ ينتظر.
                        message = $"سعر «{product.Name}» أقلّ من الحدّ الأدنى "
                            + $"({floor:0.00}) — عدّل الحدّ من بطاقة الصنف إن أردت بيعاً أرخص",
                    });
                }
            }

            resolvedLines.Add((product, line.Quantity, unitPrice, overridden, line.SoldAsSubUnit));
        }

        // ── الأدوية المقيَّدة بوصفة ──────────────────────────────────────
        //
        // القيد خاصية الدواء نفسه (medicine_reference.requires_prescription)
        // لا خاصية الصنف في متجر بعينه، فيُقرأ من النشرة المرتبطة.
        //
        // الفحص هنا لا في الواجهة: إخفاء الحقل في شاشة البيع لا يمنع إرسال
        // الطلب مباشرةً، وصرف دواء مقيَّد بلا قيد في الدفتر مخالفة نظامية لا
        // مجرّد خطأ إدخال.
        var referencedIds = resolvedLines
            .Select(l => l.Product.MedicineRefId)
            .Where(id => id.HasValue)
            .Select(id => id!.Value)
            .Distinct()
            .ToList();

        var restrictedNames = new List<string>();
        if (referencedIds.Count > 0)
        {
            var restricted = await _db.MedicineReferences
                .Where(m => referencedIds.Contains(m.Id) && !m.IsDeleted && m.RequiresPrescription)
                .Select(m => m.Id)
                .ToListAsync();

            if (restricted.Count > 0)
            {
                restrictedNames = resolvedLines
                    .Where(l => l.Product.MedicineRefId.HasValue
                             && restricted.Contains(l.Product.MedicineRefId!.Value))
                    .Select(l => l.Product.Name)
                    .Distinct()
                    .ToList();
            }
        }

        if (restrictedNames.Count > 0)
        {
            // الصلاحية منفصلة عن البيع العادي: صرف المقيَّد قرار يُسنَد إلى
            // صيدلي لا إلى كل من يقف على الصندوق.
            if (!await HasPermissionAsync("prescriptions.dispense"))
            {
                return StatusCode(StatusCodes.Status403Forbidden, new
                {
                    message = $"صرف «{string.Join("، ", restrictedNames)}» يتطلّب صلاحية صرف الأدوية المقيَّدة"
                });
            }

            var p = request.Prescription;
            if (p is null
                || string.IsNullOrWhiteSpace(p.DoctorName)
                || string.IsNullOrWhiteSpace(p.PatientName))
            {
                return BadRequest(new
                {
                    message = $"«{string.Join("، ", restrictedNames)}» يُصرَف بوصفة — أدخل اسم الطبيب والمريض",
                    requiresPrescription = restrictedNames,
                });
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
            // مفتاح العملية يُحفَظ مع الفاتورة، وهو ما يجعل فحص التكرار في
            // أعلى هذه الدالة ذا معنى: بلا حفظه لا يطابق الفحص شيئاً أبداً،
            // فتُنشئ كل إعادة إرسال فاتورة جديدة ويُخصَم المخزون مرّتين —
            // أي عكس الغرض الذي وُضع له تماماً. (كان غائباً فعلاً حتى كشفه
            // اختبار إعادة الإرسال.)
            ClientRequestId = string.IsNullOrWhiteSpace(request.ClientRequestId)
                ? null
                : request.ClientRequestId,
            // من الأسعار المُثبَّتة في السيرفر لا من الطلب.
            Subtotal = resolvedLines.Sum(l => l.Quantity * l.UnitPrice),
            // لم تكن تُضبَط أصلاً — بلا هذا الحقل تعرض "أداء الكاشير" في
            // شاشة التقارير كل الفواتير كـ"غير محدَّد" دائماً.
            CreatedBy = CurrentUserId(),
        };
        invoice.TotalAmount = invoice.Subtotal - invoice.DiscountAmount + invoice.TaxAmount;

        foreach (var (product, quantity, unitPrice, overridden, soldAsSubUnit) in resolvedLines)
        {
            var invoiceItem = new InvoiceItem
            {
                ProductId = product.Id,
                Quantity = quantity,
                UnitPrice = unitPrice,
                LineTotal = quantity * unitPrice,
                SoldAsSubUnit = soldAsSubUnit,
                // لقطة وقت البيع لا قراءة لاحقة من الكتالوج — راجع
                // InvoiceItem.SubUnitsPerBase.
                SubUnitsPerBase = soldAsSubUnit ? product.SubUnitsPerBase : 0,
            };
            invoice.Items.Add(invoiceItem);

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

            // WITH (UPDLOCK) — قفل تحديث على صفوف الرصيد حتى نهاية المعاملة.
            //
            // بدونه: قراءة ثم فحص ثم كتابة بلا قفل. كاشيران يبيعان آخر قطعة
            // في نفس اللحظة يقرآن كلاهما 1، ويمرّان الفحص كلاهما، فتُباع
            // قطعتان موجودة منهما واحدة ويصبح الرصيد سالباً. لا يظهر هذا في
            // اختبار بمستخدم واحد إطلاقاً — يظهر بعد التسليم عند فرعين
            // نشطين وثلاثة كاشيرات.
            //
            // وكل الصفوف لا صفّ واحد: UQ_stock_levels يسمح بصفٍّ لكل دفعة
            // (branch_id, product_id, batch_number)، واستلام أمر شراء لصنف
            // track_expiry=1 يكتب رقم دفعة حقيقياً (PurchaseOrdersController)
            // — فالدواء الذي وصل على ثلاث شحنات له ثلاثة صفوف. الاكتفاء بـ
            // FirstOrDefault هنا كان يلتقط دفعة عشوائية (لا ORDER BY أصلاً)
            // فيقع خطآن: رفض بيع 15 والمتاح 30 موزّعة على ثلاث دفعات، وخصمٌ
            // من دفعة بعيدة الانتهاء بينما القريبة تتلف على الرفّ.
            // الكمية المخصومة بالوحدة الأساسية: المخزون يُعدّ شرائط، والبيع
            // قد يكون بالحبّة. ثلاث حبات من شريط بعشر = 0.3 شريط، وعمود
            // quantity من نوع DECIMAL(14,3) يتّسع للكسر.
            //
            // القسمة على المعامل من الكتالوج لا من الطلب: لو أخذناه من العميل
            // لأمكن إرسال معامل ضخم فيُخصَم كسرٌ لا يُذكر مقابل بضاعة حقيقية.
            var stockQuantity = soldAsSubUnit && product.SubUnitsPerBase > 0
                ? quantity / product.SubUnitsPerBase
                : quantity;

            var batches = await _db.StockLevels
                .FromSqlInterpolated($@"
                    SELECT * FROM stock_levels WITH (UPDLOCK, ROWLOCK)
                    WHERE branch_id = {request.BranchId} AND product_id = {product.Id}")
                .ToListAsync();

            var today = DateTime.UtcNow.Date;

            // الترتيب على **تاريخ الاستراتيجية** لا على الصلاحية وحدها — راجع
            // StockLevel.StrategyDate:
            //   1) الأقدم استراتيجيةً أولاً. وهو تاريخ الانتهاء للصنف المتتبَّع
            //      (فيصير FEFO)، وتاريخ الإدخال لغيره (فيصير FIFO). قبل هذا
            //      الحقل كان الصنف بلا صلاحية يُرتَّب برقم دفعته أبجدياً — أي
            //      عشوائياً — فتبقى دفعته القديمة على الرفّ بلا سبب.
            //   2) ثم ما بلا تاريخ استراتيجية (دفعة أُدخلت قبل تفعيل التتبّع،
            //      أو مرتجع مجهول التاريخ) — يُؤخَّر لأن المعلوم أولى بالتصريف
            //      من المجهول.
            //   3) ثم رقم الدفعة لجعل الترتيب حتمياً لا يعتمد على مخطّط SQL.
            //
            // والموقوف يخرج من الترتيب كلّه (`!b.IsLocked`): القفل قرار إداري
            // بأن هذه الدفعة لا تُصرَف — فلو بقيت في الترتيب لصرفها FEFO أولاً
            // كلما كانت الأقرب انتهاءً، وهي غالباً كذلك (تُقفَل لأنها مشبوهة
            // أو مرتجعة). راجع StockLevel.IsLocked.
            var usable = batches
                .Where(b => b.Quantity > 0 && !b.IsLocked
                         && (b.ExpiryDate is null || b.ExpiryDate.Value.Date >= today))
                .OrderBy(b => b.StrategyDate is null ? 1 : 0)
                .ThenBy(b => b.StrategyDate)
                .ThenBy(b => b.BatchNumber, StringComparer.Ordinal)
                .ToList();

            var usableQuantity = usable.Sum(b => b.Quantity);
            if (usableQuantity < stockQuantity)
            {
                // المنتهي الصلاحية يُذكر صراحةً: بدونه يرى الكاشير «غير متوفر»
                // بينما الرفّ ممتلئ، فيظنّه خللاً في النظام. والرسالة تقول له
                // ما العمل — إتلاف الدفعة أو تسويتها من شاشة المخزون.
                //
                // والموقوف كذلك: الرفّ ممتلئ والنظام يرفض، فبلا ذكر السبب
                // يبدو عطلاً. ويُذكر قبل المنتهي لأنه قرار بشري قابل للرجوع
                // بضغطة — بخلاف انتهاء الصلاحية.
                var expiredQuantity = batches
                    .Where(b => b.Quantity > 0 && !b.IsLocked
                             && b.ExpiryDate is not null && b.ExpiryDate.Value.Date < today)
                    .Sum(b => b.Quantity);

                var lockedQuantity = batches.Where(b => b.Quantity > 0 && b.IsLocked).Sum(b => b.Quantity);

                var message = lockedQuantity > 0
                    ? $"الكمية المتاحة غير كافية: {product.Name} — متاح {usableQuantity}, وموقوف {lockedQuantity} حتى يُفرَج عنه من شاشة المخزون"
                    : expiredQuantity > 0
                        ? $"الكمية الصالحة غير كافية: {product.Name} — متاح {usableQuantity}, ومنتهي الصلاحية {expiredQuantity} لا يُباع"
                        : $"الكمية غير متوفرة في المخزون: {product.Name}";
                return BadRequest(new { message });
            }

            // الخصم عبر الدفتر لا على stock_levels مباشرةً: هو الطريق الوحيد
            // في النظام، ومنه يأتي سطر صرف **لكل إدخال استُهلك منه** يحمل
            // تكلفته الحقيقية ومصدره. راجع [StockLedger].
            //
            // تخصيص الدفعات على الفاتورة يبقى كما هو: هو ما يجعل المرتجع
            // يُعيد الكمية إلى دفعتها الأصلية لا إلى دفعة عامة بلا صلاحية
            // (راجع InvoiceItemBatch) — والدفتر يجيب سؤالاً آخر: بأي تكلفة
            // ومن أي شحنة.
            List<IssuedLot> issuedLots;
            try
            {
                issuedLots = await StockLedger.IssueAsync(
                    _db, invoice.OrganizationId, request.BranchId, warehouseId: null,
                    productId: product.Id, quantity: stockQuantity,
                    sourceType: StockSourceTypes.Invoice, sourceId: invoice.Id,
                    userId: CurrentUserId());
            }
            catch (InvalidOperationException ex)
            {
                return BadRequest(new { message = $"{ex.Message} — {product.Name}" });
            }

            // التكلفة الفعلية لما خرج، من الدفتر لا من سعر الكتالوج.
            //
            // IssuedLot يحمل تكلفة **كل دفعة استُهلك منها** بسعرها هي. وسعر
            // الشراء يتغيّر، فاشتقاق التكلفة من Product.CostPrice يجعل تكلفة
            // بيعٍ ماضٍ تتغيّر بأثر رجعي كلما اشتُريت شحنة بسعر جديد — أي
            // ربحاً يتحرّك بعد أن تحقّق.
            costOfGoodsSold += issuedLots.Sum(l => l.Quantity * l.UnitCost);

            foreach (var group in issuedLots.GroupBy(l => l.BatchNumber))
            {
                invoiceItem.Batches.Add(new InvoiceItemBatch
                {
                    BatchNumber = group.Key,
                    Quantity = group.Sum(l => l.Quantity),
                });
            }

            // موديول التنبيهات: دفعة SignalR اللحظية للمتصلين الآن، بالإضافة
            // إلى صف دائم في notifications حتى تظهر لاحقاً في "غرفة
            // الإشعارات" لمن لم يكن متصلاً وقت الحدث (الدفعة وحدها كانت
            // تُفقَد فوراً بلا أي أثر دائم قبل هذا الإصلاح).
            //
            // على مجموع الدفعات لا على دفعة واحدة: حدّ إعادة الطلب خاصية
            // للصنف، فقياسه برصيد دفعة بعينها كان يُطلق إنذاراً كاذباً كلما
            // نفدت دفعة والمخزون الكلي وافر.
            //
            // والموقوف مستثنى: هو مالٌ في المخزن لكنه ليس بضاعة قابلة للبيع،
            // فعدّه ضمن الرصيد يُسكت إنذار النقص عن صنف لا يوجد منه شيء صالح.
            var remainingTotal = batches.Where(b => !b.IsLocked).Sum(b => b.Quantity);
            if (remainingTotal <= product.ReorderLevel)
            {
                await _hub.Clients.Group(invoice.OrganizationId.ToString())
                    .SendAsync("LowStockAlert", new { product.Name, Quantity = remainingTotal });

                _db.Notifications.Add(new NotificationItem
                {
                    OrganizationId = invoice.OrganizationId,
                    BranchId = request.BranchId,
                    Type = "low_stock",
                    Title = $"نقص مخزون: {product.Name}",
                    Body = $"الكمية المتبقية: {remainingTotal}",
                });
            }
        }

        // ── الدفع الجزئي ──────────────────────────────────────────────
        //
        // الفرق دَينٌ على العميل، فيلزم عميل معروف: لا دَين على «زبون نقدي»
        // — من ينصرف بلا اسم لا يُطالَب لاحقاً.
        //
        // والحدّ الائتماني قرار إداري لا قرار كاشير: يُضبط لكل عميل من
        // شاشة العملاء. صفر يعني «لا بيع بالأجل لهذا العميل» لا «بلا قيد»،
        // وهو الافتراض الآمن — العكس كان يفتح الأجل للجميع بلا قرار.
        var paidAmount = request.PaidAmount ?? invoice.TotalAmount;
        if (paidAmount < 0)
        {
            return BadRequest(new { message = "المبلغ المدفوع لا يمكن أن يكون سالباً" });
        }
        if (paidAmount > invoice.TotalAmount)
        {
            return BadRequest(new { message = "المبلغ المدفوع أكبر من إجمالي الفاتورة" });
        }

        var debtAmount = invoice.TotalAmount - paidAmount;
        Customer? debtCustomer = null;
        if (debtAmount > 0)
        {
            if (payingFromWallet)
            {
                return BadRequest(new { message = "الدفع من المحفظة لا يقبل تجزئة — الرصيد يكفي أو لا يكفي" });
            }
            if (!request.CustomerId.HasValue)
            {
                return BadRequest(new { message = "الدفع الجزئي يحتاج عميلاً محدَّداً — لا دَين على زبون نقدي" });
            }
            debtCustomer = await _db.Customers.FindAsync(request.CustomerId.Value);
            if (debtCustomer is null) return BadRequest(new { message = "العميل غير موجود" });

            // الرصيد الحالي يدخل الحساب: عميل رصيده موجب يستهلكه أولاً،
            // والدَّين هو ما يتجاوزه — والحدّ يُقاس على المحصّلة لا على
            // مبلغ الفاتورة وحده.
            var current = await WalletBalances.ComputeLockedAsync(_db, debtCustomer.Id);
            var after = current - debtAmount;
            if (after < -debtCustomer.CreditLimit)
            {
                return BadRequest(new
                {
                    message = debtCustomer.CreditLimit <= 0
                        ? "البيع بالأجل غير مسموح لهذا العميل — اضبط حدّ الائتمان من شاشة العملاء"
                        : $"المبلغ يتجاوز حدّ ائتمان العميل ({debtCustomer.CreditLimit:0.##})"
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

            // السقف اليومي لنمط «بطاقة فقط» — هنا لا قبل التسعير: المبلغ
            // الحقيقي لا يُعرف إلا بعد تثبيت الأسعار من الكتالوج، وفحصُه على
            // مبلغ من الطلب يُفحَص ما يقوله المرسِل لا ما يُخصَم فعلاً.
            //
            // وداخل المعاملة لا خارجها: قفل النطاق أعلاه يمنع حركات متزامنة
            // لهذا العميل، فبيعتان في اللحظة نفسها لا تمرّان كلتاهما تحت سقف
            // يتّسع لواحدة.
            if (cardMode == CardModes.Card)
            {
                var modeCheck = await CardModeGate.CheckAsync(
                    _db, org, walletCustomer, invoice.TotalAmount, DateTime.UtcNow);
                if (!modeCheck.Allowed)
                {
                    return BadRequest(new { message = modeCheck.Message });
                }
            }
        }

        // invoice_payments كانت جدولاً معرَّفاً في المخطط بلا أي كود يكتب
        // إليه — الفاتورة كانت تُنشأ بلا سجل دفع مطابق أصلاً. صف واحد بكامل
        // المبلغ يكفي الآن (دفع مقسّم فعلي مرحلة لاحقة على شاشة POS ذاتها).
        // صف الدفع بالمبلغ المدفوع فعلاً لا بإجمالي الفاتورة: تسجيل الكامل
        // في دفع جزئي يجعل الدفتر يقول إن المال قُبض وهو لم يُقبض.
        invoice.Payments.Add(new InvoicePayment { Method = request.PaymentMethod, Amount = paidAmount });
        invoice.PaidAmount = paidAmount;

        // تاريخ الاستحقاق لقطةً من مهلة العميل لحظة البيع، لا مرجعاً إليها:
        // تغيير المهلة لاحقاً يجب ألّا يحرّك استحقاق فواتير مضت — وإلا صار
        // بالإمكان إخفاء تأخّر بتعديل حقل في شاشة العملاء.
        if (debtAmount > 0 && debtCustomer is not null)
        {
            invoice.DueDate = invoice.CreatedAt.Date.AddDays(Math.Max(0, debtCustomer.CreditDays));
        }
        invoice.TenderedAmount = request.TenderedAmount;
        if (request.TenderedAmount.HasValue)
        {
            var change = request.TenderedAmount.Value - paidAmount;
            invoice.ChangeDue = change > 0 ? change : 0;
        }

        _db.Invoices.Add(invoice);
        await _db.SaveChangesAsync();

        // قيد دفتر الوصفات بعد الفاتورة عمداً: prescriptions يحمل مفتاحاً
        // خارجياً على invoices، وEF لا يعرف هذا الاعتماد (لا Navigation
        // property بينهما) فيُدرج القيد قبل الفاتورة لو حُفظا معاً فيرفضه
        // القيد. كلاهما داخل نفس المعاملة الصريحة — إما يمرّان معاً أو
        // يُلغيان معاً، فلا يبقى صرفٌ بلا قيد ولا قيد بلا صرف.
        //
        // ويُسجَّل كلّما أُرسلت وصفة، لا فقط عند وجود دواء مقيَّد: الصيدلي قد
        // يوثّق وصفة لدواء غير مقيَّد، ورفض توثيقه لا مبرّر له.
        if (request.Prescription is { } rx
            && !string.IsNullOrWhiteSpace(rx.DoctorName)
            && !string.IsNullOrWhiteSpace(rx.PatientName))
        {
            _db.Prescriptions.Add(new Prescription
            {
                OrganizationId = invoice.OrganizationId,
                BranchId = request.BranchId,
                InvoiceId = invoice.Id,
                PrescriptionNumber = rx.PrescriptionNumber?.Trim(),
                DoctorName = rx.DoctorName.Trim(),
                DoctorLicense = rx.DoctorLicense?.Trim(),
                PatientName = rx.PatientName.Trim(),
                PatientPhone = rx.PatientPhone?.Trim(),
                IssuedOn = rx.IssuedOn,
                Notes = rx.Notes?.Trim(),
                CreatedBy = CurrentUserId(),
            });

            _db.LogAudit(invoice.OrganizationId, CurrentUserId(), "prescription.dispensed",
                "prescriptions", invoice.Id,
                newValues: new { rx.DoctorName, rx.PatientName, Medicines = restrictedNames });

            await _db.SaveChangesAsync();
        }

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

        // الدَّين حركة مدينة على دفتر العميل — بعد الفاتورة لنفس سبب حركة
        // المحفظة أعلاه (مفتاح خارجي على invoices).
        if (debtAmount > 0 && debtCustomer is not null)
        {
            _db.CustomerWalletTransactions.Add(new CustomerWalletTransaction
            {
                OrganizationId = invoice.OrganizationId,
                CustomerId = debtCustomer.Id,
                InvoiceId = invoice.Id,
                Kind = WalletKinds.Spend,
                Amount = debtAmount,
                Note = $"باقي فاتورة {invoice.InvoiceNumber} (دفع جزئي)",
                CreatedBy = CurrentUserId(),
            });
            _db.LogAudit(invoice.OrganizationId, CurrentUserId(), "invoice.partial_payment", "invoices", invoice.Id,
                newValues: new { invoice.TotalAmount, Paid = paidAmount, Debt = debtAmount, debtCustomer.Id });
            await _db.SaveChangesAsync();
        }

        // ── الترحيل المحاسبي ────────────────────────────────────────────
        //
        // داخل المعاملة نفسها: فاتورةٌ بلا قيدها ثقبٌ في الدفتر لا يُكتشف إلا
        // عند المراجعة. وترحيلٌ بمهمّة خلفية يعني دفتراً يتخلّف عن الواقع
        // بمقدار ما تعطّلت المهمّة — راجع [Ledger].
        await PostInvoiceAsync(invoice, org, paidAmount, debtAmount, payingFromWallet, costOfGoodsSold);

        await transaction.CommitAsync();

        return CreatedAtAction(nameof(GetById), new { id = invoice.Id }, invoice);
    }

    /// <summary>
    /// قيد الفاتورة.
    ///
    /// <para><b>القيد المكتوب:</b></para>
    /// <code>
    ///   من ح/ الصندوق            (المدفوع نقداً)
    ///   من ح/ العملاء            (الآجل)
    ///   من ح/ أرصدة العملاء      (المخصوم من المحفظة — إطفاء التزام)
    ///       إلى ح/ المبيعات      (الصافي قبل الضريبة)
    ///       إلى ح/ ضريبة المبيعات
    ///
    ///   من ح/ تكلفة البضاعة المباعة
    ///       إلى ح/ المخزون
    /// </code>
    ///
    /// <para><b>ولماذا قيدان لا واحد:</b> الأول يُثبت الإيراد، والثاني ينقل
    /// البضاعة من أصلٍ إلى تكلفة. دمجُهما يجعل «تكلفة البضاعة المباعة» و
    /// «المبيعات» في قيد واحد فيبدو الربح كأنه بند مستقلّ — وهو ليس بنداً بل
    /// فرقٌ يُشتقّ.</para>
    ///
    /// <para><b>والخصم من المحفظة ليس تحصيلاً نقدياً:</b> المال قُبض يوم
    /// الشحن وسُجّل التزاماً (راجع حساب «أرصدة العملاء»). فالبيع منه
    /// **يُطفئ الالتزام** لا يُدخل نقداً. تسجيله في الصندوق يُضخّم النقدية
    /// بمالٍ ليس في الدرج.</para>
    /// </summary>
    private async Task PostInvoiceAsync(
        Invoice invoice, Organization org, decimal paidAmount, decimal debtAmount, bool fromWallet,
        decimal costOfGoodsSold)
    {
        var license = await _db.Licenses.FirstOrDefaultAsync();
        if (!Ledger.IsEnabled(org, license)) return;

        var net = invoice.Subtotal - invoice.DiscountAmount;
        var lines = new List<PostingLine>();

        if (fromWallet)
        {
            lines.Add(new PostingLine(AccountRoles.CustomerWallet, invoice.TotalAmount, 0,
                "خصم من رصيد العميل"));
        }
        else
        {
            if (paidAmount > 0) lines.Add(new PostingLine(AccountRoles.Cash, paidAmount, 0));
            if (debtAmount > 0) lines.Add(new PostingLine(AccountRoles.Receivables, debtAmount, 0));
        }

        lines.Add(new PostingLine(AccountRoles.SalesRevenue, 0, net));
        if (invoice.TaxAmount > 0)
        {
            lines.Add(new PostingLine(AccountRoles.SalesTax, 0, invoice.TaxAmount));
        }

        await Ledger.PostAsync(_db, invoice.OrganizationId, invoice.BranchId,
            JournalSources.Invoice, invoice.Id,
            $"فاتورة {invoice.InvoiceNumber}", lines, CurrentUserId(),
            invoice.CreatedAt.Date);

        // قيد التكلفة بما جمعه الدفتر فعلاً أثناء الصرف. وقد يكون صفراً
        // لصنفٍ لا يُتتبَّع مخزونه (خدمة، صنف مفتوح القيمة) — فلا قيد تكلفة
        // له، إذ لم تخرج بضاعة.
        var cost = costOfGoodsSold;
        if (cost > 0)
        {
            await Ledger.PostAsync(_db, invoice.OrganizationId, invoice.BranchId,
                JournalSources.Invoice, invoice.Id,
                $"تكلفة مبيعات فاتورة {invoice.InvoiceNumber}",
                new[]
                {
                    new PostingLine(AccountRoles.CostOfGoodsSold, cost, 0),
                    new PostingLine(AccountRoles.Inventory, 0, cost),
                },
                CurrentUserId(), invoice.CreatedAt.Date);
        }

        await _db.SaveChangesAsync();
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
        // ThenInclude(Batches) — تخصيص الدفعات لازم لإعادة كل كمية إلى دفعتها
        // الأصلية بدل «دفعة عامة» بلا تاريخ صلاحية (راجع InvoiceItemBatch).
        var original = await _db.Invoices
            .Include(i => i.Items).ThenInclude(it => it.Batches)
            .Include(i => i.Payments)
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

        // تكلفة البضاعة العائدة — تُجمَع من الدفتر أثناء الإرجاع.
        decimal returnedCost = 0;

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
                // المرتجع يعكس البيع بوحدته: «أُرجعت 3 حبات» لا «0.3 شريط».
                SoldAsSubUnit = item.SoldAsSubUnit,
                SubUnitsPerBase = item.SubUnitsPerBase,
            });

            // الصنف غير المتتبَّع مخزنياً لم يُخصَم عند البيع، فإرجاعه للمخزون
            // كان سيخلق كمية من عدم — راجع Product.TracksStock.
            var refundedProduct = await _db.Products.FindAsync(item.ProductId);
            if (refundedProduct is not null && !refundedProduct.TracksStock) continue;

            // كل كمية تعود إلى دفعتها التي خرجت منها فعلاً.
            //
            // الفواتير التي بيعت قبل وجود invoice_item_batches لا تخصيص لها،
            // فتعود كما كانت إلى دفعة عامة ("") — سلوك النسخة السابقة، محفوظ
            // عمداً حتى تبقى الفواتير القديمة قابلة للاسترجاع.
            // تخصيص الدفعات محفوظ بالوحدة الأساسية أصلاً (خُصم كذلك)، فيعود
            // كما هو. أما المسار الاحتياطي فيقرأ Quantity وهي بوحدة البيع،
            // فتُحوَّل بلقطة المعامل وقت البيع — وإلا أعاد بيعُ 3 حبات ثلاثة
            // شرائط كاملة إلى الرفّ.
            var fallbackQuantity = item.SoldAsSubUnit && item.SubUnitsPerBase > 0
                ? item.Quantity / item.SubUnitsPerBase
                : item.Quantity;

            var allocations = item.Batches.Count > 0
                ? item.Batches.Select(b => (b.BatchNumber, b.Quantity)).ToList()
                : new List<(string, decimal)> { ("", fallbackQuantity) };

            foreach (var (batchNumber, batchQuantity) in allocations)
            {
                // المرتجع إدخالٌ في الدفتر كأي إدخال: بضاعة عادت إلى الرفّ
                // فيجب أن تُقيَّد، وإلا صار الرصيد يزيد بلا سطر يفسّره —
                // وهو بالضبط ما جاء الدفتر ليمنعه.
                //
                // بتكلفة سطر الصرف الأصلي لا بتكلفة الصنف اليوم: المرتجع
                // يُعيد ما خرج بثمنه، وإعادته بتكلفة اليوم تُنتج ربحاً أو
                // خسارة وهميين من عملية لم يقع فيها بيع ولا شراء.
                var originalCost = await _db.StockLedgerEntries
                    .Where(e => e.SourceType == StockSourceTypes.Invoice
                             && e.SourceId == original.Id
                             && e.ProductId == item.ProductId
                             && e.BatchNumber == batchNumber)
                    .Select(e => (decimal?)e.UnitCost)
                    .FirstOrDefaultAsync();

                var product = await _db.Products.FirstOrDefaultAsync(p => p.Id == item.ProductId);

                var returnedUnitCost = originalCost ?? product?.CostPrice ?? 0;
                // تكلفة ما عاد إلى الرفّ — يُعكَس بها قيد التكلفة أدناه.
                returnedCost += batchQuantity * returnedUnitCost;

                await StockLedger.ReceiveAsync(
                    _db, original.OrganizationId, original.BranchId, warehouseId: null,
                    productId: item.ProductId,
                    quantity: batchQuantity,
                    unitCost: returnedUnitCost,
                    sourceType: StockSourceTypes.InvoiceReturn, sourceId: original.Id,
                    userId: CurrentUserId(),
                    batchNumber: batchNumber,
                    // تاريخ الصلاحية غير محفوظ على سطر الفاتورة، فيبقى فارغاً
                    // ويُؤخَّر في الصرف: المرتجع مجهول التاريخ لا يُصرَّف قبل
                    // دفعة معلومة الانتهاء.
                    trackExpiry: true);
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

        await PostRefundAsync(original, refund, walletRefundAmount, returnedCost);

        await transaction.CommitAsync();

        return CreatedAtAction(nameof(GetById), new { id = refund.Id }, refund);
    }

    /// <summary>
    /// قيد المرتجع.
    ///
    /// <code>
    ///   من ح/ مردودات المبيعات   (الصافي قبل الضريبة)
    ///   من ح/ ضريبة المبيعات     (إطفاء الضريبة المستحقّة)
    ///       إلى ح/ أرصدة العملاء (المردود إلى المحفظة)
    ///       إلى ح/ الصندوق       (المردود نقداً)
    ///
    ///   من ح/ المخزون
    ///       إلى ح/ تكلفة البضاعة المباعة
    /// </code>
    ///
    /// <para><b>لماذا «مردودات المبيعات» لا خصمٌ من «المبيعات»:</b> الخصم
    /// يُخفي حجم المرتجع تماماً — تُقرأ المبيعات صافيةً ولا يُعرف كم بضاعةٍ
    /// عادت. وحجم المرتجع رقمٌ يقول شيئاً عن جودة البضاعة وعن البيع نفسه،
    /// فيُفرَد ليُقرأ.</para>
    ///
    /// <para><b>ولماذا قيدٌ جديد لا عكسٌ لقيد البيع:</b> العكس يمحو أثر
    /// البيع من الدفتر فتبدو الفاتورة كأنها لم تقع. والمرتجع **حدثٌ ثانٍ
    /// وقع فعلاً** — بيعٌ ثم ردّ — والدفتر يحكي ما جرى لا ما بقي.</para>
    ///
    /// <para>والضريبة تُطفأ بمدين لأنها سُجّلت دائناً عند البيع: بضاعة عادت
    /// فلم تعد ضريبتها مستحقّة على المنشأة.</para>
    /// </summary>
    private async Task PostRefundAsync(
        Invoice original, Invoice refund, decimal walletRefundAmount, decimal returnedCost)
    {
        var org = await _db.Organizations.FirstOrDefaultAsync();
        var license = await _db.Licenses.FirstOrDefaultAsync();
        if (org is null || !Ledger.IsEnabled(org, license)) return;

        var net = refund.Subtotal - refund.DiscountAmount;
        var lines = new List<PostingLine>
        {
            new(AccountRoles.SalesReturns, net, 0),
        };
        if (refund.TaxAmount > 0)
        {
            lines.Add(new PostingLine(AccountRoles.SalesTax, refund.TaxAmount, 0));
        }

        if (walletRefundAmount > 0)
        {
            lines.Add(new PostingLine(AccountRoles.CustomerWallet, 0, walletRefundAmount,
                "ردّ إلى رصيد العميل"));
        }

        // الباقي نقداً. **وهو ما يخرج من الدرج فعلاً** — الرد النقدي إجراء
        // يدوي خارج النظام (لا حساب بنكي مربوط)، لكنه وقع، وقيدٌ لا يعترف
        // به يجعل النقدية الدفترية أعلى من نقدية الدرج بمقدار كل مرتجع.
        var cashBack = refund.TotalAmount - walletRefundAmount;
        if (cashBack > 0)
        {
            lines.Add(new PostingLine(AccountRoles.Cash, 0, cashBack, "ردّ نقدي"));
        }

        await Ledger.PostAsync(_db, original.OrganizationId, original.BranchId,
            JournalSources.InvoiceReturn, refund.Id,
            $"مرتجع فاتورة {original.InvoiceNumber}", lines, CurrentUserId());

        // عكس قيد التكلفة: البضاعة عادت من التكلفة إلى المخزون.
        if (returnedCost > 0)
        {
            await Ledger.PostAsync(_db, original.OrganizationId, original.BranchId,
                JournalSources.InvoiceReturn, refund.Id,
                $"عودة تكلفة مرتجع {original.InvoiceNumber}",
                new[]
                {
                    new PostingLine(AccountRoles.Inventory, returnedCost, 0),
                    new PostingLine(AccountRoles.CostOfGoodsSold, 0, returnedCost),
                },
                CurrentUserId());
        }

        await _db.SaveChangesAsync();
    }

    /// <summary>
    /// فحص صلاحية داخل منطق الإجراء لا كسمة عليه.
    ///
    /// [RequirePermission] يحرس الإجراء كلّه، بينما «صرف المقيَّد» شرطٌ لا
    /// يقع إلا حين تحوي الفاتورة دواءً مقيَّداً — وضعه سمةً كان يمنع الكاشير
    /// من بيع علبة مناديل. نفس منطق السمة: super_admin يتجاوز، والباقي
    /// يُقرأ من role_permissions.
    /// </summary>
    private async Task<bool> HasPermissionAsync(string code)
    {
        var role = User.FindFirstValue(ClaimTypes.Role);
        var orgIdRaw = User.FindFirstValue("organization_id");
        if (role is null || orgIdRaw is null || !Guid.TryParse(orgIdRaw, out var orgId)) return false;
        if (role == "super_admin") return true;

        return await _db.RolePermissions.AnyAsync(rp =>
            rp.OrganizationId == orgId && rp.Role == role && rp.PermissionCode == code);
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
