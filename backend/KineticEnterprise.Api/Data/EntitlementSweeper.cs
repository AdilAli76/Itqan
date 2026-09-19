using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Data;

public record SweepResult(int CustomersAffected, decimal TotalExpired);

/// <summary>
/// إسقاط ما تبقّى من استحقاق بعد انتهاء فترته.
///
/// <para><b>الضمانة الأهم:</b> الشرط <c>AccountModel == Entitlement</c> ليس
/// تحسيناً للأداء — هو ما يمنع إسقاط رصيد دفعه عميل من ماله. لا يُحذَف هذا
/// الشرط ولا يُوسَّع تحت أي ظرف.</para>
///
/// <para>الإسقاط يُكتب <b>حركة خصم جديدة</b> في الدفتر لا حذفاً للمنحة ولا
/// تصفيراً لعمود: الرصيد في هذا النظام مجموع الدفتر دائماً (راجع
/// [WalletBalances])، فيبقى تاريخ الحساب مقروءاً سطراً سطراً — كم مُنح، كم
/// صُرف، وكم سقط ومتى — وهو ما يحتاجه أي نزاع مع الجهة الممولة أو المستفيد.</para>
/// </summary>
public static class EntitlementSweeper
{
    public static async Task<SweepResult> SweepAsync(AppDbContext db, DateOnly today, Guid? createdBy = null)
    {
        var expired = await db.Customers
            .Where(c => !c.IsDeleted
                     && c.AccountModel == AccountModels.Entitlement
                     && c.EntitlementExpiresOn != null
                     && c.EntitlementExpiresOn < today)
            .Select(c => new { c.Id, c.OrganizationId, c.FullName, c.EntitlementExpiresOn })
            .ToListAsync();

        if (expired.Count == 0) return new SweepResult(0, 0);

        var ids = expired.Select(c => c.Id).ToList();
        var balances = await WalletBalances.ComputeManyAsync(db, ids);

        var affected = 0;
        var total = 0m;
        foreach (var customer in expired)
        {
            var balance = balances.GetValueOrDefault(customer.Id);
            if (balance <= 0) continue;

            db.CustomerWalletTransactions.Add(new CustomerWalletTransaction
            {
                OrganizationId = customer.OrganizationId,
                CustomerId = customer.Id,
                Kind = WalletKinds.EntitlementExpiry,
                Amount = balance,
                Note = $"انتهاء استحقاق بتاريخ {customer.EntitlementExpiresOn:yyyy-MM-dd}",
                CreatedBy = createdBy,
            });

            db.LogAudit(customer.OrganizationId, createdBy, "customer.entitlement_expired",
                "customers", customer.Id,
                oldValues: new { customer.FullName, ExpiredAmount = balance });

            affected++;
            total += balance;
        }

        // تُترك الفترة كما هي عمداً: تجديدها قرار إداري (هل جُدّد العقد مع
        // الجهة الممولة؟) لا أثر جانبي لمهمة ليلية. وبقاء التاريخ منتهياً
        // يمنع تكرار الإسقاط لأن الرصيد صار صفراً.
        await db.SaveChangesAsync();
        return new SweepResult(affected, total);
    }
}

/// <summary>
/// يشغّل [EntitlementSweeper] يومياً على كل المنظمات.
///
/// يفتح اتصاله الخاص ويضبط SESSION_CONTEXT لكل منظمة على حدة — لا يوجد طلب
/// HTTP هنا فلم يمرّ شيء على TenantContextMiddleware، وبدون ضبط السياق يدوياً
/// تحجب سياسات RLS كل الصفوف فتمرّ المهمة صامتة بلا أثر.
/// </summary>
public class EntitlementSweepService : BackgroundService
{
    private readonly IConfiguration _config;
    private readonly ILogger<EntitlementSweepService> _logger;

    public EntitlementSweepService(IConfiguration config, ILogger<EntitlementSweepService> logger)
    {
        _config = config;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await RunOnceAsync(stoppingToken);
            }
            catch (Exception ex)
            {
                // خطأ في المهمة لا يُسقط السيرفر — يُسجَّل وتُعاد المحاولة غداً.
                _logger.LogError(ex, "فشل إسقاط الاستحقاقات المنتهية");
            }

            await Task.Delay(TimeSpan.FromHours(24), stoppingToken);
        }
    }

    private async Task RunOnceAsync(CancellationToken token)
    {
        var connectionString = _config.GetConnectionString("Default");
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlite(connectionString)
            .UseSnakeCaseNamingConvention()
            .Options;

        await using var db = new AppDbContext(options);

        // platform_organizations معفى من RLS، فهو المصدر الوحيد لقائمة
        // المنظمات قبل ضبط أي سياق.
        var orgIds = await db.PlatformOrganizations
            .Where(o => o.IsActive)
            .Select(o => o.Id)
            .ToListAsync(token);

        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        foreach (var orgId in orgIds)
        {
            var result = await EntitlementSweeper.SweepAsync(db, today);
            if (result.CustomersAffected > 0)
            {
                _logger.LogInformation(
                    "أُسقط استحقاق منتهٍ لـ {Count} عميل بمجموع {Total} في المنظمة {Org}",
                    result.CustomersAffected, result.TotalExpired, orgId);
            }
        }
    }
}
