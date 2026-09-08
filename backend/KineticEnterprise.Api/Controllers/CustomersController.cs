using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Data.SqlClient;
using KineticEnterprise.Api.Authorization;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Controllers;

public record RecordDebtReminderRequest(string? Note = null);

public record WalletAdjustmentRequest(decimal AmountDelta, string? Note);
/// <param name="Pin">
/// الرقم السرّي. اختياريّ: في نمط «بطاقة فقط» لا رقم أصلاً — وإلزامه هناك
/// يُنشئ سرّاً لا يستعمله أحد ويبقى قابلاً للتسريب.
/// </param>
public record IssueCardRequest(string? Pin, string? CardMode = null, decimal? DailyCap = null);

/// <summary>إصدار بطاقات لمجموعة عملاء دفعةً واحدة.</summary>
public record BulkIssueCardsRequest(
    /// عملاءٌ بأعيانهم. فارغة = كل من في [CategoryId] بلا بطاقة.
    List<Guid>? CustomerIds,
    Guid? CategoryId,
    /// النمط لكل البطاقات. NULL = افتراضي المنظمة.
    string? CardMode = null,
    /// إعادة الإصدار لمن له بطاقة. الافتراضي: تخطّيه.
    bool Reissue = false);

public record BulkIssuedCardDto(Guid CustomerId, string FullName, string CardCode);

public record BulkIssueCardsResult(
    int Issued, int Skipped, string CardMode, List<BulkIssuedCardDto> Cards);
public record IssuedCardDto(string CardCode);

public record SetCardModeRequest(string? CardMode, decimal? DailyCap);

/// صفحة عملاء: العناصر مع العدد الكلي المطابق للفلتر — الواجهة تحتاج
/// العدد الكلي لا عدد الصفحة، وإلا تعذّر عليها رسم "عرض 1–50 من 1,240"
/// ولا معرفة ما إذا كانت هناك صفحة تالية أصلاً.
public record CustomerPageDto(List<CustomerDto> Items, int TotalCount, int Page, int PageSize);

/// <summary>بيانات العميل المطلوبة للاستيراد الجماعي من ملف CSV أو JSON.</summary>
public record ImportCustomerRequest(
    string FullName,
    string? Phone = null,
    string? Email = null,
    string? Notes = null,
    decimal CreditLimit = 0,
    int CreditDays = 0,
    Guid? BranchId = null,
    string AccountModel = AccountModels.Prepaid,
    Guid? SponsorId = null,
    decimal EntitlementCeiling = 0,
    DateOnly? EntitlementExpiresOn = null,
    Guid? CategoryId = null,
    decimal? EntitlementOverride = null);

/// <summary>نتيجة استيراد عميل واحد — نجح أم فشل ولماذا.</summary>
public record ImportCustomerResult(
    int RowNumber,
    bool Success,
    string? Error = null,
    Guid? CustomerId = null,
    string? FullName = null);

/// <summary>نتائج استيراد جماعي للعملاء.</summary>
public record BulkImportCustomersResult(
    int Total,
    int Imported,
    int Failed,
    List<ImportCustomerResult> Results);

/// <summary>
/// ما يُقبَل من العميل عند إنشاء زبون أو تعديله.
///
/// <para><b>الثغرة التي يغلقها:</b> كان <c>Create</c> يربط كيان
/// <see cref="Customer"/> كاملاً من الطلب. فمن يملك <c>customers.manage</c>
/// يستطيع إرسال حقولٍ لا تعرضها أي شاشة ويحرسها الخادم في مسارات أخرى:</para>
///
/// <list type="bullet">
/// <item><c>pinHash</c> — بصمة رقمٍ سرّي يعرفه هو، متجاوزاً
///   <c>CustomerCards.ValidatePin</c> ومسار إصدار البطاقة كلّه.</item>
/// <item><c>cardBarcode</c> — بطاقةٌ برمزٍ لا صفَّ له في
///   <c>customer_card_index</c>، فتوجد بطاقة لا يعرفها فهرس البطاقات.</item>
/// <item><c>dailyCap</c> — يتجاوز سقف المنظمة الذي يفرضه
///   <see cref="CardModeGate"/>.</item>
/// <item><c>id</c> و<c>isDeleted</c> و<c>createdAt</c> — معرّفٌ من اختياره،
///   أو زبونٌ يُولَد محذوفاً.</item>
/// </list>
///
/// <para><b>ولماذا عقدٌ لا فحوصٌ إضافية:</b> ما لا يُذكَر هنا **لا يمكن
/// إرساله أصلاً** — لا يُحرَس بشرطٍ قد يُنسى عند إضافة حقلٍ جديد. وهذا
/// الفرق بين بابٍ مغلق وبابٍ عليه حارس.</para>
/// </summary>
/// <para><b>⚠ والافتراضات تطابق افتراضات الكيان</b>: نقطة البيع تُنشئ
/// زبوناً سريعاً بالاسم والهاتف وحدهما، فحقلٌ بلا قيمة افتراضية هنا كان
/// سيصل صفراً أو فارغاً — و<c>accountModel</c> فارغاً يُرفَض الطلبُ كلّه
/// فينكسر الإنشاء السريع من على الصندوق.</para>
public record SaveCustomerRequest(
    string FullName,
    string? Phone = null, string? Email = null, string? Notes = null,
    string? CardBarcode = null,
    decimal CreditLimit = 0, int CreditDays = 0,
    Guid? BranchId = null,
    string AccountModel = AccountModels.Prepaid,
    Guid? SponsorId = null, decimal EntitlementCeiling = 0,
    DateOnly? EntitlementExpiresOn = null,
    Guid? CategoryId = null, decimal? EntitlementOverride = null,
    string? PhotoUrl = null);

