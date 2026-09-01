import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/api_client.dart';
import 'app_colors.dart';

class OrganizationBranding {
  const OrganizationBranding({
    required this.displayName,
    required this.logoUrl,
    required this.colors,
    required this.currencySymbol,
    required this.navLayout,
    required this.edition,
    required this.modules,
  });

  final String displayName;
  final String? logoUrl;
  final AppColors colors;
  final String currencySymbol;
  // 'sidebar' أو 'navbar' — تفضيل عرض بحت يختاره كل عميل، راجع AdaptiveScaffold.
  final String navLayout;

  /// شكل النظام: standard | wallet | pharmacy | trial | enterprise.
  ///
  /// يُقرَّر عند إنشاء المنظمة ولا يُغيَّر من الواجهة — تغييره بعد التشغيل
  /// يعني إخفاء وحدات فيها بيانات قائمة.
  final String edition;

  /// الوحدات المفعَّلة فعلياً لهذه المنظمة — يحسبها الخادم ولا تُشتقّ هنا.
  ///
  /// الإصدار صار قالباً ابتدائياً لا سقفاً: تُشترى وحدات فوقه وتُسحب منه
  /// بعد البيع (راجع `LicenseLimits.EffectiveModules` في الخادم). فاشتقاق
  /// القائمة من الإصدار في Dart — وهو ما كان — يعني عميلاً يدفع ثمن وحدة
  /// يفتحها له الخادم ولا يجد لها بنداً في قائمته.
  final Set<String> modules;

  bool has(String module) => modules.contains(module);

  /// إصدار المحفظة: بطاقات وأرصدة بلا بضاعة. نقطة البيع تُدخِل مبلغاً،
  /// ولا كتالوج ولا مخزون ولا مشتريات.
  /// إصدارٌ على شكل المحفظة — بطاقات وأرصدة بلا بضاعة.
  ///
  /// <para>يشمل `wallet_plus` (المحفظة ومعها المحاسبة): هو محفظةٌ في كل
  /// سلوكه، والفارق دفترٌ لا شكلُ شاشة. ويقابل `Editions.IsWalletShaped`
  /// في الخادم — والقائمتان تُقرآن معاً.</para>
  bool get isWallet => edition == 'wallet' || edition == 'wallet_plus';

  /// إصدار الصيدليات: نشرة الدواء مربوطة بالأصناف وتُعرض لحظة الصرف.
  ///
  /// مقصور على من اشتراه: النظام يُباع لبقالة ومحل قطع غيار أيضاً، وحقول
  /// «موانع الاستعمال» و«الجرعة» في شاشة أصنافهم ضوضاء تُربك ولا تُفيد.
  /// والإخفاء هنا للواجهة فقط — الحارس الفعلي على الخادم
  /// (RequireModule("pharmacy")).
  bool get isPharmacy => edition == 'pharmacy';

  static const fallback = OrganizationBranding(
    displayName: 'منظومة إتقان ERP',
    logoUrl: null,
    colors: AppColors(),
    currencySymbol: 'د.ل',
    navLayout: 'sidebar',
    edition: 'standard',
    // مكتوبةً لا مستدعاةً: الثابت const لا يستدعي دوالّ. وهي عين ما
    // يُرجعه [modulesOfEdition] للإصدار القياسي.
    modules: {'inventory', 'pos', 'customers', 'reports'},
  );
}

/// وحدات الإصدار — **احتياطٌ لا مصدر**.
///
/// عامّة لا خاصّة لأن الاختبارات تبني منها قائمة التنقّل: اختبارٌ يكتب
/// مجموعته بيده يوافق نفسه أبداً ولا يوافق التطبيق.
///
/// تُستعمل في حالتين فقط: خادمٌ أقدم من هذه النسخة لا يُرسل `modules`،
/// وتعذّرُ الاتصال قبل تسجيل الدخول. وتقابل `Editions.ModulesOf` في
/// الخادم — واختلافها عنه يُخفي بنداً يسمح به الخادم لا أكثر، لأن الحارس
/// الفعلي هناك.
///
/// ولا تعرف شيئاً عن الوحدات المُباعة منفردة: تلك لا تُعرَف إلا من الخادم،
/// وهذا سبب كون هذه القائمة احتياطاً لا حساباً يُعتمد عليه.
Set<String> modulesOfEdition(String edition) => switch (edition) {
      'wallet' => const {'pos', 'customers', 'reports'},
      'wallet_plus' => const {'pos', 'customers', 'reports', 'accounting'},
      'pharmacy' => const {'inventory', 'pos', 'customers', 'reports', 'pharmacy'},
      'enterprise' => const {
          'inventory', 'pos', 'customers', 'reports',
          'warehouses', 'valuation', 'procurement', 'accounting',
        },
      _ => const {'inventory', 'pos', 'customers', 'reports'},
    };

/// يستدعي GET /api/organizations/me على الـ .NET Backend — الاستدعاء
/// الوحيد الذي كان يذهب مباشرة لجدول Supabase أصبح الآن طلب HTTP عادي
/// عبر [ApiClient]، والحماية على البيانات تتم عبر Security Policy
/// الخاصة بـ SQL Server بدل RLS الخاصة بـ Postgres — نفس الضمان، طبقة مختلفة.
final brandingProvider = FutureProvider<OrganizationBranding>((ref) async {
  try {
    final response = await ApiClient.instance.dio.get('/organizations/me');
    final data = response.data as Map<String, dynamic>;
    final edition = data['edition'] as String? ?? 'standard';
    final modules = (data['modules'] as List?)?.whereType<String>().toSet() ?? <String>{};

    return OrganizationBranding(
      displayName: data['displayName'] as String? ?? OrganizationBranding.fallback.displayName,
      logoUrl: data['logoUrl'] as String?,
      colors: AppColors.fromHex(
        primaryHex: data['primaryColor'] as String?,
        secondaryHex: data['secondaryColor'] as String?,
      ),
      currencySymbol: data['currencySymbol'] as String? ?? 'د.ل',
      navLayout: data['navLayout'] as String? ?? 'sidebar',
      edition: edition,
      // قائمة فارغة من خادمٍ أقدم لا تعني «لا وحدات» بل «لا يعرفها»: تفسيرها
      // حرفياً كان يُفرغ القائمة الجانبية تماماً بعد نشرِ واجهةٍ قبل خادمها.
      modules: modules.isEmpty ? modulesOfEdition(edition) : modules,
    );
  } catch (_) {
    // قبل تسجيل الدخول (لا توكن بعد) أو تعذّر الاتصال بالسيرفر -> اللوحة
    // الافتراضية بدل شاشة بيضاء أو استثناء غير معالَج.
    return OrganizationBranding.fallback;
  }
});
