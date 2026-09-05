using ClosedXML.Excel;

namespace KineticEnterprise.Api.Data;

/// <summary>
/// قوالب الاستيراد — ملفّ إكسل حقيقي لا CSV.
///
/// <para><b>العطب الذي يصلحه:</b> القالب كان CSV بفواصل، وإكسل على ويندوز
/// العربي يفصل بالفاصلة **المنقوطة** (الفاصلة عنده فاصلٌ عشري). فيفتح
/// المستخدم القالب فيجد الصفّ كلّه في خليّة واحدة: ستّة أعمدة صارت عموداً
/// واحداً، ولا يستطيع تعبئته — وهو كلّ غرض القالب.</para>
///
/// <para><b>وعطبٌ ثانٍ لا يظهر إلا بعد التعبئة:</b> الهاتف
/// <c>0910000000</c> يُقرأ في CSV رقماً فيسقط صفرُه الأول، فيُرفع الملف
/// بهواتف من تسع خانات لا تطابق شيئاً. وكذلك الباركود ذو الثلاثة عشر رقماً
/// يصير <c>6.22E+12</c>. والخليّة النصّية في xlsx تحفظ ما كُتب كما كُتب.
/// </para>
///
/// <para><b>ولماذا لا حلول CSV الوسطى:</b> سطر <c>sep=,</c> تفهمه إكسل
/// وحده وتعرضه جداول قوقل صفّاً زائداً، والفاصلة المنقوطة تكسر إكسل
/// الإنجليزي. وxlsx لا لغة له ولا إعداد محلّي — يُفتح عند الجميع كما
/// كُتب. والقارئ يقبل الصيغتين أصلاً، فمن عنده ملفٌّ CSV قائم يرفعه كما
/// هو.</para>
/// </summary>
public static class SpreadsheetTemplate
{
    public const string ContentType =
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";

    /// <param name="textColumns">
    /// أعمدةٌ تُكتب نصّاً بالقوّة (بادئة الصفر تبقى) — الهاتف والباركود
    /// والرمز. وتنسيقُ العمود كلّه لا الخليّة وحدها: من يكتب هاتفه في
    /// الصفّ العاشر يجب أن يبقى نصّاً أيضاً.
    /// </param>
    public static byte[] Build(
        string sheetName,
        IReadOnlyList<string> headers,
        IReadOnlyList<string[]> rows,
        IReadOnlyList<int>? textColumns = null)
    {
        using var workbook = new XLWorkbook();
        var sheet = workbook.Worksheets.Add(sheetName);

        // ورقة من اليمين: القالب عربي، وفتحُه من اليسار يجعل عمود «الاسم»
        // في أقصى الشاشة بعيداً عن العين.
        sheet.RightToLeft = true;

        for (var c = 0; c < headers.Count; c++)
        {
            var cell = sheet.Cell(1, c + 1);
            cell.Value = headers[c];
            cell.Style.Font.Bold = true;
            cell.Style.Fill.BackgroundColor = XLColor.FromHtml("#EEF2F7");
        }

        var text = new HashSet<int>(textColumns ?? Array.Empty<int>());
        for (var c = 0; c < headers.Count; c++)
        {
            if (text.Contains(c)) sheet.Column(c + 1).Style.NumberFormat.Format = "@";
        }

        for (var r = 0; r < rows.Count; r++)
        {
            var row = rows[r];
            for (var c = 0; c < headers.Count && c < row.Length; c++)
            {
                var cell = sheet.Cell(r + 2, c + 1);

                // الرقم رقماً والنصّ نصّاً: خليّةٌ فيها «250» مخزَّنةً نصّاً
                // تُظهر في إكسل مثلّث «رقم مخزَّن كنصّ» عند كل صفّ — تحذيرٌ
                // لا معنى له يُدرَّب المستخدم على تجاهله، فيتجاهل معه
                // تحذيراً حقيقياً يوماً ما.
                //
                // أمّا أعمدة النصّ المصرَّح بها فتبقى نصّاً مهما بدت أرقاماً:
                // «0910000000» رقمُ هاتف لا كمّية.
                if (!text.Contains(c)
                    && decimal.TryParse(row[c], System.Globalization.NumberStyles.Any,
                        System.Globalization.CultureInfo.InvariantCulture, out var number))
                {
                    cell.Value = number;
                }
                else
                {
                    // SetValue<string> لا Value: الأخيرة تستنتج النوع فتحوّل
                    // «0910000000» إلى رقم رغم تنسيق العمود.
                    cell.SetValue(row[c]);
                }
                // صفوف المثال بلون باهت: تُقرأ مثالاً لا بياناتٍ نُسيت.
                cell.Style.Font.FontColor = XLColor.FromHtml("#8A94A6");
            }
        }

        // سطر العناوين مثبَّت: ملفٌّ بألف صفّ يُمرَّر فيه، وبلا تثبيت
        // يكتب المستخدم في العمود الخطأ لأنه لا يرى عنوانه.
        sheet.SheetView.FreezeRows(1);
        sheet.Columns().AdjustToContents(minWidth: 12, maxWidth: 46);

        using var stream = new MemoryStream();
        workbook.SaveAs(stream);
        return stream.ToArray();
    }
}
