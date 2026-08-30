using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Controllers;

public record CustomerCategoryDto(
    Guid Id, string Name, decimal PeriodAmount, bool UnspentExpires, bool IsActive,
    /// كم عميلاً فيها — الإدارة ترفع المرتب وهي ترى على كم شخصاً يقع.
    int CustomerCount,
    /// مجموع ما سيُصرف عليها الدورة القادمة، بعد حساب التعديلات الفردية.
    decimal PeriodTotal);

/// <summary>دورة الصرف — فارغةٌ تعني الشهر الجاري بتوقيت المنظمة.</summary>
public record DisburseRequest(DateTime? PeriodStart, DateTime? PeriodEnd, Guid? CategoryId);

public record SaveCustomerCategoryRequest(
    string Name, decimal PeriodAmount, bool UnspentExpires, bool IsActive = true);

/// <summary>
/// فئات العملاء ومرتَّباتها الدورية.
///
/// <para><b>الفجوة:</b> مبلغ الاستحقاق كان رقماً على كل عميل على حدة. وجهةٌ
/// تصرف على ألف منتسب في ثلاث فئات كانت ترفع مرتب الفئة بتعديل ألف صفّ
/// يدوياً.</para>
///
/// <para>مقيَّدة بوحدة <c>customers</c> — وهي في كل الإصدارات. والفئات
/// تنفع غير المحفظة أيضاً: متجرٌ يصنّف عملاءه لا يضرّه وجودها، ومن لا
/// يستعملها لا يراها لأن شاشتها في قائمة المحفظة.</para>
/// </summary>
[ApiController]
[Route("api/customer-categories")]
[Authorize]
public class CustomerCategoriesController : ControllerBase
{
    private readonly AppDbContext _db;
    public CustomerCategoriesController(AppDbContext db) => _db = db;

    [HttpGet]
    public async Task<ActionResult<List<CustomerCategoryDto>>> GetAll()
    {
        var categories = await _db.CustomerCategories.OrderBy(c => c.Name).ToListAsync();
        if (categories.Count == 0) return new List<CustomerCategoryDto>();

        // العملاء مرّةً واحدة لا استعلاماً لكل فئة: ثلاث فئات تعني ثلاثة
        // استعلامات، وثلاثون تعني ثلاثين.
        var members = await _db.Customers
            .Where(c => !c.IsDeleted && c.CategoryId != null)
            .Select(c => new { CategoryId = c.CategoryId!.Value, c.EntitlementOverride })
            .ToListAsync();

        return categories.Select(category =>
        {
            var mine = members.Where(m => m.CategoryId == category.Id).ToList();
            return new CustomerCategoryDto(
                category.Id, category.Name, category.PeriodAmount,
                category.UnspentExpires, category.IsActive,
                mine.Count,
                // المجموع بالتعديلات الفردية لا بالضرب المجرّد: الإدارة
                // تريد ما سيخرج فعلاً، لا ما كان سيخرج لو تساوى الجميع.
                mine.Sum(m => m.EntitlementOverride ?? category.PeriodAmount));
        }).ToList();
    }

    [HttpPost]
    [Authorize(Roles = "super_admin,branch_manager")]
    public async Task<ActionResult<CustomerCategoryDto>> Create(SaveCustomerCategoryRequest request)
    {
        if (await Validate(request) is { } bad) return bad;

        var orgId = Guid.Parse(User.FindFirstValue("organization_id")!);
        var category = new CustomerCategory
        {
            OrganizationId = orgId,
            Name = request.Name.Trim(),
            PeriodAmount = request.PeriodAmount,
            UnspentExpires = request.UnspentExpires,
            IsActive = request.IsActive,
        };

        _db.CustomerCategories.Add(category);
        _db.LogAudit(orgId, CurrentUserId(), "customer_category.created", "customer_categories",
            category.Id, newValues: new { category.Name, category.PeriodAmount, category.UnspentExpires });
        await _db.SaveChangesAsync();

        return new CustomerCategoryDto(
            category.Id, category.Name, category.PeriodAmount,
            category.UnspentExpires, category.IsActive, 0, 0);
    }

