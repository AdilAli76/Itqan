import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/permissions.dart';
import '../../../core/shell/open_tabs_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/branding_provider.dart';
import '../../../shared/widgets/nav_items.dart';

/// شبكة اختصارات الشاشة الرئيسية — أيقونةٌ كبيرة لكل شاشة.
///
/// <para><b>سبب وجودها:</b> على الهاتف كان الوصول إلى أي شاشة يمرّ بقائمة
/// همبرغر ثم مجموعة ثم بند — ثلاث لمسات وقراءة سطرين. والكاشير يفتح النظام
/// ليصل إلى شاشة البيع لا ليقرأ أرقام اليوم.</para>
///
/// <para><b>وتُولَّد من [navGroupsFor] نفسها لا من قائمةٍ ثانية.</b> وهذا
/// شرطُ وجودها: خمسٌ وعشرون شاشة ظهورُها يتوقّف على الإصدار والصلاحية،
/// وقائمةٌ مكتوبة بيدها تفترق عن مصدرها أوّل ما تُضاف شاشة — فتظهر أيقونةٌ
/// لشاشة يمنعها الخادم، أو تختفي ميزةٌ اشتراها العميل ولا يعرف لماذا.</para>
///
/// <para><b>والأكثر استعمالاً أوّلاً:</b> خمسٌ وعشرون أيقونة دفعةً واحدة
/// جدارٌ لا اختصار. فما يُفتح يومياً في الأعلى، والبقيّة خلف «كل الشاشات»
/// — ولا يُحذف شيء.</para>
class ShortcutsHome extends ConsumerStatefulWidget {
  const ShortcutsHome({super.key});

  @override
  ConsumerState<ShortcutsHome> createState() => _ShortcutsHomeState();
}

class _ShortcutsHomeState extends ConsumerState<ShortcutsHome> {
  bool _showAll = false;

  /// ما يُفتح يومياً، بترتيب الاستعمال لا بترتيب القائمة.
  ///
  /// <para>مسارات لا بنود: البند نفسه يأتي من [navGroupsFor] بأيقونته
  /// واسمه، فلا يُكتب هنا إلا **الترتيب**.</para>
  static const _daily = [
    '/pos',
    '/customers',
    '/invoices',
    '/inventory',
    '/stock-count',
    '/reports',
  ];

  @override
  Widget build(BuildContext context) {
    final perms = ref.perms;
    final branding = ref.watch(brandingProvider).valueOrNull;

    final groups = filterByPermissions(
      navGroupsFor(
        isPlatformAdmin: ref.watch(isPlatformAdminProvider).valueOrNull ?? false,
        edition: branding?.edition ?? 'standard',
        modules: branding?.modules ?? OrganizationBranding.fallback.modules,
      ),
      (route) {
        final required = kRoutePermissions[route];
        return required == null || perms.can(required);
      },
    );

    final all = [for (final group in groups) ...group.items];
    // لوحة التحكّم نفسها لا تدخل الشبكة: الشبكة **هي** لوحة التحكّم الآن،
    // وأيقونةٌ تفتح ما أنت فيه تُربك.
    final available = all.where((i) => i.route != '/dashboard').toList();

    final daily = [
      for (final route in _daily)
        ...available.where((i) => i.route == route),
    ];
    final rest = available.where((i) => !_daily.contains(i.route)).toList();

    return LayoutBuilder(builder: (context, constraints) {
      // عمودان على الهاتف كما اعتاد المستخدم، وأربعة على الأوسع — والأيقونة
      // تبقى بحجمها فلا تتضخّم على اللوحي.
      final columns = constraints.maxWidth < 420
          ? 2
          : constraints.maxWidth < 700
              ? 3
              : 4;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _grid(daily, columns),
          if (rest.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => setState(() => _showAll = !_showAll),
                icon: Icon(_showAll ? Icons.expand_less : Icons.expand_more, size: 18),
                label: Text(_showAll ? 'إخفاء البقيّة' : 'كل الشاشات (${rest.length})'),
              ),
            ),
            if (_showAll) _grid(rest, columns),
          ],
        ],
      );
    });
  }

  Widget _grid(List<NavItem> items, int columns) => GridView.count(
        crossAxisCount: columns,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        // نسبةٌ تُبقي البطاقة أعلى من ٩٦ بكسل عند كل عرض: أهداف اللمس
        // مفحوصة آلياً في ui_audit_test، وبطاقةٌ ضيّقة تكسره.
        childAspectRatio: 1.15,
        children: [for (final item in items) _tile(item)],
      );

  Widget _tile(NavItem item) => Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => ref
              .read(openTabsProvider.notifier)
              .open(item.route, title: item.label, icon: item.icon),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.infoBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(item.icon, size: 26, color: AppColors.info),
                ),
                const SizedBox(height: 10),
                Text(
                  item.label,
                  textAlign: TextAlign.center,
                  // سطران بحدّ أقصى: «تحويل المخزون بين الفروع» لا يقصّ
                  // نصفه، ولا يمطّ البطاقة فتختلف عن جاراتها.
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyMd(color: AppColors.textPrimary),
                ),
              ],
            ),
          ),
        ),
      );
}
