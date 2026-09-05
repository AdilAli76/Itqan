import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/branding_provider.dart';

import 'current_user.dart';
import '../network/api_client.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// أكواد الصلاحيات كما هي مسجَّلة في جدول Permissions ومستعملة في
/// RequirePermissionAttribute على الخادم.
///
/// ثوابت لا نصوص حرّة: الكود المكتوب يدوياً في الشاشة يخطئ حرفاً فيصمت —
/// `can('inventory.mange')` تُرجع false دائماً بلا أي خطأ، فيختفي زر يملك
/// المستخدم صلاحيته ولا أحد يعرف السبب. الثابت يجعل الخطأ خطأ ترجمة.
///
/// أي رمز يُضاف على الخادم يُضاف هنا بسطر واحد.
class Perm {
  const Perm._();

  static const auditLogView = 'audit_log.view';
  static const backupManage = 'backup.manage';
  static const cardsIssue = 'cards.issue';
  static const categoriesManage = 'categories.manage';
  static const customersDelete = 'customers.delete';
  static const customersManage = 'customers.manage';
  static const customersWalletAdjust = 'customers.wallet_adjust';
  static const inventoryDelete = 'inventory.delete';
  static const inventoryManage = 'inventory.manage';
  static const invoicesRefund = 'invoices.refund';
  static const licenseView = 'license.view';
  static const purchasingManage = 'purchasing.manage';
  static const reportsView = 'reports.view';
  static const stockCountManage = 'stock_count.manage';
  static const stockTransferManage = 'stock_transfer.manage';
  static const suppliersDelete = 'suppliers.delete';
  static const suppliersManage = 'suppliers.manage';
}

/// صلاحيات المستخدم الحالي.
@immutable
class UserPermissions {
  const UserPermissions({
    required this.role,
    required this.isSuperAdmin,
    required this.codes,
  });

  factory UserPermissions.fromJson(Map<String, dynamic> json) {
    return UserPermissions(
      role: json['role'] as String? ?? '',
      isSuperAdmin: json['isSuperAdmin'] as bool? ?? false,
      codes: Set<String>.from((json['permissions'] as List? ?? const []).cast<String>()),
    );
  }

  /// الحالة قبل وصول الرد أو عند تعذّره.
  ///
  /// لا صلاحيات — لا الكل. الافتراض المتساهل هنا كان سيعرض كل الأزرار للحظة
  /// ثم يُخفي بعضها عند وصول الرد، وهو ارتجاف مربك؛ والأسوأ أنه يجعل عطلاً
  /// في الشبكة يبدو كأنه ترقية صلاحيات.
  static const none = UserPermissions(role: '', isSuperAdmin: false, codes: {});

  final String role;
  final bool isSuperAdmin;
  final Set<String> codes;

  bool can(String code) => isSuperAdmin || codes.contains(code);

  /// هل يملك أياً من هذه الصلاحيات — لشاشة تُفتح بأكثر من مسار.
  bool canAny(Iterable<String> anyOf) => anyOf.any(can);
}

/// يُقرأ مرّة واحدة لكل جلسة ويبقى محفوظاً.
///
/// ليس autoDispose عمداً: تُقرأ في كل شاشة تقريباً، وإعادة الطلب مع كل فتح
/// تبويب حِمل بلا مقابل على بيانات لا تتغيّر داخل الجلسة. تغيير المصفوفة من
/// شاشة الصلاحيات يستدعي `ref.invalidate(myPermissionsProvider)` صراحةً.
final myPermissionsProvider = FutureProvider<UserPermissions>((ref) async {
  try {
    final response = await ApiClient.instance.dio.get('/permissions/me');
    return UserPermissions.fromJson(response.data as Map<String, dynamic>);
  } catch (_) {
    return UserPermissions.none;
  }
});

/// قراءة متزامنة مريحة داخل build — تُرجع [UserPermissions.none] ريثما يصل
/// الرد، فلا تحتاج كل شاشة إلى معالجة حالة تحميل لمجرّد إظهار زر.
extension PermissionsRef on WidgetRef {
  UserPermissions get perms => watch(myPermissionsProvider).valueOrNull ?? UserPermissions.none;
}

