import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic_enterprise/core/printing/printer_profiles.dart';

/// حساب مقاس الباركود على الطابعات المعروفة.
///
/// <para><b>لماذا يستحقّ اختباراً:</b> عطبُ هذا الحساب لا يُخرج خطأً ولا
/// شاشةً حمراء — تخرج ورقةٌ عليها باركود، تبدو سليمة، ولا يقرؤها الماسح ولا
/// الكاميرا. ولا يُكتشف إلا وصاحب البطاقة واقفٌ أمام الكاشير، فيُقال له
/// «النظام لا يعمل».</para>
///
/// <para>ورمز البطاقة **اثنا عشر محرفاً** — راجع
/// `CustomerCards.GenerateCardCode`. والأرقام أدناه محسوبةٌ على هذا الطول
/// لأنه الطول الحقيقي الوحيد في النظام.</para>
void main() {
  const cardCodeLength = 12;

  group('NB80 — ثمانون ملم', () {
    final layout = PrinterProfiles.nb80.code128Layout(cardCodeLength);

    test('الرمز يسع في العرض المطبوع لا في عرض الورق', () {
      // العطب الذي يمسكه: الحساب على ٨٠ بدل ٧٢ يُخرج رمزاً أعرض من رأس
      // الطباعة، فيُقصّ طرفاه — ومنطقةٌ هادئة مقصوصة تعني رمزاً لا يُقرأ.
      expect(layout.widthMm, lessThanOrEqualTo(PrinterProfiles.nb80.printableWidthMm));
      expect(layout.widthMm, greaterThan(PrinterProfiles.nb80.printableWidthMm / 2));
    });

    test('العمود النحيف مضاعفٌ صحيح لحجم النقطة', () {
      // الطابعة الحرارية ترسم بنقاطٍ صحيحة: مقاسٌ بينها تقرّبه هي، فتختلّ
      // نسب الأعمدة عن المواصفة ويقرؤه ماسحٌ دون آخر.
      final dots = layout.moduleMm / PrinterProfiles.nb80.dotMm;
      expect((dots - dots.roundToDouble()).abs(), lessThan(0.0001));
      expect(dots.round(), greaterThanOrEqualTo(2));
    });

    test('وتقرؤه كاميرا الهاتف — فلا QR معه', () {
      expect(layout.cameraReadable, isTrue);
      expect(PrinterProfiles.nb80.needsQrFallback(cardCodeLength), isFalse);
    });
  });

  group('ثمانية وخمسون ملم', () {
    final layout = PrinterProfiles.nb58.code128Layout(cardCodeLength);

    test('يسع أيضاً — لكن بعمودٍ أنحف', () {
      expect(layout.widthMm, lessThanOrEqualTo(PrinterProfiles.nb58.printableWidthMm));
      expect(layout.moduleMm, lessThan(PrinterProfiles.nb80.code128Layout(cardCodeLength).moduleMm));
    });

    test('فلا تقرؤه الكاميرا، فيُطبع QR معه', () {
      // وهذا هو الفرق العملي بين الطابعتين: على ٥٨ ملم يبقى الرمز الخطّي
      // لماسح الليزر عند الصندوق، والهاتف يقرأ المربّع.
      expect(layout.cameraReadable, isFalse);
      expect(PrinterProfiles.nb58.needsQrFallback(cardCodeLength), isTrue);
    });
  });

  group('المنطقة الهادئة محسوبة', () {
    test('الرمز أضيق من الورق بما يكفي لعشرين عموداً', () {
      // بلا هذا يُرسم الرمز ملاصقاً للحافّة: يُطبع كاملاً ولا يُقرأ، وهو
      // أشيع عطبٍ في الباركود المطبوع وأصعبه تفسيراً.
      final layout = PrinterProfiles.nb80.code128Layout(cardCodeLength);
      final symbolOnly = layout.moduleMm * (11 * (cardCodeLength + 3) + 13);
      expect(layout.widthMm - symbolOnly, closeTo(layout.moduleMm * 20, 0.001));
    });
  });

  group('كلّما طال الرمز ضاق عموده', () {
    test('رمزٌ طويل على ٨٠ ملم يهبط تحت عتبة الكاميرا', () {
      // حارسٌ على المستقبل: من يُطيل رمز البطاقة يجب أن يعرف أنه أسقط
      // قراءتها بالهاتف — لا أن يكتشفه الميدان.
      final long = PrinterProfiles.nb80.code128Layout(24);
      expect(long.cameraReadable, isFalse);
      expect(long.widthMm, lessThanOrEqualTo(PrinterProfiles.nb80.printableWidthMm));
    });
  });

  group('الاستنتاج من إعدادات المنظمة', () {
    test('عرض ٥٨ يعني طابعةً ضيّقة، و٨٠ عريضة', () {
      expect(PrinterProfiles.fromReceiptWidth(58).printableWidthMm, 48);
      expect(PrinterProfiles.fromReceiptWidth(80).printableWidthMm, 72);
    });

    test('ومعرّفٌ مجهول لا يُسقط الطباعة', () {
      // تعريفٌ محفوظ من نسخةٍ أحدث، أو تخزينٌ تالف: الطباعة تستمرّ بالأشيع
      // ولا ترمي استثناءً في وجه من ضغط «اطبع».
      expect(PrinterProfiles.byId('لا-وجود-له').id, PrinterProfiles.nb80.id);
      expect(PrinterProfiles.byId(null).id, PrinterProfiles.nb80.id);
    });
  });
}
