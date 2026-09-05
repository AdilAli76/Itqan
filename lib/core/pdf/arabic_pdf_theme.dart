import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

/// خطوط PDF — مضمَّنة في الحزمة لا مُنزَّلة من الشبكة.
///
/// <para><b>سبب وجودها:</b> خطوط PDF الافتراضية (Helvetica وأخواتها) لا
/// حرف عربي فيها إطلاقاً، فكل إيصال وملصق وتقرير يخرج حروفاً متقطّعة.</para>
///
/// <para><b>والعطب الذي أُصلح هنا:</b> كانت تُجلب من خطوط قوقل **وقت
/// الطباعة** (`PdfGoogleFonts`). والنظام يُنشر داخل متجر (راجع
/// DEPLOYMENT.md)، وواجهته تستعمل خطّاً مضمَّناً لهذا السبب بعينه — بينما
/// بقيت الطباعة معلَّقة بالشبكة. فكاشيرٌ في محلٍّ بلا إنترنت يطبع أول
/// إيصال فيقف انتظاراً ثم يخرج بخطٍّ بديل، والزبون واقف. والطباعة أحوج
/// إلى العمل بلا شبكة من أي شاشة: هي آخر خطوة في البيع.</para>
///
/// <para>وIBM Plex Sans Arabic — وهو خطّ الواجهة نفسه — يغطّي العربية
/// واللاتينية معاً، فالإيصال يخرج بخطٍّ واحد لا بخطّين متنافرين، ورموز
/// البطاقات وأكواد الأصناف الإنجليزية تُرسم كما تُرسم في الشاشة.</para>
///
/// <para><b>ويُحمَّل مرّة واحدة</b>: قراءة أربعة ملفات خطوط عند كل طباعة
/// تُبطئ أوّل صفحة بلا سبب — والكاشير يطبع عشرات المرّات في الساعة.</para>
Future<pw.ThemeData>? _cached;

Future<pw.ThemeData> arabicPdfTheme() => _cached ??= _load();

Future<pw.ThemeData> _load() async {
  Future<pw.Font> font(String weight) async =>
      pw.Font.ttf(await rootBundle.load('assets/fonts/IBMPlexSansArabic-$weight.ttf'));

  final regular = await font('Regular');
  final bold = await font('Bold');
  final medium = await font('Medium');

  return pw.ThemeData.withFont(
    base: regular,
    bold: bold,
    // المتوسط احتياطياً لا خطّاً ثالثاً: محرِّك PDF يبحث عن الرمز في
    // الأساسي ثم في الاحتياطي، وتغطية العائلة واحدة — فالفائدة أن يبقى
    // للرموز النادرة مصدرٌ ثانٍ من نفس العائلة بدل مربّع فارغ.
    fontFallback: [medium, bold],
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
