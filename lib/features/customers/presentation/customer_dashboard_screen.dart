import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/currency_badge.dart';

class CustomerDashboardScreen extends ConsumerStatefulWidget {
  const CustomerDashboardScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<CustomerDashboardScreen> createState() =>
      _CustomerDashboardScreenState();
}

class _CustomerDashboardScreenState
    extends ConsumerState<CustomerDashboardScreen> {
  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة تحكم العملاء'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ملخص إجمالي
            _buildSummaryCards(isMobile),
            const SizedBox(height: 24),

            // إحصائيات حسب الفئات
            Text(
              'الإحصائيات حسب الفئة',
              style: AppTextStyles.headlineSm(),
            ),
            const SizedBox(height: 12),
            _buildCategoryStats(),
            const SizedBox(height: 24),

            // أعلى العملاء
            Text(
              'أعلى العملاء برصيد مستحق',
              style: AppTextStyles.headlineSm(),
            ),
            const SizedBox(height: 12),
            _buildTopCustomers(),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards(bool isMobile) {
    return GridView.count(
      crossAxisCount: isMobile ? 2 : 4,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _SummaryCard(
          label: 'إجمالي العملاء',
          value: '1,247',
          icon: Icons.people,
          color: Colors.blue,
        ),
        _SummaryCard(
          label: 'عملاء نشطون',
          value: '892',
          icon: Icons.trending_up,
          color: Colors.green,
        ),
        _SummaryCard(
          label: 'رصيد معلق',
          value: '45,320 د.ل',
          icon: Icons.wallet_outlined,
          color: Colors.orange,
        ),
        _SummaryCard(
          label: 'مبيعات الشهر',
          value: '128,500 د.ل',
          icon: Icons.bar_chart,
          color: Colors.purple,
        ),
      ],
    );
  }

  Widget _buildCategoryStats() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: ListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _CategoryStatItem(
            category: 'الموظفون',
            customerCount: 345,
            totalBalance: 23450.50,
            percentage: 0.35,
          ),
          _CategoryStatItem(
            category: 'الموردون',
            customerCount: 127,
            totalBalance: 12300.75,
            percentage: 0.25,
          ),
          _CategoryStatItem(
            category: 'تجار الجملة',
            customerCount: 89,
            totalBalance: 8950.25,
            percentage: 0.20,
          ),
          _CategoryStatItem(
            category: 'عملاء عاديون',
            customerCount: 686,
            totalBalance: 619.50,
            percentage: 0.20,
          ),
        ],
      ),
    );
  }

  Widget _buildTopCustomers() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: ListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _TopCustomerItem(
            rank: 1,
            name: 'محمد علي',
            category: 'موظف',
            balance: 5420.50,
          ),
          _TopCustomerItem(
            rank: 2,
            name: 'فاطمة أحمد',
            category: 'تاجر جملة',
            balance: 4850.25,
          ),
          _TopCustomerItem(
            rank: 3,
            name: 'علي محمود',
            category: 'موظف',
            balance: 3920.00,
          ),
          _TopCustomerItem(
            rank: 4,
            name: 'سارة خالد',
            category: 'تاجر جملة',
            balance: 3150.75,
          ),
          _TopCustomerItem(
            rank: 5,
            name: 'أحمد سالم',
            category: 'موظف',
            balance: 2890.50,
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: AppTextStyles.headlineMd().copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTextStyles.labelMd(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _CategoryStatItem extends StatelessWidget {
  final String category;
  final int customerCount;
  final double totalBalance;
  final double percentage;

  const _CategoryStatItem({
    required this.category,
    required this.customerCount,
    required this.totalBalance,
    required this.percentage,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                category,
                style: AppTextStyles.bodyMd().copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '$customerCount عميل',
                style: AppTextStyles.labelMd(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: percentage,
                    minHeight: 8,
                    backgroundColor: Colors.grey[200],
                    valueColor:
                        AlwaysStoppedAnimation(Colors.green.shade400),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${(percentage * 100).toStringAsFixed(0)}%',
                style: AppTextStyles.labelMd(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'الرصيد المعلق: ${totalBalance.toStringAsFixed(2)} د.ل',
            style: AppTextStyles.labelMd(color: Colors.orange),
          ),
        ],
      ),
    );
  }
}

class _TopCustomerItem extends StatelessWidget {
  final int rank;
  final String name;
  final String category;
  final double balance;

  const _TopCustomerItem({
    required this.rank,
    required this.name,
    required this.category,
    required this.balance,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.green.shade400,
              borderRadius: BorderRadius.circular(50),
            ),
            alignment: Alignment.center,
            child: Text(
              '#$rank',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: AppTextStyles.bodyMd().copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  category,
                  style: AppTextStyles.labelMd(),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${balance.toStringAsFixed(2)} د.ل',
                style: AppTextStyles.bodyMd().copyWith(
                  fontWeight: FontWeight.w600,
                  color: Colors.orange,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'معلق',
                style: AppTextStyles.labelMd(color: Colors.orange),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
