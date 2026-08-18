import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/currency_badge.dart';
import '../../../shared/widgets/numeric_keypad.dart';

/// حاسبة الدفع النقدي — واجهة وحساب فقط في هذه المرحلة (لا يُحفَظ المبلغ
/// المستلَم أو الباقي في قاعدة البيانات ولا يُطبَع على الإيصال، بقرار
/// صريح لتفادي تعديل الـ Backend الآن). عند "تأكيد الدفع" يُرجِع true
/// فقط، فتُنفَّذ عملية البيع الحالية دون أي تغيير في _checkout نفسها.
class CashPaymentDialog extends StatefulWidget {
  const CashPaymentDialog({
    super.key,
    required this.totalDue,
    this.currencySymbol = 'د.ل',
    this.keypadSize = KeypadSize.compact,
  });
  final double totalDue;
  final String currencySymbol;
  final KeypadSize keypadSize;

  @override
  State<CashPaymentDialog> createState() => _CashPaymentDialogState();
}

class _CashPaymentDialogState extends State<CashPaymentDialog> {
  String _amountText = '';

  double get _tendered => double.tryParse(_amountText) ?? 0;
  double get _changeDue => (_tendered - widget.totalDue).clamp(0, double.infinity);
  bool get _isSufficient => _tendered >= widget.totalDue && widget.totalDue > 0;

  List<double> get _quickAmounts {
    final exact = widget.totalDue;
    final rounded = <double>{};
    for (final step in [5, 10, 50, 100]) {
      final roundedUp = (exact / step).ceil() * step;
      if (roundedUp > exact) rounded.add(roundedUp.toDouble());
    }
    final sorted = rounded.toList()..sort();
    return [exact, ...sorted.take(3)];
  }

  void _setAmount(double value) {
    setState(() => _amountText = value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 2));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('الدفع نقداً'),
      content: SizedBox(
        width: widget.keypadSize == KeypadSize.large ? 440 : 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('الإجمالي المستحق', style: AppTextStyles.bodyMd()),
                const Spacer(),
                CurrencyBadge(amount: widget.totalDue, currencySymbol: widget.currencySymbol),
              ],
            ),
            const Divider(height: 24),
            KeypadDisplay(
              value: _amountText,
              suffix: widget.currencySymbol,
              label: 'المبلغ المستلَم',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _quickAmounts.map((amount) {
                final isExact = amount == widget.totalDue;
                return OutlinedButton(
                  onPressed: () => _setAmount(amount),
                  child: Text(isExact ? 'المبلغ بالضبط' : amount.toStringAsFixed(0)),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            NumericKeypad(
              value: _amountText,
              onChanged: (v) => setState(() => _amountText = v),
              size: widget.keypadSize,
              onSubmit: () {
                if (_isSufficient) Navigator.pop(context, true);
              },
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _isSufficient ? AppColors.successBg : AppColors.warningBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Text(
                    _isSufficient ? 'الباقي للعميل' : 'المبلغ المتبقي على العميل',
                    style: AppTextStyles.bodyMd(color: _isSufficient ? AppColors.success : AppColors.warning),
                  ),
                  const Spacer(),
                  CurrencyBadge(
                    amount: _isSufficient ? _changeDue : (widget.totalDue - _tendered),
                    currencySymbol: widget.currencySymbol,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
        FilledButton(
          onPressed: _isSufficient ? () => Navigator.pop(context, true) : null,
          child: const Text('تأكيد الدفع'),
        ),
      ],
    );
  }
}
