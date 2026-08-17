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
  });

  final String displayName;
  final String? logoUrl;
  final AppColors colors;
  final String currencySymbol;
  // 'sidebar' أو 'navbar' — تفضيل عرض بحت يختاره كل عميل، راجع AdaptiveScaffold.
  final String navLayout;

  static const fallback = OrganizationBranding(
    displayName: 'Kinetic Enterprise',
    logoUrl: null,
    colors: AppColors(),
    currencySymbol: 'د.ل',
    navLayout: 'sidebar',
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
    );
  } catch (_) {
    // قبل تسجيل الدخول (لا توكن بعد) أو تعذّر الاتصال بالسيرفر -> اللوحة
    // الافتراضية بدل شاشة بيضاء أو استثناء غير معالَج.
    return OrganizationBranding.fallback;
  }
});
