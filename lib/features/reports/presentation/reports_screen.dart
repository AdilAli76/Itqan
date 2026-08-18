import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/responsive/adaptive_scaffold.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/currency_badge.dart';
import '../../../shared/widgets/data_table_widget.dart';
import '../../../shared/widgets/stat_card.dart';
import '../data/reports_providers.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../core/auth/permissions.dart';

// ux-audit: ignore UX-03 — صفوف التقارير ناتج تجميع (GROUP BY) لا سجلات
// خام: عددها محكوم بعدد الفئات أو الفروع أو الأيام في الفترة المختارة.
// ux-audit: ignore UX-02 — الترشيح في هذه الشاشة هو اختيار نوع التقرير
// وفترته، وهو أعلى من الجدول لا داخله.

final _currencyFormat = NumberFormat('#,##0.00', 'en');
final _integerFormat = NumberFormat('#,##0', 'en');
final _dayFormat = DateFormat('yyyy-MM-dd');
final _shortDayFormat = DateFormat('MM/dd');

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(reportPeriodProvider);

    // حارس على مستوى الوحدة لا الزر: الخادم يحرس هذا الـController
    // كاملاً، فبلا الصلاحية لا توجد بيانات تُعرض أصلاً — وعرض جدول
    // فارغ هنا كان يُفهَم كـ«لا توجد سجلات» لا كـ«ليست لك صلاحية».
    if (!ref.perms.can(Perm.reportsView)) {
      return const AdaptiveScaffold(
        title: 'التقارير والتحليلات',
        activeRoute: '/reports',
        body: NoPermissionView(moduleName: 'التقارير'),
      );
    }


    return AdaptiveScaffold(
      title: 'التقارير والتحليلات',
      activeRoute: '/reports',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Wrap لا Row: شريط الفلاتر يفيض على عرض الهاتف. الالتفاف يبقي
          // كل فلتر ظاهراً وقابلاً للنقر بدل قصّ آخره بصمت.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: ReportPeriod.values
                .map((p) => Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: _PeriodChip(
                        label: p.label,
                        selected: p == period,
                        onTap: () => ref.read(reportPeriodProvider.notifier).state = p,
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 20),
          Text('المبيعات', style: AppTextStyles.headlineMd()),
          const SizedBox(height: 12),
          const _SalesSection(),
          const SizedBox(height: 32),
          Text('المخزون', style: AppTextStyles.headlineMd()),
          const SizedBox(height: 12),
          const _InventorySection(),
        ],
      ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        // 44 أدنى هدف لمس؛ الحشو وحده كان يعطي 39.
        // بلا alignment: Container مع alignment وبلا عرض محدَّد يتمدّد ليملأ
        // قيود أبيه (سلوك موثَّق في Flutter). وداخل Wrap تكون تلك القيود
        // عرض السطر كاملاً، فتصبح كل شريحة بعرض الشاشة وتنزل وحدها في سطر —
        // وهو ما جعل فلاتر المشتريات والتقارير تظهر قائمة رأسية لا شرائح.
        // الحشو وحده يوسّط النصّ ويُعطي العرض الطبيعي للمحتوى.
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? color : AppColors.border),
        ),
        child: Text(
          label,
          style: AppTextStyles.labelMd(color: selected ? color : AppColors.textSecondary)
              .copyWith(fontWeight: selected ? FontWeight.w600 : FontWeight.w500),
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

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
        children: [
          Text(message, style: AppTextStyles.bodyMd(color: AppColors.danger)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// المبيعات
// ---------------------------------------------------------------------------

class _SalesSection extends ConsumerWidget {
  const _SalesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(salesSummaryProvider);
    final period = ref.watch(reportPeriodProvider);

    return summaryAsync.when(
      loading: () => const TableSkeleton(),
      error: (err, _) => _ErrorBox(message: 'تعذّر تحميل تقرير المبيعات', onRetry: () => ref.invalidate(salesSummaryProvider)),
      data: (summary) {
        final crossAxisCount = Breakpoints.isDesktop(context) ? 4 : (Breakpoints.isTablet(context) ? 2 : 1);
        final totalRevenue = (summary['totalRevenue'] as num?)?.toDouble() ?? 0;
        final totalReturns = (summary['totalReturns'] as num?)?.toDouble() ?? 0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GridView.count(
              crossAxisCount: crossAxisCount,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1.6,
              children: [
                StatCard(
                  label: 'إجمالي المبيعات',
                  value: '${_currencyFormat.format(totalRevenue)} د.ل',
                  icon: Icons.trending_up,
                ),
                StatCard(
                  label: 'عدد الفواتير',
                  value: _integerFormat.format(summary['totalInvoices'] ?? 0),
                  icon: Icons.receipt_long_outlined,
                ),
                StatCard(
                  label: 'متوسط الفاتورة',
                  value: '${_currencyFormat.format((summary['averageInvoiceValue'] as num?) ?? 0)} د.ل',
                  icon: Icons.calculate_outlined,
                ),
                StatCard(
                  label: 'المرتجعات',
                  value: '${_currencyFormat.format(totalReturns)} د.ل',
                  icon: Icons.keyboard_return,
                  accentColor: AppColors.warning,
                  trend: '${summary['returnCount'] ?? 0} فاتورة',
                  isPositiveTrend: false,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _RevenueChart(
              revenueByDay: List<Map<String, dynamic>>.from(summary['revenueByDay'] as List? ?? []),
              from: period.fromDate,
            ),
            const SizedBox(height: 16),
            AppDataTable(
              title: 'أفضل الأصناف مبيعاً',
              columns: const [AppColumn('الصنف'), AppColumn('الكمية المباعة'), AppColumn('الإيراد')],
              rows: List<Map<String, dynamic>>.from(summary['topProducts'] as List? ?? [])
                  .map((p) => [
                        Text(p['productName'] as String? ?? ''),
                        Text(_integerFormat.format((p['quantitySold'] as num?) ?? 0)),
                        CurrencyBadge(amount: (p['revenue'] as num?)?.toDouble() ?? 0),
                      ])
                  .toList(),
            ),
            const SizedBox(height: 16),
            AppDataTable(
              title: 'أداء الفروع',
              columns: const [AppColumn('الفرع'), AppColumn('عدد الفواتير'), AppColumn('الإيراد')],
              rows: List<Map<String, dynamic>>.from(summary['revenueByBranch'] as List? ?? [])
                  .map((b) => [
                        Text(b['branchName'] as String? ?? ''),
                        Text(_integerFormat.format((b['invoiceCount'] as num?) ?? 0)),
                        CurrencyBadge(amount: (b['revenue'] as num?)?.toDouble() ?? 0),
                      ])
                  .toList(),
            ),
            const SizedBox(height: 16),
            AppDataTable(
              title: 'أداء الكاشير',
              columns: const [AppColumn('الكاشير'), AppColumn('عدد الفواتير'), AppColumn('الإيراد')],
              rows: List<Map<String, dynamic>>.from(summary['revenueByCashier'] as List? ?? [])
                  .map((c) => [
                        Text(c['cashierName'] as String? ?? ''),
                        Text(_integerFormat.format((c['invoiceCount'] as num?) ?? 0)),
                        CurrencyBadge(amount: (c['revenue'] as num?)?.toDouble() ?? 0),
                      ])
                  .toList(),
            ),
          ],
        );
      },
    );
  }
}

class _RevenueChart extends StatelessWidget {
  const _RevenueChart({required this.revenueByDay, required this.from});
  final List<Map<String, dynamic>> revenueByDay;
  final DateTime from;

  @override
  Widget build(BuildContext context) {
    final byDate = <String, double>{};
    for (final point in revenueByDay) {
      final date = DateTime.tryParse(point['date'] as String? ?? '');
      if (date == null) continue;
      byDate[_dayFormat.format(date)] = (point['revenue'] as num?)?.toDouble() ?? 0;
    }

    final dayCount = DateTime.now().difference(from).inDays + 1;
    final spots = List.generate(dayCount, (i) {
      final day = from.add(Duration(days: i));
      return FlSpot(i.toDouble(), byDate[_dayFormat.format(day)] ?? 0);
    });
    final maxRevenue = spots.map((s) => s.y).fold<double>(0, (a, b) => a > b ? a : b);
    final labelStep = (dayCount / 5).ceil().clamp(1, dayCount).toDouble();
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      height: 240,
      padding: const EdgeInsets.fromLTRB(8, 20, 20, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 12, bottom: 8),
            child: Text('اتجاه المبيعات اليومي', style: AppTextStyles.labelMd()),
          ),
          Expanded(
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: maxRevenue <= 0 ? 10 : maxRevenue * 1.2,
                gridData: FlGridData(
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(color: AppColors.border, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 52,
                      getTitlesWidget: (value, meta) => Text(
                        _integerFormat.format(value),
                        style: AppTextStyles.labelMd(color: AppColors.textMuted),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: labelStep,
                      getTitlesWidget: (value, meta) {
                        final day = from.add(Duration(days: value.round()));
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(_shortDayFormat.format(day), style: AppTextStyles.labelMd(color: AppColors.textMuted)),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => AppColors.textPrimary,
                    getTooltipItems: (spots) => spots
                        .map((s) => LineTooltipItem(
                              '${_dayFormat.format(from.add(Duration(days: s.x.round())))}\n${_currencyFormat.format(s.y)} د.ل',
                              AppTextStyles.caption(color: AppColors.surface),
                            ))
                        .toList(),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: false,
                    barWidth: 2,
                    color: primary,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(show: true, color: primary.withValues(alpha: 0.08)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// المخزون
// ---------------------------------------------------------------------------

class _InventorySection extends ConsumerWidget {
  const _InventorySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(inventorySummaryProvider);

    return summaryAsync.when(
      loading: () => const TableSkeleton(),
      error: (err, _) => _ErrorBox(message: 'تعذّر تحميل تقرير المخزون', onRetry: () => ref.invalidate(inventorySummaryProvider)),
      data: (summary) {
        final crossAxisCount = Breakpoints.isDesktop(context) ? 4 : (Breakpoints.isTablet(context) ? 2 : 1);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GridView.count(
              crossAxisCount: crossAxisCount,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1.6,
              children: [
                StatCard(
                  label: 'قيمة المخزون الإجمالية',
                  value: '${_currencyFormat.format((summary['totalInventoryValue'] as num?) ?? 0)} د.ل',
                  icon: Icons.warehouse_outlined,
                ),
                StatCard(
                  label: 'أصناف منخفضة المخزون',
                  value: _integerFormat.format(summary['lowStockCount'] ?? 0),
                  icon: Icons.trending_down,
                  accentColor: AppColors.warning,
                ),
                StatCard(
                  label: 'أصناف منتهية الصلاحية',
                  value: _integerFormat.format(summary['expiredCount'] ?? 0),
                  icon: Icons.event_busy_outlined,
                  accentColor: AppColors.danger,
                  trend: '${_currencyFormat.format((summary['expiredLossValue'] as num?) ?? 0)} د.ل خسارة',
                  isPositiveTrend: false,
                ),
                StatCard(
                  label: 'تنتهي خلال 7 أيام',
                  value: _integerFormat.format(summary['nearExpiryCount'] ?? 0),
                  icon: Icons.schedule_outlined,
                  accentColor: AppColors.warning,
                ),
              ],
            ),
            const SizedBox(height: 16),
            AppDataTable(
              title: 'نواقص المخزون',
              columns: const [AppColumn('الصنف'), AppColumn('الكمية المتاحة'), AppColumn('حد إعادة الطلب')],
              rows: List<Map<String, dynamic>>.from(summary['lowStockItems'] as List? ?? [])
                  .map((i) => [
                        Text(i['productName'] as String? ?? ''),
                        Text(_integerFormat.format((i['quantity'] as num?) ?? 0)),
                        Text(_integerFormat.format((i['reorderLevel'] as num?) ?? 0)),
                      ])
                  .toList(),
            ),
            const SizedBox(height: 16),
            AppDataTable(
              title: 'فواقد الصلاحية والأصناف القريبة من الانتهاء',
              columns: const [AppColumn('الصنف'), AppColumn('الكمية'), AppColumn('تاريخ الانتهاء'), AppColumn('قيمة الخسارة المقدَّرة')],
              rows: [
                ...List<Map<String, dynamic>>.from(summary['expiredItems'] as List? ?? []).map((i) => _expiryRow(i, expired: true)),
                ...List<Map<String, dynamic>>.from(summary['nearExpiryItems'] as List? ?? []).map((i) => _expiryRow(i, expired: false)),
              ],
            ),
          ],
        );
      },
    );
  }

  List<Widget> _expiryRow(Map<String, dynamic> item, {required bool expired}) {
    final expiryDate = DateTime.tryParse(item['expiryDate'] as String? ?? '');
    return [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: expired ? AppColors.dangerBg : AppColors.warningBg,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(expired ? 'منتهي' : 'قريب', style: AppTextStyles.labelMd(color: expired ? AppColors.danger : AppColors.warning)),
          ),
          const SizedBox(width: 8),
          Text(item['productName'] as String? ?? ''),
        ],
      ),
      Text(_integerFormat.format((item['quantity'] as num?) ?? 0)),
      Text(expiryDate != null ? _dayFormat.format(expiryDate) : '-'),
      CurrencyBadge(amount: (item['estimatedLossValue'] as num?)?.toDouble() ?? 0),
    ];
  }
}
