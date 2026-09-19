using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Controllers;

/// <summary>
/// إدارة السلف والقروض المرتبطة بحسابات العملاء
/// </summary>
[ApiController]
[Route("api/customer-loans")]
[Authorize]
public class CustomerLoansController : ControllerBase
{
    private readonly AppDbContext _db;

    public CustomerLoansController(AppDbContext db)
    {
        _db = db;
    }

    /// <summary>
    /// الحصول على جميع السلف لحساب عميل
    /// </summary>
    [HttpGet("customer-account/{customerAccountId}")]
    public async Task<ActionResult<IEnumerable<CustomerLoan>>> GetLoansByCustomerAccount(Guid customerAccountId)
    {
        var loans = await _db.CustomerLoans
            .Where(l => l.CustomerAccountId == customerAccountId)
            .OrderByDescending(l => l.LoanDate)
            .ToListAsync();

        return Ok(loans);
    }

    /// <summary>
    /// الحصول على قرض محدد مع سجل الدفعات
    /// </summary>
    [HttpGet("{id}")]
    public async Task<ActionResult> GetLoan(Guid id)
    {
        var loan = await _db.CustomerLoans
            .Include(l => l.Payments)
            .FirstOrDefaultAsync(l => l.Id == id);

        if (loan == null)
            return NotFound(new { message = "القرض غير موجود" });

        return Ok(loan);
    }

    /// <summary>
    /// إنشاء قرض جديد
    /// </summary>
    [HttpPost]
    public async Task<ActionResult> CreateLoan(CreateLoanRequest request)
    {
        try
        {
            // التحقق من وجود حساب العميل
            var account = await _db.CustomerAccounts.FindAsync(request.CustomerAccountId);
            if (account == null)
                return BadRequest(new { message = "حساب العميل غير موجود" });

            // التحقق من عدم تجاوز سقف الائتمان
            var activeLoan = await _db.CustomerLoans
                .Where(l => l.CustomerAccountId == request.CustomerAccountId && l.Status != "completed")
                .SumAsync(l => l.RemainingAmount);

            if (activeLoan + request.LoanAmount > account.CreditLimit)
                return BadRequest(new {
                    message = "تجاوز سقف الائتمان",
                    currentLoans = activeLoan,
                    creditLimit = account.CreditLimit
                });

            var monthlyInstallment = request.LoanAmount / request.InstallmentCount;

            var loan = new CustomerLoan
            {
                CustomerAccountId = request.CustomerAccountId,
                LoanAmount = request.LoanAmount,
                PaidAmount = 0,
                RemainingAmount = request.LoanAmount,
                InstallmentCount = request.InstallmentCount,
                PaidInstallments = 0,
                MonthlyInstallment = monthlyInstallment,
                InterestRate = request.InterestRate,
                LoanDate = DateTime.UtcNow,
                DueDate = request.DueDate,
                Status = "active"
            };

            _db.CustomerLoans.Add(loan);

            // تحديث رصيد الحساب
            account.Balance -= request.LoanAmount;

            await _db.SaveChangesAsync();

            return CreatedAtAction(nameof(GetLoan), new { id = loan.Id }, loan);
        }
        catch (Exception ex)
        {
            return StatusCode(500, new { message = $"خطأ: {ex.Message}" });
        }
    }

    /// <summary>
    /// تسجيل دفعة على القرض
    /// </summary>
    [HttpPost("{id}/payment")]
    public async Task<ActionResult> MakePayment(Guid id, [FromBody] dynamic paymentData)
    {
        try
        {
            var loan = await _db.CustomerLoans.FindAsync(id);
            if (loan == null)
                return NotFound(new { message = "القرض غير موجود" });

            decimal amount = paymentData.amount;
            string paymentMethod = paymentData.paymentMethod ?? "cash";
            string reference = paymentData.reference ?? "";

            if (amount <= 0)
                return BadRequest(new { message = "المبلغ يجب أن يكون أكبر من صفر" });

            if (amount > loan.RemainingAmount)
                return BadRequest(new {
                    message = "المبلغ أكثر من المتبقي",
                    remaining = loan.RemainingAmount
                });

            // تسجيل الدفعة
            var payment = new LoanPayment
            {
                CustomerLoanId = id,
                Amount = amount,
                PaymentDate = DateTime.UtcNow,
                PaymentMethod = paymentMethod,
                Reference = reference
            };

            // تحديث بيانات القرض
            loan.PaidAmount += amount;
            loan.RemainingAmount -= amount;
            loan.PaidInstallments = (int)Math.Floor(loan.PaidAmount / loan.MonthlyInstallment);

            if (loan.RemainingAmount <= 0)
            {
                loan.Status = "completed";
                loan.RemainingAmount = 0;
            }

            _db.LoanPayments.Add(payment);
            await _db.SaveChangesAsync();

            return Ok(new {
                message = "تم تسجيل الدفعة بنجاح",
                payment = payment,
                loanStatus = loan
            });
        }
        catch (Exception ex)
        {
            return StatusCode(500, new { message = $"خطأ: {ex.Message}" });
        }
    }

    /// <summary>
    /// الحصول على ملخص السلف المستحقة للعميل
    /// </summary>
    [HttpGet("summary/{customerAccountId}")]
    public async Task<ActionResult> GetLoanSummary(Guid customerAccountId)
    {
        var loans = await _db.CustomerLoans
            .Where(l => l.CustomerAccountId == customerAccountId)
            .ToListAsync();

        var summary = new
        {
            totalLoans = loans.Count,
            activeLoans = loans.Count(l => l.Status == "active"),
            totalLoanAmount = loans.Sum(l => l.LoanAmount),
            totalPaid = loans.Sum(l => l.PaidAmount),
            totalRemaining = loans.Sum(l => l.RemainingAmount),
            overdueLoan = loans.Count(l => l.DueDate < DateTime.UtcNow && l.Status != "completed")
        };

        return Ok(summary);
    }
}
