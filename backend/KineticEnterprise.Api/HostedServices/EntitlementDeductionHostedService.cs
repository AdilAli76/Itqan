using KineticEnterprise.Api.Services;

namespace KineticEnterprise.Api.HostedServices;

/// <summary>
/// خدمة خلفية تشغّل معالج الخصم الشهري يومياً.
/// يعمل في الوقت المحدد لتجنب تأثر الأداء في ساعات الذروة.
/// </summary>
public class EntitlementDeductionHostedService : BackgroundService
{
    private readonly ILogger<EntitlementDeductionHostedService> _logger;
    private readonly IServiceProvider _serviceProvider;
    private Timer? _timer;

    public EntitlementDeductionHostedService(
        ILogger<EntitlementDeductionHostedService> logger,
        IServiceProvider serviceProvider)
    {
        _logger = logger;
        _serviceProvider = serviceProvider;
    }

    protected override Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("بدء خدمة معالج الخصم الشهري");

        // الجدول اليومي: الساعة 02:00 صباحاً (بتوقيت UTC)
        var now = DateTime.UtcNow;
        var scheduledTime = now.Date.AddHours(2);
        if (now > scheduledTime)
            scheduledTime = scheduledTime.AddDays(1);

        var delay = scheduledTime - now;
        _logger.LogInformation($"الخصم الأول جدول له في {delay.TotalHours:F1} ساعة");

        _timer = new Timer(
            callback: _ => _ = ExecuteDeductionAsync(),
            state: null,
            dueTime: delay,
            period: TimeSpan.FromHours(24)
        );

        return Task.CompletedTask;
    }

    private async Task ExecuteDeductionAsync()
    {
        try
        {
            _logger.LogInformation("بدء تشغيل الخصم الشهري المجدول");

            using (var scope = _serviceProvider.CreateScope())
            {
                var deductionService = scope.ServiceProvider.GetRequiredService<EntitlementDeductionService>();
                await deductionService.ProcessDailyDeductionsAsync();
            }

            _logger.LogInformation("انتهى تشغيل الخصم الشهري المجدول بنجاح");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تشغيل الخصم الشهري المجدول");
        }
    }

    public override async Task StopAsync(CancellationToken cancellationToken)
    {
        _logger.LogInformation("إيقاف خدمة معالج الخصم الشهري");
        _timer?.Dispose();
        await base.StopAsync(cancellationToken);
    }
}
