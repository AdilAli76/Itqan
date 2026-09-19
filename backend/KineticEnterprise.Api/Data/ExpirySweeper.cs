using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Data;

public record ExpirySweepResult(int ExpiredBatches, int ExpiringBatches, int NotificationsCreated);

/// <summary>
/// إشعار دائم بالدفعات المنتهية أو المقتربة من الانتهاء.
///
/// <para>نوع <c>expiry</c> معرَّف في مخطط جدول notifications منذ البداية ولم
/// يكن أحد يكتبه — أي أن الصيدلية كانت تخسر بضاعة بلا أي إنذار، بينما
/// الحقول التي تكشفها (<c>expiry_date</c> على stock_levels) موجودة ومملوءة
/// فعلاً عند استلام أوامر الشراء.</para>
///
/// <para><b>لماذا مهمة يومية لا حساب وقت القراءة:</b> شريط نقطة البيع يقرأ
/// الحالة لحظياً من <c>GET /api/products/expiry-alerts</c>، لكن الشريط لا
/// يُرى إلا حين تكون الشاشة مفتوحة. الصفّ الدائم في notifications هو ما يجعل
/// الإنذار يصل إلى مدير المخزون الذي لا يفتح نقطة البيع أصلاً، ويبقى في
/// «غرفة الإشعارات» حتى يُقرأ — نفس منطق تنبيه نقص المخزون.</para>
///
/// <para><b>منع التكرار:</b> إشعار واحد لكل صنف في اليوم. بدونه تُنشئ المهمة
/// صفاً جديداً لكل دفعة كل يوم حتى تُتلَف، فتغرق غرفة الإشعارات خلال أسبوع
/// ويتوقف الناس عن قراءتها — وهو أسوأ من غياب الإنذار لأنه يُبطل بقية
/// الإشعارات معه.</para>
/// </summary>
public static class ExpirySweeper
{
    /// <summary>نافذة الإنذار المبكر. شهر يكفي لإرجاع بضاعة إلى مورّد أو تصريفها بخصم.</summary>
    public const int DefaultWithinDays = 30;

    public static async Task<ExpirySweepResult> SweepAsync(
        AppDbContext db, DateTime today, int withinDays = DefaultWithinDays)
    {
        var horizon = today.Date.AddDays(withinDays);

        var rows = await db.StockLevels
            .Where(s => s.Quantity > 0
                     && s.ExpiryDate != null
                     && s.ExpiryDate!.Value <= horizon)
            .Join(db.Products.Where(p => !p.IsDeleted),
                  s => s.ProductId, p => p.Id,
                  (s, p) => new
                  {
                      s.OrganizationId, s.BranchId, s.ProductId,
                      p.Name, s.BatchNumber, s.ExpiryDate, s.Quantity
                  })
            .ToListAsync();

        if (rows.Count == 0) return new ExpirySweepResult(0, 0, 0);

        var expiredCount = rows.Count(r => r.ExpiryDate!.Value.Date < today.Date);
        var expiringCount = rows.Count - expiredCount;

        // ما أُشعر به اليوم لهذا الصنف — يُقرأ مرّة واحدة لا داخل الحلقة.
        var since = today.Date;
        var alreadyNotified = await db.Notifications
            .Where(n => n.Type == "expiry" && n.CreatedAt >= since)
            .Select(n => n.Title)
            .ToListAsync();
        var seen = alreadyNotified.ToHashSet();

        var created = 0;
        foreach (var group in rows.GroupBy(r => new { r.OrganizationId, r.BranchId, r.ProductId }))
        {
            var name = group.First().Name;
            var expired = group.Where(r => r.ExpiryDate!.Value.Date < today.Date).ToList();
            var soon = group.Where(r => r.ExpiryDate!.Value.Date >= today.Date).ToList();

            // المنتهي فعلاً أولى بالذكر من المقترب: الأول بضاعة مجمَّدة لا
            // تُباع (يستبعدها تخصيص الدفعات عند البيع)، والثاني ما زال قابلاً
            // للتصريف.
            var title = expired.Count > 0
                ? $"صلاحية منتهية: {name}"
                : $"اقتراب انتهاء الصلاحية: {name}";

            if (!seen.Add(title)) continue;

            var body = expired.Count > 0
                ? $"منتهية: {expired.Sum(r => r.Quantity)} في {expired.Count} دفعة — لا تُباع حتى تُتلَف أو تُسوَّى"
                : $"تنتهي خلال {withinDays} يوماً: {soon.Sum(r => r.Quantity)} في {soon.Count} دفعة" +
                  $" (الأقرب {soon.Min(r => r.ExpiryDate)!.Value:yyyy-MM-dd})";

            db.Notifications.Add(new NotificationItem
            {
                OrganizationId = group.Key.OrganizationId,
                BranchId = group.Key.BranchId,
                Type = "expiry",
                Title = title,
                Body = body,
            });
            created++;
        }

        if (created > 0) await db.SaveChangesAsync();
        return new ExpirySweepResult(expiredCount, expiringCount, created);
    }
}

/// <summary>
/// يشغّل [ExpirySweeper] يومياً على كل المنظمات.
///
/// يفتح اتصاله الخاص ويضبط SESSION_CONTEXT لكل منظمة — لا طلب HTTP هنا فلم
/// يمرّ شيء على TenantContextMiddleware، وبدون ضبط السياق تحجب سياسات RLS كل
/// الصفوف فتمرّ المهمة صامتة بلا أثر. (نفس بنية [EntitlementSweepService].)
/// </summary>
public class ExpirySweepService : BackgroundService
{
    private readonly IConfiguration _config;
    private readonly ILogger<ExpirySweepService> _logger;

    public ExpirySweepService(IConfiguration config, ILogger<ExpirySweepService> logger)
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
                _logger.LogError(ex, "فشل فحص صلاحية المخزون");
            }

            await Task.Delay(TimeSpan.FromHours(24), stoppingToken);
        }
    }

    private async Task RunOnceAsync(CancellationToken token)
    {
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlite(_config.GetConnectionString("Default"))
            .UseSnakeCaseNamingConvention()
            .Options;

        await using var db = new AppDbContext(options);

        // platform_organizations معفى من RLS، فهو المصدر الوحيد لقائمة
        // المنظمات قبل ضبط أي سياق.
        var orgIds = await db.PlatformOrganizations
            .Where(o => o.IsActive)
            .Select(o => o.Id)
            .ToListAsync(token);

        var today = DateTime.UtcNow;
        foreach (var orgId in orgIds)
        {
            var result = await ExpirySweeper.SweepAsync(db, today);
            if (result.NotificationsCreated > 0)
            {
                _logger.LogInformation(
                    "صلاحية: {Expired} دفعة منتهية و{Expiring} مقتربة، أُنشئ {Created} إشعاراً في المنظمة {Org}",
                    result.ExpiredBatches, result.ExpiringBatches, result.NotificationsCreated, orgId);
            }
        }
    }
}
