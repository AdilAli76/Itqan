import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../shared/widgets/adaptive_dialog.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/currency_badge.dart';

/// إرجاع فاتورة **من نقطة البيع نفسها**.
///
/// <para><b>العطب الذي تصلحه:</b> الاسترجاع كان في شاشة الفواتير وحدها.
/// فالكاشير الواقف أمام زبون يُرجع بضاعة عليه أن يترك نقطة البيع، ويفتح
/// الفواتير، ويبحث، ويفتح الفاتورة، ثم يسترجع — والزبون ينتظر. وهذا هو
/// بالضبط ما يدفع الناس إلى تسوية المرتجع نقداً من الدرج بلا فاتورة: يخرج
/// المال ولا يعود الصنف إلى المخزون، ولا أثر لشيء.</para>
///
/// <para>وبحث الفاتورة بالرقم وحده لا بقائمة تُتصفَّح: الإيصال في يد الزبون
/// يحمل رقمه، والمسح أو الكتابة أسرع من أي قائمة — وأدقّ: قائمةٌ تُختار منها
/// بالنظر تُنتج استرجاع فاتورة غير التي في اليد.</para>
class ReturnInvoiceSheet extends StatefulWidget {
  const ReturnInvoiceSheet({super.key});

  @override
  State<ReturnInvoiceSheet> createState() => _ReturnInvoiceSheetState();
}

class _ReturnInvoiceSheetState extends State<ReturnInvoiceSheet> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _invoice;
  final Map<int, bool> _selectedItems = {}; // item index → selected

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final number = _controller.text.trim();
    if (number.isEmpty || _busy) return;

    setState(() {
      _busy = true;
      _error = null;
      _invoice = null;
    });
    try {
      final response = await ApiClient.instance.dio.get('/invoices', queryParameters: {
        'search': number,
        'pageSize': 5,
      });
      final body = response.data;
      final list = body is List ? body : (body as Map<String, dynamic>)['items'] as List;

      // مطابقة تامّة على الرقم: الجزئية قد تُرجع فاتورة أخرى يحتوي رقمها
      // المُدخَل، فيُسترجَع بيعٌ لم يطلبه أحد.
      final match = list.cast<Map<String, dynamic>>().firstWhere(
            (i) => (i['invoiceNumber'] as String?)?.toUpperCase() == number.toUpperCase(),
            orElse: () => <String, dynamic>{},
          );

      if (match.isEmpty) {
        setState(() => _error = 'لا فاتورة بالرقم $number');
        return;
      }
      if (match['invoiceType'] != 'sale') {
        setState(() => _error = 'هذه فاتورة مرتجع — لا تُسترجَع مرّة أخرى');
        return;
      }
      if (match['status'] == 'refunded') {
        setState(() => _error = 'هذه الفاتورة مسترجَعة مسبقاً');
        return;
      }
      setState(() => _invoice = match);
    } catch (e) {
      setState(() => _error = _message(e, 'تعذّر البحث عن الفاتورة'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refund() async {
    final invoice = _invoice;
    if (invoice == null || _busy) return;

    // التحقق من اختيار منتج واحد على الأقل
    if (_selectedItems.values.every((v) => !v)) {
      setState(() => _error = 'اختر منتجاً واحداً على الأقل للاسترجاع');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final lines = invoice['lines'] as List? ?? [];
      final selectedLineItems = <Map<String, dynamic>>[];

      for (int i = 0; i < lines.length; i++) {
        if (_selectedItems[i] ?? false) {
          selectedLineItems.add(lines[i] as Map<String, dynamic>);
        }
      }

      await ApiClient.instance.dio.post(
        '/invoices/${invoice['id']}/refund',
        data: {'lineItems': selectedLineItems},
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = _message(e, 'تعذّر إتمام الاسترجاع'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final invoice = _invoice;

    return AdaptiveDialog(
      title: 'إرجاع فاتورة',
      maxWidth: 420,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        if (invoice == null)
          FilledButton(
            onPressed: _busy ? null : _search,
            child: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('بحث'),
          )
        else
          FilledButton(
            onPressed: _busy ? null : _refund,
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('تأكيد الإرجاع'),
          ),
      ],
      body: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _controller,
                focusNode: _focus,
                autofocus: true,
                textInputAction: TextInputAction.search,
                style: AppTextStyles.headlineMd(color: AppColors.textPrimary),
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  labelText: 'رقم الفاتورة',
                  hintText: 'INV-…',
                ),
                onSubmitted: (_) => _search(),
              ),
              const SizedBox(height: 8),
              Text('من الإيصال الذي بيد الزبون.', style: AppTextStyles.caption()),
              if (invoice != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(invoice['invoiceNumber'] as String? ?? '',
                          style: AppTextStyles.headlineMd()),
                      const SizedBox(height: 6),
                      Text(
                        DateFormat('yyyy-MM-dd HH:mm').format(
                            DateTime.tryParse('${invoice['createdAt']}')?.toLocal() ?? DateTime.now()),
                        style: AppTextStyles.labelMd(),
                      ),
                      const SizedBox(height: 10),
                      CurrencyBadge(
                        amount: _calculateSelectedTotal(invoice),
                        currencySymbol: 'د.ل',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text('اختر المنتجات المراد استرجاعها:',
                    style: AppTextStyles.labelMd(color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: (invoice['lines'] as List?)?.length ?? 0,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final line = ((invoice['lines'] as List?)?[index] as Map<String, dynamic>?) ?? {};
                      final itemName = line['itemName'] as String? ?? 'منتج بدون اسم';
                      final quantity = line['quantity'] as num? ?? 0;
                      final price = line['price'] as num? ?? 0;
                      final isSelected = _selectedItems[index] ?? false;

                      return CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(itemName, style: AppTextStyles.bodyMd()),
                        subtitle: Text(
                          '${quantity.toStringAsFixed(2)} × ${price.toStringAsFixed(2)} د.ل',
                          style: AppTextStyles.labelMd(),
                        ),
                        value: isSelected,
                        onChanged: (v) {
                          setState(() => _selectedItems[index] = v ?? false);
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'ستُنشأ فاتورة مرتجع، وتعود الكمية إلى المخزون بدفعتها الأصلية.',
                  style: AppTextStyles.labelMd(),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
              ],
            ],
          ),
    );
  }

  double _calculateSelectedTotal(Map<String, dynamic> invoice) {
    final lines = invoice['lines'] as List? ?? [];
    double total = 0;

    for (int i = 0; i < lines.length; i++) {
      if (_selectedItems[i] ?? false) {
        final line = lines[i] as Map<String, dynamic>?;
        if (line != null) {
          final quantity = (line['quantity'] as num?)?.toDouble() ?? 0;
          final price = (line['price'] as num?)?.toDouble() ?? 0;
          final discount = (line['discount'] as num?)?.toDouble() ?? 0;
          final tax = (line['tax'] as num?)?.toDouble() ?? 0;
          total += (quantity * price) - discount + tax;
        }
      }
    }

    return total;
  }

  String _message(Object e, String fallback) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['message'] is String) return data['message'] as String;
      if (e.response == null) return 'لا اتصال بالخادم';
    }
    return fallback;
  }
}
