using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Controllers;

/// <summary>
/// إدارة المرتبات والرواتب للعملاء
/// </summary>
[ApiController]
[Route("api/salaries")]
[Authorize]
public class SalariesController : ControllerBase
{
    private readonly AppDbContext _db;

    public SalariesController(AppDbContext db)
    {
        _db = db;
    }

    /// <summary>
    /// الحصول على سجلات المرتبات لحساب عميل
    /// </summary>
    [HttpGet("customer-account/{customerAccountId}")]
    public async Task<ActionResult<IEnumerable<SalaryRecord>>> GetSalariesByCustomerAccount(Guid customerAccountId)
    {
        var salaries = await _db.SalaryRecords
            .Where(s => s.CustomerAccountId == customerAccountId)
            .OrderByDescending(s => s.Year)
            .ThenByDescending(s => s.Month)
            .ToListAsync();

        return Ok(salaries);
    }

    /// <summary>
    /// الحصول على مرتب محدد
    /// </summary>
    [HttpGet("{id}")]
    public async Task<ActionResult<SalaryRecord>> GetSalary(Guid id)
    {
        var salary = await _db.SalaryRecords
            .Include(s => s.Details)
            .FirstOrDefaultAsync(s => s.Id == id);

        if (salary == null)
            return NotFound(new { message = "المرتب غير موجود" });

        return Ok(salary);
    }

    /// <summary>
    /// إنشاء مرتب جديد
    /// </summary>
    [HttpPost]
    public async Task<ActionResult> CreateSalary(CreateSalaryRequest request)
    {
        try
        {
            // التحقق من وجود حساب العميل
            var account = await _db.CustomerAccounts.FindAsync(request.CustomerAccountId);
            if (account == null)
                return BadRequest(new { message = "حساب العميل غير موجود" });

            // التحقق من عدم وجود مرتب لنفس الشهر
            var existing = await _db.SalaryRecords
                .FirstOrDefaultAsync(s =>
                    s.CustomerAccountId == request.CustomerAccountId &&
                    s.Year == request.Year &&
                    s.Month == request.Month);

            if (existing != null)
                return BadRequest(new { message = "يوجد مرتب لهذا الشهر بالفعل" });

            var netSalary = request.BasicSalary + request.Allowances - request.Deductions;

            var salary = new SalaryRecord
            {
                CustomerAccountId = request.CustomerAccountId,
                Year = request.Year,
                Month = request.Month,
                BasicSalary = request.BasicSalary,
                Allowances = request.Allowances,
                Deductions = request.Deductions,
                NetSalary = netSalary,
                PaidAmount = 0,
                PaymentDate = DateTime.UtcNow,
                Status = "pending",
                Notes = request.Notes
            };

            _db.SalaryRecords.Add(salary);
            await _db.SaveChangesAsync();

            return CreatedAtAction(nameof(GetSalary), new { id = salary.Id }, salary);
        }
        catch (Exception ex)
        {
            return StatusCode(500, new { message = $"خطأ: {ex.Message}" });
        }
    }

    /// <summary>
    /// تحديث حالة المرتب (دفع كلي/جزئي)
    /// </summary>
    [HttpPost("{id}/pay")]
    public async Task<ActionResult> PaySalary(Guid id, [FromBody] dynamic paymentData)
    {
        try
        {
            var salary = await _db.SalaryRecords.FindAsync(id);
            if (salary == null)
                return NotFound(new { message = "المرتب غير موجود" });

            decimal amount = paymentData.amount;

            if (amount <= 0)
                return BadRequest(new { message = "المبلغ يجب أن يكون أكبر من صفر" });

            salary.PaidAmount += amount;
            salary.Status = salary.PaidAmount >= salary.NetSalary ? "paid" : "partial";
            salary.PaymentDate = DateTime.UtcNow;

            await _db.SaveChangesAsync();

            return Ok(new {
                message = "تم تسجيل الدفعة بنجاح",
                salary = salary
            });
        }
        catch (Exception ex)
        {
            return StatusCode(500, new { message = $"خطأ: {ex.Message}" });
        }
    }

    /// <summary>
    /// حذف مرتب (في حالة الخطأ)
    /// </summary>
    [HttpDelete("{id}")]
    public async Task<ActionResult> DeleteSalary(Guid id)
    {
        try
        {
            var salary = await _db.SalaryRecords.FindAsync(id);
            if (salary == null)
                return NotFound(new { message = "المرتب غير موجود" });

            if (salary.Status == "paid")
                return BadRequest(new { message = "لا يمكن حذف مرتب تم دفعه" });

            _db.SalaryRecords.Remove(salary);
            await _db.SaveChangesAsync();

            return Ok(new { message = "تم حذف المرتب بنجاح" });
        }
        catch (Exception ex)
        {
            return StatusCode(500, new { message = $"خطأ: {ex.Message}" });
        }
    }
}
