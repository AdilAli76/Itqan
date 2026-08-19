import 'dart:typed_data';

import 'package:flutter/material.dart' show Color;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../pdf/arabic_pdf_theme.dart';

/// طباعة بطاقة محفظة بوجهين، كل وجه بمقاس ID-1 القياسي (85.6×54 ملم — نفس
/// مقاس بطاقة الائتمان، فتناسب المحفظة وطابعات البطاقات القياسية).
///
/// الوجهان يُرسمان **جنباً إلى جنب على ورقة واحدة** لا على صفحتين منفصلتين:
/// طابعة البطاقات البلاستيكية غير متوفرة في معظم المحال، والطريقة العملية هي
/// الطباعة على ورقة عادية ثم القص ولصق الوجهين ظهراً لظهر ثم التغليف الحراري.
/// وضعهما على صفحتين كان يُخفي الوجه الخلفي (الباركود) عن المعاينة تماماً
/// فيظن المستخدم أن البطاقة بوجه واحد بلا باركود.
Future<void> printWalletCard({
  required String cardCode,
  required String holderName,
  required String orgName,
  required Color brandColor,
  DateTime? expiryDate,
  String? supportPhone,
  /// شعار المنظمة بايتاتٍ — يُجلب بالتوكن قبل الاستدعاء (نقطة الملفات
  /// محمية، ومحرّك PDF لا يحمل ترويسة مصادقة).
  Uint8List? logoBytes,
  /// هاتف حامل البطاقة — يُطبع على الظهر ليُعاد إليه إن ضاعت.
  String? holderPhone,
}) async {
  final doc = pw.Document(theme: await arabicPdfTheme());
  final brand = PdfColor.fromInt(brandColor.toARGB32());

  // لون النص يُشتق من إضاءة لون العلامة لا يُثبَّت: كل منظمة تختار لونها من
  // الإعدادات، فلون فاتح مع نص أبيض ثابت يجعل البطاقة غير مقروءة.
  final onBrand = brandColor.computeLuminance() > 0.5 ? PdfColors.black : PdfColors.white;
  final onBrandMuted = brandColor.computeLuminance() > 0.5
      ? const PdfColor.fromInt(0xFF444444)
      : const PdfColor.fromInt(0xFFD8DCE2);

  doc.addPage(
    pw.Page(
      // عمودي لا أفقي: الوجهان متجاوران يحتاجان 181 ملم عرضاً، وورقة A4
      // العمودية (210 ملم) تُطبَع بهوامش تُضيّقها لأقل من ذلك فيُقصّ الوجه
      // الثاني عند الطباعة الفعلية. رصّهما فوق بعضهما يُبقي كل وجه بمقاسه
      // الحقيقي داخل عرض الورقة مهما ضاقت الهوامش.
      pageFormat: PdfPageFormat.a4,
      textDirection: pw.TextDirection.rtl,
      build: (context) => pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text('بطاقة عميل — قصّ على الحدود، ثم ألصق الوجهين ظهراً لظهر',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
          pw.SizedBox(height: 18),
          pw.Text('الوجه الأمامي', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
          pw.SizedBox(height: 4),
          _cardFace(child: _front(
            cardCode: cardCode,
            holderName: holderName,
            orgName: orgName,
            logoBytes: logoBytes,
            expiryDate: expiryDate,
            brand: brand,
            onBrand: onBrand,
            onBrandMuted: onBrandMuted,
          )),
          pw.SizedBox(height: 14 * PdfPageFormat.mm),
          pw.Text('الوجه الخلفي', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
          pw.SizedBox(height: 4),
          _cardFace(child: _back(
            cardCode: cardCode,
            brand: brand,
            orgName: orgName,
            supportPhone: supportPhone,
            holderPhone: holderPhone,
          )),
        ],
      ),
    ),
  );

  await Printing.layoutPdf(onLayout: (format) async => doc.save());
}

/// إطار بمقاس البطاقة الحقيقي — الحد الرمادي الرفيع هو خط القص.
pw.Widget _cardFace({required pw.Widget child}) => pw.Container(
      width: 85.6 * PdfPageFormat.mm,
      height: 54.0 * PdfPageFormat.mm,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(width: 0.5, color: PdfColors.grey500),
        borderRadius: pw.BorderRadius.circular(10),
      ),
      // القص ضروري وإلا خرجت خلفية الوجه الملوّنة وشريط الظهر من تحت الزوايا
      // المستديرة فبدت البطاقة كمستطيل حاد الحواف.
      child: pw.ClipRRect(horizontalRadius: 10, verticalRadius: 10, child: child),
    );

