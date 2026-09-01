import 'package:fl_chart/fl_chart.dart';
import '../../../core/printing/report_printer.dart';
import '../../../core/theme/branding_provider.dart';
import '../../../core/time/app_clock.dart';
import 'report_card.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../shared/widgets/adaptive_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/network/api_client.dart';
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
import '../../../shared/widgets/app_surface.dart';

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
          // بطاقاتٌ تُطوى لا أقسامٌ متتالية: التقارير صارت أربعة وتزيد،
          // فمن يريد أعمار الديون كان يمرّ على المبيعات والمخزون كلّها.
          // والأوّل مفتوح: شاشةٌ كلّها مطويّة تحتاج نقرةً لترى أي رقم.
          ReportCard(
            title: 'المبيعات',
            subtitle: 'الإيراد والفواتير والمرتجعات',
            icon: Icons.trending_up,
            initiallyExpanded: true,
            onPrint: () => _printSales(ref, period),
            child: const _SalesSection(),
          ),
          ReportCard(
            title: 'المخزون',
            subtitle: 'النواقص والأكثر حركةً',
            icon: Icons.inventory_2_outlined,
            onPrint: () => _printInventory(ref),
            child: const _InventorySection(),
          ),
          ReportCard(
            title: 'المصروفات',
            subtitle: 'ما خرج، بالبند',
            icon: Icons.payments_outlined,
            onPrint: () => _printExpenses(ref, period),
            child: const _ExpensesSection(),
          ),
          ReportCard(
            title: 'أعمار الديون',
            subtitle: 'ما على العملاء وكم تأخّر',
            icon: Icons.schedule_outlined,
            onPrint: () => _printDebtAging(ref),
            child: const _DebtAgingSection(),
          ),
          // القسم يُخفي نفسه لغير إصدار المؤسسات — راجع _ValuationSection.
          const _ValuationSection(),
        ],
      ),
    );
  }
}

/// اسم المنشأة على كل تقرير — ورقةٌ بلا اسم لا تُعرَف لمن هي.
String _orgNameOf(WidgetRef ref) =>
    ref.read(brandingProvider).valueOrNull?.displayName ?? 'إتقان ERP';

Future<void> _printSales(WidgetRef ref, ReportPeriod period) async {
  final summary = await ref.read(salesSummaryProvider.future);
  final top = List<Map<String, dynamic>>.from(summary['topProducts'] as List? ?? const []);

  await printReport(
    title: 'تقرير المبيعات — ${period.label}',
    orgName: _orgNameOf(ref),
    from: period.fromDate,
    to: AppClock.now(),
    facts: [
      ('إجمالي المبيعات', _currencyFormat.format((summary['totalRevenue'] as num?) ?? 0)),
      ('عدد الفواتير', _integerFormat.format(summary['totalInvoices'] ?? 0)),
      ('متوسط الفاتورة',
          _currencyFormat.format((summary['averageInvoiceValue'] as num?) ?? 0)),
      ('المرتجعات', _currencyFormat.format((summary['totalReturns'] as num?) ?? 0)),
    ],
    columns: const ['الصنف', 'الكمية المباعة', 'الإيراد'],
    rows: [
      for (final row in top)
        [
          '${row['productName'] ?? row['name'] ?? '—'}',
          _integerFormat.format((row['quantitySold'] as num?) ?? (row['quantity'] as num?) ?? 0),
          _currencyFormat.format((row['revenue'] as num?) ?? 0),
        ],
    ],
    note: 'المرتجعات مطروحة من الإيراد أعلاه.',
  );
}

Future<void> _printInventory(WidgetRef ref) async {
  final data = await ref.read(inventorySummaryProvider.future);
  final low = List<Map<String, dynamic>>.from(data['lowStockItems'] as List? ?? const []);

  await printReport(
    title: 'تقرير المخزون',
    orgName: _orgNameOf(ref),
    to: AppClock.now(),
    facts: [
      ('قيمة المخزون', _currencyFormat.format((data['totalInventoryValue'] as num?) ?? 0)),
      ('تحت حدّ الطلب', _integerFormat.format(data['lowStockCount'] ?? 0)),
      ('قاربت الانتهاء', _integerFormat.format(data['nearExpiryCount'] ?? 0)),
      ('منتهية الصلاحية', _integerFormat.format(data['expiredCount'] ?? 0)),
      ('خسارة المنتهي', _currencyFormat.format((data['expiredLossValue'] as num?) ?? 0)),
    ],
    columns: const ['الصنف', 'المتاح', 'حدّ الطلب'],
    rows: [
      for (final row in low)
        [
          '${row['productName'] ?? '—'}',
          _integerFormat.format((row['quantity'] as num?) ?? 0),
          _integerFormat.format((row['reorderLevel'] as num?) ?? 0),
        ],
    ],
    note: 'الأرصدة لحظة الطباعة — راجع شاشة المخزون للأحدث.',
  );
}

