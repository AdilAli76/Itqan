using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Controllers;

public record EntitlementDeductionScheduleDto(
    Guid Id, Guid CategoryId, decimal DeductionAmount, int DeductionDayOfMonth,
    DateTime? LastProcessedDate, bool IsActive, string? Notes);

public record CreateEntitlementDeductionScheduleRequest(
    Guid CategoryId, decimal DeductionAmount, int DeductionDayOfMonth, string? Notes = null);

public record UpdateEntitlementDeductionScheduleRequest(
    decimal DeductionAmount, int DeductionDayOfMonth, bool IsActive, string? Notes = null);

/// <summary>
/// جداول خصم الاستحقاقات الشهرية — تخصم مبلغاً من كل عميل في فئة معيّنة في يومٍ محدّد.
///
/// <para><b>السبب:</b> فئة عملاء قد تحتاج جداولَ مختلفةٍ حسب الفترة — مثلاً: مبلغٌ
/// إضافيٌّ في رمضان، أو مبلغٌ مؤقتٌ لسنة واحدة. والجدول يسمح بذلك دون تغيير
/// الفئة نفسها.</para>
/// </summary>
[ApiController]
[Route("api/entitlement-deduction-schedules")]
[Authorize]
public class EntitlementDeductionsController : ControllerBase
{
    private readonly AppDbContext _db;
    public EntitlementDeductionsController(AppDbContext db) => _db = db;

    /// <summary>
    /// جميع جداول الخصم النشطة.
    /// </summary>
    [HttpGet]
    public async Task<ActionResult<List<EntitlementDeductionScheduleDto>>> GetAll([FromQuery] bool includeInactive = false)
    {
        var query = _db.EntitlementDeductionSchedules.AsQueryable();
        if (!includeInactive)
            query = query.Where(s => s.IsActive);

        var schedules = await query
            .OrderBy(s => s.DeductionDayOfMonth)
            .Select(s => new EntitlementDeductionScheduleDto(
                s.Id, s.CustomerCategoryId, s.DeductionAmount, s.DeductionDayOfMonth,
                s.LastProcessedDate, s.IsActive, s.Notes))
            .ToListAsync();

        return Ok(schedules);
    }

    /// <summary>
    /// الجداول لفئة محدّدة.
    /// </summary>
    [HttpGet("category/{categoryId:guid}")]
    public async Task<ActionResult<List<EntitlementDeductionScheduleDto>>> GetByCategory(Guid categoryId)
    {
        var schedules = await _db.EntitlementDeductionSchedules
            .Where(s => s.CustomerCategoryId == categoryId)
            .OrderBy(s => s.DeductionDayOfMonth)
            .Select(s => new EntitlementDeductionScheduleDto(
                s.Id, s.CustomerCategoryId, s.DeductionAmount, s.DeductionDayOfMonth,
                s.LastProcessedDate, s.IsActive, s.Notes))
            .ToListAsync();

        return Ok(schedules);
    }

    /// <summary>
    /// إنشاء جدول خصمٍ جديد.
    /// </summary>
    [HttpPost]
    [Authorize(Roles = "super_admin")]
    public async Task<ActionResult<EntitlementDeductionScheduleDto>> Create(CreateEntitlementDeductionScheduleRequest request)
    {
        if (await Validate(request) is { } error) return error;

        var orgId = Guid.Parse(User.FindFirstValue("organization_id")!);
        var schedule = new EntitlementDeductionSchedule
        {
            OrganizationId = orgId,
            CustomerCategoryId = request.CategoryId,
            DeductionAmount = request.DeductionAmount,
            DeductionDayOfMonth = request.DeductionDayOfMonth,
            IsActive = true,
            Notes = request.Notes?.Trim(),
        };

        _db.EntitlementDeductionSchedules.Add(schedule);
        _db.LogAudit(orgId, CurrentUserId(), "entitlement_deduction_schedule.created",
            "entitlement_deduction_schedules", schedule.Id,
            newValues: new { schedule.CustomerCategoryId, schedule.DeductionAmount, schedule.DeductionDayOfMonth });
        await _db.SaveChangesAsync();

        return CreatedAtAction(nameof(GetByCategory), new { categoryId = schedule.CustomerCategoryId },
            new EntitlementDeductionScheduleDto(
                schedule.Id, schedule.CustomerCategoryId, schedule.DeductionAmount,
                schedule.DeductionDayOfMonth, schedule.LastProcessedDate, schedule.IsActive, schedule.Notes));
    }

