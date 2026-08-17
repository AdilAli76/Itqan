import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// خطوط PDF الافتراضية (Helvetica وغيرها من Base-14) لا تحتوي حروفاً عربية
/// إطلاقاً — هذا هو سبب "الحروف المتقطعة" في كل تقرير/ملصق/بطاقة يُصدَّر
/// PDF في النظام (مصمِّم الباركود، بطاقة العميل، تصدير سجل التدقيق). الحل:
/// تحميل خط عربي فعلي (Noto Sans Arabic عبر PdfGoogleFonts من نفس حزمة
/// printing المستخدَمة أصلاً) وتعيينه كخط افتراضي للمستند.
///
/// ملاحظة: يحتاج اتصال إنترنت أول مرة فقط (يُنزَّل الخط ويُخزَّن مؤقتاً
/// محلياً بعدها عبر نفس آلية تخزين حزمة printing المؤقت — لا تحميل متكرر).
///
/// وبالمقابل: Noto Sans Arabic يغطي العربية والأرقام فقط ولا يحوي الأبجدية
/// اللاتينية إطلاقاً، فتعيينه وحده يقلب كل حرف إنجليزي إلى مربّع فارغ (رموز
/// البطاقات مثل EWMT2DJ5، أسماء المنتجات الإنجليزية، أكواد SKU على الملصقات).
/// لذلك يُضاف Noto Sans كخط احتياطي: محرِّك PDF يبحث عن كل رمز في الخط
/// الأساسي أولاً، فإن لم يجده انتقل للاحتياطي — فتُرسَم العربية بالخط العربي
/// واللاتينية بالخط اللاتيني داخل السطر الواحد.
Future<pw.ThemeData> arabicPdfTheme() async {
  final arabic = await PdfGoogleFonts.notoSansArabicRegular();
  final arabicBold = await PdfGoogleFonts.notoSansArabicBold();
  final latin = await PdfGoogleFonts.notoSansRegular();
  final latinBold = await PdfGoogleFonts.notoSansBold();
  return pw.ThemeData.withFont(
    base: arabic,
    bold: arabicBold,
    fontFallback: [latin, latinBold],
  );
}

/// يُجبِر محتواه على الاتجاه من اليسار لليمين داخل صفحة عربية (RTL).
///
/// أي نص مختلط حروف وأرقام (رمز بطاقة مثل EWMT2DJ5M6WZ، كود SKU، رقم فاتورة،
/// تاريخ 08/2027) تُعيد خوارزمية الاتجاه ثنائي الاتجاه ترتيب أجزائه داخل
/// صفحة RTL، فيخرج مقلوباً ومبعثراً — وكود بطاقة مقلوب بطاقة لا تعمل. تغليفه
/// بهذه الدالة يعزله عن اتجاه الصفحة فيُرسَم بترتيبه الحقيقي، دون التأثير على
/// اتجاه بقية الصفحة العربية.
pw.Widget pdfLtr(pw.Widget child) =>
    pw.Directionality(textDirection: pw.TextDirection.ltr, child: child);

final _arabicChars = RegExp(r'[؀-ۿݐ-ݿﭐ-﷿ﹰ-﻿]');

/// نص قد يكون عربياً وقد يكون لاتينياً — لا يُعرف اتجاهه إلا وقت التشغيل.
///
/// اسم المنظمة واسم حامل البطاقة واسم المنتج يكتبها الزبون بلغته: قد تكون
/// «متجر عادل» وقد تكون "Kinetic Enterprise". إجبار الاتجاه على قيمة ثابتة
/// يكسر إحدى الحالتين حتماً — تُرك اللاتيني لاتجاه الصفحة العربية فخرج معكوساً
/// حرفاً حرفاً (esirpretnE citeniK). لذلك يُفحَص النص: إن خلا من الحروف
/// العربية عُزل باتجاه LTR، وإلا تُرك لاتجاه الصفحة الطبيعي.
pw.Widget pdfAutoDir(
  String text, {
  pw.TextStyle? style,
  pw.TextAlign? textAlign,
  int? maxLines,
}) {
  final widget = pw.Text(
    text,
    style: style,
    textAlign: textAlign,
    maxLines: maxLines,
    overflow: maxLines == null ? null : pw.TextOverflow.clip,
  );
  return _arabicChars.hasMatch(text) ? widget : pdfLtr(widget);
}
