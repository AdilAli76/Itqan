import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../pdf/arabic_pdf_theme.dart';
import 'printer_profiles.dart';

final _slipDateFormat = DateFormat('yyyy-MM-dd');

/// <summary>
/// قسيمة بطاقة على اللفّة الحرارية (NB80 وأخواتها).
///
/// <para><b>سبب وجودها بجوار البطاقة ذات الوجهين:</b> تلك تُطبع على A4 ثم
/// تُقصّ وتُلصق وتُغلَّف — عملُ ربع ساعة لبطاقةٍ واحدة. وجهةٌ تسجّل عشرين
/// منتسباً في صباح لا تفعل ذلك، فيخرجون بلا بطاقة ويُبحث عنهم بالاسم كل
/// مرّة. والقسيمة تخرج من الطابعة التي أمام الكاشير في ثانيتين.</para>
///
/// <para><b>وهي ليست بديلاً عن البطاقة بل مرحلةً قبلها:</b> ورقٌ حراري يبهت
/// في أسابيع — يُقال ذلك على القسيمة نفسها لا في دليلٍ لا يُقرأ.</para>
///
/// <para><b>ومقاس الباركود يُحسب من تعريف الطابعة لا يُثبَّت:</b> رمزٌ يُرسم
/// بعرض الورقة كاملاً على NB80 يُقصّ طرفاه (تطبع على ٧٢ من ٨٠)، وعمودٌ نحيف
/// أدقّ من ثلث المليمتر لا تقرؤه كاميرا هاتف — وهي القارئ في الميدان. راجع
/// [PrinterProfile.code128Layout].</para>
/// </summary>
Future<void> printCardSlip({
  required String cardCode,
  required String holderName,
  required String orgName,
  required PrinterProfile printer,
  String? branchName,
  String? supportPhone,
  DateTime? expiryDate,
}) async {
  final doc = pw.Document(theme: await arabicPdfTheme());
  final layout = printer.code128Layout(cardCode.length);

  // الهوامش من التعريف لا رقمٌ ثابت: الفرق بين عرض الورق وما تطبعه الرأس
  // هو الحافّتان، وتوزيعُه على الجانبين يُوسّط المحتوى فعلاً.
  final margin = ((printer.paperWidthMm - printer.printableWidthMm) / 2) * PdfPageFormat.mm;

  doc.addPage(
    pw.Page(
      // الطول لا نهائي: اللفّة مستمرّة، وتثبيتُه يقصّ القسيمة عند آخر سطر.
      pageFormat: PdfPageFormat(
        printer.paperWidthMm * PdfPageFormat.mm,
        double.infinity,
        marginAll: margin,
      ),
      textDirection: pw.TextDirection.rtl,
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pdfAutoDir(orgName,
              style: const pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          if (branchName != null && branchName.trim().isNotEmpty) ...[
            pw.SizedBox(height: 2),
            pdfAutoDir(branchName,
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
          ],
          pw.SizedBox(height: 6),
          pw.Divider(height: 1, thickness: 0.5),
          pw.SizedBox(height: 6),
          pdfAutoDir(holderName,
              style: const pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),

          // الباركود أبيض تحته دائماً مهما كان لون العلامة: أي خلفية ملوّنة
          // تُضعف التباين فيفشل الماسح.
          pw.Container(
            color: PdfColors.white,
            child: pdfLtr(pw.BarcodeWidget(
              data: cardCode,
              barcode: pw.Barcode.code128(),
              // العرض محسوبٌ لا مملوء: التمدّد إلى عرض الورقة يبتلع المنطقة
              // الهادئة، وباركودٌ بلا منطقةٍ هادئة يُطبع سليماً ولا يُقرأ.
              width: layout.widthMm * PdfPageFormat.mm,
              height: 18 * PdfPageFormat.mm,
              drawText: true,
              textStyle: const pw.TextStyle(fontSize: 8),
              color: PdfColors.black,
            )),
          ),

          // وQR إن ضاقت اللفّة عن باركودٍ خطّيٍّ تقرؤه الكاميرا: على ٥٨ ملم
          // يخرج العمود النحيف أدقّ من ثلث المليمتر، فيقرؤه ماسح الليزر عند
          // الصندوق ولا يقرؤه هاتفٌ في الميدان — وهو الاستعمال المقصود.
          if (!layout.cameraReadable) ...[
            pw.SizedBox(height: 6),
            pdfLtr(pw.BarcodeWidget(
              data: cardCode,
              barcode: pw.Barcode.qrCode(),
              width: 26 * PdfPageFormat.mm,
              height: 26 * PdfPageFormat.mm,
              color: PdfColors.black,
            )),
            pw.SizedBox(height: 2),
            pw.Text('امسح المربّع بالكاميرا',
                style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
          ],

          pw.SizedBox(height: 8),
          if (expiryDate != null) ...[
            pw.Text('تنتهي في ${_slipDateFormat.format(expiryDate)}',
                style: const pw.TextStyle(fontSize: 8)),
            pw.SizedBox(height: 4),
          ],
          pw.Text(
            // يُقال على الورقة نفسها: من ظنّها بطاقةً دائمة وجدها بيضاء بعد
            // شهرين ولا يعرف أن الورق الحراري هو السبب.
            'قسيمة مؤقّتة — الورق الحراري يبهت. اطلب البطاقة الدائمة.',
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
            textAlign: pw.TextAlign.center,
          ),
          if (supportPhone != null && supportPhone.trim().isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pdfLtr(pw.Text(supportPhone, style: const pw.TextStyle(fontSize: 8))),
          ],
        ],
      ),
    ),
  );

  await Printing.layoutPdf(onLayout: (format) async => doc.save());
}
