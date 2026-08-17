import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../pdf/arabic_pdf_theme.dart';

final _currencyFormat = NumberFormat('#,##0.00', 'en');
final _dateFormat = DateFormat('yyyy-MM-dd HH:mm');

const _paymentLabels = {
  'cash': 'نقداً',
  'card': 'بطاقة',
  'customer_wallet': 'محفظة العميل',
  'credit': 'آجل',
};

/// يطبع إيصال فاتورة (بيع أو مرتجع) على عرض لفة حرارية قياسية عبر نظام
/// طباعة Windows العادي — يعمل مع أي طابعة حرارية مثبَّتة كطابعة Windows
/// (وهذا حال أغلب الطابعات الحديثة USB/شبكة)، بلا حاجة لبرمجة ESC/POS
/// مباشرة لموديل بعينه. الطول غير محدود (لفة مستمرة) والعرض فقط ثابت،
/// نفس أسلوب PdfPageFormat.roll57/roll80 المدمج في مكتبة pdf.
Future<void> printInvoiceReceipt({
  required Map<String, dynamic> invoice,
  required String orgName,
  required String currencySymbol,
  double widthMm = 80,
}) async {
  final doc = pw.Document(theme: await arabicPdfTheme());
  final items = List<Map<String, dynamic>>.from(invoice['items'] as List? ?? []);
  final payments = List<Map<String, dynamic>>.from(invoice['payments'] as List? ?? []);
  final createdAt = DateTime.tryParse(invoice['createdAt'] as String? ?? '');
  final isReturn = invoice['invoiceType'] == 'return';

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat(widthMm * PdfPageFormat.mm, double.infinity, marginAll: 4 * PdfPageFormat.mm),
      textDirection: pw.TextDirection.rtl,
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Center(child: pdfAutoDir(orgName, style: const pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold))),
          pw.SizedBox(height: 4),
          if (isReturn)
            pw.Center(child: pw.Text('فاتورة مرتجع', style: const pw.TextStyle(fontSize: 9))),
          // رقم الفاتورة والتاريخ نصوص مختلطة (حروف + أرقام + فواصل) يقلبها
          // اتجاه الصفحة العربية إن تُركت له — راجع [pdfLtr].
          pw.Center(child: pdfLtr(pw.Text(invoice['invoiceNumber'] as String? ?? '', style: const pw.TextStyle(fontSize: 9)))),
          if (createdAt != null)
            pw.Center(child: pdfLtr(pw.Text(_dateFormat.format(createdAt), style: const pw.TextStyle(fontSize: 8)))),
          if (invoice['customerName'] != null)
            pw.Center(child: pw.Text('العميل: ${invoice['customerName']}', style: const pw.TextStyle(fontSize: 8))),
          pw.Divider(),
          ...items.map((item) => pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 2),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        '${item['productName']}  x${_currencyFormat.format((item['quantity'] as num?) ?? 0)}',
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ),
                    pdfLtr(pw.Text(_currencyFormat.format((item['lineTotal'] as num?) ?? 0), style: const pw.TextStyle(fontSize: 8))),
                  ],
                ),
              )),
          pw.Divider(),
          _summaryRow('الإجمالي الفرعي', invoice['subtotal']),
          _summaryRow('الضريبة', invoice['taxAmount']),
          _summaryRow('الخصم', invoice['discountAmount']),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('الإجمالي', style: const pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pdfLtr(pw.Text(
                '${_currencyFormat.format((invoice['totalAmount'] as num?) ?? 0)} $currencySymbol',
                style: const pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
              )),
            ],
          ),
          if (payments.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            ...payments.map((p) => pw.Text(
                  '${_paymentLabels[p['method']] ?? p['method']}: ${_currencyFormat.format((p['amount'] as num?) ?? 0)} $currencySymbol',
                  style: const pw.TextStyle(fontSize: 8),
                )),
          ],
          pw.SizedBox(height: 12),
          pw.Center(child: pw.Text('شكراً لتعاملكم معنا', style: const pw.TextStyle(fontSize: 8))),
        ],
      ),
    ),
  );

  await Printing.layoutPdf(onLayout: (format) async => doc.save());
}

pw.Widget _summaryRow(String label, dynamic amount) {
  final value = (amount as num?)?.toDouble() ?? 0;
  if (value == 0) return pw.SizedBox();
  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
      pdfLtr(pw.Text(_currencyFormat.format(value), style: const pw.TextStyle(fontSize: 8))),
    ],
  );
}
