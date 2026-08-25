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

  /// إصدار المحفظة: بطاقات وأرصدة بلا بضاعة. نقطة البيع تُدخِل مبلغاً،
  /// ولا كتالوج ولا مخزون ولا مشتريات.
  bool get isWallet => edition == 'wallet';

  /// إصدار الصيدليات: نشرة الدواء مربوطة بالأصناف وتُعرض لحظة الصرف.
  ///
  /// مقصور على من اشتراه: النظام يُباع لبقالة ومحل قطع غيار أيضاً، وحقول
  /// «موانع الاستعمال» و«الجرعة» في شاشة أصنافهم ضوضاء تُربك ولا تُفيد.
  /// والإخفاء هنا للواجهة فقط — الحارس الفعلي على الخادم
  /// (RequireModule("pharmacy")).
  bool get isPharmacy => edition == 'pharmacy';

  static const fallback = OrganizationBranding(
    displayName: 'Kinetic Enterprise',
    logoUrl: null,
    colors: AppColors(),
    currencySymbol: 'د.ل',
    navLayout: 'sidebar',
    edition: 'standard',
  );
}

/// يستدعي GET /api/organizations/me على الـ .NET Backend — الاستدعاء
/// الوحيد الذي كان يذهب مباشرة لجدول Supabase أصبح الآن طلب HTTP عادي
/// عبر [ApiClient]، والحماية على البيانات تتم عبر Security Policy
/// الخاصة بـ SQL Server بدل RLS الخاصة بـ Postgres — نفس الضمان، طبقة مختلفة.
final brandingProvider = FutureProvider<OrganizationBranding>((ref) async {
  try {
    final response = await ApiClient.instance.dio.get('/organizations/me');
    final data = response.data as Map<String, dynamic>;

    return OrganizationBranding(
      displayName: data['displayName'] as String? ?? OrganizationBranding.fallback.displayName,
      logoUrl: data['logoUrl'] as String?,
      colors: AppColors.fromHex(
        primaryHex: data['primaryColor'] as String?,
        secondaryHex: data['secondaryColor'] as String?,
      ),
      currencySymbol: data['currencySymbol'] as String? ?? 'د.ل',
      navLayout: data['navLayout'] as String? ?? 'sidebar',
      edition: data['edition'] as String? ?? 'standard',
    );
  } catch (_) {
    // قبل تسجيل الدخول (لا توكن بعد) أو تعذّر الاتصال بالسيرفر -> اللوحة
    // الافتراضية بدل شاشة بيضاء أو استثناء غير معالَج.
    return OrganizationBranding.fallback;
  }
});