    /// <summary>
    /// تعديل الفئة — ومنه رفع المرتب لكل من فيها بصفٍّ واحد.
    ///
    /// <para>ولا يمسّ ما صُرف: المرتَّبات المُودعة حركاتٌ في دفتر المحفظة، ورفعُ
    /// المبلغ يسري على الصرف **القادم** وحده. تعديلُ الماضي كان سيجعل
    /// كشف حساب المنتسب لا يطابق ما قبضه.</para>
    /// </summary>
    [HttpPut("{id:guid}")]
    [Authorize(Roles = "super_admin,branch_manager")]
    public async Task<IActionResult> Update(Guid id, SaveCustomerCategoryRequest request)
    {
        var category = await _db.CustomerCategories.FirstOrDefaultAsync(c => c.Id == id);
        if (category is null) return NotFound();
        if (await Validate(request, id) is { } bad) return bad;

        var before = new { category.Name, category.PeriodAmount, category.UnspentExpires };

        category.Name = request.Name.Trim();
        category.PeriodAmount = request.PeriodAmount;
        category.UnspentExpires = request.UnspentExpires;
        category.IsActive = request.IsActive;

        _db.LogAudit(category.OrganizationId, CurrentUserId(), "customer_category.updated",
            "customer_categories", id,
            oldValues: before,
            newValues: new { category.Name, category.PeriodAmount, category.UnspentExpires });
        await _db.SaveChangesAsync();
        return NoContent();
    }

    /// <summary>
    /// إيقاف فئة — لا حذفها.
    ///
    /// <para>عملاؤها يشيرون إليها، وحذفُها يتركهم بلا مرجع ويُفقد تفسير ما
    /// صُرف لهم سابقاً. والموقوفة لا تُصرَف ولا تُختار، ويبقى تاريخها.</para>
    /// </summary>
    [HttpDelete("{id:guid}")]
    [Authorize(Roles = "super_admin")]
    public async Task<IActionResult> Deactivate(Guid id)
    {
        var category = await _db.CustomerCategories.FirstOrDefaultAsync(c => c.Id == id);
        if (category is null) return NotFound();

        category.IsActive = false;
        _db.LogAudit(category.OrganizationId, CurrentUserId(), "customer_category.deactivated",
            "customer_categories", id, oldValues: new { category.Name });
        await _db.SaveChangesAsync();
        return NoContent();
    }

    /// <summary>
    /// صرف مرتَّب الدورة — يدوياً بضغطة، أو بالخدمة المجدولة لاحقاً.
    ///
    /// <para>كلاهما يستدعي <see cref="EntitlementDisburser"/> نفسه: مساران
    /// للصرف يفترقان أوّل مرّة يُعدَّل أحدهما، فيصرف أحدهما بمبلغ والآخر
    /// بآخر — والفرق لا يُكتشف إلا حين يشتكي منتسب.</para>
    ///
    /// <para>ومقصورٌ على مدير المنظمة: هذا مالٌ يخرج.</para>
    /// </summary>
    [HttpPost("disburse")]
    [Authorize(Roles = "super_admin")]
    public async Task<ActionResult<DisburseResult>> Disburse(DisburseRequest request)
    {
        var org = await _db.Organizations.FirstOrDefaultAsync();
        if (org is null) return BadRequest(new { message = "تعذّر تحديد المنظمة" });

        // الدورة بتوقيت المنظمة لا بغرينتش — راجع [OrgClock]. جهةٌ تصرف
        // أوّل الشهر عند منتصف الليل كانت تُسجّل الصرف في الشهر السابق.
        var today = OrgClock.Today(org);
        var periodStart = request.PeriodStart?.Date ?? new DateTime(today.Year, today.Month, 1);
        var periodEnd = request.PeriodEnd?.Date
            ?? periodStart.AddMonths(1).AddDays(-1);

        if (periodEnd < periodStart)
            return BadRequest(new { message = "نهاية الدورة قبل بدايتها" });

        var result = await EntitlementDisburser.DisburseAsync(
            _db, org.Id,
            DateOnly.FromDateTime(periodStart),
            DateOnly.FromDateTime(periodEnd),
            CurrentUserId(),
            request.CategoryId);

        return result;
    }