public record CustomerDto(
    Guid Id, Guid OrganizationId, Guid? BranchId, string FullName, string? Phone,
    string? Email, string? Notes, string? CardBarcode,
    decimal WalletBalance, decimal CreditLimit,
    /// مهلة السداد بالأيام — راجع Customer.CreditDays.
    int CreditDays,
    int LoyaltyPoints, DateTime CreatedAt,
    string AccountModel, Guid? SponsorId, string? SponsorName,
    decimal EntitlementCeiling, DateOnly? EntitlementExpiresOn,
    /// فئة العميل ومبلغها — الشاشة تعرض المنحة المستحقّة بلا نداءٍ ثانٍ.
    Guid? CategoryId, string? CategoryName,
    /// مبلغٌ يخصّه وحده يَجُبّ فئته. NULL = اتبع الفئة، والصفر إيقافٌ صريح.
    decimal? EntitlementOverride,
    /// صورة صاحب البطاقة — تُطبع عليها وتظهر للكاشير عند المسح.
    string? PhotoUrl,
    /// نمط التحقّق المختار لهذا الحساب — NULL يعني اتباع افتراضي المنظمة.
    string? CardMode,
    /// النمط الفعّال بعد تطبيق مسموح المنظمة وافتراضها — ما سيحدث فعلاً.
    string EffectiveCardMode,
    decimal DailyCap,
    /// السقف الفعّال بعد الأخذ بالأشدّ بين سقف المنظمة وسقف الزبون.
    decimal EffectiveDailyCap,
    /// هل للحساب رقم سرّي مضبوط أصلاً — الواجهة تحتاجه لتمنع اختيار نمط
    /// «رقم سرّي» لحسابٍ بلا رقم، فيصير الصرف مستحيلاً.
    bool HasPin);

public record WalletTransactionDto(
    Guid Id, string Kind, decimal Amount, decimal SignedAmount, string? Note, Guid? InvoiceId, DateTime CreatedAt);

/// <summary>
/// نفس نمط ProductsController — Security Policy على جدول customers
/// (fn_OrgOnlyPredicate) تتكفّل بعزل المنظمة تلقائياً. branch_id هنا وصفي
/// فقط (عميل تابع لفرع أو عميل مركزي)، وليس عزلاً أمنياً، فلا حاجة لسياسة
/// من نوع fn_TenantPredicate (راجع DATABASE_TABLES_GUIDE.md §6.1).
///
/// رصيد المحفظة لا يُقرأ من عمود ولا يُكتب في عمود — يُجمَع دائماً من دفتر
/// customer_wallet_transactions عبر [WalletBalances]، فيستحيل أن يتعارض
/// الرصيد المعروض مع حركاته.
/// </summary>
[ApiController]
[Route("api/customers")]
[Authorize]
public class CustomersController : ControllerBase
{
    private readonly AppDbContext _db;
    public CustomersController(AppDbContext db) => _db = db;

    /// <summary>
    /// منظمة الطالب — تلزم لحساب النمط والسقف الفعّالين لكل عميل معروض.
    /// تُقرأ مرّة لكل طلب لا مرّة لكل صف: صفحةٌ بمئتَي عميل كانت ستُصدر مئتَي
    /// استعلام متطابق.
    /// </summary>
    private Organization? _org;
    private async Task<Organization?> OrgAsync() =>
        _org ??= await _db.Organizations.FirstOrDefaultAsync();

    /// <summary>
    /// قائمة العملاء مقسَّمة صفحات. كانت تُعيد كل العملاء دفعة واحدة، ومعهم
    /// استعلام أرصدة محفظة لكل واحد — أي أن تكلفة فتح الشاشة كانت تنمو خطياً
    /// مع عدد عملاء المنظمة بلا سقف. مع خمسة آلاف عميل يعني ذلك تجميد
    /// الواجهة ثوانيَ في كل فتح، وهو أشهر ما يُشتكى منه بوصف "النظام بطيء".
    ///
    /// الشكل المُعاد صار مغلَّفاً {items, totalCount, page, pageSize} على غرار
    /// AuditLogsController — وهو تغيير كاسر للعقد، حُدِّث معه كل مستهلك في
    /// التطبيق (شاشة العملاء، بحث الزبون في نقطة البيع، شاشة بطاقات المحفظة).
    /// </summary>
    [HttpGet]
    public async Task<ActionResult<CustomerPageDto>> GetAll(
        [FromQuery] string? search,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        page = Math.Max(1, page);
        // السقف 200 يمنع عميلاً (أو خطأً برمجياً) من طلب الجدول كله بحجّة
        // أنه "صفحة واحدة كبيرة"، فتعود المشكلة نفسها من الباب الخلفي.
        pageSize = Math.Clamp(pageSize, 1, 200);

        var query = _db.Customers.Where(c => !c.IsDeleted);
        if (!string.IsNullOrWhiteSpace(search))
        {
            query = query.Where(c =>
                c.FullName.Contains(search) ||
                (c.Phone != null && c.Phone.Contains(search)) ||
                (c.Email != null && c.Email.Contains(search)) ||
                (c.CardBarcode != null && c.CardBarcode.Contains(search)));
        }

        var totalCount = await query.CountAsync();
        var customers = await query.OrderBy(c => c.FullName)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync();

        // استعلام تجميع واحد لكل العملاء المعروضين بدل استعلام لكل صف.
        var ids = customers.Select(c => c.Id).ToList();
        var balances = await WalletBalances.ComputeManyAsync(_db, ids);

        // أسماء الجهات الممولة بالأعمدة المطلوبة وحدها (لا الكيان كاملاً)،
        // ولمن يملك جهة فقط — لا يُجلَب الجدول كله.
        var sponsorIds = customers.Where(c => c.SponsorId.HasValue).Select(c => c.SponsorId!.Value).Distinct().ToList();
        var sponsorNames = sponsorIds.Count == 0
            ? new Dictionary<Guid, string>()
            : await _db.Sponsors
                .Where(s => sponsorIds.Contains(s.Id))
                .Select(s => new { s.Id, s.Name })
                .ToDictionaryAsync(s => s.Id, s => s.Name);

        // أسماء الفئات مرّةً واحدة — قائمةٌ بألف عميل لا تحتمل نداءً لكلٍّ.
        var categoryNames = await _db.CustomerCategories
            .Select(c => new { c.Id, c.Name })
            .ToDictionaryAsync(c => c.Id, c => c.Name);

        var org = await OrgAsync();
        var items = customers
            .Select(c => ToDto(c, balances.GetValueOrDefault(c.Id),
                c.SponsorId is null ? null : sponsorNames.GetValueOrDefault(c.SponsorId.Value), org,
                c.CategoryId is null ? null : categoryNames.GetValueOrDefault(c.CategoryId.Value)))
            .ToList();

        return new CustomerPageDto(items, totalCount, page, pageSize);
    }

