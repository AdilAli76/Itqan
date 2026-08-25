using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Authorization;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Controllers;

/// <param name="Pin">
/// اختياريّ: نمط «البطاقة فقط» لا رقم فيه، وإلزامه هناك يُنشئ سرّاً لا
/// يستعمله أحد ويبقى قابلاً للتسريب.
/// </param>
/// <param name="CardMode">راجع [CardModes]. null = افتراضي المنظمة.</param>
public record IssueCardForCustomerRequest(
    Guid CustomerId, string? Pin, DateOnly? ExpiryDate, string? HolderName,
    string? CardMode = null, decimal? DailyCap = null);
public record BlockCardRequest(string? Reason);
public record ResetCardPinRequest(string Pin);

public record WalletCardDto(
    string CardCode, Guid CustomerId, string CustomerName, string? CustomerPhone,
    string State, bool IsUsable, decimal Balance,
    DateTime IssuedAt, DateOnly? ExpiryDate, string? BlockedReason, string? IssuedByName,
    string? HolderName,
    /// النمط الفعّال لهذه البطاقة وسقفه — ما سيحدث فعلاً عند الصرف.
    string CardMode, decimal DailyCap);

/// صفحة بطاقات محفظة.
public record WalletCardPageDto(List<WalletCardDto> Items, int TotalCount, int Page, int PageSize);

/// <summary>
/// إدارة بطاقات المحفظة — الشاشة التي يعمل عليها المدير: إصدار، حظر، رفع
/// حظر، إعادة تعيين رقم سري، وإعادة إصدار برمز جديد. حالة البطاقة تُفرَض
/// فعلياً عند دخول العميل للبوابة (راجع CustomerPortalController).
/// </summary>
[ApiController]
[Route("api/wallet-cards")]
[Authorize]

public class WalletCardsController : ControllerBase
{
    private readonly AppDbContext _db;
    public WalletCardsController(AppDbContext db) => _db = db;

    /// <summary>
    /// بطاقات المحفظة مقسَّمة صفحات. عدد البطاقات يساوي عدد العملاء تقريباً،
    /// فهو ينمو بلا سقف مثلهم.
    ///
    /// الفلترة بالحالة والبحث كانتا تُطبَّقان في الذاكرة بعد جلب كل البطاقات؛
    /// نُقلتا إلى الاستعلام لأن الترقيم فوق فلترة لاحقة يعني البحث داخل
    /// الصفحة الحالية وحدها — بطاقة موجودة لا يجدها المستخدم لأنها في صفحة
    /// أخرى.
    /// </summary>
    [HttpGet]
    public async Task<ActionResult<WalletCardPageDto>> GetAll(
        [FromQuery] string? state,
        [FromQuery] string? search,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 200);

        var today = DateOnly.FromDateTime(DateTime.UtcNow);

        // فلترة المنظمة صراحةً قبل العدّ والتقطيع.
        //
        // customer_card_index من الجداول القليلة التي لا تحملها سياسة عزل
        // (راجع DATABASE_SCHEMA_SQLSERVER.sql)، فالفلترة هنا مسؤولية
        // الـController لا قاعدة البيانات. وكان الترشيح يقع بعد التقطيع —
        // عبر مطابقة العملاء المرئيين أدناه — فيُنتج خطأين معاً: عدّ كلي
        // يشمل بطاقات منظمات أخرى، وصفحة تعود ناقصة لأن جزءاً من الخمسين
        // المقطوعة يسقط في الترشيح اللاحق.
        var orgId = Guid.Parse(User.FindFirstValue("organization_id")!);
        var cardQuery = _db.CustomerCardIndexes.Where(c => c.OrganizationId == orgId);
        if (!string.IsNullOrWhiteSpace(state)) cardQuery = cardQuery.Where(c => c.State == state);

        // البحث يمسّ اسم العميل وهاتفه أيضاً، لا رمز البطاقة وحده، فيحتاج
        // ربطاً بجدول العملاء قبل العدّ والتقطيع.
        if (!string.IsNullOrWhiteSpace(search))
        {
            cardQuery = cardQuery.Where(c =>
                c.CardCode.Contains(search) ||
                _db.Customers.Any(cu => cu.Id == c.CustomerId &&
                    (cu.FullName.Contains(search) ||
                     (cu.Phone != null && cu.Phone.Contains(search)))));
        }

