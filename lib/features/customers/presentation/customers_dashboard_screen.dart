import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_client.dart';
import '../../../core/responsive/adaptive_scaffold.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/currency_badge.dart';
import '../../../shared/widgets/app_surface.dart';

final customerStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final response = await ApiClient.instance.dio.get('/customers/stats');
  return response.data as Map<String, dynamic>;
});

final customerCategoriesStatsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final response = await ApiClient.instance.dio.get('/customer-categories');
  return (response.data as List).cast<Map<String, dynamic>>();
});

class CustomersDashboardScreen extends ConsumerWidget {
  const CustomersDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(customerStatsProvider);
    final categoriesAsync = ref.watch(customerCategoriesStatsProvider);

    return AdaptiveScaffold(
      title: 'لوحة العملاء',
      activeRoute: '/customers-dashboard',
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(customerStatsProvider);
          ref.invalidate(customerCategoriesStatsProvider);
        },
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              statsAsync.when(
                loading: () => const _StatsSkeleton(),
                error: (err, _) => Center(child: Text('خطأ: $err')),
                data: (stats) => _StatsCards(stats: stats),
              ),
              const SizedBox(height: 24),
              categoriesAsync.when(
                loading: () => const SizedBox(
                  height: 200,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (err, _) => Center(child: Text('خطأ: $err')),
                data: (categories) => _CategoriesChart(categories: categories),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatsCards extends StatelessWidget {
  final Map<String, dynamic> stats;

  const _StatsCards({required this.stats});

  @override
  Widget build(BuildContext context) {
    final totalCustomers = stats['totalCount'] as int? ?? 0;
    final totalWalletBalance = (stats['totalWalletBalance'] as num?)?.toDouble() ?? 0;
    final totalLoyaltyPoints = stats['totalLoyaltyPoints'] as int? ?? 0;
    final activeToday = stats['activeToday'] as int? ?? 0;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                title: 'إجمالي العملاء',
                value: NumberFormat('#,##0', 'en').format(totalCustomers),
                icon: Icons.people_outline,
                color: const Color(0xFF0B2540),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                title: 'رصيد المحفظة',
                value: NumberFormat('#,##0.00', 'en').format(totalWalletBalance),
                icon: Icons.account_balance_wallet_outlined,
                color: AppColors.success,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                title: 'نقاط الولاء',
                value: NumberFormat('#,##0', 'en').format(totalLoyaltyPoints),
                icon: Icons.star_outline,
                color: AppColors.warning,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                title: 'نشطين اليوم',
                value: NumberFormat('#,##0', 'en').format(activeToday),
                icon: Icons.trending_up_outlined,
                color: AppColors.info,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: AppTextStyles.bodyMd()),
              Icon(icon, color: color, size: 20),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: AppTextStyles.bodyLg(color: color),
          ),
        ],
      ),
    );
  }
}

class _CategoriesChart extends StatelessWidget {
  final List<Map<String, dynamic>> categories;

  const _CategoriesChart({required this.categories});

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return AppSurface(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('لا توجد فئات عملاء بعد', style: AppTextStyles.bodyMd()),
          ),
        ),
      );
    }

    final totalMembers = categories.fold<int>(0, (sum, c) => sum + (c['customerCount'] as int? ?? 0));
    final maxAmount = categories.fold<double>(0, (max, c) {
      final amount = (c['periodTotal'] as num?)?.toDouble() ?? 0;
      return amount > max ? amount : max;
    });

    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('توزيع الأعضاء حسب الفئات', style: AppTextStyles.bodyLg()),
          const SizedBox(height: 16),
          ...categories.map((cat) {
            final count = cat['customerCount'] as int? ?? 0;
            final percentage = totalMembers > 0 ? (count / totalMembers * 100) : 0;
            final amount = (cat['periodTotal'] as num?)?.toDouble() ?? 0;
            final barWidth = maxAmount > 0 ? (amount / maxAmount * 250) : 0;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          cat['name'] as String? ?? '',
                          style: AppTextStyles.bodyMd(),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '$count (${percentage.toStringAsFixed(1)}%)',
                        style: AppTextStyles.caption(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: barWidth.toDouble(),
                        height: 24,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0B2540),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        NumberFormat('#,##0.00', 'en').format(amount),
                        style: AppTextStyles.caption(),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _StatsSkeleton extends StatelessWidget {
  const _StatsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: AppSurface(child: SizedBox(height: 80, child: Container()))),
            const SizedBox(width: 12),
            Expanded(child: AppSurface(child: SizedBox(height: 80, child: Container()))),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: AppSurface(child: SizedBox(height: 80, child: Container()))),
            const SizedBox(width: 12),
            Expanded(child: AppSurface(child: SizedBox(height: 80, child: Container()))),
          ],
        ),
      ],
    );
  }
}