    /// <summary>
    /// بحث بالمطابقة التامة لرمز البطاقة — لمسح البطاقة مباشرة في نقطة البيع.
    ///
    /// منفصل عن بحث <see cref="GetAll"/> الجزئي عمداً: القارئ الضوئي يُرسل
    /// الرمز كاملاً، والمطابقة الجزئية قد تُرجع عميلاً آخر رمزه يحتوي المُدخَل
    /// فيُخصَم من حساب شخص غير الذي أمام الكاشير.
    ///
    /// لا يكشف الرمز شيئاً حساساً وحده — الصرف يحتاج الرقم السري أيضاً
    /// (راجع InvoicesController.Create).
    /// </summary>
    [HttpGet("by-card/{code}")]
    public async Task<ActionResult<CustomerDto>> GetByCard(string code)
    {
        var normalized = (code ?? "").Trim().ToUpperInvariant();
        if (string.IsNullOrEmpty(normalized)) return NotFound();

        var customer = await _db.Customers
            .FirstOrDefaultAsync(c => c.CardBarcode == normalized && !c.IsDeleted);
        if (customer is null) return NotFound();

        return ToDto(customer, await BalanceOf(customer.Id), await SponsorNameOf(customer), await OrgAsync());
    }

    [HttpGet("{id:guid}")]
    public async Task<ActionResult<CustomerDto>> GetById(Guid id)
    {
        var customer = await _db.Customers.FindAsync(id);
        if (customer is null) return NotFound();
        return ToDto(customer, await BalanceOf(id), await SponsorNameOf(customer), await OrgAsync());
    }

    /// <summary>
    /// كشف حركات المحفظة — هو ما يجعل الرصيد قابلاً للتفسير: أي رقم معروض
    /// يمكن ردّه إلى حركاته المكوِّنة له سطراً سطراً.
    /// </summary>
    [HttpGet("{id:guid}/wallet-transactions")]
    public async Task<ActionResult<List<WalletTransactionDto>>> GetWalletTransactions(Guid id)
    {
        var transactions = await _db.CustomerWalletTransactions
            .Where(t => t.CustomerId == id)
            .OrderByDescending(t => t.CreatedAt)
            .ToListAsync();

        return transactions.Select(t => new WalletTransactionDto(
            t.Id, t.Kind, t.Amount, t.Amount * WalletKinds.SignOf(t.Kind), t.Note, t.InvoiceId, t.CreatedAt)).ToList();
    }

