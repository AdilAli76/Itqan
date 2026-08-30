using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Controllers;

public record CustomerAdvanceDto(
    Guid Id, Guid CustomerId, string CustomerName,
    decimal Amount, decimal InstallmentAmount,
    /// المتبقّي — محسوبٌ من الدفتر لا مخزَّناً في عمود.
    decimal Outstanding,
    DateOnly IssuedOn, string? Note, bool IsCancelled, DateTime CreatedAt);

public record CreateAdvanceRequest(
    Guid CustomerId, decimal Amount,
    /// ما يُخصم من كل مرتَّب. صفر = كامل المتبقّي دفعةً واحدة.
    decimal InstallmentAmount, string? Note);

public record CancelAdvanceRequest(string Reason);

/// <summary>
/// سلف المنتسبين — مالٌ يُقرَض على البطاقة ويُستردّ من المرتَّب.
///
/// <para><b>الفجوة:</b> الجهة تُسلّف منتسبها فيدفع نقداً من الصندوق بلا
/// أثر، أو يُشحن رصيده كأنه مرتَّب — فيختلط ما وُهب بما يُسترجَع، ولا تعرف
/// الجهة كم على منتسبيها من ديون.</para>
///
/// <para><b>والاسترداد تلقائي</b> عند صرف الدورة التالية — راجع
/// <see cref="EntitlementDisburser"/>. لا متابعةَ بشرية لألف منتسب.</para>
/// </summary>
[ApiController]
[Route("api/customer-advances")]
[Authorize]
public class CustomerAdvancesController : ControllerBase
{
    private readonly AppDbContext _db;
    public CustomerAdvancesController(AppDbContext db) => _db = db;

    /// <summary>
    /// السلف — الكل، أو لمنتسبٍ بعينه، أو القائمة وحدها.
    /// </summary>
    [HttpGet]
    public async Task<ActionResult<List<CustomerAdvanceDto>>> GetAll(
        [FromQuery] Guid? customerId, [FromQuery] bool openOnly = false)
    {
        var query = _db.CustomerAdvances.AsQueryable();
        if (customerId is { } id) query = query.Where(a => a.CustomerId == id);

        var advances = await query.OrderByDescending(a => a.IssuedOn).Take(500).ToListAsync();
        if (advances.Count == 0) return new List<CustomerAdvanceDto>();

        var dtos = await ToDtosAsync(advances);
        return openOnly
            ? dtos.Where(d => !d.IsCancelled && d.Outstanding > 0).ToList()
            : dtos;
    }

    /// <summary>
    /// صرف سلفة — تُودَع على البطاقة فوراً.
    ///
    /// <para>حركةٌ من نوع <see cref="WalletKinds.Advance"/> لا
    /// <see cref="WalletKinds.TopUp"/>: كلاهما يرفع الرصيد، لكن السلفة
    /// تبقى ديناً. وخلطُهما يُخفي الدَّين تماماً.</para>
    ///
    /// <para>ولا حدَّ أدنى للمبلغ ولا للقسط — تحدّدهما الإدارة.</para>
    /// </summary>
    [HttpPost]
    [Authorize(Roles = "super_admin,branch_manager")]
    public async Task<ActionResult<CustomerAdvanceDto>> Create(CreateAdvanceRequest request)
    {
        if (request.Amount <= 0)
            return BadRequest(new { message = "مبلغ السلفة يجب أن يكون أكبر من صفر" });
        if (request.InstallmentAmount < 0)
            return BadRequest(new { message = "القسط لا يكون سالباً" });
        if (request.InstallmentAmount > request.Amount)
            return BadRequest(new { message = "القسط أكبر من السلفة نفسها" });

        var customer = await _db.Customers
            .FirstOrDefaultAsync(c => c.Id == request.CustomerId && !c.IsDeleted);
        if (customer is null) return BadRequest(new { message = "المنتسب غير موجود" });

        var org = await _db.Organizations.FirstOrDefaultAsync();
        if (org is null) return BadRequest(new { message = "تعذّر تحديد المنظمة" });

        await using var transaction = await _db.Database.BeginTransactionAsync();

        var advance = new CustomerAdvance
        {
            OrganizationId = customer.OrganizationId,
            CustomerId = customer.Id,
            Amount = request.Amount,
            InstallmentAmount = request.InstallmentAmount,
            IssuedOn = DateOnly.FromDateTime(OrgClock.Today(org)),
            Note = string.IsNullOrWhiteSpace(request.Note) ? null : request.Note.Trim(),
            CreatedBy = CurrentUserId(),
        };
        _db.CustomerAdvances.Add(advance);

        _db.CustomerWalletTransactions.Add(new CustomerWalletTransaction
        {
            OrganizationId = customer.OrganizationId,
            CustomerId = customer.Id,
            AdvanceId = advance.Id,
            Kind = WalletKinds.Advance,
            Amount = request.Amount,
            Note = advance.Note ?? "سلفة",
            CreatedBy = CurrentUserId(),
        });

        _db.LogAudit(customer.OrganizationId, CurrentUserId(), "customer.advance_issued",
            "customer_advances", advance.Id,
            newValues: new { customer.FullName, advance.Amount, advance.InstallmentAmount });

        await _db.SaveChangesAsync();
        await transaction.CommitAsync();

        return (await ToDtosAsync(new List<CustomerAdvance> { advance })).Single();
    }

