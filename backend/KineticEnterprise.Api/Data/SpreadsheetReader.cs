using System.Text;
using ClosedXML.Excel;

namespace KineticEnterprise.Api.Data;

/// <summary>
/// قارئ جداول موحّد: يحوّل ملف .xlsx أو .csv إلى صفوف قواميس مفاتيحها
/// أسماء الأعمدة كما كتبها المستخدم في السطر الأول.
///
/// لماذا القراءة على السيرفر لا في التطبيق: قواعد التحقق (تكرار SKU، وجود
/// المورّد، صحة الأرقام) تعيش في السيرفر أصلاً، ونسخ منطق القراءة إلى
/// Flutter كان يعني قاعدتين للتحقق تختلفان مع الوقت. وأي عميل آخر مستقبلاً
/// (ويب، تكامل خارجي) يستفيد من نفس النقطة.
/// </summary>
public static class SpreadsheetReader
{
    /// <summary>حد أعلى للصفوف يمنع ملفاً ضخماً من استهلاك ذاكرة السيرفر.</summary>
    public const int MaxRows = 5000;

    public static List<Dictionary<string, string>> Read(Stream stream, string fileName)
    {
        var extension = Path.GetExtension(fileName).ToLowerInvariant();
        return extension switch
        {
            ".csv" or ".txt" => ReadCsv(stream),
            ".xlsx" or ".xlsm" => ReadExcel(stream),
            _ => throw new NotSupportedException(
                "صيغة الملف غير مدعومة — استخدم ‎.xlsx أو ‎.csv"),
        };
    }

    static List<Dictionary<string, string>> ReadExcel(Stream stream)
    {
        using var workbook = new XLWorkbook(stream);
        var sheet = workbook.Worksheets.FirstOrDefault()
            ?? throw new InvalidDataException("الملف لا يحتوي على أي ورقة عمل");

        var used = sheet.RangeUsed();
        if (used is null) return new List<Dictionary<string, string>>();

        var rows = used.RowsUsed().ToList();
        if (rows.Count < 2) return new List<Dictionary<string, string>>();

        var headers = rows[0].Cells().Select(c => Normalize(c.GetString())).ToList();
        var result = new List<Dictionary<string, string>>();

        foreach (var row in rows.Skip(1).Take(MaxRows))
        {
            var record = new Dictionary<string, string>(HeaderComparer.Instance);
            for (var i = 0; i < headers.Count; i++)
            {
                if (string.IsNullOrWhiteSpace(headers[i])) continue;
                // GetFormattedString يقرأ القيمة كما تظهر للمستخدم، فالتاريخ
                // والرقم المنسَّق لا يعودان رقماً تسلسلياً غامضاً.
                record[headers[i]] = row.Cell(i + 1).GetFormattedString().Trim();
            }
            if (record.Values.Any(v => !string.IsNullOrWhiteSpace(v))) result.Add(record);
        }
        return result;
    }

    static List<Dictionary<string, string>> ReadCsv(Stream stream)
    {
        // UTF8 مع كشف علامة الترتيب: ملفات إكسل العربية تُحفَظ غالباً بـ BOM،
        // وقراءتها بترميز النظام تُنتج نصاً عربياً تالفاً بلا أي خطأ.
        using var reader = new StreamReader(stream, Encoding.UTF8, detectEncodingFromByteOrderMarks: true);

        var lines = new List<string>();
        while (!reader.EndOfStream && lines.Count <= MaxRows + 1)
        {
            var line = reader.ReadLine();
            if (line is not null) lines.Add(line);
        }
        if (lines.Count < 2) return new List<Dictionary<string, string>>();

        var separator = DetectSeparator(lines[0]);
        var headers = SplitCsvLine(lines[0], separator).Select(Normalize).ToList();
        var result = new List<Dictionary<string, string>>();

        foreach (var line in lines.Skip(1))
        {
            if (string.IsNullOrWhiteSpace(line)) continue;
            var cells = SplitCsvLine(line, separator);
            var record = new Dictionary<string, string>(HeaderComparer.Instance);
            for (var i = 0; i < headers.Count && i < cells.Count; i++)
            {
                if (string.IsNullOrWhiteSpace(headers[i])) continue;
                record[headers[i]] = cells[i].Trim();
            }
            if (record.Values.Any(v => !string.IsNullOrWhiteSpace(v))) result.Add(record);
        }
        return result;
    }

