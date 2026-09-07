import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic_enterprise/core/theme/branding_provider.dart';
import 'package:kinetic_enterprise/shared/widgets/nav_items.dart';

/// وحدة «wallet» — بطاقاتٌ جماعية ومرتَّبات، تُباع فوق أي إصدار.
///
/// <para><b>الفجوة التي تسدّها:</b> الإصدار الجماعي للبطاقات كان محصوراً في
/// «المحفظة بالمحاسبة»، وهو إصدارٌ **بلا بضاعة**. فمحلٌّ عسكري له فروعٌ
/// غذائية ومنتسبون يأخذون ببطاقاتهم يقع على الجانب الخطأ من الخطّ: يشتري
/// النسخة الكاملة فيستطيع كل شيء إلا إصدار ألف بطاقة دفعةً واحدة.</para>
///
/// <para>وما يحرسه هذا الملف قبل كل شيء: ألّا يفقد أحدٌ شيئاً يملكه اليوم.
/// </para>
void main() {
  List<String> routesFor(String edition, {Set<String>? modules}) => navGroupsFor(
        isPlatformAdmin: false,
        edition: edition,
        modules: modules ?? modulesOfEdition(edition),
      ).expand((g) => g.items).map((i) => i.route).toList();

  group('الوحدة تُباع فوق الإصدار', () {
    final entities =
        File('backend/KineticEnterprise.Api/Models/Entities.cs').readAsStringSync();

    test('مذكورة في الوحدات القابلة للبيع', () {
      // بلا هذا لا يراها مالك المنصّة في شاشة الترخيص فلا يستطيع بيعها،
      // ويرفضها الخادم اسماً مكتوباً بخطأ.
      expect(entities, contains('"wallet",'));
    });

    test('و«المحفظة بالمحاسبة» تحملها أصلاً — فلا يتغيّر عندها شيء', () {
      expect(entities,
          contains('WalletPlus => new[] { "pos", "customers", "reports", "accounting", "wallet" }'));
    });

    test('والإصدار الجماعي صار بالوحدة لا بالإصدار', () {
      final customers =
          File('backend/KineticEnterprise.Api/Controllers/CustomersController.cs').readAsStringSync();
      expect(customers, contains('[RequireModule("wallet")]'));
      // العطب الذي يمنعه: فحصُ الإصدار في جسم الدالّة لا يقرأ الوحدات
      // المُباعة منفردة، فيبقى بيع الوحدة مستحيلاً مهما كُتب في الترخيص.
      expect(customers, isNot(contains('org.Edition != Editions.WalletPlus')));
    });
  });

  group('لا يفقد أحدٌ شيئاً', () {
    test('المحفظة البسيطة تحتفظ بشاشة المرتَّبات بلا شراء الوحدة', () {
      // العطب الذي يمسكه: ربطُ الشاشة بالوحدة وحدها يسلب إصدار المحفظة
      // البسيطة شاشةً يملكها اليوم — وهي جوهر عمله.
      expect(routesFor('wallet'), contains('/payroll'));
      expect(modulesOfEdition('wallet'), isNot(contains('wallet')));
    });

    test('و«المحفظة بالمحاسبة» كذلك', () {
      expect(routesFor('wallet_plus'), contains('/payroll'));
    });

    test('والقياسيّ بلا مرتَّبات ما لم يشترِ الوحدة', () {
      expect(routesFor('standard'), isNot(contains('/payroll')));
      expect(routesFor('enterprise'), isNot(contains('/payroll')));
    });
  });

  group('ومن اشتراها يراها', () {
    test('محلٌّ عسكري: بضاعةٌ ومخزونٌ ومرتَّبات معاً', () {
      // السيناريو كلّه في سطر: فروعٌ غذائية تبيع بضاعة، وجنودٌ يأخذون
      // ببطاقاتهم، ومرتَّباتٌ تُصرف على فئاتهم.
      final routes = routesFor('enterprise', modules: {
        ...modulesOfEdition('enterprise'),
        'wallet',
      });

      expect(routes, contains('/payroll'));
      expect(routes, contains('/wallet-cards'));
      expect(routes, contains('/pos'));
      expect(routes, contains('/inventory'));
    });

    test('وبطاقات المحفظة كانت مفتوحةً للجميع أصلاً', () {
      // فالبطاقة الفردية لم تكن محجوبة يوماً — المحجوب الجملة وحدها.
      expect(routesFor('standard'), contains('/wallet-cards'));
    });
  });
}