        var totalCount = await cardQuery.CountAsync();
        var cards = await cardQuery.OrderByDescending(c => c.IssuedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync();

        var customerIds = cards.Select(c => c.CustomerId).ToList();
        var customers = await _db.Customers
            .Where(c => customerIds.Contains(c.Id))
            .ToDictionaryAsync(c => c.Id, c => c);

        var issuerIds = cards.Where(c => c.IssuedBy.HasValue).Select(c => c.IssuedBy!.Value).Distinct().ToList();
        var issuers = await _db.AppUsers
            .Where(u => issuerIds.Contains(u.Id))
            .ToDictionaryAsync(u => u.Id, u => u.FullName);

        var balances = await _db.CustomerWalletTransactions
            .Where(t => customerIds.Contains(t.CustomerId))
            .GroupBy(t => t.CustomerId)
            .Select(g => new
            {
                CustomerId = g.Key,
                In = g.Where(t => t.Kind == WalletKinds.TopUp || t.Kind == WalletKinds.InvoiceRefund || t.Kind == WalletKinds.AdjustmentIn).Sum(t => (decimal?)t.Amount) ?? 0,
                Out = g.Where(t => t.Kind == WalletKinds.Spend || t.Kind == WalletKinds.AdjustmentOut).Sum(t => (decimal?)t.Amount) ?? 0,
            })
            .ToDictionaryAsync(x => x.CustomerId, x => x.In - x.Out);

        var listOrg = await _db.Organizations.FirstOrDefaultAsync();

        var items = cards
            .Where(c => customers.ContainsKey(c.CustomerId))
            .Select(c =>
            {
                var customer = customers[c.CustomerId];
                return new WalletCardDto(
                    c.CardCode, c.CustomerId, customer.FullName, customer.Phone,
                    c.State, c.IsUsable(today), balances.GetValueOrDefault(c.CustomerId),
                    c.IssuedAt, c.ExpiryDate, c.BlockedReason,
                    c.IssuedBy.HasValue ? issuers.GetValueOrDefault(c.IssuedBy.Value) : null,
                    c.HolderName,
                    listOrg is null ? (customer.CardMode ?? CardModes.Pin) : CardModeGate.EffectiveMode(listOrg, customer),
                    listOrg is null ? customer.DailyCap : CardModeGate.EffectiveCap(listOrg, customer));
            })
            .ToList();

        return new WalletCardPageDto(items, totalCount, page, pageSize);
    }

    /// <summary>
    /// إصدار أو إعادة إصدار — إعادة الإصدار تُبطِل الرمز القديم فوراً
    /// (يُحذف من الفهرس) فلا تبقى بطاقتان صالحتان لنفس العميل.
    /// </summary>
    [HttpPost("issue")]
    [RequirePermission("cards.issue")]
    public async Task<ActionResult<WalletCardDto>> Issue(IssueCardForCustomerRequest request)
    {
        var customer = await _db.Customers.FirstOrDefaultAsync(c => c.Id == request.CustomerId && !c.IsDeleted);
        if (customer is null) return NotFound(new { message = "العميل غير موجود" });

        var org = await _db.Organizations.FirstOrDefaultAsync();
        if (org is null) return BadRequest(new { message = "تعذّر تحديد المنظمة" });

        var mode = request.CardMode ?? org.CardModeDefault;
        if (!CardModeGate.AllowedModes(org).Contains(mode))
        {
            return BadRequest(new { message = "هذا النمط غير مسموح في إعدادات المنظمة" });
        }

        // الرقم يُطلَب في نمطه وحده.
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

        var existing = await _db.CustomerCardIndexes.FirstOrDefaultAsync(c => c.CustomerId == customer.Id);
        if (existing is not null) _db.CustomerCardIndexes.Remove(existing);

        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        if (request.ExpiryDate is not null && request.ExpiryDate <= today)
        {
            return BadRequest(new { message = "تاريخ الانتهاء يجب أن يكون بعد اليوم" });
        }

        var code = CustomerCards.GenerateCardCode();
        var card = new CustomerCardIndex
        {
            CardCode = code,
            CustomerId = customer.Id,
            OrganizationId = customer.OrganizationId,
            State = CardStates.Active,
            ExpiryDate = request.ExpiryDate,
            HolderName = string.IsNullOrWhiteSpace(request.HolderName) ? null : request.HolderName.Trim(),
            IssuedBy = CurrentUserId(),
        };
        _db.CustomerCardIndexes.Add(card);

        // نفس الرمز هو باركود البطاقة — هوية واحدة تُمسح وتُكتب وتُطبع.
        customer.CardBarcode = code;
        customer.CardMode = mode;
        // في غير نمط الرقم يُمحى أي رقم قديم: النمط قائم على أن لا سرّ
        // يُحفَظ أصلاً، وإبقاؤه يترك ما يُسرَّب بلا فائدة.
        customer.PinHash = mode == CardModes.Pin
            ? BCrypt.Net.BCrypt.HashPassword(request.Pin!)
            : null;
        customer.PinLockedUntil = null;

        _db.LogAudit(customer.OrganizationId, CurrentUserId(), "card.issued", "customer_card_index", customer.Id,
            newValues: new { customer.FullName, Reissued = existing is not null, card.ExpiryDate, card.HolderName, Mode = mode });
        await _db.SaveChangesAsync();

        return new WalletCardDto(code, customer.Id, customer.FullName, customer.Phone,
            card.State, true, await WalletBalances.ComputeAsync(_db, customer.Id),
            card.IssuedAt, card.ExpiryDate, null, null, card.HolderName,
            CardModeGate.EffectiveMode(org, customer), CardModeGate.EffectiveCap(org, customer));
    }

