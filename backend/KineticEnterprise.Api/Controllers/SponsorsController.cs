using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Authorization;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Controllers;

public record SponsorDto(Guid Id, string Name, string? Phone, string? Notes, int BeneficiaryCount);

public record SponsorStatementLineDto(
    Guid CustomerId, string CustomerName, decimal Granted, decimal Spent, decimal Remaining);

public record SponsorStatementDto(
    Guid SponsorId, string SponsorName, DateTime From, DateTime To,
    decimal TotalGranted, decimal TotalSpent, List<SponsorStatementLineDto> Lines);

/// <summary>
/// الجهات الممولة لأرصدة العملاء (شركة لموظفيها، جمعية، مدرسة) — الطرف الذي
/// تُحاسبه المنشأة في نموذج الاستحقاق الممنوح، لا المستفيد نفسه.
///
/// نفس نمط SuppliersController: العزل تتكفّل به Security Policy على مستوى
/// قاعدة البيانات (fn_OrgOnlyPredicate)، فلا WHERE organization_id يدوي.
/// </summary>
[ApiController]
[Route("api/sponsors")]
[Authorize]
public class SponsorsController : ControllerBase
{
    private readonly AppDbContext _db;
    public SponsorsController(AppDbContext db) => _db = db;

    [HttpGet]
    public async Task<ActionResult<List<SponsorDto>>> GetAll([FromQuery] string? search)
    {
        var query = _db.Sponsors.Where(s => !s.IsDeleted);
        if (!string.IsNullOrWhiteSpace(search))
        {
            query = query.Where(s => s.Name.Contains(search) || (s.Phone != null && s.Phone.Contains(search)));
        }

        // الأعمدة المطلوبة وحدها بدل الكيان كاملاً، وعدّ المستفيدين بصلة
        // تجميع واحدة بدل استعلام عدّ لكل جهة على حدة.
        return await query
            .OrderBy(s => s.Name)
            .Select(s => new SponsorDto(
                s.Id, s.Name, s.Phone, s.Notes,
                _db.Customers.Count(c => c.SponsorId == s.Id && !c.IsDeleted)))
            .ToListAsync();
    }

    [HttpGet("{id:guid}")]
    public async Task<ActionResult<SponsorDto>> GetById(Guid id)
    {
        var sponsor = await _db.Sponsors
            .Where(s => s.Id == id && !s.IsDeleted)
            .Select(s => new SponsorDto(
                s.Id, s.Name, s.Phone, s.Notes,
                _db.Customers.Count(c => c.SponsorId == s.Id && !c.IsDeleted)))
            .FirstOrDefaultAsync();

        return sponsor is null ? NotFound() : sponsor;
    }

    /// <summary>
    /// كشف محاسبة الجهة الممولة: كم مُنح لمستفيديها وكم صرفوا فعلاً خلال فترة.
    ///
    /// هذا هو مبرر وجود الموديول تجارياً — بدونه تمنح المنشأة أرصدة لا تعرف
    /// كيف تطالب بها. الفرق بين المنوح والمصروف مهم: بعض الجهات تحاسِب على
    /// المصروف فعلاً، وبعضها على المخصَّص.
    /// </summary>
    [HttpGet("{id:guid}/statement")]
    public async Task<ActionResult<SponsorStatementDto>> GetStatement(
        Guid id, [FromQuery] DateTime? from, [FromQuery] DateTime? to)
    {
        var sponsor = await _db.Sponsors
            .Where(s => s.Id == id && !s.IsDeleted)
            .Select(s => new { s.Id, s.Name })
            .FirstOrDefaultAsync();
        if (sponsor is null) return NotFound();

        var start = from ?? DateTime.UtcNow.AddMonths(-1);
        var end = to ?? DateTime.UtcNow;

        var beneficiaries = await _db.Customers
            .Where(c => c.SponsorId == id && !c.IsDeleted)
            .Select(c => new { c.Id, c.FullName })
            .ToListAsync();
        if (beneficiaries.Count == 0)
        {
            return new SponsorStatementDto(sponsor.Id, sponsor.Name, start, end, 0, 0, new List<SponsorStatementLineDto>());
        }

        var ids = beneficiaries.Select(b => b.Id).ToList();

        // استعلام تجميع واحد لكل المستفيدين — لا استعلامان لكل مستفيد.
        var totals = await _db.CustomerWalletTransactions
            .Where(t => ids.Contains(t.CustomerId) && t.CreatedAt >= start && t.CreatedAt <= end)
            .GroupBy(t => t.CustomerId)
            .Select(g => new
            {
                CustomerId = g.Key,
                Granted = g.Where(t => t.Kind == WalletKinds.EntitlementGrant).Sum(t => (decimal?)t.Amount) ?? 0,
                Spent = g.Where(t => t.Kind == WalletKinds.Spend).Sum(t => (decimal?)t.Amount) ?? 0,
                Refunded = g.Where(t => t.Kind == WalletKinds.InvoiceRefund).Sum(t => (decimal?)t.Amount) ?? 0,
            })
            .ToDictionaryAsync(x => x.CustomerId, x => x);

        var lines = beneficiaries.Select(b =>
        {
            totals.TryGetValue(b.Id, out var t);
            var granted = t?.Granted ?? 0;
            // المرتجع يُنقص المصروف الفعلي، وإلا حوسبت الجهة على بضاعة أُعيدت.
            var spent = (t?.Spent ?? 0) - (t?.Refunded ?? 0);
            return new SponsorStatementLineDto(b.Id, b.FullName, granted, spent, granted - spent);
        })
        .OrderByDescending(l => l.Spent)
        .ToList();

        return new SponsorStatementDto(
            sponsor.Id, sponsor.Name, start, end,
            lines.Sum(l => l.Granted), lines.Sum(l => l.Spent), lines);
    }