/// يُظهر [child] لمن يملك [permission] فقط.
///
/// الإخفاء هو الافتراضي لا التعطيل: زر رمادي دائم يسأل عنه المستخدم الدعم
/// كل مرّة، ولا يستطيع فعل شيء حياله لأن الصلاحية ليست بيده. أما [disable]
/// فلحالة يكون فيها غياب الزر نفسه مربكاً — كأن يختفي زر «حفظ» من نموذج
/// مفتوح، فيظنّ المستخدم أن الشاشة معطّلة.
class Can extends ConsumerWidget {
  const Can({
    super.key,
    required this.permission,
    required this.child,
    this.disable = false,
    this.fallback,
  });

  final String permission;
  final Widget child;
  final bool disable;

  /// بديل يُعرض بدل الإخفاء التام (مثل نص «للاطّلاع فقط»).
  final Widget? fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.perms.can(permission)) return child;
    if (disable) {
      return Tooltip(
        message: 'ليست لديك صلاحية هذا الإجراء',
        child: Opacity(
          opacity: 0.45,
          // IgnorePointer لا onPressed: null — الأخير يتطلّب تعديل كل ودجت
          // على حدة، وهذا يعمل مع أي محتوى مهما كان نوعه.
          child: IgnorePointer(child: child),
        ),
      );
    }
    return fallback ?? const SizedBox.shrink();
  }
}

/// شريط يعلن أن الشاشة للاطّلاع فقط.
///
/// بدونه يبدو غياب أزرار الإضافة والتعديل عطلاً في النظام لا قيداً مقصوداً —
/// وهذا أكثر ما يولّد بلاغات دعم لا سبب لها.
class ReadOnlyBanner extends ConsumerWidget {
  const ReadOnlyBanner({super.key, required this.permission, this.message});

  final String permission;
  final String? message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.perms.can(permission)) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.visibility_outlined, size: 16, color: AppColors.info),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message ?? 'عرض للاطّلاع فقط — لا تملك صلاحية التعديل في هذه الشاشة',
              style: AppTextStyles.labelMd(color: AppColors.info),
            ),
          ),
        ],
      ),
    );
  }
}

/// المسارات المحجوبة بالكامل، لا أزرارها فقط.
///
/// الفرق جوهري ويجب ألّا يُخلط: أغلب الوحدات تسمح بالاطّلاع وتحرس الأفعال
/// وحدها (المخزون يُقرأ بلا صلاحية، وتعديله يحتاج inventory.manage). أما
/// هذه الثلاث فالحارس فيها على مستوى الـController كله في الخادم — لا
/// قراءة أصلاً بلا الصلاحية.
///
/// إخفاء وحدة يملك المستخدم حقّ الاطّلاع عليها خطأ بنفس سوء إظهار زر لا
/// يملكه: كلاهما يحجب عملاً مشروعاً. لذلك تقتصر هذه الخريطة على ما يحجبه
/// الخادم فعلاً.
const Map<String, String> kRoutePermissions = {
  '/audit-log': Perm.auditLogView,
  '/reports': Perm.reportsView,
  '/license': Perm.licenseView,
};

/// شاشة بديلة حين لا يملك المستخدم صلاحية فتح الوحدة.
///
/// رسالة صريحة بدل جدول فارغ أو خطأ 403 خام: الأول يجعل المستخدم يظن أن
/// لا بيانات، والثاني يجعله يظن أن النظام معطّل. كلاهما ينتهي ببلاغ دعم.
class NoPermissionView extends StatelessWidget {
  const NoPermissionView({super.key, required this.moduleName});

