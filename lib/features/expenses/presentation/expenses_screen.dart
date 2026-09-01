import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../shared/widgets/adaptive_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/permissions.dart';
import '../../../core/network/api_client.dart';
import '../../../core/responsive/adaptive_scaffold.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/app_surface.dart';
import '../../accounting/data/accounting_providers.dart';
import '../../branches/data/branches_providers.dart';
import '../../../core/time/app_clock.dart';

final _money = NumberFormat('#,##0.00', 'en');

final expensesProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final response = await ApiClient.instance.dio.get('/expenses');
  return response.data as Map<String, dynamic>;
});

/// المصروفات.
///
/// <para>الشاشة الأولى لجدول كان في المخطّط منذ اليوم الأول بلا كود يقرؤه.
/// والتاجر الذي يدفع إيجاراً من درج الكاشير لم يكن يجد له مكاناً، فيسجّله
/// على ورقة أو لا يسجّله — وحينها يقول تقرير الأرباح ربحاً ليس ربحاً.</para>
class ExpensesScreen extends ConsumerWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(expensesProvider);
    final canAdd = ref.watch(myPermissionsProvider).valueOrNull?.can('expenses.manage') ?? false;

    return AdaptiveScaffold(
      title: 'المصروفات',
      activeRoute: '/expenses',
      // القائمة تمرّر نفسها: لفّها بمُمرِّر خارجي يعطيها ارتفاعاً غير محدود
      // فتنهار بـ«Vertical viewport was given unbounded height» — شاشةٌ
      // بيضاء عند المستخدم بلا رسالة. راجع AdaptiveScaffold.scrollable.
      scrollable: false,
      actions: [
        if (canAdd)
          TextButton.icon(
            onPressed: () => _add(context, ref),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('مصروف جديد'),
          ),
      ],
      body: dataAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_errorText(err, 'تعذّر تحميل المصروفات'),
                    style: AppTextStyles.bodyMd(color: AppColors.danger),
                    textAlign: TextAlign.center),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: () => ref.invalidate(expensesProvider),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('أعد المحاولة'),
                ),
              ],
            ),
          ),
        ),
        data: (data) {
          final items = (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
          final total = (data['total'] as num?)?.toDouble() ?? 0;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AppSurface(
                child: Row(
                  children: [
                    Icon(Icons.payments_outlined, color: AppColors.textSecondary),
                    const SizedBox(width: 10),
                    Expanded(child: Text('إجمالي المصروفات', style: AppTextStyles.bodyMd())),
                    Text(_money.format(total), style: AppTextStyles.headlineMd()),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      'لا مصروفات مسجَّلة. الإيجار والرواتب والكهرباء تُسجَّل هنا — '
                      'وبدونها يقول تقرير الأرباح ربحاً ليس ربحاً.',
                      style: AppTextStyles.bodyMd(color: AppColors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                for (final e in items) _ExpenseRow(expense: e),
            ],
          );
        },
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => const _AddExpenseDialog(),
    );
    if (saved == true) {
      ref.invalidate(expensesProvider);
      // القيد المحاسبي وُلد مع المصروف، فالشجرة والميزان لم يعودا صحيحين.
      ref.invalidate(chartOfAccountsProvider);
      ref.invalidate(trialBalanceProvider);
      ref.invalidate(journalProvider);
    }
  }
}

class _ExpenseRow extends StatelessWidget {
  const _ExpenseRow({required this.expense});
  final Map<String, dynamic> expense;

  @override
  Widget build(BuildContext context) {
    final account = expense['accountName'] as String?;
    return AppSurface(
      margin: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(expense['category'] as String? ?? '',
                    style: AppTextStyles.bodyMd(color: AppColors.textPrimary)),
                const SizedBox(height: 3),
                Text(
                  [
                    expense['branchName'],
                    // تاريخ الصرف لا الإدخال: هو ما يخصّ المصروف.
                    DateFormat('yyyy-MM-dd').format(
                        DateTime.tryParse('${expense['spentOn']}') ?? AppClock.now()),
                    if (expense['createdByName'] != null) expense['createdByName'],
                  ].join(' · '),
                  style: AppTextStyles.labelMd(),
                ),
                if (account != null) ...[
                  const SizedBox(height: 3),
                  Text(account, style: AppTextStyles.labelMd(color: AppColors.info)),
                ],
                if (expense['note'] != null) ...[
                  const SizedBox(height: 3),
                  Text(expense['note'] as String, style: AppTextStyles.caption()),
                ],
              ],
            ),
          ),
          Text(_money.format(expense['amount']), style: AppTextStyles.currency()),
        ],
      ),
    );
  }
}