Future<void> _printExpenses(WidgetRef ref, ReportPeriod period) async {
  final data = await ref.read(expensesSummaryProvider.future);
  final byCategory = List<Map<String, dynamic>>.from(data['byCategory'] as List? ?? const []);

  await printReport(
    title: 'تقرير المصروفات — ${period.label}',
    orgName: _orgNameOf(ref),
    from: period.fromDate,
    to: AppClock.now(),
    facts: [
      ('إجمالي المصروفات', _currencyFormat.format((data['totalExpenses'] as num?) ?? 0)),
      ('عدد المصروفات', _integerFormat.format(data['expenseCount'] ?? 0)),
      ('متوسط المصروف', _currencyFormat.format((data['averageExpense'] as num?) ?? 0)),
    ],
    columns: const ['البند', 'العدد', 'المبلغ'],
    rows: [
      for (final row in byCategory)
        [
          '${row['category'] ?? '—'}',
          _integerFormat.format((row['count'] as num?) ?? 0),
          _currencyFormat.format((row['amount'] as num?) ?? 0),
        ],
    ],
    // بتاريخ الصرف لا الإدخال — راجع Expense.SpentOn.
    note: 'المصروفات محسوبة بتاريخ الصرف الفعلي لا بتاريخ إدخالها.',
  );
}