    /// <summary>
    /// إلغاء سلفة — إعفاءٌ من متبقّيها.
    ///
    /// <para><b>ولا يُسترجَع ما صُرف منها:</b> المال دخل البطاقة وأُنفق.
    /// الإلغاء يوقف الخصم القادم فقط — وهو إعفاءٌ إداري لا محوٌ للماضي.
    /// وحذفُ السلفة كان سيترك أقساطاً مخصومة بلا سببٍ ظاهر في كشف
    /// المنتسب.</para>
    /// </summary>
    [HttpPost("{id:guid}/cancel")]
    [Authorize(Roles = "super_admin")]
    public async Task<IActionResult> Cancel(Guid id, CancelAdvanceRequest request)
    {
        var reason = (request?.Reason ?? "").Trim();
        if (reason.Length == 0) return BadRequest(new { message = "سبب الإلغاء إلزامي" });

        var advance = await _db.CustomerAdvances.FirstOrDefaultAsync(a => a.Id == id);
        if (advance is null) return NotFound();
        if (advance.IsCancelled) return BadRequest(new { message = "السلفة مُلغاة أصلاً" });

        advance.IsCancelled = true;
        _db.LogAudit(advance.OrganizationId, CurrentUserId(), "customer.advance_cancelled",
            "customer_advances", id, newValues: new { advance.Amount, Reason = reason });
        await _db.SaveChangesAsync();
        return NoContent();
    }

    /// <summary>
    /// سداد يدوي — لمن يدفع نقداً بدل انتظار الخصم.
    /// </summary>
    [HttpPost("{id:guid}/repay")]
    [Authorize(Roles = "super_admin,branch_manager")]
    public async Task<ActionResult<CustomerAdvanceDto>> Repay(Guid id, [FromBody] decimal amount)
    {
        if (amount <= 0) return BadRequest(new { message = "المبلغ يجب أن يكون أكبر من صفر" });

        var advance = await _db.CustomerAdvances.FirstOrDefaultAsync(a => a.Id == id);
        if (advance is null) return NotFound();
        if (advance.IsCancelled) return BadRequest(new { message = "السلفة مُلغاة" });

        var outstanding = await OutstandingOf(advance);
        if (outstanding <= 0) return BadRequest(new { message = "السلفة مسدَّدة بالكامل" });
        if (amount > outstanding)
        {
            // سدادٌ يتجاوز المتبقّي يُنتج سلفةً برصيدٍ سالب — رقمٌ لا معنى له.
            return BadRequest(new { message = $"المبلغ يتجاوز المتبقّي ({outstanding:0.00})" });
        }

        _db.CustomerWalletTransactions.Add(new CustomerWalletTransaction
        {
            OrganizationId = advance.OrganizationId,
            CustomerId = advance.CustomerId,
            AdvanceId = advance.Id,
            Kind = WalletKinds.AdvanceRepayment,
            Amount = amount,
            Note = "سداد سلفة نقداً",
            CreatedBy = CurrentUserId(),
        });

        _db.LogAudit(advance.OrganizationId, CurrentUserId(), "customer.advance_repaid",
            "customer_advances", id, newValues: new { Amount = amount });
        await _db.SaveChangesAsync();

        return (await ToDtosAsync(new List<CustomerAdvance> { advance })).Single();
    }

    /// <summary>المتبقّي من سلفة — أصلها ناقص أقساطها في الدفتر.</summary>
    private async Task<decimal> OutstandingOf(CustomerAdvance advance)
    {
        var repaid = await _db.CustomerWalletTransactions
            .Where(t => t.AdvanceId == advance.Id && t.Kind == WalletKinds.AdvanceRepayment)
            .SumAsync(t => (decimal?)t.Amount) ?? 0;
        return advance.Amount - repaid;
    }

    private async Task<List<CustomerAdvanceDto>> ToDtosAsync(List<CustomerAdvance> advances)
    {
        var ids = advances.Select(a => a.Id).ToList();
        // مجموع الأقساط لكل السلف باستعلامٍ واحد — قائمةٌ بخمسمئة سلفة
        // كانت ستُنتج خمسمئة استعلام.
        var repaid = await _db.CustomerWalletTransactions
            .Where(t => t.AdvanceId != null && ids.Contains(t.AdvanceId.Value)
                     && t.Kind == WalletKinds.AdvanceRepayment)
            .GroupBy(t => t.AdvanceId!.Value)
            .Select(g => new { AdvanceId = g.Key, Total = g.Sum(t => t.Amount) })
            .ToDictionaryAsync(x => x.AdvanceId, x => x.Total);

        var customerIds = advances.Select(a => a.CustomerId).Distinct().ToList();
        var names = await _db.Customers
            .Where(c => customerIds.Contains(c.Id))
            .ToDictionaryAsync(c => c.Id, c => c.FullName);

        return advances.Select(a => new CustomerAdvanceDto(
            a.Id, a.CustomerId, names.GetValueOrDefault(a.CustomerId, "—"),
            a.Amount, a.InstallmentAmount,
            a.Amount - repaid.GetValueOrDefault(a.Id),
            a.IssuedOn, a.Note, a.IsCancelled, a.CreatedAt)).ToList();
    }

    private Guid? CurrentUserId()
    {
        var raw = User.FindFirstValue(JwtRegisteredClaimNames.Sub) ?? User.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(raw, out var id) ? id : null;
    }
}