class _AddExpenseDialog extends ConsumerStatefulWidget {
  const _AddExpenseDialog();

  @override
  ConsumerState<_AddExpenseDialog> createState() => _AddExpenseDialogState();
}

class _AddExpenseDialogState extends ConsumerState<_AddExpenseDialog> {
  final _categoryController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  String? _branchId;
  String? _accountId;
  DateTime _spentOn = AppClock.now();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _categoryController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final branchesAsync = ref.watch(branchesProvider);
    final accountsAsync = ref.watch(chartOfAccountsProvider);

    // حسابات «الاستخدامات» الورقية وحدها: التجميعية لا يُرحَّل إليها، وحسابٌ
    // من نوع آخر يُفسد قائمة الدخل بصمت.
    final expenseAccounts = accountsAsync.valueOrNull
            ?.where((a) => a['type'] == 'expense' && (a['isPostable'] as bool? ?? false))
            .toList() ??
        const <Map<String, dynamic>>[];

    return AdaptiveDialog(
      title: 'مصروف جديد',
      maxWidth: 420,
      body: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              branchesAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => Text('تعذّر تحميل الفروع',
                    style: AppTextStyles.bodyMd(color: AppColors.danger)),
                data: (branches) {
                  _branchId ??= branches.isNotEmpty ? branches.first['id'] as String : null;
                  return DropdownButtonFormField<String>(
                    initialValue: _branchId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'الفرع'),
                    items: branches
                        .map((b) => DropdownMenuItem(
                            value: b['id'] as String, child: Text(b['name'] as String? ?? '')))
                        .toList(),
                    onChanged: (v) => setState(() => _branchId = v),
                  );
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _categoryController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'البند',
                  hintText: 'إيجار المحل، فاتورة كهرباء، أجرة نقل…',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'المبلغ'),
              ),
              if (expenseAccounts.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _accountId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'الحساب المحاسبي (اختياري)',
                    helperText: 'اتركه فارغاً ليُقيَّد على «مصروفات عمومية»',
                  ),
                  items: expenseAccounts
                      .map((a) => DropdownMenuItem(
                            value: a['id'] as String,
                            child: Text('${a['code']} — ${a['name']}'),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _accountId = v),
                ),
              ],
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _spentOn,
                    firstDate: DateTime(2020),
                    lastDate: AppClock.now(),
                  );
                  if (picked != null) setState(() => _spentOn = picked);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'تاريخ الصرف',
                    // كان يُقيَّد بتاريخ الإدخال دائماً، ففاتورة كهرباء
                    // الأسبوع الماضي تقع في أرقام اليوم — ويُقفَل شهرٌ ناقصاً
                    // مصروفاته وتُحمَّل بها مدّةٌ لا تخصّها.
                    helperText: 'تاريخ الدفع الفعلي لا تاريخ الإدخال',
                  ),
                  child: Text(DateFormat('yyyy-MM-dd').format(_spentOn),
                      style: AppTextStyles.bodyMd()),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteController,
                decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)'),
              ),
              const SizedBox(height: 12),
              Text(
                'المصروف لا يُعدَّل ولا يُحذف بعد تسجيله — حركة مالية وقعت، '
                'وتصحيحها بحركة مقابلة لا بمحوها.',
                style: AppTextStyles.caption(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
              ],
            ],
          ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('تسجيل'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (_branchId == null) {
      setState(() => _error = 'اختر الفرع');
      return;
    }
    if (_categoryController.text.trim().isEmpty) {
      setState(() => _error = 'البند إلزامي');
      return;
    }
    if (amount == null || amount <= 0) {
      setState(() => _error = 'أدخل مبلغاً أكبر من صفر');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ApiClient.instance.dio.post('/expenses', data: {
        'branchId': _branchId,
        'category': _categoryController.text.trim(),
        'amount': amount,
        'note': _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
        'accountId': _accountId,
        'spentOn': _spentOn.toIso8601String(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = _errorText(e, 'تعذّر تسجيل المصروف'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

String _errorText(Object e, String fallback) {
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map && data['message'] is String) return data['message'] as String;
    if (e.response == null) return 'لا اتصال بالخادم';
  }
  return fallback;
}