    [HttpPost("{cardCode}/block")]
    [RequirePermission("cards.issue")]
    public async Task<IActionResult> Block(string cardCode, BlockCardRequest request)
    {
        var card = await _db.CustomerCardIndexes.FirstOrDefaultAsync(c => c.CardCode == cardCode);
        if (card is null) return NotFound();

        card.State = CardStates.Blocked;
        card.BlockedReason = request.Reason;
        _db.LogAudit(card.OrganizationId, CurrentUserId(), "card.blocked", "customer_card_index", card.CustomerId,
            newValues: new { cardCode, request.Reason });
        await _db.SaveChangesAsync();
        return NoContent();
    }

    [HttpPost("{cardCode}/unblock")]
    [RequirePermission("cards.issue")]
    public async Task<IActionResult> Unblock(string cardCode)
    {
        var card = await _db.CustomerCardIndexes.FirstOrDefaultAsync(c => c.CardCode == cardCode);
        if (card is null) return NotFound();

        card.State = CardStates.Active;
        card.BlockedReason = null;
        _db.LogAudit(card.OrganizationId, CurrentUserId(), "card.unblocked", "customer_card_index", card.CustomerId,
            newValues: new { cardCode });
        await _db.SaveChangesAsync();
        return NoContent();
    }

    /// <summary>
    /// إعادة تعيين الرقم السري دون تغيير رمز البطاقة — للعميل الذي نسي رقمه
    /// وبطاقته الورقية ما زالت بيده (تغيير الرمز هنا كان سيُبطل بطاقة سليمة).
    /// يرفع القفل أيضاً لأن سببه غالباً هو النسيان نفسه.
    /// </summary>
    [HttpPost("{cardCode}/reset-pin")]
    [RequirePermission("cards.issue")]
    public async Task<IActionResult> ResetPin(string cardCode, ResetCardPinRequest request)
    {
        var card = await _db.CustomerCardIndexes.FirstOrDefaultAsync(c => c.CardCode == cardCode);
        if (card is null) return NotFound();

        var pinError = CustomerCards.ValidatePin(request.Pin);
        if (pinError is not null) return BadRequest(new { message = pinError });

        var customer = await _db.Customers.FirstOrDefaultAsync(c => c.Id == card.CustomerId);
        if (customer is null) return NotFound();

        customer.PinHash = BCrypt.Net.BCrypt.HashPassword(request.Pin);
        customer.PinLockedUntil = null;
        // ضبط رقم لحسابٍ في نمط «بطاقة فقط» يعني اختيار النمط الأشدّ — وهذا
        // تشديد لا تخفيف، فيقع بلا شرط إضافي. ولولا هذا السطر لبقي الرقم
        // مضبوطاً ولا يُطلَب أبداً.
        customer.CardMode = CardModes.Pin;
        _db.LogAudit(card.OrganizationId, CurrentUserId(), "card.pin_reset", "customer_card_index", card.CustomerId,
            newValues: new { cardCode });
        await _db.SaveChangesAsync();
        return NoContent();
    }

    private Guid? CurrentUserId()
    {
        var raw = User.FindFirstValue(JwtRegisteredClaimNames.Sub) ?? User.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(raw, out var id) ? id : null;
    }
}
