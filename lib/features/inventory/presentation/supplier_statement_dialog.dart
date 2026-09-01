import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../shared/widgets/adaptive_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../branches/data/branches_providers.dart';

final _money = NumberFormat('#,##0.00', 'en');
final _date = DateFormat('yyyy-MM-dd');

final supplierStatementProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) async {
  final response = await ApiClient.instance.dio.get('/suppliers/$id/statement');
  return response.data as Map<String, dynamic>;
});

/// كشف حساب مورّد وسداده.
///
/// <para><b>الثقب الذي يسدّه:</b> حساب «الموردون» كان يتراكم بلا طرف مقابل —
/// كل استلام يزيد الدَّين ولا شيء يُنقصه. فالنظام يقول إنك مدينٌ بكل ما
/// اشتريتَه منذ أول يوم، ولو سدّدتَ كلّه نقداً.</para>
///
/// <para><b>والرصيد مُشتقّ لا مخزَّن:</b> الرقم في شاشة الموردين يكتبه
/// المستخدم بيده ولا يحدّثه شيء — فصار يُقرأ رصيداً افتتاحياً، والحالي
/// يُحسَب من الحركات.</para>
class SupplierStatementDialog extends ConsumerWidget {
  const SupplierStatementDialog({super.key, required this.supplier});

  final Map<String, dynamic> supplier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = supplier['id'] as String;
    final async = ref.watch(supplierStatementProvider(id));

    return AlertDialog(
      title: Text('كشف حساب: ${supplier['name'] ?? ''}'),
      content: SizedBox(
        width: 520,
        child: async.when(
          loading: () => const SizedBox(height: 160, child: Center(child: CircularProgressIndicator())),
          error: (err, _) => SizedBox(
            height: 160,
            child: Center(
              child: Text(_errorText(err, 'تعذّر تحميل كشف الحساب'),
                  style: AppTextStyles.bodyMd(color: AppColors.danger),
                  textAlign: TextAlign.center),
            ),
          ),
          data: (data) {
            final balance = (data['balance'] as num?)?.toDouble() ?? 0;
            final payments = (data['payments'] as List?)?.cast<Map<String, dynamic>>() ?? const [];

            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // الرصيد أولاً: من يفتح كشف حساب مورّد يسأل سؤالاً واحداً —
                  // «كم عليّ له». ووضعُه بعد التفاصيل يعني بحثاً عنه.
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: balance > 0 ? AppColors.warningBg : AppColors.successBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            balance > 0 ? 'المستحقّ عليك' : balance < 0 ? 'له عندك (دفعة مقدَّمة)' : 'الحساب مسوّى',
                            style: AppTextStyles.bodyMd(
                                color: balance > 0 ? AppColors.warning : AppColors.success),
                          ),
                        ),
                        Text(_money.format(balance.abs()),
                            style: AppTextStyles.displayLg(
                                color: balance > 0 ? AppColors.warning : AppColors.success)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _row('رصيد افتتاحي', data['openingBalance']),
                  _row('قيمة ما استُلم', data['received']),
                  _row('ما أُعيد إليه', data['returned'], negative: true),
                  _row('ما سُدِّد له', data['paid'], negative: true),
                  const Divider(height: 24),
                  Row(
                    children: [
                      Expanded(child: Text('الدفعات', style: AppTextStyles.headlineMd())),
                      Text('${payments.length}', style: AppTextStyles.labelMd()),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (payments.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text('لا دفعات مسجَّلة بعد.', style: AppTextStyles.labelMd()),
                    )
                  else
                    for (final p in payments)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    [
                                      _date.format(DateTime.tryParse('${p['paidOn']}') ?? DateTime.now()),
                                      p['method'] == 'bank' ? 'حوالة' : 'نقداً',
                                      if (p['reference'] != null) 'إيصال ${p['reference']}',
                                    ].join(' · '),
                                    style: AppTextStyles.bodyMd(color: AppColors.textPrimary),
                                  ),
                                  if (p['note'] != null)
                                    Text(p['note'] as String, style: AppTextStyles.caption()),
                                ],
                              ),
                            ),
                            Text(_money.format(p['amount']), style: AppTextStyles.currency()),
                          ],
                        ),
                      ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
        FilledButton.icon(
          onPressed: () => _pay(context, ref, id),
          icon: const Icon(Icons.payments_outlined, size: 18),
          label: const Text('تسجيل سداد'),
        ),
      ],
    );
  }

  Widget _row(String label, Object? value, {bool negative = false}) {
    final amount = (value as num?)?.toDouble() ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppTextStyles.bodyMd())),
          Text('${negative && amount != 0 ? '−' : ''}${_money.format(amount)}',
              style: AppTextStyles.currency()),
        ],
      ),
    );
  }

  Future<void> _pay(BuildContext context, WidgetRef ref, String id) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _PayDialog(supplierId: id),
    );
    if (saved == true) ref.invalidate(supplierStatementProvider(id));
  }
}

class _PayDialog extends ConsumerStatefulWidget {
  const _PayDialog({required this.supplierId});
  final String supplierId;

  @override
  ConsumerState<_PayDialog> createState() => _PayDialogState();
}

class _PayDialogState extends ConsumerState<_PayDialog> {
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();
  final _noteController = TextEditingController();

  String? _branchId;
  String _method = 'cash';
  DateTime _paidOn = DateTime.now();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final branchesAsync = ref.watch(branchesProvider);

    return AdaptiveDialog(
      title: 'تسجيل سداد',
      maxWidth: 400,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('تسجيل'),
        ),
      ],
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
                controller: _amountController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'المبلغ'),
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'cash', label: Text('نقداً')),
                  ButtonSegment(value: 'bank', label: Text('حوالة')),
                ],
                selected: {_method},
                onSelectionChanged: (v) => setState(() => _method = v.first),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _paidOn,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                  );
                  if (picked != null) setState(() => _paidOn = picked);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'تاريخ السداد',
                    // الفصل عن تاريخ الإدخال ليس ترفاً: الحوالة تُرسَل الخميس
                    // ويُدخلها المحاسب الأحد، فتأريخها بالإدخال يضع سداد شهرٍ
                    // في الشهر التالي.
                    helperText: 'تاريخ الدفع الفعلي لا تاريخ الإدخال',
                  ),
                  child: Text(_date.format(_paidOn), style: AppTextStyles.bodyMd()),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _referenceController,
                decoration: const InputDecoration(
                  labelText: 'رقم الإيصال أو الحوالة (اختياري)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteController,
                decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)'),
              ),
              const SizedBox(height: 12),
              Text(
                'الدفعة لا تُعدَّل ولا تُحذف بعد تسجيلها — حركة مالية وقعت، '
                'وتصحيحها بدفعة مقابلة.',
                style: AppTextStyles.caption(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
              ],
            ],
          ),
    );
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (_branchId == null) {
      setState(() => _error = 'اختر الفرع');
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
      await ApiClient.instance.dio.post('/suppliers/${widget.supplierId}/payments', data: {
        'branchId': _branchId,
        'amount': amount,
        'method': _method,
        'paidOn': _paidOn.toIso8601String(),
        'reference': _referenceController.text.trim().isEmpty ? null : _referenceController.text.trim(),
        'note': _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = _errorText(e, 'تعذّر تسجيل السداد'));
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
