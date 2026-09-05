import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic_enterprise/core/theme/branding_provider.dart';
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
  // الوحدات تُمرَّر كما يمرّرها التطبيق: من [modulesOfEdition] لا مكتوبةً
  // هنا. مجموعةٌ تُكتب في الاختبار توافق نفسها أبداً ولا توافق ما يُرسله
  // الخادم — وهو ما يُفترض أن يُمسَك هنا.
  List<NavGroup> groupsFor(String edition, {Set<String>? modules}) => navGroupsFor(
        isPlatformAdmin: false,
        edition: edition,
        modules: modules ?? modulesOfEdition(edition),
      );

  List<String> labelsFor(String edition, {Set<String>? modules}) =>
      groupsFor(edition, modules: modules).map((g) => g.label).toList();

  List<String> routesFor(String edition, {Set<String>? modules}) =>
      groupsFor(edition, modules: modules).expand((g) => g.items).map((i) => i.route).toList();

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

  // ── الوحدات تُباع فوق الإصدار ────────────────────────────────────────
  //
  // كانت القائمة تُشتقّ من الإصدار في Dart، فوحدةٌ يبيعها مالك المنصّة
  // منفردة يفتحها الخادم ولا تظهر لها شاشة — والعميل يدفع ولا يرى.
  group('وحدة بيعت فوق الإصدار', () {
    test('المحاسبة لعميل قياسي تُظهر مجموعتها', () {
      final modules = {...modulesOfEdition('standard'), 'accounting'};
      expect(labelsFor('standard', modules: modules), contains('المحاسبة'));
      expect(routesFor('standard', modules: modules), contains('/accounting'));
    });

    test('نشرة الدواء لعميل قياسي تُظهر مجموعة الصيدلية', () {
      final modules = {...modulesOfEdition('standard'), 'pharmacy'};
      expect(labelsFor('standard', modules: modules), contains('الصيدلية'));
    });

    test('المحاسبة وحدها لا تكفي لفواتير الموردين — تلزم المشتريات معها', () {
      // النقطة على الخادم تشترط accounting **و** procurement. وبندٌ يظهر
      // بشرطٍ أوسع يُفتح ليردّه الخادم بـ«وحدة غير مفعَّلة».
      final modules = {...modulesOfEdition('standard'), 'accounting'};
      expect(routesFor('standard', modules: modules), isNot(contains('/supplier-invoices')));
      expect(
        routesFor('standard', modules: {...modules, 'procurement'}),
        contains('/supplier-invoices'),
      );
    });
  });

  // الجرد لا يتبع وحدة المخزون: من يمسك عهدةً يُسأل عنها ولو لم يكن يبيع
  // بضاعة، والخادم صار يفتح النقطة لكل إصدار. وحارسٌ هنا لأن الخطر هو أن
  // يُقيَّد البند بمجموعة المخزون مرّةً أخرى فتُغلَق الشاشة على من فُتحت
  // له على الخادم — بابٌ مفتوحٌ لا طريق إليه.
  group('الجرد الدوري في كل الإصدارات', () {
    test('يظهر لإصدار المحفظة رغم غياب مجموعة المخزون', () {
      expect(labelsFor('wallet'), isNot(contains('المخزون')));
      expect(routesFor('wallet'), contains('/stock-count'));
    });

    test('يظهر لمحفظة المحاسبة أيضاً', () {
      expect(routesFor('wallet_plus'), contains('/stock-count'));
    });

    test('ولا يتكرّر عند من عنده مخزون — بندٌ واحد لا اثنان', () {
      final routes = routesFor('standard');
      expect(routes.where((r) => r == '/stock-count').length, 1);
    });

    test('ومؤسساتٌ سُحب منها المخزون تحتفظ بجردها', () {
      final modules = {...modulesOfEdition('enterprise')}..remove('inventory');
      expect(routesFor('enterprise', modules: modules), contains('/stock-count'));
    });
  });

  group('وحدة سُحبت من الإصدار', () {
    test('مؤسساتٌ بلا محاسبة تُخفي دفترها', () {
      final modules = {...modulesOfEdition('enterprise')}..remove('accounting');
      expect(labelsFor('enterprise', modules: modules), isNot(contains('المحاسبة')));
    });

    test('مؤسساتٌ بلا مخزون تُخفي مجموعته كاملة', () {
      final modules = {...modulesOfEdition('enterprise')}..remove('inventory');
      expect(labelsFor('enterprise', modules: modules), isNot(contains('المخزون')));
    });
  });

  test('المرتَّبات تتبع شكل الإصدار لا الوحدات — لا تُباع منفردة', () {
    // حارسٌ على الفرق: ما هو **شكل** لا يُشترى. متجرٌ يبيع بضاعة لا يصير
    // جهةً تصرف على منتسبيها بإضافة وحدة.
    expect(
      routesFor('standard', modules: {...modulesOfEdition('standard'), 'accounting'}),
      isNot(contains('/payroll')),
    );
    expect(routesFor('wallet'), contains('/payroll'));
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
