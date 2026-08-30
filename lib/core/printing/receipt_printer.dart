import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:barcode/barcode.dart' show Barcode;
import '../pdf/arabic_pdf_theme.dart';
import 'receipt_template.dart';

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
  ReceiptTemplate template = ReceiptTemplate.fallback,
  Uint8List? logoBytes,
}) async {
  final doc = pw.Document(theme: await arabicPdfTheme());
  doc.addPage(buildReceiptPage(
    invoice: invoice,
    orgName: orgName,
    currencySymbol: currencySymbol,
    template: template,
    logoBytes: logoBytes,
  ));
  await Printing.layoutPdf(onLayout: (format) async => doc.save());
}

/// صفحة الإيصال — مفصولةً عن الطباعة **كي تستعملها المعاينة نفسها**.
///
/// <para>ولولا الفصل لرسمت شاشةُ المصمّم شكلاً يشبه الإيصال ولا يطابقه،
/// فيَعِد المستخدمَ بشيء وتُخرج الطابعة غيره. وهو نفس مبدأ معاينة مصمّم
/// الباركود.</para>
pw.Page buildReceiptPage({
  required Map<String, dynamic> invoice,
  required String orgName,
  required String currencySymbol,
  required ReceiptTemplate template,
  Uint8List? logoBytes,
}) {
  final items = List<Map<String, dynamic>>.from(invoice['items'] as List? ?? []);
  final payments = List<Map<String, dynamic>>.from(invoice['payments'] as List? ?? []);
  final createdAt = DateTime.tryParse(invoice['createdAt'] as String? ?? '');
  final isReturn = invoice['invoiceType'] == 'return';

  // اللفّة الحرارية ضيّقة فخطّها صغير؛ وA4 صفحةٌ يضيع عليها خطّ الثماني
  // نقاط. مقياسٌ واحد يضبط الأحجام كلها بدل جدولٍ لكل مقاس.
  final roll = ReceiptPapers.isRoll(template.paper);
  final scale = roll ? 1.0 : 1.5;

  return pw.Page(
      pageFormat: ReceiptPapers.formatOf(template.paper),
      textDirection: pw.TextDirection.rtl,
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          if (template.showLogo && logoBytes != null) ...[
            pw.Center(
              child: pw.Image(pw.MemoryImage(logoBytes),
                  height: (roll ? 28 : 44) * PdfPageFormat.point, fit: pw.BoxFit.contain),
            ),
            pw.SizedBox(height: 4),
          ],
          pw.Center(child: pdfAutoDir(orgName, style: pw.TextStyle(fontSize: 12 * scale, fontWeight: pw.FontWeight.bold))),
          if (template.showTaxNumber && template.taxNumber != null)
            pw.Center(child: pdfLtr(pw.Text('الرقم الضريبي: ${template.taxNumber}',
                style: pw.TextStyle(fontSize: 7 * scale)))),
          if (template.showCommercialRegistry && template.commercialRegistry != null)
            pw.Center(child: pdfLtr(pw.Text('السجلّ التجاري: ${template.commercialRegistry}',
                style: pw.TextStyle(fontSize: 7 * scale)))),
          if (template.headerText != null && template.headerText!.isNotEmpty) ...[
            pw.SizedBox(height: 2),
            pw.Center(child: pdfAutoDir(template.headerText!, style: pw.TextStyle(fontSize: 8 * scale))),
          ],
          pw.SizedBox(height: 4),
          if (isReturn)
            pw.Center(child: pw.Text('فاتورة مرتجع', style: pw.TextStyle(fontSize: 9 * scale))),
          // رقم الفاتورة والتاريخ نصوص مختلطة (حروف + أرقام + فواصل) يقلبها
          // اتجاه الصفحة العربية إن تُركت له — راجع [pdfLtr].
          pw.Center(child: pdfLtr(pw.Text(invoice['invoiceNumber'] as String? ?? '', style: pw.TextStyle(fontSize: 9 * scale)))),
          if (createdAt != null)
            pw.Center(child: pdfLtr(pw.Text(_dateFormat.format(createdAt), style: pw.TextStyle(fontSize: 8 * scale)))),
          if (invoice['customerName'] != null)
            pw.Center(child: pw.Text('العميل: ${invoice['customerName']}', style: pw.TextStyle(fontSize: 8 * scale))),
          pw.Divider(),
          ...items.map((item) => pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 2),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        '${item['productName']}  x${_currencyFormat.format((item['quantity'] as num?) ?? 0)}',
                        style: pw.TextStyle(fontSize: 8 * scale),
                      ),
                    ),
                    pdfLtr(pw.Text(_currencyFormat.format((item['lineTotal'] as num?) ?? 0), style: pw.TextStyle(fontSize: 8 * scale))),
                  ],
                ),
              )),
          pw.Divider(),
          _summaryRow('الإجمالي الفرعي', invoice['subtotal'], scale),
          _summaryRow('الضريبة', invoice['taxAmount'], scale),
          _summaryRow('الخصم', invoice['discountAmount'], scale),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('الإجمالي', style: pw.TextStyle(fontSize: 10 * scale, fontWeight: pw.FontWeight.bold)),
              pdfLtr(pw.Text(
                '${_currencyFormat.format((invoice['totalAmount'] as num?) ?? 0)} $currencySymbol',
                style: pw.TextStyle(fontSize: 10 * scale, fontWeight: pw.FontWeight.bold),
              )),
            ],
          ),
          if (payments.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            ...payments.map((p) => pw.Text(
                  '${_paymentLabels[p['method']] ?? p['method']}: ${_currencyFormat.format((p['amount'] as num?) ?? 0)} $currencySymbol',
                  style: pw.TextStyle(fontSize: 8 * scale),
                )),
          ],
          if (template.showQr) ...[
            pw.SizedBox(height: 8),
            pw.Center(
              // رقم الفاتورة لا رابطٌ إلى خادم: الرمز يجب أن يعمل بعد سنة
              // ومن هاتفٍ خارج الشبكة. ومن يمسحه يريد المرجع لا صفحة.
              child: pw.BarcodeWidget(
                barcode: Barcode.qrCode(),
                data: invoice['invoiceNumber'] as String? ?? '',
                width: (roll ? 48 : 70) * PdfPageFormat.point,
                height: (roll ? 48 : 70) * PdfPageFormat.point,
                drawText: false,
              ),
            ),
          ],
          pw.SizedBox(height: 12),
          if (template.footerText != null && template.footerText!.isNotEmpty)
            pw.Center(child: pdfAutoDir(template.footerText!, style: pw.TextStyle(fontSize: 8 * scale))),
        ],
      ),
    );
}

pw.Widget _summaryRow(String label, dynamic amount, double scale) {
  final value = (amount as num?)?.toDouble() ?? 0;
  if (value == 0) return pw.SizedBox();
  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text(label, style: pw.TextStyle(fontSize: 8 * scale)),
      pdfLtr(pw.Text(_currencyFormat.format(value), style: pw.TextStyle(fontSize: 8 * scale))),
    ],
  );
}
