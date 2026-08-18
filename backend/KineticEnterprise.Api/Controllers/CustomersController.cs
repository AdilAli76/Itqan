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

public record WalletAdjustmentRequest(decimal AmountDelta, string? Note);
public record IssueCardRequest(string Pin);
public record IssuedCardDto(string CardCode);

/// صفحة عملاء: العناصر مع العدد الكلي المطابق للفلتر — الواجهة تحتاج
/// العدد الكلي لا عدد الصفحة، وإلا تعذّر عليها رسم "عرض 1–50 من 1,240"
/// ولا معرفة ما إذا كانت هناك صفحة تالية أصلاً.
public record CustomerPageDto(List<CustomerDto> Items, int TotalCount, int Page, int PageSize);

public record CustomerDto(
    Guid Id, Guid OrganizationId, Guid? BranchId, string FullName, string? Phone,
    string? Email, string? Notes, string? CardBarcode,
    decimal WalletBalance, decimal CreditLimit, int LoyaltyPoints, DateTime CreatedAt,
    string AccountModel, Guid? SponsorId, string? SponsorName,
    decimal EntitlementCeiling, DateOnly? EntitlementExpiresOn);

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

        var items = customers
            .Select(c => ToDto(c, balances.GetValueOrDefault(c.Id),
                c.SponsorId is null ? null : sponsorNames.GetValueOrDefault(c.SponsorId.Value)))
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

        return ToDto(customer, await BalanceOf(customer.Id), await SponsorNameOf(customer));
    }

    [HttpGet("{id:guid}")]
    public async Task<ActionResult<CustomerDto>> GetById(Guid id)
    {
        var customer = await _db.Customers.FindAsync(id);
        if (customer is null) return NotFound();
        return ToDto(customer, await BalanceOf(id), await SponsorNameOf(customer));
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
    public async Task<ActionResult<CustomerDto>> Create(Customer customer)
    {
        customer.OrganizationId = Guid.Parse(User.FindFirstValue("organization_id")!);
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
        return CreatedAtAction(nameof(GetById), new { id = customer.Id }, ToDto(customer, 0));
    }

    [HttpPut("{id:guid}")]
    [RequirePermission("customers.manage")]
    public async Task<IActionResult> Update(Guid id, Customer update)
    {
        var customer = await _db.Customers.FindAsync(id);
        if (customer is null) return NotFound();

        customer.FullName = update.FullName;
        customer.Phone = update.Phone;
        customer.Email = update.Email;
        customer.Notes = update.Notes;
        customer.CardBarcode = update.CardBarcode;
        customer.BranchId = update.BranchId;
        customer.CreditLimit = update.CreditLimit;

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

        return ToDto(customer, newBalance);
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

        var pinError = CustomerCards.ValidatePin(request.Pin);
        if (pinError is not null) return BadRequest(new { message = pinError });

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
        customer.PinHash = BCrypt.Net.BCrypt.HashPassword(request.Pin);
        customer.PinLockedUntil = null;

        _db.LogAudit(customer.OrganizationId, CurrentUserId(), "customer.card_issued", "customers", customer.Id,
            newValues: new { customer.FullName, Reissued = existing is not null });
        await _db.SaveChangesAsync();

        return new IssuedCardDto(code);
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

    private static CustomerDto ToDto(Customer c, decimal balance, string? sponsorName = null) =>
        new(c.Id, c.OrganizationId, c.BranchId, c.FullName, c.Phone, c.Email, c.Notes,
            c.CardBarcode, balance, c.CreditLimit, c.LoyaltyPoints, c.CreatedAt,
            c.AccountModel, c.SponsorId, sponsorName, c.EntitlementCeiling, c.EntitlementExpiresOn);

    private Guid? CurrentUserId()
    {
        var raw = User.FindFirstValue(JwtRegisteredClaimNames.Sub) ?? User.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(raw, out var id) ? id : null;
    }
}
