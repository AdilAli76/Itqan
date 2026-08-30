using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace KineticEnterprise.Api.Data;

/// <summary>
/// حمولة الترخيص الموقَّعة — ما يُثبته المفتاح فعلياً.
///
/// <para>كل حدّ تجاري هنا لا في قاعدة العميل: الحدود في الجدول تُقرأ للعرض
/// والسرعة، والحمولة هي المرجع عند الخلاف.</para>
/// </summary>
public record LicensePayload(
    Guid OrganizationId,
    string Edition,
    string PlanTier,
    int MaxBranches,
    int MaxUsers,
    string[] Modules,
    DateTime ExpiresAt,
    /// <summary>بصمة الجهاز المسموح له. فارغة = ترخيص سحابي بلا تقييد جهاز.</summary>
    string? HardwareFingerprint,
    DateTime IssuedAt);

/// <summary>
/// توقيع التراخيص والتحقّق منها.
///
/// <para><b>المشكلة التي يحلّها:</b> في التركيب المحلّي يملك العميل قاعدة
/// البيانات كاملةً. وصفّ <c>licenses</c> فيها ليس حاجزاً: أمرُ
/// <c>UPDATE licenses SET expires_at = '2099-01-01', max_branches = 999</c>
/// واحد يمنحه النظام أبداً بكل وحداته. كل ما بنيناه من فرض حدود
/// (<see cref="LicenseLimits"/>) وحالة اشتراك يسقط بهذا السطر.</para>
///
/// <para><b>الحلّ:</b> توقيع غير متماثل. الحدود تُوقَّع بمفتاح **خاصّ** لا
/// يملكه إلا مالك المنصّة، ويتحقّق النظام منها بمفتاح **عامّ** مضمَّن في
/// الحزمة. تعديل أي حقل يُبطل التوقيع فوراً، وتزوير توقيع جديد يحتاج
/// المفتاح الخاصّ.</para>
///
/// <para><b>ECDsa P-256 لا RSA:</b> التوقيع 64 بايتاً بدل 256، فيبقى مفتاح
/// الترخيص نصّاً يُنسَخ في رسالة أو يُملى على الهاتف. وكلاهما مدعوم في
/// .NET بلا حزمة خارجية.</para>
///
/// <para><b>ما لا يدّعيه هذا التصميم:</b> لا يمنع من يملك الجهاز ويعدّل
/// الملف التنفيذي. لا شيء يمنع ذلك في برنامج يعمل عند العميل — والهدف أن
/// يكون التحايل **عملاً متعمّداً موثَّقاً** لا سطر SQL عابراً يفعله موظف
/// فضولي أو مبرمج يعمل عندهم.</para>
/// </summary>
public static class LicenseSigning
{
    /// <summary>يفصل الحمولة عن توقيعها في نصّ المفتاح.</summary>
    private const char Separator = '.';

    /// <summary>
    /// يوقّع حمولة بمفتاح خاصّ، ويُعيد نصّ المفتاح.
    ///
    /// <para>يُستدعى من أداة الإصدار عند مالك المنصّة وحده — لا من الخادم
    /// المنشور، فالمفتاح الخاصّ لا يسافر مع أي حزمة.</para>
    /// </summary>
    public static string Sign(LicensePayload payload, string privateKeyPem)
    {
        using var ecdsa = ECDsa.Create();
        ecdsa.ImportFromPem(privateKeyPem);

        var json = JsonSerializer.SerializeToUtf8Bytes(payload);
        var signature = ecdsa.SignData(json, HashAlgorithmName.SHA256);

        return Base64Url(json) + Separator + Base64Url(signature);
    }