pw.Widget _front({
  required String cardCode,
  required String holderName,
  required String orgName,
  required Uint8List? logoBytes,
  required DateTime? expiryDate,
  required PdfColor brand,
  required PdfColor onBrand,
  required PdfColor onBrandMuted,
}) {
  return pw.Container(
    color: brand,
    padding: const pw.EdgeInsets.all(14),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (logoBytes != null) ...[
              pw.Container(
                width: 26,
                height: 26,
                // خلفية بيضاء تحت الشعار: أغلب الشعارات مصمَّمة على أبيض،
                // ووضعها مباشرة على لون العلامة يبتلع تفاصيلها.
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                padding: const pw.EdgeInsets.all(2),
                child: pw.Image(pw.MemoryImage(logoBytes), fit: pw.BoxFit.contain),
              ),
              pw.SizedBox(width: 8),
            ],
            pw.Expanded(
              child: pdfAutoDir(
                orgName,
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: onBrand),
                maxLines: 2,
              ),
            ),
            pw.SizedBox(width: 8),
            // الغرض مكتوب صراحةً على الوجه.
            //
            // بطاقة تحمل اسم شخص ورمزاً وباركود بلا كلمة تشرح غرضها تدعو من
            // يجدها إلى أسوأ الظنون. وسطر واحد يُنهي ذلك.
            pw.Text('بطاقة صرف ومشتريات',
                style: pw.TextStyle(fontSize: 7, color: onBrandMuted)),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('حامل البطاقة', style: pw.TextStyle(fontSize: 7, color: onBrandMuted)),
            pw.SizedBox(height: 3),
            pdfAutoDir(
              holderName,
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: onBrand),
              maxLines: 1,
            ),
          ],
        ),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pdfLtr(pw.Text(
              _spacedCode(cardCode),
              style: pw.TextStyle(fontSize: 11, letterSpacing: 1.4, color: onBrand),
            )),
            if (expiryDate != null)
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('تنتهي في', style: pw.TextStyle(fontSize: 6, color: onBrandMuted)),
                  pdfLtr(pw.Text(
                    DateFormat('MM/yyyy').format(expiryDate),
                    style: pw.TextStyle(fontSize: 9, color: onBrand),
                  )),
                ],
              ),
          ],
        ),
      ],
    ),
  );
}

pw.Widget _back({
  required String cardCode,
  required PdfColor brand,
  required String orgName,
  required String? supportPhone,
  required String? holderPhone,
}) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      // الشريط الداكن المعتاد على ظهر البطاقات، بلون العلامة لا بالأسود.
      pw.Container(height: 9 * PdfPageFormat.mm, color: brand),
      pw.Expanded(
        child: pw.Container(
          // الباركود يبقى أسود على أبيض دائماً مهما كان لون العلامة — أي خلفية
          // ملوّنة تحته تُضعف التباين فيفشل الماسح الضوئي في قراءته.
          color: PdfColors.white,
          padding: const pw.EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(
                child: pdfLtr(pw.BarcodeWidget(
                  data: cardCode,
                  barcode: pw.Barcode.code128(),
                  drawText: true,
                  textStyle: const pw.TextStyle(fontSize: 7),
                  color: PdfColors.black,
                )),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'بطاقة صرف ومشتريات صادرة عن $orgName. تُقدَّم عند الشراء، '
                'ولا تُشارَك مع أحد ولا يُفصَح عن رقمها السري.',
                style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey700),
                textAlign: pw.TextAlign.center,
              ),
              // بيانات الإعادة عند الفقد.
              //
              // بطاقة ضائعة بلا رقم يُتّصل به تُرمى أو تُهمَل، ومن يجدها لا
              // يعرف إلى من يعيدها. هاتف الجهة المُصدِرة هو الطريق العملي —
              // وهاتف الحامل يُطبع باختياره.
              pw.SizedBox(height: 3),
              pw.Text('إن وجدت هذه البطاقة فأعِدها إلى:',
                  style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey700),
                  textAlign: pw.TextAlign.center),
              if (supportPhone != null && supportPhone.isNotEmpty)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Text('الجهة المُصدِرة: ', style: const pw.TextStyle(fontSize: 6)),
                    pdfLtr(pw.Text(supportPhone, style: const pw.TextStyle(fontSize: 6))),
                  ],
                ),
              if (holderPhone != null && holderPhone.isNotEmpty)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Text('حامل البطاقة: ', style: const pw.TextStyle(fontSize: 6)),
                    pdfLtr(pw.Text(holderPhone, style: const pw.TextStyle(fontSize: 6))),
                  ],
                ),
            ],
          ),
        ),
      ),
    ],
  );
}

/// يُقسَّم الرمز إلى مجموعات رباعية كأرقام بطاقة الائتمان — أسهل بكثير في
/// القراءة والنطق عبر الهاتف من 12 خانة متلاصقة.
String _spacedCode(String code) {
  final buffer = StringBuffer();
  for (var i = 0; i < code.length; i++) {
    if (i > 0 && i % 4 == 0) buffer.write('  ');
    buffer.write(code[i]);
  }
  return buffer.toString();
}
