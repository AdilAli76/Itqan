import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_client.dart';
import '../../../core/responsive/adaptive_scaffold.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/currency_badge.dart';
import '../../../shared/widgets/app_surface.dart';
import '../../../core/auth/permissions.dart';

final disbursementAnalysisProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final response = await ApiClient.instance.dio.get('/customer-categories/analysis');
  return response.data as Map<String, dynamic>;
});

class DisbursementAnalysisScreen extends ConsumerWidget {
  const DisbursementAnalysisScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analysisAsync = ref.watch(disbursementAnalysisProvider);

    return AdaptiveScaffold(
      title: 'تحليل الصرف الدوري',
      activeRoute: '/disbursement-analysis',
      actions: [
        Can(
          permission: Perm.customersManage,
          child: ElevatedButton.icon(
            onPressed: () => _openDisbursementDialog(context, ref),
            icon: const Icon(Icons.send_outlined, size: 18),
            label: const Text('تنفيذ صرف'),
          ),
        ),
      ],
      body: RefreshIndicator(
        onRefresh: () async =>
            ref.invalidate(disbursementAnalysisProvider),
        child: analysisAsync.when(
          loading: () => const Center(
              child: CircularProgressIndicator()),
          error: (err, _) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('خطأ: $err'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () =>
                      ref.invalidate(disbursementAnalysisProvider),
                  child: const Text('إعادة محاولة'),
                ),
              ],
            ),
          ),
          data: (analysis) => SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SummaryCard(analysis: analysis),
                const SizedBox(height: 24),
                _CategoriesBreakdown(
                  categories: (analysis['categories'] as List? ?? [])
                      .cast<Map<String, dynamic>>(),
                ),
                const SizedBox(height: 24),
                _ScenarioProjections(
                  scenarios: (analysis['scenarios'] as List? ?? [])
                      .cast<Map<String, dynamic>>(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openDisbursementDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => _DisbursementDialog(
        onExecuted: () =>
            ref.invalidate(disbursementAnalysisProvider),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final Map<String, dynamic> analysis;

  const _SummaryCard({required this.analysis});

  @override
  Widget build(BuildContext context) {
    final totalAmount = (analysis['totalDisbursementAmount'] as num?)?.toDouble() ?? 0;
    final totalMembers = analysis['totalMembers'] as int? ?? 0;
    final averagePerMember = totalMembers > 0 ? totalAmount / totalMembers : 0;
    final periodStart = analysis['currentPeriodStart'] as String?;
    final periodEnd = analysis['currentPeriodEnd'] as String?;

    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ملخص الدورة الحالية', style: AppTextStyles.bodyLg()),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _SummaryItem(
                  label: 'الفترة',
                  value: '$periodStart إلى $periodEnd',
                ),
              ),
              Expanded(
                child: _SummaryItem(
                  label: 'إجمالي الصرف',
                  value: NumberFormat('#,##0.00', 'en').format(totalAmount),
                  isAmount: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SummaryItem(
                  label: 'عدد المستحقين',
                  value: NumberFormat('#,##0', 'en').format(totalMembers),
                ),
              ),
              Expanded(
                child: _SummaryItem(
                  label: 'المتوسط للفرد',
                  value: NumberFormat('#,##0.00', 'en').format(averagePerMember),
                  isAmount: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final String label;
  final String value;
  final bool isAmount;

  const _SummaryItem({
    required this.label,
    required this.value,
    this.isAmount = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.caption()),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTextStyles.bodyMd(
            color: isAmount ? AppColors.success : null,
          ),
        ),
      ],
    );
  }
}

class _CategoriesBreakdown extends StatelessWidget {
  final List<Map<String, dynamic>> categories;

  const _CategoriesBreakdown({required this.categories});

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return AppSurface(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('لا توجد فئات للصرف',
                style: AppTextStyles.bodyMd()),
          ),
        ),
      );
    }

    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('توزيع الصرف حسب الفئات',
              style: AppTextStyles.bodyLg()),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('الفئة')),
                DataColumn(label: Text('الأعضاء')),
                DataColumn(label: Text('المبلغ الدوري')),
                DataColumn(label: Text('إجمالي الصرف')),
              ],
              rows: categories.map((cat) {
                final count = cat['memberCount'] as int? ?? 0;
                final periodAmount =
                    (cat['periodAmount'] as num?)?.toDouble() ?? 0;
                final totalAmount =
                    (cat['totalAmount'] as num?)?.toDouble() ?? 0;

                return DataRow(cells: [
                  DataCell(Text(cat['name'] as String? ?? '')),
                  DataCell(Text(NumberFormat('#,##0', 'en')
                      .format(count))),
                  DataCell(Text(NumberFormat('#,##0.00', 'en')
                      .format(periodAmount))),
                  DataCell(CurrencyBadge(amount: totalAmount)),
                ]);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScenarioProjections extends StatelessWidget {
  final List<Map<String, dynamic>> scenarios;

  const _ScenarioProjections({required this.scenarios});

  @override
  Widget build(BuildContext context) {
    if (scenarios.isEmpty) {
      return const SizedBox.shrink();
    }

    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('السيناريوهات المحتملة', style: AppTextStyles.bodyLg()),
          const SizedBox(height: 16),
          ...scenarios.map((scenario) {
            final name = scenario['name'] as String? ?? '';
            final description = scenario['description'] as String? ?? '';
            final totalAmount =
                (scenario['projectedAmount'] as num?)?.toDouble() ?? 0;
            final impact = scenario['impact'] as String? ?? '';

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: impact == 'increase'
                        ? AppColors.warning
                        : AppColors.info,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(name,
                            style: AppTextStyles.bodyMd()),
                        Chip(
                          label: Text(
                            impact == 'increase'
                                ? 'زيادة'
                                : 'نقص',
                            style: const TextStyle(fontSize: 12),
                          ),
                          backgroundColor: impact == 'increase'
                              ? AppColors.warning.withValues(alpha: 0.2)
                              : AppColors.info.withValues(alpha: 0.2),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(description,
                        style: AppTextStyles.caption()),
                    const SizedBox(height: 8),
                    Text(
                      'المبلغ المتوقع: ${NumberFormat('#,##0.00', 'en').format(totalAmount)}',
                      style: AppTextStyles.bodyMd(
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _DisbursementDialog extends ConsumerStatefulWidget {
  final VoidCallback onExecuted;

  const _DisbursementDialog({required this.onExecuted});

  @override
  ConsumerState<_DisbursementDialog> createState() =>
      _DisbursementDialogState();
}

class _DisbursementDialogState
    extends ConsumerState<_DisbursementDialog> {
  String? _selectedCategoryId;
  DateTime? _periodStart;
  DateTime? _periodEnd;
  bool _busy = false;
  List<Map<String, dynamic>> _categories = [];

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final response =
          await ApiClient.instance.dio.get('/customer-categories');
      setState(() {
        _categories = (response.data as List)
            .cast<Map<String, dynamic>>();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تنفيذ صرف دوري'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String?>(
              initialValue: _selectedCategoryId,
              decoration: const InputDecoration(
                labelText: 'الفئة (اختياري - الكل إذا لم تختر)',
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('جميع الفئات'),
                ),
                ..._categories.map((cat) => DropdownMenuItem(
                      value: cat['id'] as String,
                      child: Text(cat['name'] as String? ?? ''),
                    )),
              ],
              onChanged: _busy
                  ? null
                  : (v) =>
                      setState(() => _selectedCategoryId = v),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_periodStart != null
                  ? 'من: ${DateFormat('yyyy-MM-dd').format(_periodStart!)}'
                  : 'من التاريخ'),
              trailing: const Icon(Icons.calendar_today),
              onTap: _busy
                  ? null
                  : () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate:
                            _periodStart ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) {
                        setState(
                            () => _periodStart = date);
                      }
                    },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_periodEnd != null
                  ? 'إلى: ${DateFormat('yyyy-MM-dd').format(_periodEnd!)}'
                  : 'إلى التاريخ'),
              trailing: const Icon(Icons.calendar_today),
              onTap: _busy
                  ? null
                  : () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _periodEnd ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now()
                            .add(const Duration(days: 365)),
                      );
                      if (date != null) {
                        setState(() => _periodEnd = date);
                      }
                    },
            ),
            if (_busy) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('تراجع'),
        ),
        FilledButton(
          onPressed: _busy ? null : _execute,
          child: const Text('تنفيذ'),
        ),
      ],
    );
  }

  Future<void> _execute() async {
    setState(() => _busy = true);
    try {
      await ApiClient.instance.dio.post(
        '/customer-categories/disburse',
        data: {
          'categoryId': _selectedCategoryId,
          'periodStart': _periodStart?.toIso8601String(),
          'periodEnd': _periodEnd?.toIso8601String(),
        },
      );
      widget.onExecuted();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('خطأ: $e')));
      }
    } finally {
      setState(() => _busy = false);
    }
  }
}
