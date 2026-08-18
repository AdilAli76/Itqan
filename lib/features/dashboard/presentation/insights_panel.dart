import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/shell/open_tabs_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/animations.dart';
import '../../../shared/widgets/nav_items.dart';
import '../../../shared/widgets/skeleton.dart';

/// رؤية واحدة كما يعيدها InsightsController.
class Insight {
  const Insight({
    required this.kind,
    required this.severity,
    required this.title,
    required this.detail,
    this.action,
  });

  factory Insight.fromJson(Map<String, dynamic> json) => Insight(
        kind: json['kind'] as String? ?? '',
        severity: json['severity'] as String? ?? 'info',
        title: json['title'] as String? ?? '',
        detail: json['detail'] as String? ?? '',
        action: json['action'] as String?,
      );

  final String kind;
  final String severity;
  final String title;
  final String detail;
  final String? action;
}

final insightsProvider = FutureProvider.autoDispose<List<Insight>>((ref) async {
  final response = await ApiClient.instance.dio.get('/insights');
  return (response.data as List).map((e) => Insight.fromJson(e as Map<String, dynamic>)).toList();
});

/// لوحة الرؤى التشغيلية أعلى لوحة التحكم.
///
/// موضعها فوق بطاقات الإحصاء مقصود: البطاقات تقول «ماذا حدث» (مبيعات
/// اليوم، عدد الأصناف)، والرؤى تقول «ما الذي يحتاج قراراً الآن». الثاني هو
/// سبب فتح المدير للوحة أصلاً، والأول ما يقرأه بعد أن يطمئنّ.
///
/// وحين لا توجد رؤى لا تختفي اللوحة بل تعلن ذلك صراحةً: «لا شيء يستدعي
/// انتباهك» معلومة مطمئِنة لها قيمة، بينما الفراغ يُقرأ كعطل.
class InsightsPanel extends ConsumerWidget {
  const InsightsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insightsAsync = ref.watch(insightsProvider);

    return insightsAsync.when(
      loading: () => const ListSkeleton(items: 3, showAvatar: true),
      // فشل الرؤى لا يجوز أن يُفشل لوحة التحكم كلها: هي طبقة إضافية فوق
      // الأرقام الأساسية، وغيابها أهون من حجب اللوحة.
      error: (_, __) => const SizedBox.shrink(),
      data: (insights) {
        if (insights.isEmpty) {
          return _Card(
            child: Row(
              children: [
                Icon(Icons.check_circle_outline, size: 20, color: AppColors.success),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'لا شيء يستدعي انتباهك — لا نفاد وشيك ولا بيع بخسارة ولا فواتير شاذّة.',
                    style: AppTextStyles.bodyMd(),
                  ),
                ),
              ],
            ),
          );
        }

        return _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.insights_outlined,
                      size: 18, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('يحتاج انتباهك', style: AppTextStyles.headlineMd()),
                  const Spacer(),
                  Text('${insights.length}',
                      style: AppTextStyles.labelMd(color: AppColors.textMuted)),
                ],
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < insights.length; i++)
                FadeSlideIn(
                  delay: staggerDelay(i),
                  child: _InsightRow(insight: insights[i]),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

class _InsightRow extends ConsumerWidget {
  const _InsightRow({required this.insight});

  final Insight insight;

  /// اللون يحمل معنى الخطورة، والأيقونة تحمل معنى النوع. الفصل بينهما
  /// مقصود: من لا يميّز الألوان يبقى قادراً على التمييز بالأيقونة والنص.
  (Color, Color) get _severityColors => switch (insight.severity) {
        'critical' => (AppColors.danger, AppColors.dangerBg),
        'warning' => (AppColors.warning, AppColors.warningBg),
        _ => (AppColors.info, AppColors.infoBg),
      };

  IconData get _kindIcon => switch (insight.kind) {
        'stockout' => Icons.trending_down,
        'dead_stock' => Icons.inventory_2_outlined,
        'negative_margin' => Icons.money_off_outlined,
        'anomaly' => Icons.error_outline,
        _ => Icons.info_outline,
      };

  void _openAction(WidgetRef ref) {
    final route = insight.action;
    if (route == null) return;
    final item = kNavItems.where((i) => i.route == route).firstOrNull;
    if (item == null) return;
    ref.read(openTabsProvider.notifier).open(item.route, title: item.label, icon: item.icon);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (fg, bg) = _severityColors;
    final actionable = insight.action != null;

    return Semantics(
      button: actionable,
      label: '${insight.title}. ${insight.detail}',
      excludeSemantics: true,
      child: InkWell(
        onTap: actionable ? () => _openAction(ref) : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
                child: Icon(_kindIcon, size: 16, color: fg),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(insight.title,
                        style: AppTextStyles.bodyLg(color: AppColors.textPrimary)
                            .copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(insight.detail, style: AppTextStyles.caption()),
                  ],
                ),
              ),
              if (actionable) ...[
                const SizedBox(width: 8),
                // arrow_back: تنعكس تلقائياً في العربية فتشير لجهة التقدّم.
                Icon(Icons.arrow_back, size: 16, color: AppColors.textMuted),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
