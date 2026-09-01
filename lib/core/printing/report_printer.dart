import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../pdf/arabic_pdf_theme.dart';

final _dateFormat = DateFormat('yyyy-MM-dd');

/// صفٌّ في جدول تقرير.
typedef ReportRow = List<String>;

/// طباعة تقريرٍ واحد على ورق A4.
///
/// <para><b>الفجوة التي تسدّها:</b> شاشة التقارير تُقرأ ولا تُطبع. ومن
/// يريد عرض رقمٍ على شريكه أو حفظه في ملفّ الشهر يصوّر الشاشة بهاتفه — أو
/// ينسخ الأرقام بيده إلى ورقة.</para>
///
/// <para><b>وواحدةٌ لكل التقارير لا واحدةٌ لكلّ تقرير:</b> أربعة تقارير
/// اليوم وستّة غداً، ولكلٍّ طابعةٌ خاصّة تعني ستّة أشكال تفترق أوّل مرّة
/// يُغيَّر أحدها — وترويسةٌ بلا اسم المنشأة في واحدٍ منها لا يلاحظها أحد.</para>
Future<void> printReport({
  required String title,
  required String orgName,
  DateTime? from,
  DateTime? to,
  /// أرقامٌ رئيسية تُعرض أعلى التقرير: (الوصف، القيمة).
  List<(String, String)> facts = const [],
  /// عناوين الجدول — فارغةٌ تعني بلا جدول.
  List<String> columns = const [],
  List<ReportRow> rows = const [],
  /// سطرٌ يُذيَّل به التقرير — تنبيهٌ أو مصدر البيانات.
  String? note,
}) async {
  final doc = pw.Document(theme: await arabicPdfTheme());

  doc.addPage(
    pw.MultiPage(
      // MultiPage لا Page: تقرير أعمار الديون قد يحمل مئتَي عميل، وصفحةٌ
      // واحدة تقصّ ما بعد الأولى بصمت.
      pageFormat: PdfPageFormat.a4.copyWith(
        marginLeft: 14 * PdfPageFormat.mm,
        marginRight: 14 * PdfPageFormat.mm,
        marginTop: 14 * PdfPageFormat.mm,
        marginBottom: 14 * PdfPageFormat.mm,
      ),
      textDirection: pw.TextDirection.rtl,
      header: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pdfAutoDir(orgName,
                  style: const pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pdfLtr(pw.Text(_dateFormat.format(DateTime.now()),
                  style: const pw.TextStyle(fontSize: 9))),
            ],
          ),
          pw.SizedBox(height: 6),
          pdfAutoDir(title,
              style: const pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
          if (from != null || to != null) ...[
            pw.SizedBox(height: 2),
            // سطرٌ مختلط: كلمتان عربيّتان وتاريخان لاتينيّان.
            //
            // كان مغلّفاً كلّه بـ[pdfLtr] فخرج «ىل إ — نم» — الكلمات
            // العربية معكوسةً ومقطّعة الحروف. وتغليفه كلّه بـRTL يقلب
            // التاريخ. فيُبنى صفّاً: كلٌّ باتجاهه، والصفّ نفسه يتبع اتجاه
            // الصفحة فيبدأ من اليمين.
            pw.Row(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pdfAutoDir('من ', style: const pw.TextStyle(fontSize: 9)),
                pdfLtr(pw.Text(from == null ? '—' : _dateFormat.format(from),
                    style: const pw.TextStyle(fontSize: 9))),
                pdfAutoDir('  إلى ', style: const pw.TextStyle(fontSize: 9)),
                pdfLtr(pw.Text(to == null ? '—' : _dateFormat.format(to),
                    style: const pw.TextStyle(fontSize: 9))),
              ],
            ),
          ],
          pw.Divider(),
        ],
      ),
      // رقم الصفحة على كل صفحة: تقريرٌ من ثلاث ورقات تتفرّق أوراقه على
      // مكتب، ولا يُعرف ترتيبها بلا رقم.
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerLeft,
        child: pdfLtr(pw.Text(
          '${context.pageNumber} / ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8),
        )),
      ),
      build: (context) => [
        if (facts.isNotEmpty) ...[
          pw.Wrap(
            spacing: 24,
            runSpacing: 10,
            children: [
              for (final (label, value) in facts)
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  mainAxisSize: pw.MainAxisSize.min,
                  children: [
                    pdfAutoDir(label, style: const pw.TextStyle(fontSize: 8)),
                    pw.SizedBox(height: 2),
                    pdfAutoDir(value,
                        style: const pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
            ],
          ),
          pw.SizedBox(height: 14),
        ],
        if (columns.isNotEmpty)
          // ── الأعمدة معكوسة عمداً ───────────────────────────────────────
          //
          // `textDirection: rtl` على الصفحة يضبط اتجاه **النصّ** لا ترتيب
          // أعمدة الجدول: حزمة pdf ترصّ الأعمدة من اليسار دائماً. فكان
          // العمود الأول («الرمز» في دليل الحسابات) يقع أقصى اليسار
          // والأخير أقصى اليمين — جدولٌ إنجليزي بنصّ عربي، يُقرأ بالمقلوب.
          //
          // والقلب **هنا** لا في كل مُستدعٍ: خمسة دفاتر وشاشة التقارير
          // تمرّ كلّها من هذه الدالّة، وقلبٌ يُنفَّذ في أربعةٍ ويُنسى في
          // الخامس هو ما ينتهي على ورقٍ بيد محاسب. راجع نفس المصيدة
          // محلولةً يدوياً في [purchase_order_printer].
          //
          // والمُستدعون يكتبون أعمدتهم بالترتيب الطبيعي (الأول يميناً)،
          // فلا يعرف أحدهم بهذا القلب ولا يحتاج أن يعرف.
          pw.TableHelper.fromTextArray(
            headers: columns.reversed.toList(),
            data: [for (final row in rows) row.reversed.toList()],
            headerStyle: const pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 8),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellAlignment: pw.Alignment.centerRight,
            headerAlignment: pw.Alignment.centerRight,
          ),
        if (rows.isEmpty && columns.isNotEmpty) ...[
          pw.SizedBox(height: 8),
          pdfAutoDir('لا بيانات في هذه المدّة',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        ],
        if (note != null) ...[
          pw.SizedBox(height: 14),
          pdfAutoDir(note, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        ],
      ],
    ),
  );

  await Printing.layoutPdf(onLayout: (format) async => doc.save());
}