    [HttpPost]
    [RequirePermission("customers.manage")]
    public async Task<ActionResult<CustomerDto>> Create(SaveCustomerRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.FullName))
            return BadRequest(new { message = "اسم العميل إلزامي" });
        if (!AccountModels.IsValid(request.AccountModel))
            return BadRequest(new { message = "نموذج حساب غير معروف" });

        var customer = new Customer
        {
            OrganizationId = Guid.Parse(User.FindFirstValue("organization_id")!),
            FullName = request.FullName.Trim(),
            Phone = request.Phone,
            Email = request.Email,
            Notes = request.Notes,
            // الباركود يُقبَل هنا لأن الاستيراد القديم يعتمده، ورمز البطاقة
            // الحقيقي يُولَّد في مسار الإصدار — راجع IssueCard.
            CardBarcode = string.IsNullOrWhiteSpace(request.CardBarcode) ? null : request.CardBarcode,
            CreditLimit = request.CreditLimit,
            CreditDays = request.CreditDays,
            BranchId = request.BranchId,
            AccountModel = request.AccountModel,
            SponsorId = request.SponsorId,
            EntitlementCeiling = request.EntitlementCeiling,
            EntitlementExpiresOn = request.EntitlementExpiresOn,
            CategoryId = request.CategoryId,
            EntitlementOverride = request.EntitlementOverride,
            PhotoUrl = request.PhotoUrl,
        };

        _db.Customers.Add(customer);
        try
        {
            await _db.SaveChangesAsync();
        }
        catch (DbUpdateException ex) when (IsDuplicateKey(ex))
        {
            // card_barcode فريد عالمياً (وليس داخل المنظمة فقط) — راجع
            // DATABASE_TABLES_GUIDE.md §6.1، لتفادي التباس عند مسح البطاقة في POS.
            return Conflict(new { message = "باركود البطاقة مستخدَم بالفعل" });
        }
        return CreatedAtAction(nameof(GetById), new { id = customer.Id }, ToDto(customer, 0, null, await OrgAsync()));
    }

    /// <summary>
    /// استيراد عملاء جماعي من ملف CSV أو JSON.
    ///
    /// <para><b>السلوك عند التكرار:</b> الهاتف مفتاح المطابقة — إذا وُجد عميلٌ
    /// برقم هاتفٍ موجود، يُحدَّث بيانات العميل الجديدة ولا يُنشأ مكرّر.
    /// فمن يستورد ملفاً مرتين بسهو لن يجد عملاء مكرّرين.</para>
    ///
    /// <para><b>الخطأ لكل صفّ يُسجَّل لكن لا يوقف الاستيراد:</b> فشل صفّ واحد
    /// لا يعني ترك بقية الملف — يُرجع التقرير أيّ الصفوف نجحت وأيّها فشلت
    /// ولماذا.</para>
    /// </summary>
    [HttpPost("import")]
    [RequirePermission("customers.manage")]
    public async Task<ActionResult<BulkImportCustomersResult>> BulkImport(
        [FromBody] List<ImportCustomerRequest> requests)
    {
        if (requests is null || requests.Count == 0)
            return BadRequest(new { message = "الملف فارغ — لا عملاء للاستيراد" });

        if (requests.Count > 10000)
            return BadRequest(new { message = "عدد العملاء يتجاوز 10000" });

        var orgId = Guid.Parse(User.FindFirstValue("organization_id")!);
        var results = new List<ImportCustomerResult>();
        var imported = 0;
        var org = await OrgAsync();

        // التحقّق من صحة نموذج الحساب
        for (int i = 0; i < requests.Count; i++)
        {
            var request = requests[i];
            var index = i;

            if (string.IsNullOrWhiteSpace(request.FullName))
            {
                results.Add(new ImportCustomerResult(
                    index + 1, false, "اسم العميل مطلوب"));
                continue;
            }

            if (!AccountModels.IsValid(request.AccountModel))
            {
                results.Add(new ImportCustomerResult(
                    index + 1, false, "نموذج حساب غير معروف"));
                continue;
            }

            try
            {
                var existing = string.IsNullOrWhiteSpace(request.Phone)
                    ? null
                    : await _db.Customers.FirstOrDefaultAsync(c =>
                        c.Phone == request.Phone && !c.IsDeleted);

                Customer customer;
                if (existing is not null)
                {
                    customer = existing;
                    customer.FullName = request.FullName.Trim();
                    customer.Email = request.Email;
                    customer.Notes = request.Notes;
                    customer.CreditLimit = request.CreditLimit;
                    customer.CreditDays = Math.Max(0, request.CreditDays);
                    customer.BranchId = request.BranchId;
                    customer.AccountModel = request.AccountModel;

                    if (customer.AccountModel == AccountModels.Entitlement)
                    {
                        customer.SponsorId = request.SponsorId;
                        customer.EntitlementCeiling = request.EntitlementCeiling;
                        customer.EntitlementExpiresOn = request.EntitlementExpiresOn;
                    }
                    else
                    {
                        customer.SponsorId = null;
                        customer.EntitlementCeiling = 0;
                        customer.EntitlementExpiresOn = null;
                    }
                }
                else
                {
                    customer = new Customer
                    {
                        OrganizationId = orgId,
                        FullName = request.FullName.Trim(),
                        Phone = request.Phone,
                        Email = request.Email,
                        Notes = request.Notes,
                        CreditLimit = request.CreditLimit,
                        CreditDays = Math.Max(0, request.CreditDays),
                        BranchId = request.BranchId,
                        AccountModel = request.AccountModel,
                        SponsorId = request.AccountModel == AccountModels.Entitlement
                            ? request.SponsorId
                            : null,
                        EntitlementCeiling = request.AccountModel == AccountModels.Entitlement
                            ? request.EntitlementCeiling
                            : 0,
                        EntitlementExpiresOn = request.AccountModel == AccountModels.Entitlement
                            ? request.EntitlementExpiresOn
                            : null,
                        CategoryId = request.CategoryId,
                        EntitlementOverride = request.EntitlementOverride,
                    };
                    _db.Customers.Add(customer);
                }

                await _db.SaveChangesAsync();
                imported++;
                results.Add(new ImportCustomerResult(
                    index + 1, true, null, customer.Id, customer.FullName));
            }
            catch (Exception ex)
            {
                var errorMsg = ex is DbUpdateException dbEx && IsDuplicateKey(dbEx)
                    ? "الهاتف مستخدَم بالفعل من قبل عميل آخر"
                    : "خطأ في حفظ البيانات";
                results.Add(new ImportCustomerResult(
                    index + 1, false, errorMsg));
            }
        }

        _db.LogAudit(orgId, CurrentUserId(), "customers.bulk_imported", "customers", null,
            newValues: new { Total = requests.Count, Imported = imported, Failed = requests.Count - imported });

        return new BulkImportCustomersResult(
            requests.Count, imported, requests.Count - imported, results);
    }

    [HttpPut("{id:guid}")]
    [RequirePermission("customers.manage")]
    public async Task<IActionResult> Update(Guid id, SaveCustomerRequest update)
    {
        if (string.IsNullOrWhiteSpace(update.FullName))
            return BadRequest(new { message = "اسم العميل إلزامي" });
        if (!AccountModels.IsValid(update.AccountModel))
            return BadRequest(new { message = "نموذج حساب غير معروف" });

        var customer = await _db.Customers.FindAsync(id);
        if (customer is null) return NotFound();

        customer.FullName = update.FullName;
        customer.Phone = update.Phone;
        customer.Email = update.Email;
        customer.Notes = update.Notes;
        customer.CardBarcode = update.CardBarcode;
        customer.BranchId = update.BranchId;
        customer.CreditLimit = update.CreditLimit;
        // السالب مرفوض هنا لا في الواجهة وحدها: مهلة سالبة تجعل كل بيع
        // متأخّراً لحظة إنشائه، فتُغرق سلّم التذكير بضجيج يُبطله.
        customer.CreditDays = Math.Max(0, update.CreditDays);

        if (!AccountModels.IsValid(update.AccountModel))
        {
            return BadRequest(new { message = "نموذج حساب غير معروف" });
        }
        customer.AccountModel = update.AccountModel;

        // حقول الاستحقاق تُمحى عند العودة للدفع المسبق، وإلا بقي سقف وتاريخ
        // انتهاء معلَّقين على حساب لا يُطبَّق عليهما — فيسقط رصيد العميل يوماً
        // ما لسبب لا يظهر في الشاشة.
        if (customer.AccountModel == AccountModels.Entitlement)
        {
            customer.SponsorId = update.SponsorId;
            customer.EntitlementCeiling = update.EntitlementCeiling;
            customer.EntitlementExpiresOn = update.EntitlementExpiresOn;
        }
        else
        {
            customer.SponsorId = null;
            customer.EntitlementCeiling = 0;
            customer.EntitlementExpiresOn = null;
        }

        try
        {
            await _db.SaveChangesAsync();
        }
        catch (DbUpdateException ex) when (IsDuplicateKey(ex))
        {
            return Conflict(new { message = "باركود البطاقة مستخدَم بالفعل" });
        }
        return NoContent();
    }

    /// <summary>
    /// تعديل رصيد المحفظة بصيغة "فرق" (+/-) — يُسجَّل كحركة جديدة في الدفتر،
    /// ولا يُعدَّل أي رصيد قائم. الرصيد الناتج يُحسَب بجمع الدفتر بعد الإضافة.
    /// </summary>
    [HttpPost("{id:guid}/wallet-adjustments")]
    [RequirePermission("customers.wallet_adjust")]
    public async Task<ActionResult<CustomerDto>> AdjustWallet(Guid id, WalletAdjustmentRequest request)
    {
        var customer = await _db.Customers.FindAsync(id);
        if (customer is null) return NotFound();
        if (request.AmountDelta == 0)
        {
            return BadRequest(new { message = "المبلغ صفر — لا حركة" });
        }

        var balance = await BalanceOf(id);
        if (balance + request.AmountDelta < 0)
        {
            return BadRequest(new { message = "الرصيد الناتج سالب" });
        }

        // الإيداع في حساب استحقاق منحةٌ من جهة ممولة لا شحناً من مال العميل،
        // فيُسجَّل بنوعه الصحيح ويخضع لسقف الفترة. تمييز النوع في الدفتر هو ما
        // يسمح لاحقاً بمحاسبة الجهة الممولة على ما مُنح فعلاً.
        var isEntitlement = customer.AccountModel == AccountModels.Entitlement;
        if (isEntitlement && request.AmountDelta > 0)
        {
            if (customer.EntitlementExpiresOn is null)
            {
                return BadRequest(new { message = "حدّد تاريخ انتهاء الاستحقاق قبل المنح" });
            }
            if (customer.EntitlementCeiling > 0)
            {
                var granted = await WalletBalances.GrantedInPeriodAsync(_db, customer.Id, PeriodStartOf(customer));
                var remaining = customer.EntitlementCeiling - granted;
                if (request.AmountDelta > remaining)
                {
                    return BadRequest(new
                    {
                        message = $"يتجاوز سقف الفترة — المتبقي للمنح {remaining:0.###}",
                    });
                }
            }
        }

        var kind = request.AmountDelta > 0
            ? (isEntitlement ? WalletKinds.EntitlementGrant : WalletKinds.AdjustmentIn)
            : WalletKinds.AdjustmentOut;
        _db.CustomerWalletTransactions.Add(new CustomerWalletTransaction
        {
            OrganizationId = customer.OrganizationId,
            CustomerId = customer.Id,
            Kind = kind,
            Amount = Math.Abs(request.AmountDelta),
            Note = request.Note,
            CreatedBy = CurrentUserId(),
        });

        var newBalance = balance + request.AmountDelta;
        _db.LogAudit(customer.OrganizationId, CurrentUserId(), "customer.wallet_adjusted", "customers", customer.Id,
            newValues: new { customer.FullName, request.AmountDelta, NewBalance = newBalance });
        await _db.SaveChangesAsync();

        return ToDto(customer, newBalance, null, await OrgAsync());
    }

    /// <summary>
    /// إصدار بطاقات لمجموعة عملاء دفعةً واحدة.
    ///
    /// <para><b>الفجوة:</b> جهةٌ تُدخل ألف منتسب تحتاج ألف بطاقة. وإصدارها
    /// واحدةً واحدة عملُ يومين، ويُنسى فيها من يُنسى فلا يعرف أحد من بقي
    /// بلا بطاقة إلا حين يقف على الصندوق.</para>
    ///
    /// <para><b>ولا يقبل رقماً سرّياً إطلاقاً</b> — نمط <c>pin</c> مرفوض
    /// هنا: رقمٌ واحد لألف بطاقة يُبطل معنى السرّ، ورقمٌ لكلٍّ يحتاج تسليماً
    /// فردياً فلا يبقى للجملة معنى. والبطاقة بلا رقم تُسلَّم باليد وتُقفَل
    /// بسقفٍ يومي — وهو ما يجعل الإصدار الجماعي ممكناً أصلاً.</para>
    ///
    /// <para>ولا يُعاد الإصدار لمن له بطاقة إلا بطلبٍ صريح: إعادةٌ بالخطأ
    /// تُبطل ألف بطاقة في جيوب أصحابها دفعةً واحدة.</para>
    /// </summary>
    [HttpPost("bulk-issue-cards")]
    [RequirePermission("cards.issue")]
    // ── وحدة «wallet» لا إصدارٌ بعينه ───────────────────────────────────
    //
    // كان الشرط على إصدار «المحفظة بالمحاسبة» وحده، وذاك إصدارٌ
    // **بلا بضاعة**. فجهةٌ لها بضاعة ومنتسبون معاً — محلٌّ عسكري بفروعه
    // الغذائية — تشتري النسخة الكاملة فتستطيع كل شيء إلا إصدار ألف بطاقة
    // دفعةً واحدة. والوحدة تُباع فوق أي إصدار، و«المحفظة بالمحاسبة» تحملها
    // أصلاً (راجع [Editions.ModulesOf]) فلا يتغيّر عندها شيء.
    //
    // وبالسمة لا بفحصٍ في الجسم: هي التي تقرأ الوحدات المُباعة منفردة
    // (راجع [LicenseLimits.EffectiveModules]) — وفحصُ الإصدار وحده كان
    // يجعل بيع الوحدة مستحيلاً مهما كُتب في الترخيص.
    [RequireModule("wallet")]
    public async Task<ActionResult<BulkIssueCardsResult>> BulkIssueCards(BulkIssueCardsRequest request)
    {
        var org = await OrgAsync();
        if (org is null) return BadRequest(new { message = "تعذّر تحديد المنظمة" });

        var mode = request.CardMode ?? org.CardModeDefault;
        if (!CardModeGate.AllowedModes(org).Contains(mode))
            return BadRequest(new { message = "هذا النمط غير مسموح في إعدادات المنظمة" });

        if (mode == CardModes.Pin)
        {
            return BadRequest(new
            {
                message = "الإصدار الجماعي لا يصلح لنمط الرقم السرّي — "
                    + "رقمٌ واحد لألف بطاقة يُبطل السرّ. استعمل نمط «بطاقة فقط».",
            });
        }

        var query = _db.Customers.Where(c => !c.IsDeleted);
        if (request.CustomerIds is { Count: > 0 })
        {
            query = query.Where(c => request.CustomerIds.Contains(c.Id));
        }
        else if (request.CategoryId is { } categoryId)
        {
            query = query.Where(c => c.CategoryId == categoryId);
        }
        else
        {
            // بلا تحديد لأصدرنا بطاقةً لكل عميل في المنظمة — ومنهم من لا
            // يُراد له بطاقة. الاختيار الصريح شرطٌ لا تشدّد.
            return BadRequest(new { message = "حدّد العملاء أو الفئة" });
        }

        var customers = await query.ToListAsync();
        if (customers.Count == 0) return new BulkIssueCardsResult(0, 0, mode, new List<BulkIssuedCardDto>());

        var ids = customers.Select(c => c.Id).ToList();
        var existing = await _db.CustomerCardIndexes
            .Where(c => ids.Contains(c.CustomerId))
            .ToDictionaryAsync(c => c.CustomerId, c => c);

        var cards = new List<BulkIssuedCardDto>();
        var skipped = 0;

        foreach (var customer in customers)
        {
            var hasCard = existing.TryGetValue(customer.Id, out var old);
            if (hasCard && !request.Reissue) { skipped++; continue; }
            if (hasCard) _db.CustomerCardIndexes.Remove(old!);

            var code = CustomerCards.GenerateCardCode();
            _db.CustomerCardIndexes.Add(new CustomerCardIndex
            {
                CardCode = code,
                CustomerId = customer.Id,
                OrganizationId = customer.OrganizationId,
            });

            customer.CardBarcode = code;
            customer.CardMode = mode;
            // نمط «بطاقة فقط» يمحو أي رقم قديم: تركُه محفوظاً يُبقي سرّاً
            // قابلاً للتسريب لا يستعمله أحد.
            customer.PinHash = null;
            customer.PinLockedUntil = null;

            cards.Add(new BulkIssuedCardDto(customer.Id, customer.FullName, code));
        }

        if (cards.Count > 0)
        {
            _db.LogAudit(org.Id, CurrentUserId(), "customers.bulk_cards_issued", "customers", null,
                newValues: new { Issued = cards.Count, Skipped = skipped, Mode = mode, request.Reissue });
            await _db.SaveChangesAsync();
        }

        return new BulkIssueCardsResult(cards.Count, skipped, mode, cards);
    }

    /// <summary>
    /// إصدار بطاقة محفظة للعميل (أو إعادة إصدارها برقم سري جديد) — يولّد رمز
    /// بطاقة من 12 خانة بحروف غير ملتبسة، ويخزّن الرقم السري مُجزَّأً بـ BCrypt.
    /// الرمز يُعرض *مرة واحدة فقط* في استجابة هذا الطلب لتسليمه للعميل؛
    /// الرقم السري لا يُخزَّن ولا يُعرض نصاً أبداً بعدها.
    /// </summary>
    [HttpPost("{id:guid}/issue-card")]
    // إصدار البطاقة ليس تعديل بيانات عميل: البطاقة أداة دفع، ومن يصدرها
    // ويضبط رقمها السري يستطيع إنفاق رصيدها. صلاحية منفصلة عمداً.
    [RequirePermission("cards.issue")]
    public async Task<ActionResult<IssuedCardDto>> IssueCard(Guid id, IssueCardRequest request)
    {
        var customer = await _db.Customers.FirstOrDefaultAsync(c => c.Id == id && !c.IsDeleted);
        if (customer is null) return NotFound();

        var org = await OrgAsync();
        if (org is null) return BadRequest(new { message = "تعذّر تحديد المنظمة" });

        // النمط المطلوب لهذه البطاقة — أو افتراضي المنظمة إن لم يُحدَّد.
        var mode = request.CardMode ?? org.CardModeDefault;
        if (!CardModeGate.AllowedModes(org).Contains(mode))
        {
            return BadRequest(new { message = "هذا النمط غير مسموح في إعدادات المنظمة" });
        }

        // الرقم يُطلَب ويُتحقَّق منه في نمطه وحده. وفي نمط «بطاقة فقط» يُمحى
        // أي رقم قديم: تركُه محفوظاً يُبقي سرّاً قابلاً للتسريب لا يستعمله
        // أحد، والنمط كلّه قائم على أن لا شيء يُحفَظ.
        if (mode == CardModes.Pin)
        {
            var pinError = CustomerCards.ValidatePin(request.Pin ?? "");
            if (pinError is not null) return BadRequest(new { message = pinError });
        }
        else if (!string.IsNullOrEmpty(request.Pin))
        {
            return BadRequest(new { message = "نمط «بطاقة فقط» لا يأخذ رقماً سرّياً" });
        }

        if (request.DailyCap is { } cap)
        {
            if (cap < 0) return BadRequest(new { message = "السقف لا يكون سالباً" });
            if (cap > 0 && cap > org.CardOpenModeDailyCap)
            {
                return BadRequest(new
                {
                    message = $"سقف الزبون لا يتجاوز سقف المنظمة ({org.CardOpenModeDailyCap:0.##})"
                });
            }
            customer.DailyCap = cap;
        }

        // إعادة الإصدار تستبدل الرمز القديم فيبطل مفعوله فوراً.
        var existing = await _db.CustomerCardIndexes.FirstOrDefaultAsync(c => c.CustomerId == customer.Id);
        if (existing is not null) _db.CustomerCardIndexes.Remove(existing);

        var code = CustomerCards.GenerateCardCode();
        _db.CustomerCardIndexes.Add(new CustomerCardIndex
        {
            CardCode = code,
            CustomerId = customer.Id,
            OrganizationId = customer.OrganizationId,
        });

        // نفس الرمز يصبح باركود البطاقة أيضاً — هوية واحدة للبطاقة لا اثنتين:
        // يُطبَع كباركود على البطاقة الورقية، ويُعرض كباركود على شاشة هاتف
        // العميل، ويُكتب يدوياً للدخول للبوابة، ويجده بحث نقطة البيع. لو
        // بقي باركود منفصل عن رمز الدخول لأصبح للبطاقة الواحدة رقمان
        // مختلفان يربكان الكاشير والعميل معاً.
        customer.CardBarcode = code;
        customer.CardMode = mode;
        customer.PinHash = mode == CardModes.Pin
            ? BCrypt.Net.BCrypt.HashPassword(request.Pin!)
            : null;
        customer.PinLockedUntil = null;

        _db.LogAudit(customer.OrganizationId, CurrentUserId(), "customer.card_issued", "customers", customer.Id,
            newValues: new { customer.FullName, Reissued = existing is not null, Mode = mode });
        await _db.SaveChangesAsync();

        return new IssuedCardDto(code);
    }

    /// <summary>
    /// تغيير نمط التحقّق وسقف حساب عميل.
    ///
    /// <para><b>لماذا صلاحية <c>cards.issue</c> لا <c>customers.manage</c>:</b>
    /// من يستطيع تخفيف الحماية على محفظة يستطيع إنفاقها. **والكاشير لا يملك
    /// هذه الصلاحية** — من يغيّر النمط لحظة الصرف تسقط الحماية كلّها بين
    /// يديه، وهي نفس الصلاحية التي يُشترَط وجودها لإصدار البطاقة أصلاً.</para>
    ///
    /// <para><b>وأين رضا صاحب المال:</b> النظام لا يملك قناة تُبلِّغ الزبون،
    /// وبوابة العميل تُصادِق برمز + رقم سرّي — فحسابٌ في نمط «بطاقة فقط» لا
    /// يستطيع الدخول إليها أصلاً ليختار. فالرضا هنا حضوره عند الكاشير مع
    /// مسؤولٍ يملك الصلاحية، وهو ما يُسجَّل في التدقيق باسمه. وإتاحة نقطة
    /// نهاية في البوابة تعمل لبعض الأنماط دون بعض كانت ستوهم بضمانٍ لا
    /// يتحقّق.</para>
    /// </summary>
    [HttpPut("{id:guid}/card-mode")]
    [RequirePermission("cards.issue")]
    public async Task<ActionResult<CustomerDto>> SetCardMode(Guid id, SetCardModeRequest request)
    {
        var customer = await _db.Customers.FirstOrDefaultAsync(c => c.Id == id && !c.IsDeleted);
        if (customer is null) return NotFound();

        var org = await OrgAsync();
        if (org is null) return BadRequest(new { message = "تعذّر تحديد المنظمة" });

        var allowed = CardModeGate.AllowedModes(org);

        // null = عُد إلى افتراضي المنظمة. يختلف عن إرسال نمطٍ صريح يساويه:
        // الأول يتبع المدير إن غيّر افتراضه لاحقاً، والثاني يثبت.
        if (request.CardMode is { } mode)
        {
            if (!allowed.Contains(mode))
            {
                return BadRequest(new { message = "هذا النمط غير مسموح في إعدادات المنظمة" });
            }
            if (mode == CardModes.Pin && customer.PinHash is null)
            {
                // نمطٌ يحتاج رقماً لحسابٍ بلا رقم يعني حساباً لا يُصرَف منه
                // أبداً — رفضٌ صامت وقت البيع بدل خطأ واضح الآن.
                return BadRequest(new { message = "لا يوجد رقم سرّي لهذا الحساب — أصدر البطاقة برقم سرّي أولاً" });
            }
            customer.CardMode = mode;
        }
        else
        {
            customer.CardMode = null;
        }

        if (request.DailyCap is { } cap)
        {
            if (cap < 0) return BadRequest(new { message = "السقف لا يكون سالباً" });

            // الأعلى من سقف المنظمة يُرفض صراحةً لا يُقصّ صامتاً: مسؤولٌ ظنّ
            // أنه رفع سقف زبون وهو لم يرتفع سيكتشف ذلك يوم يُرفَض بيع.
            if (cap > 0 && cap > org.CardOpenModeDailyCap)
            {
                return BadRequest(new
                {
                    message = $"سقف الزبون لا يتجاوز سقف المنظمة ({org.CardOpenModeDailyCap:0.##})"
                });
            }
            customer.DailyCap = cap;
        }

        _db.LogAudit(customer.OrganizationId, CurrentUserId(), "customer.card_mode_changed", "customers", customer.Id,
            newValues: new { customer.FullName, customer.CardMode, customer.DailyCap });
        await _db.SaveChangesAsync();

        return ToDto(customer, await BalanceOf(customer.Id), await SponsorNameOf(customer), org);
    }

    // حذف فعلي غير مسموح به (راجع ARCHITECTURE.md §3.2) — فواتير قديمة قد
    // تشير لهذا العميل، فقط Soft Delete.
    [HttpDelete("{id:guid}")]
    [RequirePermission("customers.delete")]
    public async Task<IActionResult> SoftDelete(Guid id)
    {
        var customer = await _db.Customers.FindAsync(id);
        if (customer is null) return NotFound();

        customer.IsDeleted = true;
        _db.LogAudit(customer.OrganizationId, CurrentUserId(), "customer.deleted", "customers", customer.Id,
            oldValues: new { customer.FullName });
        await _db.SaveChangesAsync();
        return NoContent();
    }

    /// <summary>
    /// يُرجع عميلاً محذوفاً.
    ///
    /// <para><b>العطب الذي يصلحه:</b> نافذة الحذف كانت تَعِد صراحةً: «يمكن
    /// استرجاعه لاحقاً من سجل التدقيق» — **ولا استرجاع في النظام كلّه**: لا
    /// نقطة ولا زرّ. فمن حذف عميلاً بالخطأ وثِق بالوعد ثم بحث عن الزرّ فلم
    /// يجده، وبقي رصيدُ العميل وحركاته في القاعدة لا يصل إليها أحد. ووعدٌ
    /// لا يُوفى في لحظة حذفٍ أسوأ من ألّا يُوعَد أصلاً: من قرأه ضغط «حذف»
    /// وهو مطمئنّ.</para>
    ///
    /// <para><b>وبنفس صلاحية الحذف</b> — من يملك أن يُخفي يملك أن يُظهر،
    /// وصلاحيةٌ ثالثة لا تضيف حمايةً بل تُعقّد المصفوفة.</para>
    /// </summary>
    [HttpPost("{id:guid}/restore")]
    [RequirePermission("customers.delete")]
    public async Task<IActionResult> Restore(Guid id)
    {
        var customer = await _db.Customers.FindAsync(id);
        if (customer is null) return NotFound();

        // ليس خطأً بل حالةٌ تُقال: اثنان يعملان على نفس السجلّ، أو ضغطةٌ
        // ثانية على الزرّ نفسه.
        if (!customer.IsDeleted)
            return BadRequest(new { message = "العميل غير محذوف أصلاً" });

        // الهاتف مفتاح المطابقة في الاستيراد وفي البحث. وقد يكون قد أُعيد
        // استعماله لعميلٍ جديد بعد الحذف، فإرجاعُ القديم بنفس الرقم يُنتج
        // عميلين بهاتفٍ واحد — والاستيراد بعدها يُحدّث أيّهما صادفه أوّلاً.
        if (!string.IsNullOrWhiteSpace(customer.Phone))
        {
            var taken = await _db.Customers.AnyAsync(c =>
                !c.IsDeleted && c.Id != customer.Id && c.Phone == customer.Phone);
            if (taken)
                return BadRequest(new
                {
                    message = $"الهاتف {customer.Phone} صار لعميل آخر — غيّر رقمه ثم أعد الاسترجاع",
                });
        }

        customer.IsDeleted = false;
        _db.LogAudit(customer.OrganizationId, CurrentUserId(), "customer.restored", "customers", customer.Id,
            newValues: new { customer.FullName });
        await _db.SaveChangesAsync();
        return NoContent();
    }

    /// اسم الجهة الممولة — عمود واحد لا الكيان كاملاً، ولا استعلام أصلاً لمن
    /// لا جهة له. غيابه كان يجعل القراءة المفردة تُرجع اسماً فارغاً بينما
    /// تُرجعه القائمة، فيختفي اسم الجهة عند فتح نموذج العميل.
    private async Task<string?> SponsorNameOf(Customer c) =>
        c.SponsorId is null
            ? null
            : await _db.Sponsors.Where(s => s.Id == c.SponsorId).Select(s => s.Name).FirstOrDefaultAsync();

    /// <summary>
    /// يميّز خطأ تكرار المفتاح (2601/2627) عن بقية أخطاء الكتابة.
    ///
    /// بدون هذا التمييز كان أي فشل كتابة — قيد CHECK، مفتاح خارجي مفقود،
    /// عمود مطلوب — يُبلَّغ عنه بـ "باركود البطاقة مستخدَم بالفعل"، فيبحث
    /// المستخدم (والمطوّر) في المكان الخطأ تماماً. حدث ذلك فعلاً: قيد UNIQUE
    /// عادي على card_barcode كان يمنع وجود عميلَين بلا بطاقة (SQL Server
    /// يعتبر كل NULL متساوية)، وظهر الخطأ كأنه تكرار باركود.
    /// </summary>
    /// <summary>
    /// تسجيل تذكير أُرسل للعميل بدَينه.
    ///
    /// <para>يُسجَّل بعد الاتصال أو الرسالة لا قبلها — راجع [DebtReminder]:
    /// صفٌّ يقول «أُرسل» عن شيء لم يُرسَل يجعل سجلّ المطالبة عديم القيمة،
    /// ويوقف المطالبة الحقيقية لأن النظام يظنّها تمّت.</para>
    /// </summary>
    [HttpPost("{id:guid}/debt-reminders")]
    [RequirePermission("customers.manage")]
    public async Task<ActionResult<DebtReminder>> RecordDebtReminder(Guid id, RecordDebtReminderRequest request)
    {
        var customer = await _db.Customers.FirstOrDefaultAsync(c => c.Id == id && !c.IsDeleted);
        if (customer is null) return NotFound();

        var aging = (await Data.DebtAging.ComputeAsync(_db, DateTime.UtcNow))
            .FirstOrDefault(a => a.CustomerId == id);
        if (aging is null)
        {
            return BadRequest(new { message = "لا دَين على هذا العميل" });
        }

        // المرحلة من الحساب لا من الطلب: تركُها للعميل يسمح بتسجيل «المرحلة
        // الثالثة» على دَين حلّ أمس، فينهار معنى السلّم كلّه.
        var reminder = new DebtReminder
        {
            OrganizationId = customer.OrganizationId,
            CustomerId = customer.Id,
            Stage = Math.Max(1, aging.Stage),
            DueOn = aging.OldestDueDate ?? DateTime.UtcNow.Date,
            AmountAtReminder = aging.TotalOutstanding,
            SentBy = CurrentUserId(),
            Note = string.IsNullOrWhiteSpace(request.Note) ? null : request.Note.Trim(),
        };

        _db.DebtReminders.Add(reminder);
        _db.LogAudit(customer.OrganizationId, CurrentUserId(), "customer.debt_reminded", "customers", customer.Id,
            newValues: new { reminder.Stage, reminder.AmountAtReminder, aging.DaysOverdue });
        await _db.SaveChangesAsync();
        return reminder;
    }

    /// <summary>سجلّ تذكيرات هذا العميل — الأحدث أولاً.</summary>
    [HttpGet("{id:guid}/debt-reminders")]
    public async Task<ActionResult<List<DebtReminder>>> DebtReminders(Guid id) =>
        await _db.DebtReminders
            .Where(r => r.CustomerId == id)
            .OrderByDescending(r => r.SentAt)
            .ToListAsync();

    private static bool IsDuplicateKey(DbUpdateException ex) =>
        ex.InnerException is SqlException sql && (sql.Number == 2601 || sql.Number == 2627);

    private async Task<decimal> BalanceOf(Guid customerId) =>
        await WalletBalances.ComputeAsync(_db, customerId);

    /// <summary>
    /// بداية فترة الاستحقاق الجارية.
    ///
    /// الفترة تُعرَّف بتاريخ نهايتها وحده (لا بتاريخي بداية ونهاية) لأن ذلك ما
    /// يفهمه المستخدم فعلاً: "صالح حتى". فالبداية تُشتق شهراً قبل النهاية —
    /// والسقف بذلك سقف شهر واحد لا سقف مفتوح منذ إنشاء الحساب.
    /// </summary>
    private static DateTime PeriodStartOf(Customer c) =>
        c.EntitlementExpiresOn is null
            ? DateTime.UtcNow.AddMonths(-1)
            : c.EntitlementExpiresOn.Value.ToDateTime(TimeOnly.MinValue).AddMonths(-1);

    /// <param name="org">
    /// منظمة العميل — تلزم لحساب النمط والسقف الفعّالين. حين تكون null
    /// يُعرَض اختيار العميل الخام: لا نخترع نمطاً فعّالاً من فراغ.
    /// </param>
    private static CustomerDto ToDto(Customer c, decimal balance, string? sponsorName = null,
        Organization? org = null, string? categoryName = null) =>
        new(c.Id, c.OrganizationId, c.BranchId, c.FullName, c.Phone, c.Email, c.Notes,
            c.CardBarcode, balance, c.CreditLimit, c.CreditDays, c.LoyaltyPoints, c.CreatedAt,
            c.AccountModel, c.SponsorId, sponsorName, c.EntitlementCeiling, c.EntitlementExpiresOn,
            c.CategoryId, categoryName, c.EntitlementOverride, c.PhotoUrl,
            c.CardMode,
            org is null ? (c.CardMode ?? CardModes.Pin) : CardModeGate.EffectiveMode(org, c),
            c.DailyCap,
            org is null ? c.DailyCap : CardModeGate.EffectiveCap(org, c),
            c.PinHash is not null);

    private Guid? CurrentUserId()
    {
        var raw = User.FindFirstValue(JwtRegisteredClaimNames.Sub) ?? User.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(raw, out var id) ? id : null;
    }
}