    /// <summary>
    /// تشغيل إسقاط الاستحقاقات المنتهية فوراً بدل انتظار المهمة اليومية.
    ///
    /// موجود لأن المهمة الليلية غير قابلة للملاحظة: بدون زر يدوي لا يستطيع
    /// المدير التأكد من أنها تعمل أصلاً، ولا معالجة يوم توقّف فيه السيرفر.
    /// </summary>
    [HttpPost("run-expiry-sweep")]
    [RequirePermission("customers.wallet_adjust")]
    public async Task<ActionResult<SweepResult>> RunExpirySweep()
    {
        var result = await EntitlementSweeper.SweepAsync(
            _db, DateOnly.FromDateTime(DateTime.UtcNow), CurrentUserId());
        return result;
    }

    [HttpPost]
    [RequirePermission("customers.manage")]
    public async Task<ActionResult<SponsorDto>> Create(Sponsor sponsor)
    {
        sponsor.OrganizationId = Guid.Parse(User.FindFirstValue("organization_id")!);
        _db.Sponsors.Add(sponsor);
        await _db.SaveChangesAsync();
        return CreatedAtAction(nameof(GetById), new { id = sponsor.Id },
            new SponsorDto(sponsor.Id, sponsor.Name, sponsor.Phone, sponsor.Notes, 0));
    }

    [HttpPut("{id:guid}")]
    [RequirePermission("customers.manage")]
    public async Task<IActionResult> Update(Guid id, Sponsor update)
    {
        var sponsor = await _db.Sponsors.FindAsync(id);
        if (sponsor is null) return NotFound();

        sponsor.Name = update.Name;
        sponsor.Phone = update.Phone;
        sponsor.Notes = update.Notes;
        await _db.SaveChangesAsync();
        return NoContent();
    }

    [HttpDelete("{id:guid}")]
    [RequirePermission("customers.delete")]
    public async Task<IActionResult> SoftDelete(Guid id)
    {
        var sponsor = await _db.Sponsors.FindAsync(id);
        if (sponsor is null) return NotFound();

        // حذف جهة لها مستفيدون كان سيترك عملاء بمرجع معلَّق لا يظهر في أي شاشة.
        var beneficiaries = await _db.Customers.CountAsync(c => c.SponsorId == id && !c.IsDeleted);
        if (beneficiaries > 0)
        {
            return BadRequest(new { message = $"مرتبطة بـ {beneficiaries} عميل — انقلهم لجهة أخرى أولاً" });
        }

        sponsor.IsDeleted = true;
        _db.LogAudit(sponsor.OrganizationId, CurrentUserId(), "sponsor.deleted", "sponsors", sponsor.Id,
            oldValues: new { sponsor.Name });
        await _db.SaveChangesAsync();
        return NoContent();
    }

    /// <summary>
    /// يُعيد جهةً راعيةً محذوفة إلى القوائم.
    ///
    /// <para><b>سبب وجودها:</b> الحذف ناعمٌ والصفّ باقٍ، ولم يكن ما يقلب
    /// الراية. وإنشاءُ جهةٍ جديدة باسمها ليس بديلاً: مرتَّبات المنتسبين
    /// وكشوف الصرف تُنسب إلى معرّف الجهة لا إلى اسمها، فيبقى تاريخ الصرف
    /// معلَّقاً بجهةٍ لا تظهر في شاشة.</para>
    ///
    /// <para><b>ولا يُشترط أن تكون فارغة كما اشتُرط عند الحذف:</b> ذاك
    /// حارسٌ يمنع تعليق عملاء بمرجعٍ لا يظهر، والاسترجاع يفعل عكسه — يُظهر
    /// المرجع الذي يشيرون إليه.</para>
    /// </summary>
    [HttpPost("{id:guid}/restore")]
    [RequirePermission("customers.delete")]
    public async Task<IActionResult> Restore(Guid id)
    {
        var sponsor = await _db.Sponsors.FindAsync(id);
        if (sponsor is null) return NotFound();

        if (!sponsor.IsDeleted)
            return BadRequest(new { message = "الجهة غير محذوفة أصلاً" });

        sponsor.IsDeleted = false;
        _db.LogAudit(sponsor.OrganizationId, CurrentUserId(), "sponsor.restored", "sponsors", sponsor.Id,
            newValues: new { sponsor.Name });
        await _db.SaveChangesAsync();
        return NoContent();
    }

    private Guid? CurrentUserId()
    {
        var raw = User.FindFirstValue(JwtRegisteredClaimNames.Sub) ?? User.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(raw, out var id) ? id : null;
    }
}