Future<void> _printDebtAging(WidgetRef ref) async {
  final data = await ref.read(debtAgingProvider.future);
  final rows = List<Map<String, dynamic>>.from(data['items'] as List? ?? const []);

  await printReport(
    title: 'تقرير أعمار الديون',
    orgName: _orgNameOf(ref),
    to: AppClock.now(),
    facts: [
      ('عدد المدينين', _integerFormat.format(rows.length)),
      ('إجمالي المستحقّ', _currencyFormat.format((data['totalOutstanding'] as num?) ?? 0)),
      // «لم يحن بعد» رقمٌ يُسأل عنه: دَينٌ في مهلته ليس متأخّراً،
      // وخلطُه بالمتأخّر يُضخّم المشكلة ويُربك القرار.
      ('لم يحن موعده', _currencyFormat.format((data['notYetDue'] as num?) ?? 0)),
    ],
    columns: const ['العميل', 'الهاتف', 'المستحقّ', 'التأخّر (يوم)', 'المرحلة'],
    rows: [
      for (final row in rows)
        [
          '${row['customerName'] ?? '—'}',
          '${row['phone'] ?? '—'}',
          _currencyFormat.format((row['totalOutstanding'] as num?) ?? 0),
          _integerFormat.format((row['daysOverdue'] as num?) ?? 0),
          '${row['stage'] ?? '—'}',
        ],
    ],
    note: 'الدَّين محسوبٌ من دفتر الفواتير — راجع كشف العميل للتفصيل.',
  );
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
      error: (err, _) => _ErrorBox(
          message: 'تعذّر تحميل تقرير المبيعات', onRetry: () => ref.invalidate(salesSummaryProvider)),
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
              mainAxisExtent: 168,
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
            // المصروفات على نفس الرسم: تقريرُ إيرادٍ بلا مصروف يقول رقماً
            // يظنّه التاجر ربحاً وليس كذلك. وتُقرأ بلا انتظارها — فشلُ
            // تحميلها يُنقص خطّاً ولا يمنع رؤية المبيعات.
            _RevenueChart(
              revenueByDay: List<Map<String, dynamic>>.from(summary['revenueByDay'] as List? ?? []),
              from: period.fromDate,
              expensesByDay: List<Map<String, dynamic>>.from(
                  ref.watch(expensesSummaryProvider).valueOrNull?['byDay'] as List? ?? const []),
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
  const _RevenueChart({
    required this.revenueByDay,
    required this.from,
    this.expensesByDay = const [],
  });

  final List<Map<String, dynamic>> revenueByDay;
  final DateTime from;

  /// المصروفات اليومية — خطٌّ ثانٍ على نفس الرسم.
  ///
  /// <para><b>ولماذا على نفس الرسم لا في رسمٍ مجاور:</b> ما يهمّ ليس أيّ
  /// الخطّين أعلى، بل **المسافة بينهما** — وهي لا تُقاس بالعين بين رسمين
  /// بمقياسين مختلفين. وخطُّ مبيعاتٍ وحده يصعد فيُفرح، وقد تكون المصروفات
  /// صعدت معه أكثر.</para>
  final List<Map<String, dynamic>> expensesByDay;

  @override
  Widget build(BuildContext context) {
    final byDate = <String, double>{};
    for (final point in revenueByDay) {
      final date = DateTime.tryParse(point['date'] as String? ?? '');
      if (date == null) continue;
      byDate[_dayFormat.format(date)] = (point['revenue'] as num?)?.toDouble() ?? 0;
    }

    final expenseByDate = <String, double>{};
    for (final point in expensesByDay) {
      final date = DateTime.tryParse(point['date'] as String? ?? '');
      if (date == null) continue;
      expenseByDate[_dayFormat.format(date)] = (point['amount'] as num?)?.toDouble() ?? 0;
    }

    // تاريخ بداية بعد اليوم يُنتج عدداً سالباً، وList.generate بعدد سالب
    // يرمي RangeError **فتسقط شاشة التقارير كلّها** — لا رسماً فارغاً بل
    // شاشة بيضاء. ويقع فعلاً بمن يختار تاريخاً في المستقبل من منتقي المدى.
    //
    // (كشفته جولة اللقطات حين ثُبِّت وقتها قبل تواريخ العيّنات.)
    final dayCount = AppClock.now().difference(from).inDays + 1;
    if (dayCount <= 0) {
      return Container(
        height: 240,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Text('تاريخ البداية بعد اليوم — اختر مدى منتهياً.',
            style: AppTextStyles.bodyMd(color: AppColors.textSecondary)),
      );
    }

    final spots = List.generate(dayCount, (i) {
      final day = from.add(Duration(days: i));
      return FlSpot(i.toDouble(), byDate[_dayFormat.format(day)] ?? 0);
    });
    final expenseSpots = expenseByDate.isEmpty
        ? <FlSpot>[]
        : List.generate(dayCount, (i) {
            final day = from.add(Duration(days: i));
            return FlSpot(i.toDouble(), expenseByDate[_dayFormat.format(day)] ?? 0);
          });

    // المقياس يشمل الخطّين: مقياسٌ على الإيراد وحده يقصّ قمم المصروفات
    // فتبدو أصغر ممّا هي — وهو تضليلٌ بالرسم لا خطأ في الرقم.
    final maxRevenue = [...spots, ...expenseSpots]
        .map((s) => s.y)
        .fold<double>(0, (a, b) => a > b ? a : b);
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
                          child: Text(_shortDayFormat.format(day),
                              style: AppTextStyles.labelMd(color: AppColors.textMuted)),
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
                  if (expenseSpots.isNotEmpty)
                    LineChartBarData(
                      spots: expenseSpots,
                      isCurved: true,
                      curveSmoothness: 0.25,
                      color: AppColors.warning,
                      barWidth: 2,
                      // متقطّعٌ لا مصمت: يُميَّز عن خطّ الإيراد بلا اعتمادٍ
                      // على اللون وحده — ومن لا يميّز الألوان يقرأ الرسم.
                      dashArray: const [6, 4],
                      dotData: const FlDotData(show: false),
                    ),
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
      error: (err, _) => _ErrorBox(
          message: 'تعذّر تحميل تقرير المخزون', onRetry: () => ref.invalidate(inventorySummaryProvider)),
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
              // أطول من شبكة المبيعات: بطاقات المخزون تحمل شارة إضافية
              // («خسارة»/«منخفض») فوق الرقم، فثمانية وستون ومئة لا تسعها —
              // رُصد فيضاً بثلاثين بكسل في جولة اللقطات.
              mainAxisExtent: 200,
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
              columns: const [
                AppColumn('الصنف'),
                AppColumn('الكمية'),
                AppColumn('تاريخ الانتهاء'),
                AppColumn('قيمة الخسارة المقدَّرة')
              ],
              rows: [
                ...List<Map<String, dynamic>>.from(summary['expiredItems'] as List? ?? [])
                    .map((i) => _expiryRow(i, expired: true)),
                ...List<Map<String, dynamic>>.from(summary['nearExpiryItems'] as List? ?? [])
                    .map((i) => _expiryRow(i, expired: false)),
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
            child: Text(expired ? 'منتهي' : 'قريب',
                style: AppTextStyles.labelMd(color: expired ? AppColors.danger : AppColors.warning)),
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

// ---------------------------------------------------------------------------
// أعمار الديون
// ---------------------------------------------------------------------------

/// من يدين، بكم، ومنذ متى — مرتّباً بأولوية التحصيل.
///
/// الشرائح أفقية قبل الجدول: مدير يريد أولاً أن يعرف **كم مالٍ عالق وكم
/// منه قديم**، ثم من هم. عرض الأسماء أولاً يجعله يقرأ عشرين سطراً ليصل إلى
/// رقم واحد.
// ---------------------------------------------------------------------------
// المصروفات
// ---------------------------------------------------------------------------

class _ExpensesSection extends ConsumerWidget {
  const _ExpensesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(expensesSummaryProvider);

    return async.when(
      loading: () => const TableSkeleton(),
      error: (err, _) => _ErrorBox(
        message: 'تعذّر تحميل تقرير المصروفات',
        onRetry: () => ref.invalidate(expensesSummaryProvider),
      ),
      data: (data) {
        final crossAxisCount =
            Breakpoints.isDesktop(context) ? 3 : (Breakpoints.isTablet(context) ? 2 : 1);
        final total = (data['totalExpenses'] as num?)?.toDouble() ?? 0;
        final byCategory =
            List<Map<String, dynamic>>.from(data['byCategory'] as List? ?? const []);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GridView.count(
              crossAxisCount: crossAxisCount,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              mainAxisExtent: 168,
              children: [
                StatCard(
                  label: 'إجمالي المصروفات',
                  value: '${_currencyFormat.format(total)} د.ل',
                  icon: Icons.payments_outlined,
                  accentColor: AppColors.warning,
                ),
                StatCard(
                  label: 'عدد المصروفات',
                  value: _integerFormat.format(data['expenseCount'] ?? 0),
                  icon: Icons.receipt_outlined,
                ),
                StatCard(
                  label: 'متوسط المصروف',
                  value: '${_currencyFormat.format((data['averageExpense'] as num?) ?? 0)} د.ل',
                  icon: Icons.calculate_outlined,
                ),
              ],
            ),
            const SizedBox(height: 16),
            AppDataTable(
              title: 'المصروفات بالبند',
              columns: const [AppColumn('البند'), AppColumn('العدد'), AppColumn('المبلغ')],
              rows: byCategory
                  .map((c) => [
                        Text(c['category'] as String? ?? ''),
                        Text(_integerFormat.format((c['count'] as num?) ?? 0)),
                        CurrencyBadge(amount: (c['amount'] as num?)?.toDouble() ?? 0),
                      ])
                  .toList(),
              emptyMessage: 'لا مصروفات في هذه المدّة',
            ),
          ],
        );
      },
    );
  }
}

class _DebtAgingSection extends ConsumerWidget {
  const _DebtAgingSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agingAsync = ref.watch(debtAgingProvider);

    return agingAsync.when(
      loading: () => const TableSkeleton(),
      error: (_, __) => _ErrorBox(
        message: 'تعذّر تحميل أعمار الديون',
        onRetry: () => ref.invalidate(debtAgingProvider),
      ),
      data: (report) {
        final items = List<Map<String, dynamic>>.from(report['items'] as List? ?? []);
        if (items.isEmpty) {
          return AppSurface(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text('لا ديون مستحقّة على أي عميل.',
                  style: AppTextStyles.bodyMd(color: AppColors.textSecondary)),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _bucket('الإجمالي', report['totalOutstanding'], AppColors.textPrimary),
                _bucket('لم يحن أجله', report['notYetDue'], AppColors.textSecondary),
                _bucket('1–30 يوماً', report['days1To30'], AppColors.warning),
                _bucket('31–60', report['days31To60'], AppColors.warning),
                _bucket('61–90', report['days61To90'], AppColors.danger),
                // أكثر من تسعين يوماً هو الرقم الذي يُقرَّر عنده أن الدَّين
                // قد لا يُحصَّل أصلاً — فيُفرَد بلونه.
                _bucket('أكثر من 90', report['over90'], AppColors.danger),
              ],
            ),
            const SizedBox(height: 16),
            AppDataTable(
              title: 'المدينون (${items.length})',
              columns: const [
                AppColumn('العميل'),
                AppColumn('الهاتف'),
                AppColumn('المستحقّ'),
                AppColumn('التأخّر'),
                AppColumn('المرحلة'),
                AppColumn('آخر تذكير'),
                AppColumn(''),
              ],
              rows: items.map((r) => _row(context, ref, r)).toList(),
            ),
          ],
        );
      },
    );
  }

  Widget _bucket(String label, Object? value, Color color) {
    final amount = (value as num?)?.toDouble() ?? 0;
    return AppSurface(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: AppTextStyles.labelMd(color: AppColors.textMuted)),
          const SizedBox(height: 4),
          Text(NumberFormat('#,##0.00', 'en').format(amount),
              style: AppTextStyles.headlineMd(color: color)),
        ],
      ),
    );
  }

  List<Widget> _row(BuildContext context, WidgetRef ref, Map<String, dynamic> r) {
    final days = (r['daysOverdue'] as num?)?.toInt() ?? 0;
    final stage = (r['stage'] as num?)?.toInt() ?? 0;
    final lastAt = r['lastReminderAt'] != null
        ? DateTime.tryParse(r['lastReminderAt'] as String)
        : null;
    final lastStage = (r['lastReminderStage'] as num?)?.toInt();

    return [
      Text(r['customerName'] as String? ?? '-'),
      Text(r['phone'] as String? ?? '-'),
      CurrencyBadge(amount: (r['totalOutstanding'] as num?)?.toDouble() ?? 0),
      Text(
        days == 0 ? 'في الموعد' : 'منذ $days يوماً',
        style: AppTextStyles.bodyMd(
            color: days == 0
                ? AppColors.textSecondary
                : (days > 60 ? AppColors.danger : AppColors.warning)),
      ),
      Text(stage == 0 ? '-' : 'المرحلة $stage',
          style: AppTextStyles.labelMd(
              color: stage >= 3 ? AppColors.danger : AppColors.textSecondary)),
      // المرحلة الأخيرة مع تاريخها: من ذُكِّر ثلاث مرّات ولم يسدّد حالة
      // مختلفة تماماً عمّن لم يُطالَب قطّ، والعمودان معاً هما ما يُظهر ذلك.
      Text(
        lastAt == null
            ? 'لم يُذكَّر'
            : '${lastStage ?? "-"} — ${DateFormat('yyyy-MM-dd').format(lastAt)}',
        style: AppTextStyles.labelMd(
            color: lastAt == null ? AppColors.textMuted : AppColors.textSecondary),
      ),
      // التسجيل بعد المطالبة لا قبلها: الزرّ لا يُرسل شيئاً — النظام لا يملك
      // قناة إرسال — بل يوثّق أن إنساناً طالَب فعلاً. راجع DebtReminder.
      IconButton(
        tooltip: 'تسجيل تذكير',
        icon: const Icon(Icons.campaign_outlined, size: 18),
        onPressed: stage == 0
            ? null
            : () => _recordReminder(context, ref, r['customerId'] as String,
                r['customerName'] as String? ?? ''),
      ),
    ];
  }

  Future<void> _recordReminder(
      BuildContext context, WidgetRef ref, String customerId, String name) async {
    final note = await showDialog<String>(
      context: context,
      builder: (_) => _ReminderNoteDialog(customerName: name),
    );
    if (note == null) return;

    try {
      await ApiClient.instance.dio.post(
        '/customers/$customerId/debt-reminders',
        data: {'note': note.trim().isEmpty ? null : note.trim()},
      );
      ref.invalidate(debtAgingProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('سُجِّل التذكير')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text((e is DioException && e.response?.data is Map && (e.response!.data as Map)['message'] is String)
                    ? (e.response!.data as Map)['message'] as String
                    : 'تعذّر تسجيل التذكير')));
      }
    }
  }
}

