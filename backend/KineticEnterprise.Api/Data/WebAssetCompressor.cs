using System.IO.Compression;

namespace KineticEnterprise.Api.Data;

/// <summary>
/// يضغط أصول الويب مرّة واحدة وقت البناء بأقصى جودة.
///
/// <para><b>لماذا هنا لا في publish.ps1:</b> <c>BrotliStream</c> غير موجود
/// في Windows PowerShell 5.1 (يحتاج .NET Core)، وهو الإصدار المثبَّت على
/// أجهزة ويندوز افتراضياً. وهذا المشروع يستهدف .NET 8 حيث الصنف متاح —
/// فالأمر يُنفَّذ من الحزمة نفسها ولا يفرض تثبيت PowerShell 7.</para>
///
/// <para><b>ولماذا وقت البناء لا وقت الطلب:</b> القياس على main.dart.js —
/// خام 5476 كيلوبايت، وبالضغط اللحظي السريع 1949، وبأقصى جودة نحو 1100.
/// والأقصى لحظياً يستغرق ثوانيَ على ملف بهذا الحجم **في كل طلب**، فيصبح
/// العلاج أسوأ من الداء. الضغط مرّة واحدة يعطي أفضل حجم بلا أي معالجة عند
/// الزائر.</para>
///
/// <para>يقدّمها الخادم لمن يقبلها — راجع الوسيط في <c>Program.cs</c>.</para>
/// </summary>
public static class WebAssetCompressor
{
    public const string CommandName = "compress-web";

    /// <summary>
    /// أقلّ من كيلوبايت لا يُضغط: ترويسات الاستجابة وحدها تقارب حجمه،
    /// والمكسب يتحوّل إلى خسارة.
    /// </summary>
    private const int MinBytes = 1024;

    private static readonly HashSet<string> Compressible = new(StringComparer.OrdinalIgnoreCase)
    {
        ".js", ".wasm", ".json", ".css", ".html", ".svg", ".ttf", ".otf", ".map",
    };

    public static int Run(string[] args)
    {
        var root = args.Length > 1 ? args[1] : "wwwroot";
        if (!Directory.Exists(root))
        {
            Console.Error.WriteLine($"مجلد الأصول غير موجود: {root}");
            return 1;
        }

        long before = 0, afterBr = 0, afterGz = 0;
        var count = 0;

        foreach (var file in Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories))
        {
            var ext = Path.GetExtension(file);
            // الملفات المضغوطة سلفاً تُتخطّى: إعادة تشغيل الأمر يجب ألّا
            // تُنتج main.dart.js.br.br.
            if (ext is ".br" or ".gz" || !Compressible.Contains(ext)) continue;

            var bytes = File.ReadAllBytes(file);
            if (bytes.Length < MinBytes) continue;

            before += bytes.Length;
            afterBr += Write(file + ".br", bytes, br: true);
            afterGz += Write(file + ".gz", bytes, br: false);
            count++;
        }

        if (count == 0)
        {
            Console.WriteLine("لا أصول قابلة للضغط.");
            return 0;
        }

        Console.WriteLine(
            $"ضُغط {count} ملفاً: {before / 1024.0 / 1024:N1} ميغابايت ← " +
            $"{afterBr / 1024.0 / 1024:N1} بـBrotli ({100 - 100.0 * afterBr / before:N0}٪ أقلّ) " +
            $"و{afterGz / 1024.0 / 1024:N1} بـGzip");
        return 0;
    }

    private static long Write(string path, byte[] bytes, bool br)
    {
        using var output = new MemoryStream();
        // SmallestSize لا Optimal: الفارق بينهما في brotli كبير (جودة 11
        // مقابل 4)، والثمن يُدفع مرّة واحدة هنا لا عند كل زائر.
        using (Stream stream = br
            ? new BrotliStream(output, CompressionLevel.SmallestSize, leaveOpen: true)
            : new GZipStream(output, CompressionLevel.SmallestSize, leaveOpen: true))
        {
            stream.Write(bytes, 0, bytes.Length);
        }

        var data = output.ToArray();
        File.WriteAllBytes(path, data);
        return data.Length;
    }
}
