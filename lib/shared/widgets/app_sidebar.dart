import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/shell/open_tabs_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/branding_provider.dart';
import 'nav_items.dart';
import 'animations.dart';
import '../../core/auth/permissions.dart';
import 'authed_image.dart';

/// الشريط الجانبي الموحّد — أي موديول جديد يُضاف مستقبلاً (حسب
/// ARCHITECTURE.md) يُسجَّل في nav_items.dart بسطر واحد فقط ويظهر تلقائياً
/// على كل الشاشات. النقر يفتح تبويباً في AppShell (أو يُنشِّط الموجود منه)،
/// لا يستبدل الصفحة كلها.
///
/// العناصر مجمَّعة في مجموعات قابلة للطي بدل قائمة واحدة من 18 عنصراً —
/// وعلى الموبايل هذا هو الفرق بين درج قابل للاستخدام ودرج يحتاج تمريراً
/// طويلاً للوصول لأي شيء.
class AppSidebar extends ConsumerStatefulWidget {
  const AppSidebar({super.key, required this.activeRoute});
  final String activeRoute;

  @override
  ConsumerState<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends ConsumerState<AppSidebar> {
  // ⚠ من isPlatformAdminProvider لا من نسخةٍ محلّية في initState.
  //
  // كانت الدعوى تُقرأ مرّةً واحدة عند أوّل بناء وتُحفَظ في الحالة. فمن
  // خرج ودخل بحسابٍ آخر بلا إعادة تحميل الصفحة يبقى على قيمة الحساب
  // الأوّل — يرى بنود المنصّة وليس مالكها، أو لا يراها وهو مالكها.
  //
  // والمُوفِّر واحدٌ للتطبيق كلّه: الشريط الجانبي وشريط الهاتف كانا
  // يقرآن الدعوى كلٌّ على حدة، فيفترقان أوّل مرّة يتغيّر أحدهما.

  void _open(NavItem item) {
    ref.read(openTabsProvider.notifier).open(item.route, title: item.label, icon: item.icon);
    // على الموبايل هذا الشريط داخل Drawer قابل للسحب — يجب إغلاقه يدوياً
    // لأن فتح تبويب لم يعد يُغيّر المسار (go_router) فلا يُغلَق تلقائياً.
    Scaffold.maybeOf(context)?.closeDrawer();
  }

  @override
  Widget build(BuildContext context) {
    final perms = ref.perms;
    final groups = filterByPermissions(
      navGroupsFor(
        isPlatformAdmin: ref.watch(isPlatformAdminProvider).valueOrNull ?? false,
        edition: ref.watch(brandingProvider).valueOrNull?.edition ?? 'standard',
        modules: ref.watch(brandingProvider).valueOrNull?.modules ??
            OrganizationBranding.fallback.modules,
      ),
      (route) {
        final required = kRoutePermissions[route];
        return required == null || perms.can(required);
      },
    );
    final branding = ref.watch(brandingProvider).valueOrNull;
    final color = Theme.of(context).colorScheme.primary;

    // Material لا Container: ExpansionTile (وهو ListTile داخلياً) يرسم
    // خلفيته وأثر النقر على أقرب Material أعلاه. مع Container ملوّن يعترض
    // الطريق تختفي تلك الآثار خلف لونه — وFlutter يؤكّد على ذلك بصراحة في
    // وضع التطوير. Material يوفّر اللون والسطح معاً فيزول التعارض.
    return Material(
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            alignment: AlignmentDirectional.centerStart,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    branding?.displayName ?? 'إتقان ERP',
                    style: AppTextStyles.headlineMd(),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 10),
                // شعار المنظمة إن رفعته، وإلا شعار المنتج — لا أيقونة
                // عامّة. والسقوط على الأصل المحلي يجعل الشريط يحمل هويةً
                // ولو انقطعت الشبكة أو حُذف الملف من الخادم.
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: branding?.logoUrl != null
                      ? AuthedImage(
                          path: branding!.logoUrl!,
                          width: 32,
                          height: 32,
                          fit: BoxFit.cover,
                          errorWidget: Image.asset(
                            'assets/branding/itqan_logo.png',
                            width: 32,
                            height: 32,
                            fit: BoxFit.cover,
                          ),
                        )
                      : Image.asset(
                          'assets/branding/itqan_logo.png',
                          width: 32,
                          height: 32,
                          fit: BoxFit.cover,
                        ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: groups.map((group) {
                if (group.isSingle) {
                  return _SidebarTile(
                    item: group.single,
                    active: widget.activeRoute == group.single.route,
                    onTap: () => _open(group.single),
                  );
                }

                final hasActive = group.containsRoute(widget.activeRoute);
                return Theme(
                  // ExpansionTile يرسم خطَّي فاصل افتراضيين يشوّشان القائمة.
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    key: PageStorageKey(group.label),
                    initiallyExpanded: hasActive,
                    tilePadding: const EdgeInsets.symmetric(horizontal: 20),
                    childrenPadding: EdgeInsets.zero,
                    leading: Icon(group.icon, size: 20, color: hasActive ? color : AppColors.textSecondary),
                    title: Text(
                      group.label,
                      style: AppTextStyles.bodyMd(color: hasActive ? color : AppColors.textPrimary)
                          .copyWith(fontWeight: hasActive ? FontWeight.w600 : FontWeight.w400),
                    ),
                    children: group.items
                        .map((item) => _SidebarTile(
                              item: item,
                              active: widget.activeRoute == item.route,
                              indented: true,
                              onTap: () => _open(item),
                            ))
                        .toList(),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.item,
    required this.active,
    required this.onTap,
    this.indented = false,
  });

  final NavItem item;
  final bool active;
  final VoidCallback onTap;
  final bool indented;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    // selected لا يُستنتج بصرياً: التظليل الخفيف هو كل ما يميّز العنصر
    // النشط، وهو غير مرئي لقارئ الشاشة. بدون الوسم يتنقّل المستخدم بين
    // ثمانية عشر عنصراً متطابقة صوتياً بلا معرفة أين هو الآن.
    return Semantics(
      button: true,
      selected: active,
      label: item.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          // AnimatedContainer بدل Container: تبديل التبويب يُظلّل العنصر
          // الجديد تدريجياً بدل قفزة لونية مفاجئة، فيتابع النظر أين انتقل.
          child: AnimatedContainer(
            duration: AppMotion.fast,
            curve: AppMotion.curve,
            color: active ? color.withValues(alpha: 0.08) : Colors.transparent,
            padding: EdgeInsetsDirectional.only(start: indented ? 44 : 20, end: 20, top: 12, bottom: 12),
            child: Row(
              children: [
                Icon(item.icon, size: indented ? 18 : 20, color: active ? color : AppColors.textSecondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.label,
                    style: AppTextStyles.bodyMd(
                      color: active ? color : AppColors.textPrimary,
                    ).copyWith(fontWeight: active ? FontWeight.w600 : FontWeight.w400),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