    /// <summary>
    /// يتحقّق من مفتاح ويُعيد حمولته، أو NULL إن كان التوقيع باطلاً.
    ///
    /// <para>الفشل يُرجع NULL ولا يرمي: مفتاح تالف أو مقصوص عند النسخ حالة
    /// متوقّعة، ورميُ استثناء منها يُسقط الطلب بخطأ خادم بدل رسالة مفهومة.
    /// </para>
    /// </summary>
    public static LicensePayload? Verify(string? licenseKey, string publicKeyPem)
    {
        if (string.IsNullOrWhiteSpace(licenseKey)) return null;

        var parts = licenseKey.Split(Separator);
        if (parts.Length != 2) return null;

        try
        {
            var json = FromBase64Url(parts[0]);
            var signature = FromBase64Url(parts[1]);

            using var ecdsa = ECDsa.Create();
            ecdsa.ImportFromPem(publicKeyPem);

            if (!ecdsa.VerifyData(json, signature, HashAlgorithmName.SHA256)) return null;

            return JsonSerializer.Deserialize<LicensePayload>(json);
        }
        catch (Exception ex) when (ex is FormatException or CryptographicException or JsonException)
        {
            return null;
        }
    }

    /// <summary>ينشئ زوج مفاتيح جديداً. يُستدعى مرّة واحدة عند مالك المنصّة.</summary>
    public static (string PrivatePem, string PublicPem) CreateKeyPair()
    {
        using var ecdsa = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        return (
            new string(PemEncoding.Write("PRIVATE KEY", ecdsa.ExportPkcs8PrivateKey())),
            new string(PemEncoding.Write("PUBLIC KEY", ecdsa.ExportSubjectPublicKeyInfo())));
    }

    // Base64 عادي فيه '+' و'/' و'=' — وكلها تُكسر عند النسخ في رابط أو
    // رسالة. والصيغة الآمنة للروابط تُبقي المفتاح قابلاً للإرسال بأي وسيلة.
    private static string Base64Url(byte[] data) =>
        Convert.ToBase64String(data).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    private static byte[] FromBase64Url(string value)
    {
        var s = value.Replace('-', '+').Replace('_', '/');
        return Convert.FromBase64String(s.PadRight(s.Length + (4 - s.Length % 4) % 4, '='));
    }
}

/// <summary>
/// بصمة الجهاز — ما يمنع نقل ترخيص محلّي من محلّ إلى محلّ.
///
/// <para><b>لماذا MachineGuid وحده:</b> بصمة تجمع القرص واللوحة والمعالج
/// تبدو أقوى وهي **أخطر**: تبديل قرص معطوب أو ترقية ذاكرة يُبطل ترخيص عميل
/// دافع في منتصف يوم عمل، فيتحوّل الحارس إلى عطب. وMachineGuid يُولَّد عند
/// تثبيت ويندوز ويبقى ثابتاً عبر تبديل العتاد، ويتغيّر عند إعادة التثبيت أو
/// النسخ إلى جهاز آخر — وهو بالضبط الحدّ المطلوب.</para>
///
/// <para>وعلى غير ويندوز يُرجَع مُعرّف الجهاز من ملف نظام — النشر المحلّي
/// على ويندوز حصراً اليوم، والبديل موجود كي لا يفشل التطوير على غيره.</para>
/// </summary>
public static class HardwareFingerprint
{
    public static string Current()
    {
        var raw = ReadMachineId() ?? Environment.MachineName;

        // مجزّأ لا خام: المعرّف نفسه بيانات نظام لا داعي لظهورها في مفتاح
        // يُرسَل في رسالة، والتجزئة تُثبّت الطول أيضاً.
        var hash = SHA256.HashData(Encoding.UTF8.GetBytes("kinetic:" + raw));
        return Convert.ToHexString(hash)[..24];
    }

    private static string? ReadMachineId()
    {
        if (OperatingSystem.IsWindows())
        {
            try
            {
                using var key = Microsoft.Win32.Registry.LocalMachine
                    .OpenSubKey(@"SOFTWARE\Microsoft\Cryptography");
                return key?.GetValue("MachineGuid") as string;
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                return null;
            }
        }

        foreach (var path in new[] { "/etc/machine-id", "/var/lib/dbus/machine-id" })
        {
            if (File.Exists(path)) return File.ReadAllText(path).Trim();
        }
        return null;
    }
}
