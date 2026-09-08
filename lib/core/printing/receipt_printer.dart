import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:barcode/barcode.dart' show Barcode;
import '../pdf/arabic_pdf_theme.dart';
import 'receipt_template.dart';
import 'print_cache_manager.dart';
import 'print_error_handler.dart';

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
///
/// [shouldPrint]: إذا كانت false، لا تُطبع الفاتورة. يُستخدم عند رغبة الكاشير
/// في عدم الطباعة.
Future<void> printInvoiceReceipt({
  required Map<String, dynamic> invoice,
  required String orgName,
  required String currencySymbol,
  ReceiptTemplate template = ReceiptTemplate.fallback,
  Uint8List? logoBytes,
  bool shouldPrint = true,
  Function(PrintErrorHandler)? onError,
}) async {
  if (!shouldPrint) return;

  try {
    final doc = pw.Document(theme: await arabicPdfTheme());
    doc.addPage(buildReceiptPage(
      invoice: invoice,
      orgName: orgName,
      currencySymbol: currencySymbol,
      template: template,
      logoBytes: logoBytes,
    ));
    await Printing.layoutPdf(onLayout: (format) async => doc.save()).timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw TimeoutException('انقطع الاتصال بالطابعة', const Duration(seconds: 30)),
    );
  } catch (e) {
    final error = e is Exception ? classifyError(e) : PrintErrorHandler(
      errorMessage: e.toString(),
      type: PrintErrorType.unknown,
    );
    onError?.call(error);
    rethrow;
  }
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
  // مقياس الورق × اختيار المستخدم: الأوّل يمنع خطّ الثماني نقاط على A4،
  // والثاني يترك لمن عينه ضعيفة أن يكبّر بلا أن يكسر التخطيط.
  final scale = (roll ? 1.0 : 1.5) * template.fontScale;
  final accent = _accentOf(template);

  return pw.Page(
      pageFormat: ReceiptPapers.formatOf(template.paper),
      textDirection: pw.TextDirection.rtl,
      build: (context) => pw.Container(
        // إطار الصفحة للورق الرسمي وحده: اللفّة الحرارية تُقصّ بلا هامش
        // ثابت، فإطارٌ عليها يخرج مقطوعاً من جهة.
        decoration: (template.showPageBorder && !roll)
            ? pw.BoxDecoration(border: pw.Border.all(color: accent, width: 1))
            : null,
        padding: (template.showPageBorder && !roll) ? const pw.EdgeInsets.all(10) : null,
        child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          if (template.showLogo && logoBytes != null) ...[
            pw.Center(
              child: pw.Image(pw.MemoryImage(logoBytes),
                  height: (roll ? 28 : 44) * PdfPageFormat.point, fit: pw.BoxFit.contain),
            ),
            pw.SizedBox(height: 4),
          ],
          // شريط ملوّن باسم الجهة في القالب الحديث: هو ما يجعل الإيصال
          // «يشبه المحلّ» — والاسم وحده وسط ورقة بيضاء لا يفعل ذلك.
          if (template.preset == ReceiptPresets.modern)
            pw.Container(
              width: double.infinity,
              color: accent,
              padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 6),
              child: pw.Center(
                child: pdfAutoDir(orgName,
                    style: pw.TextStyle(
                        fontSize: 12 * scale,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white)),
              ),
            )
          else
            pw.Center(
                child: pdfAutoDir(orgName,
                    style: pw.TextStyle(fontSize: 12 * scale, fontWeight: pw.FontWeight.bold))),
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
          if (template.tableStyle != ReceiptTableStyles.plain) pw.Divider(),
          ...items.asMap().entries.map((entry) {
            final item = entry.value;
            final line = pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  child: pw.Text(
                    '${item['productName']}  x${_currencyFormat.format((item['quantity'] as num?) ?? 0)}',
                    style: pw.TextStyle(fontSize: 8 * scale),
                  ),
                ),
                pdfLtr(pw.Text(_currencyFormat.format((item['lineTotal'] as num?) ?? 0),
                    style: pw.TextStyle(fontSize: 8 * scale))),
              ],
            );

            return pw.Container(
              // التظليل المتناوب يُقرأ بالعين على صفحةٍ بعشرين سطراً،
              // والمسافة الأوسع في «المبسّط» تعوّض غياب الخطوط.
              decoration: pw.BoxDecoration(
                color: template.tableStyle == ReceiptTableStyles.zebra && entry.key.isEven
                    ? PdfColors.grey100
                    : null,
                border: template.tableStyle == ReceiptTableStyles.grid
                    ? const pw.Border(bottom: pw.BorderSide(width: 0.4))
                    : null,
              ),
              padding: pw.EdgeInsets.symmetric(
                  vertical: template.tableStyle == ReceiptTableStyles.plain ? 3.5 : 2,
                  horizontal: template.tableStyle == ReceiptTableStyles.zebra ? 3 : 0),
              child: line,
            );
          }),
          if (template.tableStyle != ReceiptTableStyles.plain) pw.Divider(),
          _summaryRow('الإجمالي الفرعي', invoice['subtotal'], scale),
          _summaryRow('الضريبة', invoice['taxAmount'], scale),
          _summaryRow('الخصم', invoice['discountAmount'], scale),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('الإجمالي',
                  style: pw.TextStyle(
                      fontSize: 10 * scale, fontWeight: pw.FontWeight.bold, color: accent)),
              pdfLtr(pw.Text(
                '${_currencyFormat.format((invoice['totalAmount'] as num?) ?? 0)} $currencySymbol',
                style: pw.TextStyle(
                    fontSize: 10 * scale, fontWeight: pw.FontWeight.bold, color: accent),
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
      ),
    );
}

/// لون القالب — أو الرمادي الداكن إن كانت القيمة تالفة.
///
/// <para>لونٌ مكتوب بخطأ لا يجوز أن يُسقط الطباعة: الكاشير أمامه زبون.</para>
PdfColor _accentOf(ReceiptTemplate template) {
  final raw = template.accentColor.replaceAll('#', '');
  final value = int.tryParse(raw, radix: 16);
  if (value == null || raw.length != 6) return PdfColors.blueGrey800;
  return PdfColor.fromInt(0xFF000000 | value);
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