    /// <summary>
    /// معاينة الصرف قبل تنفيذه — كم شخصاً وكم مبلغاً.
    ///
    /// <para>مالٌ يخرج على ألف بطاقة لا يُضغَط زرُّه على عمياء. والمعاينة
    /// تحسب بنفس قواعد الصرف: التعديل الفردي، والصفر الموقوف، ومن قُبض له
    /// في الدورة أصلاً.</para>
    /// </summary>
    [HttpGet("disburse/preview")]
    [Authorize(Roles = "super_admin,branch_manager")]
    public async Task<ActionResult<object>> PreviewDisburse([FromQuery] Guid? categoryId)
    {
        var org = await _db.Organizations.FirstOrDefaultAsync();
        if (org is null) return BadRequest(new { message = "تعذّر تحديد المنظمة" });

        var today = OrgClock.Today(org);
        var periodStart = new DateTime(today.Year, today.Month, 1);

        var categories = await _db.CustomerCategories
            .Where(c => c.IsActive && (categoryId == null || c.Id == categoryId))
            .ToDictionaryAsync(c => c.Id, c => c);
        var ids = categories.Keys.ToList();

        var members = await _db.Customers
            .Where(c => !c.IsDeleted
                     && c.AccountModel == AccountModels.Entitlement
                     && c.CategoryId != null
                     && ids.Contains(c.CategoryId.Value))
            .Select(c => new { c.Id, c.CategoryId, c.EntitlementOverride })
            .ToListAsync();

        var memberIds = members.Select(m => m.Id).ToList();
        var alreadyPaid = (await _db.CustomerWalletTransactions
            .Where(t => memberIds.Contains(t.CustomerId)
                     && t.Kind == WalletKinds.EntitlementGrant
                     && t.CreatedAt >= periodStart)
            .Select(t => t.CustomerId).Distinct().ToListAsync()).ToHashSet();

        var due = members.Where(m => !alreadyPaid.Contains(m.Id)).ToList();
        var amounts = due.Select(m => m.EntitlementOverride ?? categories[m.CategoryId!.Value].PeriodAmount);

        return Ok(new
        {
            period = periodStart.ToString("yyyy-MM"),
            eligible = members.Count,
            alreadyPaid = alreadyPaid.Count,
            // الموقوفون صراحةً (تعديل فردي بصفر) يُعدّون على حدة: رقمٌ
            // يُسأل عنه، وخلطُه بالمدفوع يُخفيه.
            suspended = due.Count(m => (m.EntitlementOverride ?? categories[m.CategoryId!.Value].PeriodAmount) <= 0),
            toPay = amounts.Count(a => a > 0),
            totalAmount = amounts.Where(a => a > 0).Sum(),
        });
    }

    private async Task<ActionResult?> Validate(SaveCustomerCategoryRequest request, Guid? excludeId = null)
    {
        var name = (request.Name ?? "").Trim();
        if (name.Length == 0) return BadRequest(new { message = "اسم الفئة إلزامي" });
        if (request.PeriodAmount < 0)
            return BadRequest(new { message = "المرتَّب لا يكون سالباً" });

        var clash = await _db.CustomerCategories
            .AnyAsync(c => c.Name == name && (excludeId == null || c.Id != excludeId));
        if (clash) return Conflict(new { message = $"فئة باسم «{name}» موجودة" });

        return null;
    }

    private Guid? CurrentUserId()
    {
        var raw = User.FindFirstValue(JwtRegisteredClaimNames.Sub) ?? User.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(raw, out var id) ? id : null;
    }
}
