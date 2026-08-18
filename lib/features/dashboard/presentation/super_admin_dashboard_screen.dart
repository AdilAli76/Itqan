import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/responsive/adaptive_scaffold.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/stat_card.dart';
import '../../../shared/widgets/currency_badge.dart';
import '../../../shared/widgets/data_table_widget.dart';
import '../data/dashboard_providers.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../core/auth/permissions.dart';
import 'insights_panel.dart';

// ux-audit: ignore UX-03 — لوحة التحكم تعرض مؤشّرات مجمَّعة وأعلى عناصر
// فقط، لا أرشيف سجلات. حجم كل جدول فيها ثابت بحكم الاستعلام نفسه.
// ux-audit: ignore UX-02 — الفلاتر هنا هي الفترة الزمنية، وهي مطبَّقة على
// مستوى اللوحة كلها لا داخل كل جدول.

final _currencyFormat = NumberFormat('#,##0.00', 'en');
final _integerFormat = NumberFormat('#,##0', 'en');

class SuperAdminDashboardScreen extends ConsumerWidget {
  const SuperAdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // لوحة التحكم تُبنى من /reports/sales-summary و/reports/inventory-summary،
    // وكلاهما داخل ReportsController المحروس بـ reports.view على مستوى
    // الـController كله. من لا يملك الصلاحية كان يرى «تعذّر تحميل بيانات
    // اللوحة» — رسالة عطل عن قيدٍ مقصود، على الشاشة الأولى التي تُفتح كل
    // صباح. هذا أسوأ انطباع أول ممكن عن النظام.
    //
    // الفحص هنا قبل أي طلب: لا نُرسل طلباً نعرف أنه سيُرفض بـ403.
    if (!ref.perms.can(Perm.reportsView)) {
      return const AdaptiveScaffold(
        title: 'لوحة التحكم',
        activeRoute: '/dashboard',
        body: NoPermissionView(moduleName: 'لوحة التحكم والتقارير'),
      );
    }

    final crossAxisCount = Breakpoints.isDesktop(context) ? 4 : (Breakpoints.isTablet(context) ? 2 : 1);
    final salesAsync = ref.watch(dashboardSalesProvider);
    final inventoryAsync = ref.watch(dashboardInventoryProvider);
    final branchesAsync = ref.watch(dashboardBranchesProvider);

    final loading = salesAsync.isLoading || inventoryAsync.isLoading || branchesAsync.isLoading;
    final hasError = salesAsync.hasError || inventoryAsync.hasError || branchesAsync.hasError;

    return AdaptiveScaffold(
      title: 'لوحة تحكم المدير العام',
      activeRoute: '/dashboard',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // الرؤى فوق الأرقام: البطاقات تقول «ماذا حدث»، والرؤى تقول «ما
          // الذي يحتاج قراراً الآن» — والثاني هو سبب فتح اللوحة أصلاً.
          // ولها حالة تحميل مستقلة فلا تؤخّر ظهور الأرقام ولا تنتظرها.
          const InsightsPanel(),
          loading
              // هيكل بطاقات الإحصاء بعدد أعمدة الشبكة نفسه — لوحة التحكم أول
              // شاشة تُفتح كل صباح، فانطباع سرعتها هو انطباع سرعة النظام كله.
              ? StatCardsSkeleton(count: crossAxisCount == 1 ? 2 : crossAxisCount)
              : hasError
                  ? Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: [
                          Text('تعذّر تحميل بيانات اللوحة',
                              style: AppTextStyles.bodyMd(color: AppColors.danger)),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: () {
                              ref.invalidate(dashboardSalesProvider);
                              ref.invalidate(dashboardInventoryProvider);
                              ref.invalidate(dashboardBranchesProvider);
                            },
                            child: const Text('إعادة المحاولة'),
                          ),
                        ],
                      ),
                    )
                  : _DashboardContent(
                      crossAxisCount: crossAxisCount,
                      sales: salesAsync.requireValue,
                      inventory: inventoryAsync.requireValue,
                      branches: branchesAsync.requireValue,
                    ),
        ],
      ),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({
    required this.crossAxisCount,
    required this.sales,
    required this.inventory,
    required this.branches,
  });

  final int crossAxisCount;
  final Map<String, dynamic> sales;
  final Map<String, dynamic> inventory;
  final List<Map<String, dynamic>> branches;

  @override
  Widget build(BuildContext context) {
    final revenueByBranch = List<Map<String, dynamic>>.from(sales['revenueByBranch'] as List? ?? []);
    final branchRevenue = <String, Map<String, dynamic>>{
      for (final b in revenueByBranch) b['branchId'] as String: b,
    };

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
              label: 'مبيعات اليوم (كل الفروع)',
              value: '${_currencyFormat.format((sales['totalRevenue'] as num?) ?? 0)} د.ل',
              icon: Icons.trending_up,
            ),
            StatCard(
              label: 'عدد الفواتير اليوم',
              value: _integerFormat.format(sales['totalInvoices'] ?? 0),
              icon: Icons.receipt_long_outlined,
            ),
            StatCard(
              label: 'أصناف منخفضة المخزون',
              value: _integerFormat.format(inventory['lowStockCount'] ?? 0),
              icon: Icons.inventory_2_outlined,
              accentColor: ((inventory['lowStockCount'] as num?) ?? 0) > 0 ? AppColors.warning : null,
              isPositiveTrend: false,
            ),
            StatCard(
              label: 'الفروع النشطة',
              value: _integerFormat.format(branches.length),
              icon: Icons.store_outlined,
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (branches.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              'لا توجد فروع مسجَّلة بعد — أضف فرعاً من شاشة "الفروع والهوية" لتبدأ العمل.',
              style: AppTextStyles.bodyMd(),
            ),
          )
        else
          AppDataTable(
            title: 'أداء الفروع اليوم',
            columns: const [
              AppColumn('الفرع'),
              AppColumn('مبيعات اليوم'),
              AppColumn('عدد الفواتير'),
              AppColumn('الحالة'),
            ],
            rows: branches.map((b) {
              final stats = branchRevenue[b['id'] as String];
              return [
                Text(b['name'] as String? ?? ''),
                CurrencyBadge(amount: (stats?['revenue'] as num?)?.toDouble() ?? 0),
                Text(_integerFormat.format(stats?['invoiceCount'] ?? 0)),
                const _StatusChip(label: 'نشط', ok: true),
              ];
            }).toList(),
          ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.ok});
  final String label;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: ok ? AppColors.successBg : AppColors.warningBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: AppTextStyles.labelMd(color: ok ? AppColors.success : AppColors.warning)),
    );
  }
}