    /// <summary>
    /// إكسل على ويندوز العربي يحفظ CSV بفاصلة منقوطة لا فاصلة، لأن الفاصلة
    /// تُستعمل فاصلاً عشرياً في بعض الإعدادات المحلية. الكشف من سطر العناوين
    /// بدل فرض فاصل واحد يجنّب المستخدم ملفاً "لا يعمل" بلا سبب ظاهر.
    /// </summary>
    static char DetectSeparator(string headerLine)
    {
        var semicolons = headerLine.Count(c => c == ';');
        var commas = headerLine.Count(c => c == ',');
        var tabs = headerLine.Count(c => c == '\t');
        if (tabs > semicolons && tabs > commas) return '\t';
        return semicolons > commas ? ';' : ',';
    }

    static List<string> SplitCsvLine(string line, char separator)
    {
        var cells = new List<string>();
        var current = new StringBuilder();
        var inQuotes = false;

        for (var i = 0; i < line.Length; i++)
        {
            var c = line[i];
            if (c == '"')
            {
                // "" داخل حقل مقتبس = علامة اقتباس واحدة
                if (inQuotes && i + 1 < line.Length && line[i + 1] == '"')
                {
                    current.Append('"');
                    i++;
                }
                else
                {
                    inQuotes = !inQuotes;
                }
            }
            else if (c == separator && !inQuotes)
            {
                cells.Add(current.ToString());
                current.Clear();
            }
            else
            {
                current.Append(c);
            }
        }
        cells.Add(current.ToString());
        return cells;
    }

    /// <summary>
    /// توحيد اسم العمود: إزالة المسافات الزائدة والمحارف غير المرئية.
    /// أسماء الأعمدة تأتي من ملف كتبه محاسب، لا من واجهة برمجية منضبطة.
    /// </summary>
    static string Normalize(string value) =>
        value.Replace("‏", "").Replace("‎", "").Replace("﻿", "").Trim();

    /// <summary>
    /// توحيد نصٍّ عربي للمطابقة وحدها — لا للعرض ولا للتخزين.
    ///
    /// <para><b>العطب الذي يمنعه:</b> عناوين الأعمدة وأسماء الفئات والفروع
    /// يكتبها إنسانٌ في إكسل، لا واجهةٌ برمجية. فمن كتب «الإسم» بهمزة —
    /// وهي أشيع من «الاسم» في كشوف الجهات — كان يُطابَق حرفياً فلا يُطابِق،
    /// فيخرج عمود الأسماء غير معروف، **فيفشل كل صفٍّ في الملف** برسالة
    /// «الاسم مطلوب» واسمٍ فارغ. ومن رفع ملفاً كهذا يرى ألف خطأ لا يدلّ
    /// أيٌّ منها على السبب الواحد.</para>
    ///
    /// <para>فتُوحَّد صور الهمزة والألف، والتاء المربوطة بالهاء، والألف
    /// المقصورة بالياء، وتُحذف الحركات والتطويل، وتُحوَّل الأرقام
    /// العربية-الهندية، وتُطوى المسافات المتكرّرة والمسافة غير الفاصلة.</para>
    /// </summary>
    public static string Fold(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return "";

        var sb = new StringBuilder(value.Length);
        var lastWasSpace = true; // يبتلع مسافات البداية

        foreach (var raw in Normalize(value))
        {
            var c = raw;

            // الحركات والتطويل: زينةٌ في الكتابة لا معنى لها في المطابقة.
            if (c == 'ـ') continue;                       // تطويل
            if (c >= 'ً' && c <= 'ْ') continue;      // فتحة..سكون
            if (c == 'ٰ' || c == 'ٓ' || c == 'ٔ' || c == 'ٕ') continue;

            c = c switch
            {
                'أ' or 'إ' or 'آ' or 'ٱ' => 'ا', // أ إ آ ٱ => ا
                'ة' => 'ه',                                     // ة => ه
                'ى' => 'ي',                                     // ى => ي
                'ؤ' => 'و',                                     // ؤ => و
                'ئ' => 'ي',                                     // ئ => ي
                _ => c,
            };

            if (c >= '٠' && c <= '٩') c = (char)(c - '٠' + '0'); // ٠-٩
            else if (c >= '۰' && c <= '۹') c = (char)(c - '۰' + '0'); // ۰-۹

            // المسافة غير الفاصلة تأتي من النسخ عن الويب ولا تُرى بالعين.
            if (char.IsWhiteSpace(c) || c == ' ')
            {
                if (!lastWasSpace) { sb.Append(' '); lastWasSpace = true; }
                continue;
            }

            sb.Append(char.ToLowerInvariant(c));
            lastWasSpace = false;
        }

        return sb.ToString().TrimEnd();
    }

