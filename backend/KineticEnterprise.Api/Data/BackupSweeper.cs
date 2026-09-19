using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Data;

/// <summary>
/// النسخة الليلية: تُبنى وتُرفع إلى درايف المنظمة بلا أن يفتح أحد التطبيق.
///
/// <para><b>سبب وجودها:</b> النسخة اليدوية تعتمد على أن يتذكّرها إنسان —
/// يتذكّرها شهراً ثم ينسى، ولا يكتشف نسيانه إلا يوم يحتاجها. والجهةُ التي
/// تُسلَّم لها الأداة تظنّ أن «فيه نسخ احتياطي» يعني أن النسخ يحدث.</para>
///
/// <para><b>وتفتح اتصالها وتضبط SESSION_CONTEXT لكل منظمة</b> — لا طلب HTTP
/// هنا فلم يمرّ شيء على [TenantContextMiddleware]، وبلا ضبط السياق تحجب
/// سياسات العزل كل الصفوف فتمرّ المهمّة صامتة بلا أثر (نفس نهج
/// [EntitlementSweepService]).</para>
///
/// <para><b>وتدور كل ساعة لا كل أربع وعشرين:</b> الساعة المضبوطة بتوقيت
/// المنظمة، ومنظمتان في منطقتين مختلفتين لا تشتركان في لحظة واحدة. ودورةٌ
/// يومية واحدة كانت تعني أن كل منظمة تُنسَخ حين يصادف تشغيل الخادم لا حين
/// طلبت.</para>
/// </summary>
public class BackupSweepService : BackgroundService
{
    private readonly IConfiguration _config;
    private readonly IHttpClientFactory _http;
    private readonly ILogger<BackupSweepService> _logger;

    public BackupSweepService(
        IConfiguration config, IHttpClientFactory http, ILogger<BackupSweepService> logger)
    {
        _config = config;
        _http = http;
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
                // فشلٌ عام لا يُسقط الخادم — يُسجَّل وتُعاد المحاولة بعد ساعة.
                _logger.LogError(ex, "فشلت دورة النسخ الاحتياطي التلقائي");
            }

            await Task.Delay(TimeSpan.FromHours(1), stoppingToken);
        }
    }

    async Task RunOnceAsync(CancellationToken token)
    {
        var options = GoogleOptions.From(_config);
        // خادمٌ بلا بيانات اعتماد قوقل: لا شيء يُفعل، ولا رسالة تُكرَّر كل
        // ساعة في السجلّ.
        if (!options.Configured) return;

        var connectionString = _config.GetConnectionString("Default");
        var dbOptions = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlite(connectionString)
            .UseSnakeCaseNamingConvention()
            .Options;

        await using var db = new AppDbContext(dbOptions);

        // platform_organizations معفى من العزل، فهو المصدر الوحيد لقائمة
        // المنظمات قبل ضبط أي سياق.
        var orgIds = await db.PlatformOrganizations
            .Where(o => o.IsActive)
            .Select(o => o.Id)
            .ToListAsync(token);

        foreach (var orgId in orgIds)
        {
            if (token.IsCancellationRequested) return;
            try
            {
                await SweepOrganizationAsync(db, orgId, options, token);
            }
            catch (Exception ex)
            {
                // منظمةٌ تفشل لا توقف البقيّة: فشلُ درايف عند عميل واحد كان
                // سيمنع نسخ كل العملاء بعده في نفس الدورة.
                _logger.LogError(ex, "تعذّر رفع نسخة المنظمة {OrgId}", orgId);
                await RecordFailureAsync(db, orgId, ex.Message, token);
            }
        }
    }

    async Task SweepOrganizationAsync(
        AppDbContext db, Guid orgId, GoogleOptions options, CancellationToken token)
    {
        await SetContextAsync(db, orgId, token);

        var org = await db.Organizations.FirstOrDefaultAsync(token);
        if (org is null || !org.AutoBackupEnabled || string.IsNullOrEmpty(org.GoogleRefreshToken)) return;

        var now = OrgClock.Now(org);
        if (now.Hour != org.AutoBackupHour) return;

        // نسخةٌ واحدة في اليوم: الدورة تمرّ كل ساعة، وبلا هذا الشرط تُرفع
        // نسخةٌ في كل مرور داخل الساعة نفسها إن أُعيد تشغيل الخادم.
        if (org.LastAutoBackupAt is not null)
        {
            var last = TimeZoneInfo.ConvertTimeFromUtc(org.LastAutoBackupAt.Value, OrgClock.Zone(org));
            if (last.Date == now.Date) return;
        }

        var http = _http.CreateClient();
        var size = await GoogleBackupUploader.UploadAsync(db, org, options, http, token);

        db.LogAudit(org.Id, null, "backup.auto_uploaded", "organizations", org.Id,
            newValues: new { At = DateTime.UtcNow, Bytes = size });
        await db.SaveChangesAsync(token);
        _logger.LogInformation("رُفعت نسخة {Org} إلى درايف", org.DisplayName);
    }

    /// <summary>
    /// يسجّل سبب الفشل في صفّ المنظمة ليظهر في شاشة الإعدادات.
    ///
    /// <para>رفعٌ يفشل ليلةً بعد ليلة بلا أثر في الشاشة أسوأ من ألّا يكون
    /// هناك رفع: المالك يظنّ نفسه محميّاً.</para>
    /// </summary>
    async Task RecordFailureAsync(AppDbContext db, Guid orgId, string message, CancellationToken token)
    {
        try
        {
            await SetContextAsync(db, orgId, token);
            var org = await db.Organizations.FirstOrDefaultAsync(token);
            if (org is null) return;

            org.LastAutoBackupStatus = "failed";
            org.LastAutoBackupError = message.Length > 500 ? message[..500] : message;
            await db.SaveChangesAsync(token);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "تعذّر تسجيل فشل النسخ للمنظمة {OrgId}", orgId);
        }
    }

    static async Task SetContextAsync(AppDbContext db, Guid orgId, CancellationToken token)
    {
        // SQLite doesn't have stored procedures, just return
        await Task.CompletedTask;
    }
}
