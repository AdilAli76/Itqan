using System.Text.Json;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Data;

/// <summary>
/// أوامر الترخيص على سطر الأوامر — لمالك المنصّة وحده.
///
/// <para><b>لماذا أوامر لا نقاط HTTP:</b> التوقيع يحتاج المفتاح الخاصّ،
/// والمفتاح الخاصّ **لا يسافر مع أي حزمة ولا يوضع على خادم عميل**. من ملكه
/// أصدر لنفسه ترخيصاً أبدياً بكل الوحدات — فتسقط المنظومة كلّها. فتبقى
/// عملية الإصدار على جهاز مالك المنصّة وحده.</para>
///
/// <para>وهو نفس سبب كون <c>create-platform-owner</c> أمراً على السيرفر لا
/// نقطة نهاية — راجع [PlatformOwnerBootstrap].</para>
/// </summary>
public static class LicenseCommands
{
    public const string KeyPairCommand = "license-keypair";
    public const string FingerprintCommand = "machine-fingerprint";
    public const string IssueCommand = "issue-license";

    public static bool Handles(string command) =>
        command is KeyPairCommand or FingerprintCommand or IssueCommand;

    public static int Run(string[] args) => args[0] switch
    {
        KeyPairCommand => KeyPair(),
        FingerprintCommand => Fingerprint(),
        IssueCommand => Issue(args),
        _ => 1,
    };

    /// <summary>ينشئ زوج مفاتيح — مرّة واحدة في عمر المنتج.</summary>
    private static int KeyPair()
    {
        var (privatePem, publicPem) = LicenseSigning.CreateKeyPair();

        Console.WriteLine();
        Console.WriteLine("═══ المفتاح الخاصّ — لا يُنشر ولا يُرفع إلى Git ولا يُوضع على خادم عميل ═══");
        Console.WriteLine();
        Console.WriteLine(privatePem);
        Console.WriteLine();
        Console.WriteLine("احفظه في مكان آمن ومنسوخ احتياطياً. **ضياعه يعني تعذّر إصدار أي");
        Console.WriteLine("ترخيص جديد**، وتسرّبه يعني أن أي أحد يصدر لنفسه ترخيصاً أبدياً.");
        Console.WriteLine();
        Console.WriteLine("═══ المفتاح العامّ — يوضع في appsettings تحت License:PublicKey ═══");
        Console.WriteLine();
        Console.WriteLine(publicPem);
        Console.WriteLine();
        Console.WriteLine("مفتاح واحد لكل نسخك: تغييره يُبطل كل التراخيص المُصدَرة قبله.");
        Console.WriteLine();
        return 0;
    }

    /// <summary>يطبع بصمة هذا الجهاز — تُشغَّل على جهاز العميل ويُرسَل ناتجها.</summary>
    private static int Fingerprint()
    {
        Console.WriteLine();
        Console.WriteLine("بصمة هذا الجهاز:");
        Console.WriteLine();
        Console.WriteLine("    " + HardwareFingerprint.Current());
        Console.WriteLine();
        Console.WriteLine("أرسلها لإصدار ترخيص مرتبط بهذا الجهاز. وهي مشتقّة من معرّف");
        Console.WriteLine("تثبيت ويندوز: تبقى ثابتة عبر تبديل العتاد، وتتغيّر عند إعادة");
        Console.WriteLine("تثبيت النظام أو نقله إلى جهاز آخر.");
        Console.WriteLine();
        return 0;
    }

    /// <summary>
    /// يُصدر مفتاح ترخيص موقَّعاً.
    ///
    /// <para>الوسائط تُمرَّر كأزواج <c>--اسم قيمة</c>. المفتاح الخاصّ يُقرأ
    /// من ملف لا من وسيط سطر أوامر: الوسائط تُسجَّل في تاريخ الأوامر وفي
    /// قائمة العمليات، وسرٌّ يظهر هناك ليس سرّاً.</para>
    /// </summary>
    private static int Issue(string[] args)
    {
        var options = ParseOptions(args);

        if (!options.TryGetValue("key-file", out var keyFile) || !File.Exists(keyFile))
        {
            Console.Error.WriteLine("مطلوب --key-file مساراً لملف المفتاح الخاصّ.");
            PrintUsage();
            return 1;
        }
        if (!options.TryGetValue("org", out var orgRaw) || !Guid.TryParse(orgRaw, out var orgId))
        {
            Console.Error.WriteLine("مطلوب --org معرّف المنظمة (GUID).");
            PrintUsage();
            return 1;
        }

        var edition = options.GetValueOrDefault("edition", Editions.Standard);
        if (!Editions.All.Contains(edition))
        {
            Console.Error.WriteLine($"إصدار غير معروف: {edition}. المتاح: {string.Join(", ", Editions.All)}");
            return 1;
        }

        var months = int.TryParse(options.GetValueOrDefault("months", "12"), out var m) ? m : 12;
        var maxBranches = int.TryParse(options.GetValueOrDefault("branches", "1"), out var b) ? b : 1;
        var maxUsers = int.TryParse(options.GetValueOrDefault("users", "5"), out var u) ? u : 5;
        var fingerprint = options.GetValueOrDefault("fingerprint");

        var payload = new LicensePayload(
            OrganizationId: orgId,
            Edition: edition,
            PlanTier: options.GetValueOrDefault("plan", "standard"),
            MaxBranches: maxBranches,
            MaxUsers: maxUsers,
            Modules: Editions.ModulesOf(edition),
            ExpiresAt: DateTime.UtcNow.Date.AddMonths(months),
            // فارغة = ترخيص سحابي يعمل على أي خادم. وتُملأ للتركيب المحلّي
            // حيث القاعدة بيد العميل.
            HardwareFingerprint: string.IsNullOrWhiteSpace(fingerprint) ? null : fingerprint.Trim(),
            IssuedAt: DateTime.UtcNow);

        var key = LicenseSigning.Sign(payload, File.ReadAllText(keyFile));

        Console.WriteLine();
        Console.WriteLine("═══ مفتاح الترخيص ═══");
        Console.WriteLine();
        Console.WriteLine(key);
        Console.WriteLine();
        Console.WriteLine("الحمولة الموقَّعة:");
        Console.WriteLine(JsonSerializer.Serialize(payload, new JsonSerializerOptions
        {
            WriteIndented = true,
            Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        }));
        Console.WriteLine();
        Console.WriteLine("ضعه في licenses.license_key للمنظمة، ثم أعد تشغيل مجمّع التطبيقات");
        Console.WriteLine("(أو انتظر خمس دقائق — النتيجة محفوظة مؤقّتاً بهذه المدّة).");
        Console.WriteLine();
        return 0;
    }

    private static Dictionary<string, string> ParseOptions(string[] args)
    {
        var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        for (var i = 1; i < args.Length - 1; i++)
        {
            if (args[i].StartsWith("--")) result[args[i][2..]] = args[i + 1];
        }
        return result;
    }

    private static void PrintUsage()
    {
        Console.Error.WriteLine();
        Console.Error.WriteLine("الاستعمال:");
        Console.Error.WriteLine("  issue-license --key-file <مسار> --org <GUID> [--edition standard]");
        Console.Error.WriteLine("                [--plan standard] [--months 12] [--branches 1]");
        Console.Error.WriteLine("                [--users 5] [--fingerprint <بصمة الجهاز>]");
        Console.Error.WriteLine();
    }
}
