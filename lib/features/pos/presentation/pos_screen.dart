import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/network/api_client.dart';
import '../../../core/printing/print_settings_provider.dart';
import '../../../core/printing/receipt_printer.dart';
import '../../../core/responsive/adaptive_scaffold.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/branding_provider.dart';
import '../../../shared/widgets/currency_badge.dart';
import '../../../shared/widgets/pin_pad.dart';
import '../data/pos_providers.dart';
import 'cash_payment_dialog.dart';

class _CartLine {
  _CartLine({
    required this.productId,
    required this.name,
    required this.unitPrice,
    required this.availableQuantity,
  });

  final String productId;
  final String name;
  final double unitPrice;
  final double availableQuantity;
  double quantity = 1;

  double get lineTotal => unitPrice * quantity;
}

class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key});

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final List<_CartLine> _cart = [];
  Map<String, dynamic>? _customer;
  String? _branchId;
  bool _loadingBranch = true;
  bool _placingOrder = false;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    readCurrentBranchId().then((id) {
      if (mounted) {
        setState(() {
          _branchId = id;
          _loadingBranch = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  double get _subtotal => _cart.fold(0, (sum, line) => sum + line.lineTotal);

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(posProductSearchProvider.notifier).state = value;
    });
  }

  Future<void> _onSearchSubmitted(String value) async {
    final code = value.trim();
    if (code.isEmpty) return;
    try {
      final response = await ApiClient.instance.dio.get('/products/inventory', queryParameters: {
        'search': code,
      });
      final results = List<Map<String, dynamic>>.from(response.data as List);
      final exact = results.where((p) => p['barcode'] == code || p['sku'] == code).toList();
      final match = exact.length == 1 ? exact.first : (results.length == 1 ? results.first : null);
      if (match != null) {
        await _addProduct(match);
        _searchController.clear();
        ref.read(posProductSearchProvider.notifier).state = '';
        return;
      }
      // لا صنف يطابق: قد يكون الممسوح بطاقة عميل لا بضاعة. تُجرَّب البضاعة
      // أولاً دائماً لأنها الأكثر تكراراً، ولئلا تختطف بطاقةٌ رمزاً يطابق
      // باركود صنف حقيقي.
      await _tryCardScan(code);
    } catch (_) {
      // تُترك الأخطاء لطلب البحث العادي عبر posProductResultsProvider
    }
  }

  /// يحوّل المسحة إلى اختيار عميل — الكاشير يمرّر البطاقة على نفس القارئ
  /// دون فتح نافذة اختيار العميل ولا كتابة أي شيء.
  Future<void> _tryCardScan(String code) async {
    try {
      final response = await ApiClient.instance.dio.get('/customers/by-card/$code');
      final customer = Map<String, dynamic>.from(response.data as Map);
      if (!mounted) return;
      setState(() {
        _customer = customer;
        _error = null;
      });
      _searchController.clear();
      ref.read(posProductSearchProvider.notifier).state = '';
      _searchFocusNode.requestFocus();
    } on DioException {
      // ليس رمز بطاقة ولا باركود صنف — تُترك الشبكة كما هي ليختار الكاشير يدوياً.
    }
  }

  /// الصنف مفتوح القيمة يُسأل عن قيمته أولاً؛ غيره يُضاف مباشرة.
  Future<void> _addProduct(Map<String, dynamic> product) async {
    final tracksStock = product['tracksStock'] as bool? ?? true;
    if (!tracksStock) {
      final amount = await showDialog<double>(
        context: context,
        builder: (_) => _OpenValueDialog(
          productName: product['name'] as String? ?? '',
          suggested: (product['salePrice'] as num?)?.toDouble() ?? 0,
          currencySymbol: ref.read(brandingProvider).valueOrNull?.currencySymbol ?? 'د.ل',
        ),
      );
      if (amount == null) return;
      // نسخة بالقيمة المُدخَلة — لا تُعدَّل خريطة الصنف الأصلية القادمة من
      // مزوّد البحث، وإلا حملت القيمة إلى عمليات البيع التالية.
      _addToCart({...product, 'salePrice': amount});
      return;
    }
    _addToCart(product);
  }

  void _addToCart(Map<String, dynamic> product) {
    final id = product['id'] as String;
    final price = (product['salePrice'] as num?)?.toDouble() ?? 0;
    _CartLine? existing;
    for (final line in _cart) {
      // السعر جزء من شرط الدمج لا المعرّف وحده: صنف مفتوح القيمة قد يُضاف
      // مرتين بقيمتين مختلفتين، ودمجهما كان سيُلغي إحداهما بصمت.
      if (line.productId == id && line.unitPrice == price) {
        existing = line;
        break;
      }
    }
    setState(() {
      if (existing != null) {
        existing.quantity += 1;
      } else {
        _cart.add(_CartLine(
          productId: id,
          name: product['name'] as String? ?? '',
          unitPrice: (product['salePrice'] as num?)?.toDouble() ?? 0,
          availableQuantity: (product['quantity'] as num?)?.toDouble() ?? 0,
        ));
      }
    });
    // إعادة التركيز لحقل المسح فوراً — قارئ الباركود (جهاز HID) يحتاج
    // الحقل مركَّزاً باستمرار ليكتب فيه، حتى لو أضاف الكاشير صنفاً بالنقر
    // بالماوس بين مسحتين متتاليتين.
    _searchFocusNode.requestFocus();
  }

  void _changeQuantity(_CartLine line, double delta) {
    setState(() {
      final next = line.quantity + delta;
      if (next <= 0) {
        _cart.remove(line);
      } else {
        line.quantity = next;
      }
    });
  }

  Future<void> _pickCustomer() async {
    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _CustomerPickerDialog(),
    );
    if (selected != null) setState(() => _customer = selected);
  }

  /// يفتح حاسبة الدفع النقدي أولاً (مبلغ مستلَم + باقٍ) قبل تنفيذ البيع
  /// فعلياً — راجع تعليق CashPaymentDialog لسبب بقاء هذا عرضاً وحساباً في
  /// الواجهة فقط دون تغيير _checkout أو الـ Backend في هذه المرحلة.
  Future<void> _startCashCheckout() async {
    if (_cart.isEmpty) {
      setState(() => _error = 'السلة فارغة');
      return;
    }
    final branding = ref.read(brandingProvider).valueOrNull;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => CashPaymentDialog(totalDue: _subtotal, currencySymbol: branding?.currencySymbol ?? 'د.ل'),
    );
    if (confirmed == true) await _checkout('cash');
  }

  /// الخصم من المحفظة يمرّ بالرقم السري إلزامياً — بطاقة بلا رقم سري نقودٌ
  /// لحاملها، من وجدها أنفقها. الرقم يُرسَل مع الفاتورة نفسها ويُتحقَّق منه
  /// في السيرفر (راجع InvoicesController.Create)، فلا يمكن تجاوزه من الواجهة.
  Future<void> _startWalletCheckout() async {
    if (_cart.isEmpty) {
      setState(() => _error = 'السلة فارغة');
      return;
    }
    if (_customer == null) {
      setState(() => _error = 'امسح بطاقة العميل أو اختره أولاً للخصم من رصيده');
      return;
    }
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => _WalletPinDialog(
        customerName: _customer!['fullName'] as String? ?? '',
        amount: _subtotal,
        currencySymbol: ref.read(brandingProvider).valueOrNull?.currencySymbol ?? 'د.ل',
      ),
    );
    if (pin != null) await _checkout('customer_wallet', customerPin: pin);
  }

  Future<void> _checkout(String paymentMethod, {String? customerPin}) async {
    if (_cart.isEmpty) {
      setState(() => _error = 'السلة فارغة');
      return;
    }
    if (_branchId == null) {
      setState(() => _error = 'يجب تسجيل الدخول من حساب مرتبط بفرع لاستخدام نقطة البيع');
      return;
    }
    if (paymentMethod == 'customer_wallet' && _customer == null) {
      setState(() => _error = 'اختر عميلاً أولاً للخصم من رصيده');
      return;
    }

    setState(() {
      _placingOrder = true;
      _error = null;
    });

    try {
      final response = await ApiClient.instance.dio.post('/invoices', data: {
        'branchId': _branchId,
        'customerId': _customer?['id'],
        'paymentMethod': paymentMethod,
        'customerPin': customerPin,
        'lines': _cart
            .map((l) => {
                  'productId': l.productId,
                  'quantity': l.quantity,
                  'unitPrice': l.unitPrice,
                })
            .toList(),
      });

      final invoiceId = response.data['id'] as String;
      final invoiceNumber = response.data['invoiceNumber'] as String? ?? '';
      setState(() {
        _cart.clear();
        _customer = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم إصدار الفاتورة $invoiceNumber بنجاح'),
            action: SnackBarAction(label: 'طباعة الإيصال', onPressed: () => _printReceipt(invoiceId)),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      setState(() => _error = _dioErrorMessage(e, 'تعذّر إتمام عملية البيع'));
    } finally {
      if (mounted) setState(() => _placingOrder = false);
    }
  }

  Future<void> _printReceipt(String invoiceId) async {
    try {
      final response = await ApiClient.instance.dio.get('/invoices/$invoiceId');
      final branding = ref.read(brandingProvider).valueOrNull;
      final widthMm = await ref.read(receiptWidthMmProvider.future);
      await printInvoiceReceipt(
        invoice: response.data as Map<String, dynamic>,
        orgName: branding?.displayName ?? 'Kinetic Enterprise',
        currencySymbol: branding?.currencySymbol ?? 'د.ل',
        widthMm: widthMm,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذّر تحضير الإيصال للطباعة')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Breakpoints.isDesktop(context);
    final scanner = _scannerBuilder(context);
    final cart = _cartBuilder(context);

    return AdaptiveScaffold(
      title: 'نقطة البيع',
      activeRoute: '/pos',
      body: isDesktop
          ? IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: scanner),
                  const SizedBox(width: 20),
                  Expanded(flex: 2, child: cart),
                ],
              ),
            )
          : Column(children: [scanner, const SizedBox(height: 20), cart]),
    );
  }

  Widget _scannerBuilder(BuildContext context) {
    final resultsAsync = ref.watch(posProductResultsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          autofocus: true,
          onChanged: _onSearchChanged,
          onSubmitted: _onSearchSubmitted,
          decoration: const InputDecoration(
            hintText: 'امسح باركود الصنف أو ابحث بالاسم...',
            prefixIcon: Icon(Icons.qr_code_scanner_outlined),
            filled: true,
            fillColor: AppColors.surface,
          ),
        ),
        const SizedBox(height: 16),
        resultsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (err, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: Text('تعذّر البحث عن الأصناف', style: AppTextStyles.bodyMd(color: AppColors.danger)),
          ),
          data: (products) {
            if (products.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _searchController.text.trim().isEmpty ? 'اكتب اسم الصنف أو امسح الباركود لبدء البيع' : 'لا توجد نتائج',
                  style: AppTextStyles.bodyMd(),
                ),
              );
            }
            return GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.3,
              children: products.map((p) => _ProductTile(product: p, onTap: () => _addProduct(p))).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _cartBuilder(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('الفاتورة الحالية', style: AppTextStyles.headlineMd()),
              const Spacer(),
              InkWell(
                onTap: _pickCustomer,
                child: Row(
                  children: [
                    const Icon(Icons.person_outline, size: 18, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text(_customer?['fullName'] as String? ?? 'زبون نقدي', style: AppTextStyles.bodyMd()),
                    if (_customer != null)
                      IconButton(
                        icon: const Icon(Icons.close, size: 14),
                        onPressed: () => setState(() => _customer = null),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          if (_cart.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text('السلة فارغة — أضف أصنافاً من القائمة', style: AppTextStyles.bodyMd()),
            )
          else
            ..._cart.map((line) => _CartLineRow(
                  line: line,
                  onIncrement: () => _changeQuantity(line, 1),
                  onDecrement: () => _changeQuantity(line, -1),
                  onRemove: () => setState(() => _cart.remove(line)),
                )),
          const Divider(height: 24),
          Row(
            children: [
              Text('الإجمالي المستحق', style: AppTextStyles.headlineMd()),
              const Spacer(),
              CurrencyBadge(amount: _subtotal),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: (_placingOrder || _loadingBranch) ? null : _startCashCheckout,
                  icon: const Icon(Icons.calculate_outlined, size: 18),
                  label: const Text('نقداً'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: (_placingOrder || _loadingBranch) ? null : _startWalletCheckout,
                  child: _placingOrder
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('خصم من رصيد العميل'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _dioErrorMessage(Object error, String fallback) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] is String) return data['message'] as String;
  }
  return fallback;
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, required this.onTap});
  final Map<String, dynamic> product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final quantity = (product['quantity'] as num?)?.toDouble() ?? 0;
    return InkWell(
      onTap: quantity > 0 ? onTap : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.inventory_2_outlined, color: quantity > 0 ? AppColors.textMuted : AppColors.danger),
            const Spacer(),
            Text(product['name'] as String? ?? '',
                style: AppTextStyles.bodyMd(color: AppColors.textPrimary), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            CurrencyBadge(amount: (product['salePrice'] as num?)?.toDouble() ?? 0),
            Text(
              quantity > 0 ? 'متوفر: ${quantity.toStringAsFixed(0)}' : 'نفد المخزون',
              style: AppTextStyles.labelMd(color: quantity > 0 ? AppColors.textMuted : AppColors.danger),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartLineRow extends StatelessWidget {
  const _CartLineRow({
    required this.line,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
  });

  final _CartLine line;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(line.name, style: AppTextStyles.bodyMd(color: AppColors.textPrimary)),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, size: 18),
            onPressed: onDecrement,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          SizedBox(width: 28, child: Text(line.quantity.toStringAsFixed(0), textAlign: TextAlign.center)),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 18),
            onPressed: onIncrement,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
          CurrencyBadge(amount: line.lineTotal),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 16, color: AppColors.danger),
            onPressed: onRemove,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

class _CustomerPickerDialog extends ConsumerStatefulWidget {
  const _CustomerPickerDialog();

  @override
  ConsumerState<_CustomerPickerDialog> createState() => _CustomerPickerDialogState();
}

class _CustomerPickerDialogState extends ConsumerState<_CustomerPickerDialog> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(posCustomerSearchProvider.notifier).state = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final resultsAsync = ref.watch(posCustomerResultsProvider);

    return AlertDialog(
      title: const Text('اختيار عميل'),
      content: SizedBox(
        width: 360,
        height: 380,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              autofocus: true,
              onChanged: _onSearch,
              decoration: const InputDecoration(hintText: 'ابحث بالاسم أو الهاتف...', prefixIcon: Icon(Icons.search, size: 18)),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: resultsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => const Center(child: Text('تعذّر البحث')),
                data: (customers) {
                  if (customers.isEmpty) {
                    return Center(child: Text('اكتب للبحث عن عميل', style: AppTextStyles.bodyMd()));
                  }
                  return ListView.builder(
                    itemCount: customers.length,
                    itemBuilder: (context, index) {
                      final c = customers[index];
                      return ListTile(
                        title: Text(c['fullName'] as String? ?? ''),
                        subtitle: Text(c['phone'] as String? ?? '-'),
                        onTap: () => Navigator.pop(context, c),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
      ],
    );
  }
}

/// تأكيد الخصم من محفظة العميل برقمه السري.
///
/// يعرض اسم صاحب البطاقة والمبلغ قبل اللوحة عمداً: الكاشير قد يكون مسح بطاقة
/// خاطئة أو بقي عميل سابق مختاراً من عملية لم تكتمل، والعميل نفسه يجب أن يرى
/// المبلغ الذي يوافق عليه قبل أن يُدخل رقمه.
class _WalletPinDialog extends StatefulWidget {
  const _WalletPinDialog({
    required this.customerName,
    required this.amount,
    required this.currencySymbol,
  });

  final String customerName;
  final double amount;
  final String currencySymbol;

  @override
  State<_WalletPinDialog> createState() => _WalletPinDialogState();
}

class _WalletPinDialogState extends State<_WalletPinDialog> {
  String _pin = '';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تأكيد الخصم بالرقم السري'),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('صاحب البطاقة', style: AppTextStyles.labelMd()),
                    const SizedBox(height: 2),
                    Text(widget.customerName, style: AppTextStyles.headlineMd()),
                    const SizedBox(height: 10),
                    Text('المبلغ المخصوم', style: AppTextStyles.labelMd()),
                    const SizedBox(height: 2),
                    CurrencyBadge(amount: widget.amount, currencySymbol: widget.currencySymbol),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text('يُدخل العميل رقمه السري', style: AppTextStyles.labelMd()),
              const SizedBox(height: 8),
              PinPad(value: _pin, onChanged: (v) => setState(() => _pin = v)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          // 4 خانات هو الحد الأدنى الذي يقبله السيرفر (CustomerCards.ValidatePin)،
          // فمنع الإرسال قبله يوفّر محاولة فاشلة تُحتسب على عدّاد القفل بلا داعٍ.
          onPressed: _pin.length < 4 ? null : () => Navigator.pop(context, _pin),
          child: const Text('تأكيد الخصم'),
        ),
      ],
    );
  }
}

/// إدخال قيمة صنف مفتوح القيمة عند البيع.
///
/// يُقترَح سعر الصنف الافتراضي إن كان له سعر، ويبقى قابلاً للتعديل — كثير من
/// حالات الاستخدام (سحب بضاعة بقيمة، خدمة بسعر متفاوت) لا سعر ثابت لها أصلاً.
class _OpenValueDialog extends StatefulWidget {
  const _OpenValueDialog({
    required this.productName,
    required this.suggested,
    required this.currencySymbol,
  });

  final String productName;
  final double suggested;
  final String currencySymbol;

  @override
  State<_OpenValueDialog> createState() => _OpenValueDialogState();
}

class _OpenValueDialogState extends State<_OpenValueDialog> {
  late final _controller =
      TextEditingController(text: widget.suggested > 0 ? widget.suggested.toString() : '');
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = double.tryParse(_controller.text.trim());
    if (value == null || value <= 0) {
      setState(() => _error = 'أدخل قيمة أكبر من صفر');
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.productName),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('صنف مفتوح القيمة — تُكتب قيمته عند البيع', style: AppTextStyles.bodyMd()),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'القيمة',
                suffixText: widget.currencySymbol,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(onPressed: _submit, child: const Text('إضافة')),
      ],
    );
  }
}