    /// <summary>كلمات الوصف التي يسبق بها الناس الاسم — تُسقَط في [FoldLoose] وحده.</summary>
    static readonly string[] LabelWords =
    {
        "الفئة", "فئة", "التصنيف", "تصنيف", "الدرجة", "درجة", "الفرع", "فرع",
        "category", "grade", "branch", "class",
    };

    /// <summary>
    /// طيٌّ أوسع من <see cref="Fold"/>: يُسقط كلمة الوصف البادئة و«ال»
    /// التعريف.
    ///
    /// <para><b>العطب الذي يمنعه:</b> الإدارة تسمّي الفئة «ب» في الشاشة،
    /// ومن يعبّئ كشف المنتسبين يكتب في عمود «الفئة» كلمة «الفئة ب» — وهما
    /// عنده شيءٌ واحد، فيسقط ملفُه كلّه. و<see cref="Fold"/> وحده لا يمسك
    /// هذه لأن الفرق ليس في رسم الحرف بل في كلمةٍ زائدة.</para>
    ///
    /// <para><b>ولا يُطابَق به إلا اسمٌ واحد:</b> الفئة تحمل مرتَّباً،
    /// وإسنادُ منتسبٍ إلى فئةٍ بمرتَّبٍ آخر خطأٌ لا يظهر إلا في كشف الصرف
    /// بعد شهر. فحين يطويه اسمان إلى مفتاحٍ واحد — «أ» و«الفئة أ» مثلاً —
    /// يُرفض الصفّ كما لو لم يُطابِق شيئاً، فيرى صاحبه الأسماء المعرَّفة
    /// ويختار بنفسه.</para>
    /// </summary>
    public static string FoldLoose(string? value)
    {
        var key = Fold(value);
        if (key.Length == 0) return key;

        foreach (var word in LabelWords)
        {
            var prefix = Fold(word) + " ";
            if (key.Length > prefix.Length && key.StartsWith(prefix, StringComparison.Ordinal))
            {
                key = key[prefix.Length..];
                break;
            }
        }

        // «ال» التعريف: «الرئيسي» و«رئيسي» فرعٌ واحد. والشرط على الطول يمنع
        // ابتلاع اسمٍ قصيرٍ كـ«الف».
        if (key.Length > 3 && key.StartsWith("ال", StringComparison.Ordinal)) key = key[2..];

        return key;
    }

    /// <summary>
    /// مقارِن مفاتيح الأعمدة: يطوي العربية قبل المقارنة — راجع [Fold].
    /// وهو مقارِن القاموس نفسه لا فحصٌ إضافي، فتستفيد منه كل عمليات
    /// الاستيراد بلا أن تعرف به.
    /// </summary>
    public sealed class HeaderComparer : IEqualityComparer<string>
    {
        public static readonly HeaderComparer Instance = new();
        public bool Equals(string? x, string? y) => Fold(x) == Fold(y);
        public int GetHashCode(string obj) => Fold(obj).GetHashCode();
    }

    /// <summary>البادئة التي تُعلَّم بها صفوف المثال في كل القوالب.</summary>
    public const string ExamplePrefix = "مثال:";

