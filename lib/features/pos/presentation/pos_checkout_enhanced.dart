import 'package:flutter/material.dart';
import '../../../shared/widgets/print_control_toggle.dart';

/// خيارات الدفع المتاحة في نقطة البيع.
enum PaymentMethod { cash, wallet, split }

/// قسم الخروج المحسّن من نقطة البيع — مع خيارات الدفع والطباعة.
class EnhancedPOSCheckout extends StatefulWidget {
  final double totalAmount;
  final double customerBalance;
  final Map<String, dynamic>? customer;
  final Function(PaymentMethod, bool shouldPrint) onCheckout;
  final bool isLoading;

  const EnhancedPOSCheckout({
    Key? key,
    required this.totalAmount,
    required this.customerBalance,
    this.customer,
    required this.onCheckout,
    this.isLoading = false,
  }) : super(key: key);

  @override
  State<EnhancedPOSCheckout> createState() => _EnhancedPOSCheckoutState();
}

class _EnhancedPOSCheckoutState extends State<EnhancedPOSCheckout> {
  PaymentMethod _selectedMethod = PaymentMethod.cash;
  bool _shouldPrint = true;

  bool get _isWalletSufficient => widget.customerBalance >= widget.totalAmount;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ملخص المبلغ
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('المجموع', style: Theme.of(context).textTheme.titleMedium),
                  Text(
                    '${widget.totalAmount.toStringAsFixed(2)} د.ل',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
              if (widget.customer != null) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('رصيد المحفظة', style: Theme.of(context).textTheme.bodyMedium),
                    Text(
                      '${widget.customerBalance.toStringAsFixed(2)} د.ل',
                      style: TextStyle(
                        color: _isWalletSufficient ? Colors.green : Colors.red,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // خيارات الدفع
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('طريقة الدفع',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _PaymentMethodButton(
                    label: 'نقداً',
                    method: PaymentMethod.cash,
                    isSelected: _selectedMethod == PaymentMethod.cash,
                    onTap: () => setState(() => _selectedMethod = PaymentMethod.cash),
                  ),
                  const SizedBox(width: 8),
                  if (widget.customer != null)
                    _PaymentMethodButton(
                      label: 'محفظة',
                      method: PaymentMethod.wallet,
                      isSelected: _selectedMethod == PaymentMethod.wallet,
                      isEnabled: _isWalletSufficient,
                      onTap: _isWalletSufficient
                          ? () => setState(() => _selectedMethod = PaymentMethod.wallet)
                          : null,
                    ),
                  if (widget.customer != null) const SizedBox(width: 8),
                  if (widget.customer != null)
                    _PaymentMethodButton(
                      label: 'مختلط',
                      method: PaymentMethod.split,
                      isSelected: _selectedMethod == PaymentMethod.split,
                      onTap: () => setState(() => _selectedMethod = PaymentMethod.split),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // خيار الطباعة
        PrintControlToggle(
          initialValue: true,
          onChanged: (shouldPrint) {
            setState(() => _shouldPrint = shouldPrint);
          },
        ),
        const SizedBox(height: 16),

        // زر إتمام الشراء
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: widget.isLoading ? null : () {
              widget.onCheckout(_selectedMethod, _shouldPrint);
            },
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Colors.green,
              disabledBackgroundColor: Colors.grey[400],
            ),
            child: widget.isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                  )
                : const Text('إتمام الشراء', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        ),
      ],
    );
  }
}

/// زرّ اختيار طريقة الدفع.
class _PaymentMethodButton extends StatelessWidget {
  final String label;
  final PaymentMethod method;
  final bool isSelected;
  final bool isEnabled;
  final VoidCallback? onTap;

  const _PaymentMethodButton({
    required this.label,
    required this.method,
    required this.isSelected,
    this.isEnabled = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isEnabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? Colors.green : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
          color: isSelected ? Colors.green.shade50 : (isEnabled ? Colors.white : Colors.grey[200]),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.green : (isEnabled ? Colors.black : Colors.grey),
          ),
        ),
      ),
    );
  }
}
