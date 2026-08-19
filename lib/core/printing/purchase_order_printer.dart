import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../pdf/arabic_pdf_theme.dart';

final _currencyFormat = NumberFormat('#,##0.00', 'en');
final _dateFormat = DateFormat('yyyy-MM-dd HH:mm');

const _statusLabels = {
  'draft': 'مسودة',
  'ordered': 'مُرسَل للمورّد',
  'received': 'مستلَم',
  'cancelled': 'ملغى',
};

/// يطبع أمر الشراء على مقاس A4.
///
/// ليس إيصالاً حرارياً كإيصال البيع، والفرق ليس شكلياً: أمر الشراء مستند
/// يُرسَل إلى مورّد ويُوقَّع ويُحفَظ في الأرشيف، فيحتاج ترويسة تعرّف بالشركة
/// وبيانات تواصل يردّ عليها المورّد وخانتَي توقيع — المُصدِر والمستلِم.
/// وقصاصة بعرض ثمانين مليمتراً لا تؤدي شيئاً من ذلك.
Future<void> printPurchaseOrder({
  required Map<String, dynamic> order,
  required String orgName,
  required String currencySymbol,
  /// شعار الشركة بايتاتٍ — يُجلب بالتوكن قبل الاستدعاء (راجع AuthedImage:
  /// نقطة الملفات محمية، فلا يمكن للـPDF جلبها برابط مباشر).
  Uint8List? logoBytes,
  String? branchAddress,
  String? branchPhone,
  /// اسم من أصدر الأمر — يُطبع تحت خانة التوقيع.
  String? issuedBy,
}) async {
  final doc = pw.Document(theme: await arabicPdfTheme());
  final items = List<Map<String, dynamic>>.from(order['items'] as List? ?? []);
  final createdAt = DateTime.tryParse(order['createdAt'] as String? ?? '');
  final total = (order['totalAmount'] as num?)?.toDouble() ?? 0;
  final status = order['status'] as String? ?? '';

  // رقم مختصر من المعرّف: المعرّف الكامل ستٌّ وثلاثون خانة لا يقرؤها أحد
  // ولا يُملى على الهاتف، والثمانية الأولى تكفي للتمييز والبحث.
  final id = order['id'] as String? ?? '';
  final shortId = id.length >= 8 ? id.substring(0, 8).toUpperCase() : id;

  pw.Widget cell(String text, {bool bold = false, pw.TextAlign align = pw.TextAlign.right}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: pw.Text(text,
            textAlign: align,
            style: pw.TextStyle(fontSize: 9, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
      );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      textDirection: pw.TextDirection.rtl,
      margin: const pw.EdgeInsets.fromLTRB(32, 32, 32, 44),
      // الترويسة تتكرّر على كل صفحة: أمر بأربعين صنفاً يمتدّ صفحتين، وصفحة
      // بلا اسم الشركة ولا رقم الأمر ورقة مجهولة إن انفصلت عن أختها.
      header: (context) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 14),
        padding: const pw.EdgeInsets.only(bottom: 8),
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(width: 1.2)),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (logoBytes != null) ...[
              pw.SizedBox(
                width: 52,
                height: 52,
                child: pw.Image(pw.MemoryImage(logoBytes), fit: pw.BoxFit.contain),
              ),
              pw.SizedBox(width: 12),
            ],
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(orgName, style: const pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 2),
                  pw.Text('أمر شراء', style: const pw.TextStyle(fontSize: 11)),
                ],
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pdfLtr(pw.Text('PO-$shortId',
                    style: const pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold))),
                pw.SizedBox(height: 2),
                if (createdAt != null)
                  pdfLtr(pw.Text(_dateFormat.format(createdAt), style: const pw.TextStyle(fontSize: 9))),
                pw.SizedBox(height: 2),
                pw.Text(_statusLabels[status] ?? status, style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
          ],
        ),
      ),
      // التذييل: بيانات التواصل ورقم الصفحة على كل ورقة.
      footer: (context) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 6),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(width: 0.6)),
        ),
        child: pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(
                [
                  if (branchAddress != null && branchAddress.isNotEmpty) branchAddress,
                  if (branchPhone != null && branchPhone.isNotEmpty) 'هاتف: $branchPhone',
                ].join('   •   '),
                style: const pw.TextStyle(fontSize: 8),
              ),
            ),
            pdfLtr(pw.Text('${context.pageNumber} / ${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 8))),
          ],
        ),
      ),
      build: (context) => [
        // بيانات المورّد والفرع
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: _infoBlock('المورّد', [
                order['supplierName'] as String? ?? 'غير محدَّد',
              ]),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: _infoBlock('فرع الاستلام', [
                order['branchName'] as String? ?? '',
                if (branchAddress != null && branchAddress.isNotEmpty) branchAddress,
              ]),
            ),
          ],
        ),
        pw.SizedBox(height: 16),

        pw.Table(
          border: pw.TableBorder.all(width: 0.6, color: PdfColors.grey600),
          columnWidths: {
            0: const pw.FlexColumnWidth(0.6),
            1: const pw.FlexColumnWidth(4),
            2: const pw.FlexColumnWidth(1.2),
            3: const pw.FlexColumnWidth(1.6),
            4: const pw.FlexColumnWidth(1.8),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey300),
              children: [
                cell('#', bold: true, align: pw.TextAlign.center),
                cell('الصنف', bold: true),
                cell('الكمية', bold: true, align: pw.TextAlign.center),
                cell('التكلفة', bold: true, align: pw.TextAlign.center),
                cell('الإجمالي', bold: true, align: pw.TextAlign.center),
              ],
            ),
            ...items.asMap().entries.map((e) {
              final it = e.value;
              final qty = (it['quantity'] as num?)?.toDouble() ?? 0;
              final unitCost = (it['unitCost'] as num?)?.toDouble() ?? 0;
              final lineTotal = (it['lineTotal'] as num?)?.toDouble() ?? (qty * unitCost);
              return pw.TableRow(children: [
                cell('${e.key + 1}', align: pw.TextAlign.center),
                cell(it['productName'] as String? ?? ''),
                cell(_currencyFormat.format(qty), align: pw.TextAlign.center),
                cell(_currencyFormat.format(unitCost), align: pw.TextAlign.center),
                cell(_currencyFormat.format(lineTotal), align: pw.TextAlign.center),
              ]);
            }),
          ],
        ),
        pw.SizedBox(height: 10),

        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          children: [
            pw.Container(
              width: 200,
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('الإجمالي', style: const pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                  pw.Text('${_currencyFormat.format(total)} $currencySymbol',
                      style: const pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 36),

        // خانتا التوقيع — المُصدِر والمستلِم.
        //
        // اسم المُصدِر مطبوع تحت الخط لا مكتوب بخط اليد: المستند يُراجَع بعد
        // شهور، وتوقيع بلا اسم مقروء لا يدلّ على أحد.
        pw.Row(
          children: [
            pw.Expanded(child: _signatureBlock('أصدره', issuedBy)),
            pw.SizedBox(width: 40),
            pw.Expanded(child: _signatureBlock('استلمه', null)),
          ],
        ),
      ],
    ),
  );

  await Printing.layoutPdf(onLayout: (format) => doc.save());
}

pw.Widget _infoBlock(String title, List<String> lines) => pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.6, color: PdfColors.grey600)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title, style: const pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
          pw.SizedBox(height: 3),
          ...lines.where((l) => l.isNotEmpty).map(
                (l) => pw.Text(l, style: const pw.TextStyle(fontSize: 10)),
              ),
        ],
      ),
    );

pw.Widget _signatureBlock(String label, String? name) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 30),
        pw.Container(height: 0.8, color: PdfColors.grey700),
        pw.SizedBox(height: 3),
        pw.Text(name ?? 'الاسم والتوقيع', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
      ],
    );