  final String moduleName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: 32, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text('لا تملك صلاحية الاطّلاع على $moduleName',
              style: AppTextStyles.headlineMd(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Text(
            'راجع مدير النظام لديك لمنحك الصلاحية من شاشة «مصفوفة الصلاحيات».',
            style: AppTextStyles.bodyMd(),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// هل المستخدم الحالي مالك المنصّة (بائع النظام لا عميله)؟
///
/// بوابة مستقلة تماماً عن مصفوفة الصلاحيات، ومقصودٌ إبقاؤها كذلك: المصفوفة
/// يعدّلها مدير كل منظمة لأدوار منظمته، فلو كانت «إدارة المنصّة» عنصراً
/// فيها لأمكن لأي مدير منظمة أن يمنح نفسه صلاحيات على المنصّة كلها — وهو
/// تصعيد امتيازات عبر الحدود بين العملاء.
///
/// تُقرأ من دعوى is_platform_admin في التوكن، نفس ما يفحصه الخادم في
/// PlatformController وPlatformSettingsController.
final isPlatformAdminProvider = FutureProvider<bool>((ref) async {
  final claims = await readJwtClaims();
  return claims?['is_platform_admin'] == 'True';
});

/// أمالكُ المنصّة هو، أم مهندس بيع يعمل تحت ترخيصه؟
///
/// **والغياب يعني مالكاً لا مهندساً.** كل حساب منصّة أُنشئ قبل وجود
/// المهندسين مالكٌ، وتوكنٌ أُصدر قبل الترقية يبقى صالحاً ثماني ساعات —
/// فتفسير غياب الدعوى «مهندس» كان يسلب المالك أزراره حتى ينتهي توكنه،
/// بلا شيء في الشاشة يدلّه على السبب. يقابل `PlatformRoles.IsOwner`.
///
/// وهذا إخفاءُ واجهة لا حماية: الحارس الفعلي `PlatformScope` على الخادم.
final isPlatformOwnerProvider = FutureProvider<bool>((ref) async {
  final claims = await readJwtClaims();
  if (claims?['is_platform_admin'] != 'True') return false;
  return claims?['platform_role'] != 'engineer';
});

/// رقم ترخيص البائع — يُطبع في عقد كل عميل يبيعه صاحب هذا التوكن.
final resellerLicenseProvider = FutureProvider<String?>((ref) async {
  final claims = await readJwtClaims();
  final value = claims?['reseller_license'];
  return (value is String && value.isNotEmpty) ? value : null;
});

/// يُبطل كل ما يخصّ المستخدم — يُستدعى عند الدخول وعند الخروج.
///
/// **العطب الذي يصلحه:** هذه المُوفِّرات تُخزَّن لعمر التطبيق، ولا شيء
/// يخبرها أن المستخدم تبدّل. فمن خرج ودخل بحسابٍ آخر في نفس الجلسة يبقى
/// على صلاحيات الأوّل: مدير منظمةٍ عادية يرى بنود المنصّة، ومالك المنصّة
/// لا يراها — وكلاهما وقع فعلاً.
///
/// وأخطر من اختفاء زرّ: صلاحياتٌ مخزَّنة من حسابٍ أوسع تُظهر أزراراً لمن
/// لا يملكها. والخادم يرفض الطلب — فالعزل قائم — لكنّ الواجهة تَعِد بما
/// لا يُنفَّذ، وذاك عطبٌ يُبلَّغ عنه كأنه خلل في النظام.
///
/// وتُستدعى في **الموضعين**: الدخول وحده لا يكفي إن أُغلق التطبيق على
/// شاشة الدخول، والخروج وحده لا يكفي لمن دخل بعد انتهاء توكن.
void invalidateUserScopedProviders(WidgetRef ref) {
  ref.invalidate(myPermissionsProvider);
  ref.invalidate(isPlatformAdminProvider);
  // ومُوفِّرا الدور والرقم معهما: نسيانُ أحدهما هو عين العطب الذي أوجد هذه
  // الدالّة — مهندسٌ يدخل بعد مالك فيرى أزرار المالك حتى يُغلق التطبيق.
  ref.invalidate(isPlatformOwnerProvider);
  ref.invalidate(resellerLicenseProvider);
  ref.invalidate(brandingProvider);
}

/// نظير [Can] لبوابة مالك المنصّة.
class CanPlatform extends ConsumerWidget {
  const CanPlatform({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOwner = ref.watch(isPlatformAdminProvider).valueOrNull ?? false;
    return isOwner ? child : const SizedBox.shrink();
  }
}
