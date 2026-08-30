import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../pdf/arabic_pdf_theme.dart';

final _currencyFormat = NumberFormat('#,##0.00', 'en');
final _dateFormat = DateFormat('yyyy-MM-dd HH:mm');

/// إثبات خصم من رصيد — على لفة حرارية.
///
/// العامل يحتاج ورقةً تقول: كم خُصم، ومتى، وكم بقي. الخصم من رصيدٍ بلا إثبات
/// هو أول ما يُتنازَع عليه آخر الشهر، وحينها لا يملك أحد إلا ذاكرته.
///
/// وهو ليس إيصال بيع: لا أصناف ولا كميات ولا أسعار وحدة — هذه مفاهيم متجر
/// يبيع بضاعة، والجهة هنا تصرف على منتسبيها.
Future<void> printWalletDeduction({
  required Map<String, dynamic> invoice,
  required String orgName,
  required String currencySymbol,
  required String? customerName,
  required double amount,
  required double? remaining,
  required bool isWallet,
  double widthMm = 80,
}) async {
  final doc = pw.Document(theme: await arabicPdfTheme());
  final createdAt = DateTime.tryParse(invoice['createdAt'] as String? ?? '') ?? DateTime.now();

  pw.Widget line(String label, String value, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label, style: pw.TextStyle(fontSize: bold ? 11 : 9, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
            pw.Text(value, style: pw.TextStyle(fontSize: bold ? 11 : 9, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          ],
        ),
      );

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat(widthMm * PdfPageFormat.mm, double.infinity, marginAll: 5 * PdfPageFormat.mm),
      textDirection: pw.TextDirection.rtl,
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Center(child: pw.Text(orgName, style: const pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold))),
          pw.SizedBox(height: 2),
          pw.Center(
            child: pw.Text(isWallet ? 'إثبات خصم من الرصيد' : 'إيصال بيع نقدي',
                style: const pw.TextStyle(fontSize: 10)),
          ),
          pw.Divider(),
          if (customerName != null) line('الاسم', customerName),
          line('التاريخ', _dateFormat.format(createdAt)),
          line('رقم العملية', '${invoice['invoiceNumber'] ?? ''}'),
          pw.Divider(),
          line('المبلغ المخصوم', '${_currencyFormat.format(amount)} $currencySymbol', bold: true),
          if (remaining != null) ...[
            pw.SizedBox(height: 2),
            line('الرصيد المتبقي', '${_currencyFormat.format(remaining)} $currencySymbol', bold: true),
          ],
          pw.Divider(),
          pw.SizedBox(height: 18),
          // خانة توقيع: الإثبات الورقي بلا توقيع يبقى دعوى طرف واحد.
          pw.Text('توقيع المستلِم', style: const pw.TextStyle(fontSize: 8)),
          pw.SizedBox(height: 22),
          pw.Container(height: 0.8, color: PdfColors.grey700),
          pw.SizedBox(height: 10),
          pw.Center(child: pw.Text('احتفظ بهذا الإثبات', style: const pw.TextStyle(fontSize: 8))),
        ],
      ),
    ),
  );

  await Printing.layoutPdf(onLayout: (format) => doc.save());
}