/// نافذة التسجيل — تسأل عمّا حدث لا عمّا سيحدث.
class _ReminderNoteDialog extends StatefulWidget {
  const _ReminderNoteDialog({required this.customerName});
  final String customerName;

  @override
  State<_ReminderNoteDialog> createState() => _ReminderNoteDialogState();
}

class _ReminderNoteDialogState extends State<_ReminderNoteDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveDialog(
      title: 'تسجيل تذكير — ${widget.customerName}',
      maxWidth: 380,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('تسجيل'),
        ),
      ],
      body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'سجّل بعد أن تُطالِب فعلاً. المرحلة تُحسب من عمر الدَّين ولا '
              'تُختار — وإلا فقد السلّم معناه.',
              style: AppTextStyles.bodyMd(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: 'ملاحظة (اختياري)',
                hintText: 'مثال: اتصال هاتفي — وعد بالسداد نهاية الأسبوع',
              ),
            ),
          ],
        ),
    );
  }
}

// ---------------------------------------------------------------------------
// قيمة المخزون بالتكلفة الحقيقية — إصدار المؤسسات
// ---------------------------------------------------------------------------

/// من الدفتر لا من سعر تكلفة الصنف.
///
/// **لماذا يُعرَض الفارق:** سعر التكلفة على الصنف رقم واحد يُكتب فوقه عند كل
/// استلام، فمخزونٌ اشتُري على ثلاث دفعات بأسعار مختلفة كان يُقيَّم بسعر
/// آخرها كلّه. عرض القيمتين جنباً إلى جنب يجعل الفرق مفهوماً بدل أن يبدو
/// رقماً تغيّر بلا سبب.
///
/// ويُخفي نفسه كاملاً حين يردّ الخادم 403 (وحدة `valuation` غير مملوكة):
/// عرض «تعذّر التحميل» لمن لا يملك الوحدة يدفعه إلى الدعم بلا سبب.
class _ValuationSection extends ConsumerWidget {
  const _ValuationSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final valuationAsync = ref.watch(inventoryValuationProvider);

