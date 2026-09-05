using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Data;

/// <summary>
/// بناء النسخة ورفعها إلى درايف المنظمة — خطوةٌ واحدة يستدعيها الرفع
/// الليلي وزرُّ «إلى درايف» في لوحة التحكّم.
///
/// <para><b>ولماذا مشتركة:</b> نسختان من نفس المنطق تفترقان: تُصلَح ثغرةُ
/// عزلٍ في إحداهما وتبقى في الأخرى — وهي التي تعمل بلا أحد ينظر. راجع
/// [BackupArchive] لنفس السبب.</para>
/// </summary>
public static class GoogleBackupUploader
{
    /// <param name="db">سياقٌ ضُبط عليه <c>SESSION_CONTEXT</c> للمنظمة سلفاً.</param>
    /// <returns>حجم الملف المرفوع بالبايت.</returns>
    public static async Task<long> UploadAsync(
        AppDbContext db, Organization org, GoogleOptions options, HttpClient http,
        CancellationToken token = default)
    {
        if (string.IsNullOrEmpty(org.GoogleRefreshToken))
            throw new InvalidOperationException("لا حساب قوقل مربوط");

        var accessToken = await GoogleDrive.AccessTokenAsync(http, options, org.GoogleRefreshToken, token);

        if (string.IsNullOrEmpty(org.GoogleFolderId))
        {
            org.GoogleFolderId = await GoogleDrive.EnsureFolderAsync(
                http, accessToken, $"نسخ Kinetic — {org.DisplayName}", token);
        }

        // ملفٌ مؤقّت لا ذاكرة: النسخة قد تبلغ عشرات الميغابايتات، وحملُها في
        // ذاكرة الخادم يزاحمه وهو يبيع.
        var tempPath = Path.Combine(Path.GetTempPath(), $"kinetic-backup-{Guid.NewGuid():N}.zip");
        try
        {
            var connection = db.Database.GetDbConnection();
            var plan = await BackupArchive.PlanAsync(db, connection);

            await using (var file = File.Create(tempPath))
            {
                await BackupArchive.WriteAsync(
                    connection,
                    new BackupOrg(org.Id, org.DisplayName, org.LegalName, org.Edition),
                    plan,
                    file);
            }

            var size = new FileInfo(tempPath).Length;
            var stamp = OrgClock.Now(org).ToString("yyyy-MM-dd-HHmm");

            await using (var upload = File.OpenRead(tempPath))
            {
                await GoogleDrive.UploadAsync(
                    http, accessToken, org.GoogleFolderId!, $"kinetic-backup-{stamp}.zip", upload, token);
            }

            org.LastAutoBackupAt = DateTime.UtcNow;
            org.LastAutoBackupStatus = "ok";
            org.LastAutoBackupError = null;
            return size;
        }
        finally
        {
            // يُحذف ولو فشل الرفع: نسخةٌ كاملة بكل البيانات متروكةً في مجلّد
            // مؤقّت على الخادم تسريبٌ ينتظر.
            if (File.Exists(tempPath)) File.Delete(tempPath);
        }
    }
}
