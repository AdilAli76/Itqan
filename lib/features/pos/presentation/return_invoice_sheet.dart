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
  Map<int, double> _returnQuantities = {};
  bool _showItemsList = false;

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
      setState(() {
        _invoice = match;
        _returnQuantities.clear();
        _showItemsList = false;
      });
    } catch (e) {
      setState(() => _error = _message(e, 'تعذّر البحث عن الفاتورة'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refund() async {
    final invoice = _invoice;
    if (invoice == null || _busy) return;

    if (_returnQuantities.isEmpty) {
      setState(() => _error = 'اختر مادة واحدة على الأقل');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final items = invoice['items'] as List? ?? [];
      final returnItems = <Map<String, dynamic>>[];

      for (var i = 0; i < items.length; i++) {
        final qty = _returnQuantities[i] ?? 0;
        if (qty > 0) {
          returnItems.add({
            'invoiceLineId': items[i]['id'],
            'returnQuantity': qty,
          });
        }
      }

      if (returnItems.isEmpty) {
        setState(() => _error = 'اختر كمية أكبر من صفر');
        return;
      }

      await ApiClient.instance.dio.post(
        '/invoices/${invoice['id']}/partial-refund',
        data: {'returnItems': returnItems},
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

    final totalReturnQty = _returnQuantities.values.fold(0.0, (a, b) => a + b);
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
            onPressed: (_busy || totalReturnQty == 0) ? null : _refund,
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('إرجاع (${totalReturnQty.toInt()})'),
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(invoice['invoiceNumber'] as String? ?? '',
                              style: AppTextStyles.headlineMd()),
                          TextButton(
                            onPressed: () {
                              setState(() => _showItemsList = !_showItemsList);
                            },
                            child: Text(_showItemsList ? 'إخفاء' : 'عناصر الفاتورة'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        DateFormat('yyyy-MM-dd HH:mm').format(
                            DateTime.tryParse('${invoice['createdAt']}')?.toLocal() ?? DateTime.now()),
                        style: AppTextStyles.labelMd(),
                      ),
                      const SizedBox(height: 10),
                      CurrencyBadge(
                        amount: (invoice['totalAmount'] as num?)?.toDouble() ?? 0,
                        currencySymbol: 'د.ل',
                      ),
                    ],
                  ),
                ),
                if (_showItemsList) ...[
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: (invoice['items'] as List? ?? []).length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey[200]),
                      itemBuilder: (_, index) {
                        final item = (invoice['items'] as List)[index] as Map<String, dynamic>;
                        final itemId = item['id'] as int?;
                        final returnQty = _returnQuantities[index] ?? 0;
                        final maxQty = (item['quantity'] as num?)?.toDouble() ?? 0;

                        return Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      item['productName'] as String? ?? 'منتج',
                                      style: AppTextStyles.bodyMd(),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    'الكمية: ${maxQty.toInt()}',
                                    style: AppTextStyles.labelMd(),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: Slider(
                                      value: returnQty,
                                      min: 0,
                                      max: maxQty,
                                      divisions: maxQty.toInt(),
                                      onChanged: (val) {
                                        setState(() {
                                          _returnQuantities[index] = val;
                                        });
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 50,
                                    child: TextField(
                                      textAlign: TextAlign.center,
                                      decoration: InputDecoration(
                                        isDense: true,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                      ),
                                      keyboardType: TextInputType.number,
                                      controller: TextEditingController(
                                        text: returnQty.toInt().toString(),
                                      ),
                                      onChanged: (val) {
                                        final newQty = double.tryParse(val) ?? 0;
                                        if (newQty >= 0 && newQty <= maxQty) {
                                          setState(() {
                                            _returnQuantities[index] = newQty;
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  'ستُنشأ فاتورة مرتجع، وتعود الكمية إلى المخزون بدفعتها الأصلية. '
                  'ما دُفع من المحفظة يعود إليها، وما دُفع نقداً يُردّ من الدرج يدوياً.',
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

  String _message(Object e, String fallback) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['message'] is String) return data['message'] as String;
      if (e.response == null) return 'لا اتصال بالخادم';
    }
    return fallback;
  }
}
