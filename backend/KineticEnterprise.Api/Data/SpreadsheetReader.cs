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
            var record = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
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
            var record = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
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
        // فواصل آلاف متعددة: 1.234.567 => 1234567
        var dots = cleaned.Count(c => c == '.');
        if (dots > 1)
        {
            var lastDot = cleaned.LastIndexOf('.');
            cleaned = cleaned[..lastDot].Replace(".", "") + cleaned[lastDot..];
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