    /// <summary>
    /// أهذا صفُّ مثالٍ من القالب لا بياناتُ مستخدم؟
    ///
    /// <para><b>سبب وجوده:</b> القوالب تُسلَّم بصفِّ مثالٍ مملوء — عناوين
    /// وحدها تترك المستخدم يخمّن صيغة كل عمود. لكن أكثر من يفتح القالب
    /// يكتب بياناته **تحت** صفّ المثال ولا يحذفه، فيُرفَع الملف بمثالٍ
    /// فيه فئةٌ وفرعٌ من عندنا لا من عنده — وهو ما كان يُفشل الاستيراد
    /// كلَّه بخطأين لا علاقة لهما ببيانات المستخدم، أو — أسوأ — يزرع
    /// «محمد علي» عميلاً حقيقياً في الكشف.</para>
    ///
    /// <para>فتُتجاهَل هذه الصفوف صراحةً ويُعلَن عددها، ولا تُحسَب خطأً.</para>
    /// </summary>
    public static bool IsExampleRow(string? name)
    {
        if (string.IsNullOrWhiteSpace(name)) return false;
        var trimmed = Normalize(name).TrimStart('#', ' ');
        return trimmed.StartsWith(ExamplePrefix, StringComparison.Ordinal)
            || trimmed.StartsWith("مثال ", StringComparison.Ordinal);
    }

    /// <summary>
    /// يقرأ قيمة عمود بأي من الأسماء المقبولة له — الملف قد يكتب "الاسم"
    /// أو "اسم الصنف" أو "name"، وكلها تعني الشيء نفسه.
    /// </summary>
    public static string? Value(Dictionary<string, string> row, params string[] names)
    {
        foreach (var name in names)
        {
            if (row.TryGetValue(name, out var value) && !string.IsNullOrWhiteSpace(value))
            {
                return value.Trim();
            }
        }
        return null;
    }

    /// <summary>
    /// تحويل رقم كتبه إنسان: يقبل الأرقام العربية الهندية، والفاصلة العشرية
    /// العربية، وفواصل الآلاف، وعلامة العملة الملتصقة.
    /// </summary>
    public static decimal? Number(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return null;

        var sb = new StringBuilder();
        foreach (var c in raw)
        {
            if (c >= '٠' && c <= '٩') sb.Append((char)(c - '٠' + '0'));      // ٠-٩
            else if (c >= '۰' && c <= '۹') sb.Append((char)(c - '۰' + '0')); // ۰-۹ فارسية
            else if (char.IsDigit(c) || c == '.' || c == '-') sb.Append(c);
            else if (c == '٫' || c == ',') sb.Append('.');  // الفاصلة العشرية العربية
        }

        var cleaned = sb.ToString();
        // فواصل الآلاف: لا عدد فيه فاصلتان عشريّتان، فتعدّدها يعني تجميعاً
        // لا كسراً. والمجموعة الأخيرة تحسم: ثلاثة أرقام بعد آخر فاصلة
        // (1.234.567) تجميعٌ كلّه، وغيرها (1.234.567,89) كسرٌ بعد تجميع.
        //
        // وكان الحاصل قبلها أن الفاصلة الأخيرة تُعدّ عشرية دائماً، فمرتَّبٌ
        // كُتب «1.234.567» يُقرأ ألفاً ومئتين — والتعليق يَعِد بغير ما يفعل.
        var dots = cleaned.Count(c => c == '.');
        if (dots > 1)
        {
            var lastDot = cleaned.LastIndexOf('.');
            var tail = cleaned[(lastDot + 1)..];
            cleaned = tail.Length == 3
                ? cleaned.Replace(".", "")
                : cleaned[..lastDot].Replace(".", "") + cleaned[lastDot..];
        }

        return decimal.TryParse(cleaned, System.Globalization.NumberStyles.Any,
            System.Globalization.CultureInfo.InvariantCulture, out var result)
            ? result
            : null;
    }

    public static bool? Boolean(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return null;
        var v = raw.Trim().ToLowerInvariant();
        if (v is "نعم" or "yes" or "true" or "1" or "y" or "صح") return true;
        if (v is "لا" or "no" or "false" or "0" or "n" or "خطأ") return false;
        return null;
    }
}
