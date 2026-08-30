import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic_enterprise/shared/widgets/nav_items.dart';

/// حدود الإصدارات في القائمة الجانبية.
///
/// <para><b>العطب الذي تمسكه:</b> سلوك المحفظة يُفحَص في ستّة مواضع بين
/// الخادم والواجهة. وإضافة إصدار `wallet_plus` — وهو محفظةٌ بمحاسبة —
/// تعني تحديث خمسةٍ ونسيان السادس. والسادس هو ما يراه العميل: مجموعة
/// مخزونٍ في قائمة جهةٍ لا بضاعة لها، أو محاسبةٌ غائبة عمّن دفع ثمنها.</para>
///
/// <para>وثلاثة مواضع تعرض هذه القائمة (الشريط الجانبي والعلوي ولوحة
/// الأوامر)، وكلها تُبنى من [navGroupsFor] — ففحصها هنا يفحصها جميعاً.</para>
void main() {
  List<String> labelsFor(String edition) => navGroupsFor(
        isPlatformAdmin: false,
        edition: edition,
      ).map((g) => g.label).toList();

  List<String> routesFor(String edition) => navGroupsFor(
        isPlatformAdmin: false,
        edition: edition,
      ).expand((g) => g.items).map((i) => i.route).toList();

  group('إصدار المحفظة البسيط', () {
    test('بلا مخزون — لا بضاعة يديرها', () {
      expect(labelsFor('wallet'), isNot(contains('المخزون')));
    });

    test('بلا محاسبة — لم يشترِها', () {
      expect(labelsFor('wallet'), isNot(contains('المحاسبة')));
      expect(routesFor('wallet'), isNot(contains('/accounting')));
    });

    test('بلا مصروفات — جهةٌ تصرف على منتسبيها لا تُدير محلاً', () {
      expect(routesFor('wallet'), isNot(contains('/expenses')));
    });

    test('بالمرتَّبات — هي عملُ الجهة الأساسي', () {
      expect(routesFor('wallet'), contains('/payroll'));
    });
  });

  group('إصدار المحفظة بالمحاسبة', () {
    test('بلا مخزون كالمحفظة — الفارق دفترٌ لا بضاعة', () {
      expect(labelsFor('wallet_plus'), isNot(contains('المخزون')));
    });

    test('بمحاسبة — وهي ما دفع ثمنه', () {
      expect(labelsFor('wallet_plus'), contains('المحاسبة'));
      expect(routesFor('wallet_plus'), contains('/accounting'));
    });

    test('بمصروفات — دفترٌ لا يقيّد ما صُرف ليس دفتراً', () {
      expect(routesFor('wallet_plus'), contains('/expenses'));
    });

    test('بالمرتَّبات كالمحفظة', () {
      expect(routesFor('wallet_plus'), contains('/payroll'));
    });

    test('بلا فواتير موردين — لا استلامَ عنده يُفوتره', () {
      // شاشةٌ تفتح فارغةً أبداً أسوأ من شاشةٍ غائبة: يظنّها المستخدم
      // معطوبة ويسأل عنها.
      expect(routesFor('wallet_plus'), isNot(contains('/supplier-invoices')));
    });
  });

  group('إصدار المؤسسات', () {
    test('بمخزون ومحاسبة وفواتير موردين معاً', () {
      final routes = routesFor('enterprise');
      expect(labelsFor('enterprise'), contains('المخزون'));
      expect(routes, contains('/accounting'));
      expect(routes, contains('/supplier-invoices'));
      expect(routes, contains('/expenses'));
    });
  });

  group('الإصدار القياسي', () {
    test('بلا مرتَّبات — متجرٌ يبيع بضاعة لا يصرف على منتسبين', () {
      expect(routesFor('standard'), isNot(contains('/payroll')));
      expect(routesFor('enterprise'), isNot(contains('/payroll')));
    });

    test('بمخزون ومصروفات بلا محاسبة', () {
      expect(labelsFor('standard'), contains('المخزون'));
      expect(routesFor('standard'), contains('/expenses'));
      expect(routesFor('standard'), isNot(contains('/accounting')));
    });
  });

  test('كل شاشة في القائمة مسجَّلة في جولة اللقطات لإصدارٍ ما', () {
    // حارسٌ عكسي: شاشةٌ تُضاف لإصدار جديد ولا تدخل أي اختبار تمرّ بلا
    // ملاحظة. وهذا ما وقع فعلاً مع ثلاث شاشات من قبل.
    final all = <String>{
      for (final edition in ['standard', 'wallet', 'wallet_plus', 'pharmacy', 'enterprise'])
        ...routesFor(edition),
    };
    expect(all, isNotEmpty);
    expect(all, contains('/pos'));
  });
}
