import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/shell/open_tabs_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/constants/app_constants.dart';
import 'nav_items.dart';
import '../../core/auth/permissions.dart';
import '../../core/theme/branding_provider.dart';
import '../../features/notifications/presentation/notification_bell.dart';

/// بديل أفقي عن AppSidebar لمن يفضّل شريطاً علوياً بدل شريط جانبي ثابت —
/// نفس مجموعات nav_items.dart بالضبط، فقط بتخطيط مختلف. راجع AppShell
/// للاختيار بين الاثنين حسب organizations.nav_layout.
///
/// المجموعات تُعرض كقوائم منسدلة بدل صفّ من 18 زراً كان يمتدّ أفقياً
/// خارج الشاشة ويحتاج تمريراً جانبياً للوصول لآخره.
class AppNavbar extends ConsumerStatefulWidget {
  const AppNavbar({super.key, required this.activeRoute});
  final String activeRoute;

  @override
  ConsumerState<AppNavbar> createState() => _AppNavbarState();
}

class _AppNavbarState extends ConsumerState<AppNavbar> {
  // ⚠ من isPlatformAdminProvider لا من نسخةٍ محلّية في initState.
  //
  // كانت الدعوى تُقرأ مرّةً واحدة عند أوّل بناء وتُحفَظ في الحالة. فمن
  // خرج ودخل بحسابٍ آخر بلا إعادة تحميل الصفحة يبقى على قيمة الحساب
  // الأوّل — يرى بنود المنصّة وليس مالكها، أو لا يراها وهو مالكها.
  //
  // والمُوفِّر واحدٌ للتطبيق كلّه: الشريط الجانبي وشريط الهاتف كانا
  // يقرآن الدعوى كلٌّ على حدة، فيفترقان أوّل مرّة يتغيّر أحدهما.

  void _open(NavItem item) =>
      ref.read(openTabsProvider.notifier).open(item.route, title: item.label, icon: item.icon);

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
    final color = Theme.of(context).colorScheme.primary;

    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: groups.map((group) {
                  final active = group.containsRoute(widget.activeRoute);

                  if (group.isSingle) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                      child: _NavButton(
                        icon: group.single.icon,
                        label: group.single.label,
                        active: active,
                        onTap: () => _open(group.single),
                      ),
                    );
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                    child: PopupMenuButton<NavItem>(
                      tooltip: group.label,
                      position: PopupMenuPosition.under,
                      onSelected: _open,
                      itemBuilder: (context) => group.items
                          .map((item) => PopupMenuItem<NavItem>(
                                value: item,
                                child: Row(
                                  children: [
                                    Icon(
                                      item.icon,
                                      size: 18,
                                      color: widget.activeRoute == item.route ? color : AppColors.textSecondary,
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      item.label,
                                      style: AppTextStyles.bodyMd(
                                        color: widget.activeRoute == item.route ? color : AppColors.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ))
                          .toList(),
                      child: _NavButton(
                        icon: group.icon,
                        label: group.label,
                        active: active,
                        showChevron: true,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: Text(
                'v${AppConstants.appVersion}',
                style: AppTextStyles.caption(color: AppColors.textSecondary),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: NotificationBell(),
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.label,
    required this.active,
    this.onTap,
    this.showChevron = false,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: active ? color : AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(
            label,
            // labelMd هو 13 نقطة أصلاً — لا حاجة لفرضه يدوياً فوق bodyMd.
            style: AppTextStyles.labelMd(color: active ? color : AppColors.textPrimary)
                .copyWith(fontWeight: active ? FontWeight.w600 : FontWeight.w400),
          ),
          if (showChevron) ...[
            const SizedBox(width: 2),
            Icon(Icons.expand_more, size: 16, color: active ? color : AppColors.textSecondary),
          ],
        ],
      ),
    );

    return Material(
      color: active ? color.withValues(alpha: 0.08) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: onTap == null
          ? content
          : InkWell(onTap: onTap, borderRadius: BorderRadius.circular(8), child: content),
    );
  }
}
