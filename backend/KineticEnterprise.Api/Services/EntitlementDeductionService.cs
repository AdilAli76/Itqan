using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Services;

/// <summary>
/// معالج خصم الاستحقاقات الشهرية — يُنفّذ جداول الخصم المجدولة.
/// </summary>
public class EntitlementDeductionService
{
    private readonly AppDbContext _db;
    private readonly ILogger<EntitlementDeductionService> _logger;

    public EntitlementDeductionService(AppDbContext db, ILogger<EntitlementDeductionService> logger)
    {
        _db = db;
        _logger = logger;
    }

    /// <summary>
    /// معالج الخصم الشهري: يجد الجداول المُستحقة اليوم ويطبّقها.
    /// </summary>
    public async Task ProcessDailyDeductionsAsync()
    {
        try
        {
            var today = DateTime.UtcNow.Date;
            var dayOfMonth = today.Day;

            // البحث عن جداول الخصم المستحقة اليوم
            var schedules = await _db.EntitlementDeductionSchedules
                .Where(s => s.IsActive && s.DeductionDayOfMonth == dayOfMonth)
                .ToListAsync();

            if (schedules.Count == 0)
            {
                _logger.LogInformation("لا توجد جداول خصم مستحقة اليوم");
                return;
            }

            _logger.LogInformation($"معالجة {schedules.Count} جداول خصم");

            foreach (var schedule in schedules)
            {
                await ProcessScheduleAsync(schedule, today);
            }

            await _db.SaveChangesAsync();
            _logger.LogInformation("انتهت معالجة الخصم الشهري بنجاح");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في معالجة الخصم الشهري");
            throw;
        }
    }

    private async Task ProcessScheduleAsync(EntitlementDeductionSchedule schedule, DateTime today)
    {
        try
        {
            // تحقق من أن الجدول لم يُطبّق مسبقاً اليوم
            if (schedule.LastProcessedDate?.Date == today.Date)
            {
                _logger.LogInformation($"الجدول {schedule.Id} طُبّق بالفعل اليوم");
                return;
            }

            // احصل على كل العملاء في الفئة مع استحقاق نشط
            var customers = await _db.Customers
                .Where(c => c.CategoryId == schedule.CustomerCategoryId
                    && c.AccountModel == "entitlement"
                    && (c.EntitlementExpiresOn == null || c.EntitlementExpiresOn > today))
                .ToListAsync();

            _logger.LogInformation($"وجدت {customers.Count} عميل في الفئة {schedule.CustomerCategoryId}");

            var transactions = new List<CustomerWalletTransaction>();

            foreach (var customer in customers)
            {
                // احسب المبلغ: تخصيص العميل الخاص به أم مبلغ الجدول
                var deductionAmount = customer.EntitlementOverride ?? schedule.DeductionAmount;

                // تجاهل إذا كان المبلغ صفر (العميل موقوف صراحة)
                if (deductionAmount == 0)
                    continue;

                var transaction = new CustomerWalletTransaction
                {
                    Id = Guid.NewGuid(),
                    CustomerId = customer.Id,
                    OrganizationId = customer.OrganizationId,
                    BranchId = customer.BranchId,
                    Kind = "entitlement_deduction",
                    Amount = deductionAmount,
                    Notes = $"خصم استحقاق شهري - {schedule.Notes}",
                    CreatedAt = DateTime.UtcNow,
                };

                transactions.Add(transaction);
                _logger.LogInformation($"خصم {deductionAmount} من العميل {customer.FullName}");
            }

            // أضف جميع المعاملات
            await _db.CustomerWalletTransactions.AddRangeAsync(transactions);

            // حدّث تاريخ آخر معالجة
            schedule.LastProcessedDate = today;

            _logger.LogInformation($"طُبّق {transactions.Count} خصم من الجدول {schedule.Id}");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, $"خطأ في معالجة الجدول {schedule.Id}");
            throw;
        }
    }
}