    /// <summary>
    /// تحديث جدول الخصم.
    /// </summary>
    [HttpPut("{id:guid}")]
    [Authorize(Roles = "super_admin")]
    public async Task<IActionResult> Update(Guid id, UpdateEntitlementDeductionScheduleRequest request)
    {
        var schedule = await _db.EntitlementDeductionSchedules.FirstOrDefaultAsync(s => s.Id == id);
        if (schedule is null) return NotFound();

        if (request.DeductionDayOfMonth < 1 || request.DeductionDayOfMonth > 28)
            return BadRequest(new { message = "اليوم يجب أن يكون بين 1 و 28" });
        if (request.DeductionAmount < 0)
            return BadRequest(new { message = "المبلغ لا يكون سالباً" });

        var before = new { schedule.DeductionAmount, schedule.DeductionDayOfMonth, schedule.IsActive };

        schedule.DeductionAmount = request.DeductionAmount;
        schedule.DeductionDayOfMonth = request.DeductionDayOfMonth;
        schedule.IsActive = request.IsActive;
        schedule.Notes = request.Notes?.Trim();

        _db.LogAudit(schedule.OrganizationId, CurrentUserId(), "entitlement_deduction_schedule.updated",
            "entitlement_deduction_schedules", id,
            oldValues: before,
            newValues: new { schedule.DeductionAmount, schedule.DeductionDayOfMonth, schedule.IsActive });
        await _db.SaveChangesAsync();
        return NoContent();
    }

    /// <summary>
    /// حذف جدول الخصم.
    /// </summary>
    [HttpDelete("{id:guid}")]
    [Authorize(Roles = "super_admin")]
    public async Task<IActionResult> Delete(Guid id)
    {
        var schedule = await _db.EntitlementDeductionSchedules.FirstOrDefaultAsync(s => s.Id == id);
        if (schedule is null) return NotFound();

        _db.EntitlementDeductionSchedules.Remove(schedule);
        _db.LogAudit(schedule.OrganizationId, CurrentUserId(), "entitlement_deduction_schedule.deleted",
            "entitlement_deduction_schedules", id, oldValues: new { schedule.DeductionAmount });
        await _db.SaveChangesAsync();
        return NoContent();
    }

    private async Task<ActionResult?> Validate(CreateEntitlementDeductionScheduleRequest request)
    {
        if (request.DeductionDayOfMonth < 1 || request.DeductionDayOfMonth > 28)
            return BadRequest(new { message = "اليوم يجب أن يكون بين 1 و 28" });
        if (request.DeductionAmount < 0)
            return BadRequest(new { message = "المبلغ لا يكون سالباً" });

        var categoryExists = await _db.CustomerCategories
            .AnyAsync(c => c.Id == request.CategoryId && c.IsActive);
        if (!categoryExists)
            return BadRequest(new { message = "فئة العميل المطلوبة غير موجودة أو موقوفة" });

        var scheduleExists = await _db.EntitlementDeductionSchedules
            .AnyAsync(s => s.CustomerCategoryId == request.CategoryId && s.IsActive);
        if (scheduleExists)
            return Conflict(new { message = "هناك جدول نشط بالفعل لهذه الفئة" });

        return null;
    }

    private Guid? CurrentUserId()
    {
        var raw = User.FindFirstValue(JwtRegisteredClaimNames.Sub) ?? User.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(raw, out var id) ? id : null;
    }
}