    return valuationAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (report) {
        final items = List<Map<String, dynamic>>.from(report['items'] as List? ?? []);
        if (items.isEmpty) return const SizedBox.shrink();

        final real = (report['totalValue'] as num?)?.toDouble() ?? 0;
        final legacy = (report['legacyValue'] as num?)?.toDouble() ?? 0;
        final gap = real - legacy;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 32),
            Text('قيمة المخزون بالتكلفة', style: AppTextStyles.headlineMd()),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _card('القيمة الفعلية (من الدفتر)', real, AppColors.textPrimary),
                _card('التقدير السابق (سعر التكلفة)', legacy, AppColors.textSecondary),
                _card(gap >= 0 ? 'فرق زائد' : 'فرق ناقص', gap.abs(),
                    gap.abs() < 0.005 ? AppColors.textMuted : AppColors.warning),
              ],
            ),
            const SizedBox(height: 16),
            AppDataTable(
              title: 'الأصناف (${items.length})',
              columns: const [
                AppColumn('الصنف'),
                AppColumn('الكمية'),
                AppColumn('متوسط التكلفة'),
                AppColumn('سعر الصنف'),
                AppColumn('الشحنات'),
                AppColumn('القيمة'),
              ],
              rows: items.map((i) {
                final avg = (i['averageCost'] as num?)?.toDouble() ?? 0;
                final listed = (i['productCostPrice'] as num?)?.toDouble() ?? 0;
                final drifted = (avg - listed).abs() > 0.005;
                return [
                  Text(i['productName'] as String? ?? '-'),
                  Text('${i['quantity']} ${i['unitBase'] ?? ''}'),
                  Text(NumberFormat('#,##0.00', 'en').format(avg),
                      style: AppTextStyles.bodyMd(
                          color: drifted ? AppColors.warning : AppColors.textPrimary)),
                  Text(NumberFormat('#,##0.00', 'en').format(listed),
                      style: AppTextStyles.bodyMd(color: AppColors.textSecondary)),
                  // عدد الشحنات التي بقي منها شيء: صنفٌ من سبع شحنات بأسعار
                  // مختلفة هو حيث يكون التقدير القديم أبعد ما يكون عن الحقيقة.
                  Text('${i['lotCount'] ?? 0}',
                      style: AppTextStyles.labelMd(color: AppColors.textMuted)),
                  CurrencyBadge(amount: (i['totalValue'] as num?)?.toDouble() ?? 0),
                ];
              }).toList(),
            ),
          ],
        );
      },
    );
  }

  Widget _card(String label, double value, Color color) => AppSurface(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: AppTextStyles.labelMd(color: AppColors.textMuted)),
            const SizedBox(height: 4),
            Text(NumberFormat('#,##0.00', 'en').format(value),
                style: AppTextStyles.headlineMd(color: color)),
          ],
        ),
      );
}
