using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Data;

public record DebtSweepResult(int OverdueCustomers, decimal OverdueAmount, int NotificationsCreated);

/// <summary>
/// إشعار يومي بالديون المتأخّرة — نوع <c>overdue_debt</c>.
///
/// <para><b>لماذا لا يُرسل التذكير آلياً:</b> النظام لا يملك قناة إرسال
/// (رسالة أو اتصال)، وادّعاء الإرسال أسوأ من عدمه. فهو يُنبّه **صاحب
/// المتجر** بمن يجب أن يُطالِبه، ويُسجَّل التذكير حين يُرسله إنسان فعلاً
/// (راجع [DebtReminder] وCustomersController.RecordDebtReminder).</para>
///
/// <para><b>منع الإغراق:</b> إشعار واحد لكل عميل في اليوم، وعند **تغيّر
/// المرحلة** فقط بعد ذلك. بلا هذا يمتلئ الإشعارات بنفس الأسماء كل صباح حتى
/// يتوقّف الناس عن قراءتها — فيُبطل بقية الإشعارات معه، وهو أسوأ من غياب
/// الإنذار. نفس درس [ExpirySweeper].</para>
/// </summary>
public static class DebtReminderSweeper
{
    public const string NotificationType = "overdue_debt";

    public static async Task<DebtSweepResult> SweepAsync(AppDbContext db, DateTime today)
    {
        var aging = await DebtAging.ComputeAsync(db, today);

        // المتأخّر وحده: من لم يحلّ أجله بعد ليس مديناً متأخّراً، وإشعاره
        // اليوم يُعلّم المستخدم أن هذه الإشعارات لا تعني شيئاً.
        var overdue = aging.Where(a => a.Stage > 0).ToList();
        if (overdue.Count == 0) return new DebtSweepResult(0, 0, 0);

        var since = today.Date;
        var notifiedToday = (await db.Notifications
                .Where(n => n.Type == NotificationType && n.CreatedAt >= since)
                .Select(n => n.Title)
                .ToListAsync())
            .ToHashSet();

        var created = 0;
        foreach (var row in overdue)
        {
            // العنوان يحمل المرحلة: تصعيدُ العميل من الثانية إلى الثالثة حدثٌ
            // جديد يستحقّ إشعاراً، بخلاف بقائه في مرحلته.
            var title = $"دين متأخّر (مرحلة {row.Stage}): {row.CustomerName}";
            if (!notifiedToday.Add(title)) continue;

            db.Notifications.Add(new NotificationItem
            {
                OrganizationId = await OrganizationOfAsync(db, row.CustomerId),
                Type = NotificationType,
                Title = title,
                Body = $"المستحقّ {row.TotalOutstanding:0.##} — متأخّر {row.DaysOverdue} يوماً"
                     + (string.IsNullOrWhiteSpace(row.Phone) ? "" : $" — هاتف: {row.Phone}"),
            });
            created++;
        }

        if (created > 0) await db.SaveChangesAsync();

        return new DebtSweepResult(overdue.Count, overdue.Sum(o => o.TotalOutstanding), created);
    }

    private static async Task<Guid> OrganizationOfAsync(AppDbContext db, Guid customerId) =>
        await db.Customers.Where(c => c.Id == customerId).Select(c => c.OrganizationId).FirstAsync();
}

/// <summary>مهمة يومية — نفس نمط [ExpirySweepService].</summary>
public class DebtReminderSweepService : BackgroundService
{
    private readonly IConfiguration _config;
    private readonly ILogger<DebtReminderSweepService> _logger;

    public DebtReminderSweepService(IConfiguration config, ILogger<DebtReminderSweepService> logger)
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
                _logger.LogError(ex, "فشل فحص الديون المتأخّرة");
            }

            await Task.Delay(TimeSpan.FromHours(24), stoppingToken);
        }
    }

    private async Task RunOnceAsync(CancellationToken token)
    {
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlServer(_config.GetConnectionString("Default"))
            .UseSnakeCaseNamingConvention()
            .Options;

        await using var db = new AppDbContext(options);

        var orgIds = await db.PlatformOrganizations
            .Where(o => o.IsActive)
            .Select(o => o.Id)
            .ToListAsync(token);

        var today = DateTime.UtcNow;
        foreach (var orgId in orgIds)
        {
            var connection = db.Database.GetDbConnection();
            if (connection.State != System.Data.ConnectionState.Open)
            {
                await connection.OpenAsync(token);
            }
            await using (var cmd = connection.CreateCommand())
            {
                cmd.CommandText = "EXEC sp_set_session_context @key=N'organization_id', @value=@orgId;";
                cmd.Parameters.Add(new SqlParameter("@orgId", orgId));
                await cmd.ExecuteNonQueryAsync(token);
            }

            var result = await DebtReminderSweeper.SweepAsync(db, today);
            if (result.NotificationsCreated > 0)
            {
                _logger.LogInformation(
                    "ديون: {Count} عميلاً متأخّراً بمجموع {Amount}، أُنشئ {Created} إشعاراً في المنظمة {Org}",
                    result.OverdueCustomers, result.OverdueAmount, result.NotificationsCreated, orgId);
            }
        }
    }
}
