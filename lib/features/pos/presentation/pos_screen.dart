import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
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
import '../../../shared/widgets/numeric_keypad.dart';
import '../../../shared/widgets/pin_pad.dart';
import '../data/pos_providers.dart';
import '../data/pos_settings_provider.dart';
import 'cash_payment_dialog.dart';
import '../../../shared/widgets/icon_action.dart';
import '../../../core/network/offline_queue.dart';
import '../../../shared/widgets/app_surface.dart';
import '../../../shared/widgets/pagination_bar.dart';

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

  /// السطر الذي تعمل عليه لوحة الأرقام. آلة الكاشير الحقيقية تعمل هكذا:
  /// صنف محدَّد، ثم رقم، ثم تأكيد. آخر صنف مضاف يُحدَّد تلقائياً فيصبح
  /// المسار المعتاد (امسح ← اكتب الكمية) بلا نقرة اختيار إضافية.
  _CartLine? _selectedLine;

  /// لوحة الأرقام مفتوحة؟ مفتوحة دائماً في وضع اللمس، وقابلة للفتح على
  /// سطح المكتب. القيمة null تعني «اتبع وضع اللمس».
  bool? _padOpenOverride;

  String _padValue = '';

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
      final results = PagedResult.fromJson(response.data as Map<String, dynamic>).items;
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
      // بوابة إعداد المنظمة: الصنف قد يكون موجوداً في الكتالوج من قبل تفعيل
      // الإعداد أو بعد إطفائه، فالمنع يتم هنا عند البيع لا بإخفاء الزر فقط
      // — إخفاء الزر وحده يترك الباركود والبحث طريقاً مفتوحاً للصنف نفسه.
      final allowed = ref.read(posAllowOpenProductProvider).valueOrNull ?? false;
      if (!allowed) {
        setState(() => _error = 'بيع الأصناف مفتوحة القيمة غير مفعَّل — '
            'يفعّله مدير المنظمة من الإعدادات');
        return;
      }
      final touch = ref.read(posTouchModeProvider);
      final amount = await showNumericEntryDialog(
        context: context,
        title: product['name'] as String? ?? '',
        subtitle: 'صنف مفتوح القيمة — تُكتب قيمته عند البيع',
        suffix: ref.read(brandingProvider).valueOrNull?.currencySymbol ?? 'د.ل',
        initialValue: (product['salePrice'] as num?)?.toDouble() ?? 0,
        size: touch ? KeypadSize.large : KeypadSize.compact,
        confirmLabel: 'إضافة',
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
        _selectedLine = existing;
      } else {
        final line = _CartLine(
          productId: id,
          name: product['name'] as String? ?? '',
          unitPrice: (product['salePrice'] as num?)?.toDouble() ?? 0,
          availableQuantity: (product['quantity'] as num?)?.toDouble() ?? 0,
        );
        _cart.add(line);
        // آخر صنف مضاف هو هدف لوحة الأرقام — يكتب الكاشير الكمية مباشرة
        // بعد المسح بلا اختيار السطر أولاً.
        _selectedLine = line;
      }
      _padValue = '';
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

  /// إدخال الكمية رقماً بدل النقر عليها مرة لكل وحدة — بيع 24 قطعة كان
  /// يعني 23 نقرة على زر الزيادة.
  Future<void> _editQuantity(_CartLine line) async {
    final touch = ref.read(posTouchModeProvider);
    final value = await showNumericEntryDialog(
      context: context,
      title: line.name,
      subtitle: 'أدخل الكمية',
      initialValue: line.quantity,
      // الكسور مسموحة: الأصناف الموزونة (لحوم، خضار) تُباع بالكيلوغرام.
      allowDecimal: true,
      decimalPlaces: 3,
      size: touch ? KeypadSize.large : KeypadSize.compact,
      confirmLabel: 'تعديل الكمية',
    );
    if (value == null) return;
    setState(() => line.quantity = value);
  }

  /// تطبيق الرقم المكتوب على كمية السطر المحدَّد.
  void _applyPadQuantity() {
    final line = _selectedLine;
    final value = double.tryParse(_padValue);
    if (line == null || value == null || value <= 0) return;
    setState(() {
      line.quantity = value;
      _padValue = '';
    });
    // إعادة التركيز لحقل المسح: الصنف التالي يُمسح مباشرة بلا نقرة وسيطة.
    _searchFocusNode.requestFocus();
  }

  /// تفريغ السلة يمرّ بتأكيد: نقرة واحدة بالخطأ على شاشة لمس كانت ستمحو
  /// فاتورة اكتملت أصنافها.
  Future<void> _confirmClearCart() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('إلغاء الفاتورة'),
        content: Text('سيُحذف ${_cart.length} صنفاً من السلة. متأكد؟', style: AppTextStyles.bodyMd()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('تراجع')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('إلغاء الفاتورة'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _cart.clear();
      _customer = null;
      _error = null;
      _selectedLine = null;
      _padValue = '';
    });
    _searchFocusNode.requestFocus();
  }

  /// زر "قيمة حرة" — يظهر فقط إن فعّل مدير المنظمة الإعداد.
  ///
  /// الـ Backend يشترط productId حقيقياً في كل سطر، فالصنف المفتوح ليس سطراً
  /// بلا مرجع: هو صنف في الكتالوج لا يتبع المخزون. لذلك تُعرَض أصناف الكتالوج
  /// المفتوحة، ويُختار منها.
  Future<void> _addOpenProduct() async {
    final products = await ref.read(posOpenProductsProvider.future).catchError(
      (_) => <Map<String, dynamic>>[],
    );

    if (!mounted) return;

    if (products.isEmpty) {
      setState(() => _error = 'لا يوجد صنف مفتوح القيمة في الكتالوج — أنشئ صنفاً '
          'بخيار "لا يتبع المخزون" من شاشة المخزون أولاً');
      return;
    }

    final product = products.length == 1
        ? products.first
        : await showDialog<Map<String, dynamic>>(
            context: context,
            builder: (_) => _OpenProductPickerDialog(products: products),
          );
    if (product == null) return;
    await _addProduct(product);
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
      builder: (_) => CashPaymentDialog(
        totalDue: _subtotal,
        currencySymbol: branding?.currencySymbol ?? 'د.ل',
        keypadSize: ref.read(posTouchModeProvider) ? KeypadSize.large : KeypadSize.compact,
      ),
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

    // مفتاح العملية يُولَّد هنا مرّة واحدة، قبل أول محاولة إرسال: هو ما
    // يجعل إعادة الإرسال — سواء بعد انقطاع أو من الطابور — تُنشئ فاتورة
    // واحدة لا أكثر.
    final payload = {
      'branchId': _branchId,
      'customerId': _customer?['id'],
      'paymentMethod': paymentMethod,
      'customerPin': customerPin,
      'clientRequestId': OfflineQueueNotifier.newRequestId(),
      'lines': _cart
          .map((l) => {
                'productId': l.productId,
                'quantity': l.quantity,
                'unitPrice': l.unitPrice,
              })
          .toList(),
    };

    try {
      final response = await ApiClient.instance.dio.post('/invoices', data: payload);

      final invoiceId = response.data['id'] as String;
      final invoiceNumber = response.data['invoiceNumber'] as String? ?? '';
      setState(() {
        _cart.clear();
        _customer = null;
        _selectedLine = null;
        _padValue = '';
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
      // فشل الشبكة وحده يُحوَّل إلى طابور. رفض الخادم (صنف غير موجود، رصيد
      // غير كافٍ) خطأ حقيقي يجب أن يراه الكاشير فوراً، وتحويله إلى طابور
      // كان سيؤجّل ظهوره إلى ما بعد انصراف الزبون.
      //
      // والدفع من المحفظة لا يُطابَر أبداً مهما كان سبب الفشل: التحقّق من
      // الرصيد والرقم السري لا يمكن إلا على الخادم (راجع OfflineQueue).
      final offlineCapable = _isNetworkFailure(e) && paymentMethod == 'cash';
      if (offlineCapable) {
        final queued = await ref.read(offlineQueueProvider.notifier).enqueue(payload);
        if (queued) {
          setState(() {
            _cart.clear();
            _customer = null;
            _selectedLine = null;
            _padValue = '';
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'لا يوجد اتصال — حُفظت العملية وستُرسَل تلقائياً عند عودة الشبكة'),
                duration: Duration(seconds: 5),
              ),
            );
          }
        } else {
          setState(() => _error =
              'طابور العمليات المؤجَّلة ممتلئ (${OfflineQueueNotifier.maxQueued}) — '
              'راجع الاتصال قبل متابعة البيع');
        }
      } else {
        setState(() => _error = _dioErrorMessage(e, 'تعذّر إتمام عملية البيع'));
      }
    } finally {
      if (mounted) setState(() => _placingOrder = false);
    }
  }

  /// عطل شبكة لا رفض من الخادم.
  ///
  /// التمييز جوهري: انقطاع الاتصال يعني «أعد المحاولة لاحقاً»، أما رد 400
  /// فيعني «هذه العملية خاطئة» وإعادة إرسالها ألف مرّة لن تنجح.
  bool _isNetworkFailure(Object e) {
    if (e is! DioException) return false;
    return e.response == null ||
        e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout;
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
    final touch = ref.watch(posTouchModeProvider);
    final scanner = _scannerBuilder(context, touch);
    final cart = _cartBuilder(context, touch);

    return AdaptiveScaffold(
      title: 'نقطة البيع',
      activeRoute: '/pos',
      actions: [
        // وضع اللمس إعداد للجهاز لا للمنظمة: جهاز الكاشير شاشة لمس وجهاز
        // المدير فأرة، في نفس اللحظة وعلى نفس الحساب.
        Tooltip(
          message: touch ? 'وضع اللمس مفعَّل — أزرار كبيرة' : 'وضع اللمس مطفأ',
          child: TextButton.icon(
            onPressed: () => ref.read(posTouchModeProvider.notifier).toggle(),
            icon: Icon(touch ? Icons.touch_app : Icons.touch_app_outlined, size: 18),
            label: Text(touch ? 'لمس' : 'فأرة'),
          ),
        ),
      ],
      // كشف اللمس من نوع المؤشر نفسه: شاشة كاشير تعمل باللمس على ويندوز لا
      // يميّزها نوع المنصة (ويندوز هو ويندوز بفأرة أو بشاشة لمس)، لكن حدث
      // الضغط يحمل kind = touch أو mouse. فمن أول لمسة بإصبع يتحوّل النظام
      // إلى الأزرار الكبيرة بلا أن يبحث الكاشير عن مفتاح في الشريط.
      body: Listener(
        onPointerDown: (event) {
          if (event.kind == PointerDeviceKind.touch) {
            ref.read(posTouchModeProvider.notifier).enableFromTouchInput();
          }
        },
        child: isDesktop
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
      ),
    );
  }

  Widget _scannerBuilder(BuildContext context, bool touch) {
    final resultsAsync = ref.watch(posProductResultsProvider);
    final allowOpen = ref.watch(posAllowOpenProductProvider).valueOrNull ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          autofocus: true,
          onChanged: _onSearchChanged,
          onSubmitted: _onSearchSubmitted,
          style: touch ? AppTextStyles.headlineMd(color: AppColors.textPrimary) : null,
          decoration: InputDecoration(
            hintText: 'امسح باركود الصنف أو ابحث بالاسم...',
            prefixIcon: const Icon(Icons.qr_code_scanner_outlined),
            filled: true,
            fillColor: AppColors.surface,
            // حقل أطول في وضع اللمس: هو هدف النقر الأول في الشاشة وأكثرها
            // استخداماً، ولوحة المفاتيح الافتراضية تغطي نصف الشاشة عند فتحه.
            contentPadding: touch ? const EdgeInsets.symmetric(vertical: 22, horizontal: 16) : null,
          ),
        ),
        if (allowOpen) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: touch ? 56 : 44,
            child: OutlinedButton.icon(
              onPressed: _addOpenProduct,
              icon: const Icon(Icons.edit_note_outlined, size: 20),
              label: Text('قيمة حرة', style: touch ? AppTextStyles.headlineMd() : null),
            ),
          ),
        ],
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
            // بطاقات أقل في الصف وأكبر حجماً في وضع اللمس — الهدف أن تُنقَر
            // بالإصبع دون تكبير ولا دقة، لا أن تُعرَض أكبر عدد ممكن.
            return GridView.count(
              crossAxisCount: touch ? 2 : 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: touch ? 1.1 : 1.3,
              children: products
                  .map((p) => _ProductTile(product: p, touch: touch, onTap: () => _addProduct(p)))
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  /// لوحة أرقام **ظاهرة** لإدخال الكمية — كآلة الكاشير الحقيقية.
  ///
  /// كانت اللوحة موجودة لكنها لا تُفتح إلا بالنقر على مربع الكمية، ولا شيء
  /// يدل على أن المربع قابل للنقر. ميزة لا يعرف المستخدم أنها موجودة ليست
  /// موجودة — فصارت ظاهرة افتراضياً في وضع اللمس، وبزر واضح على سطح المكتب.
  Widget _buildQuantityPad(bool touch) {
    if (_cart.isEmpty) return const SizedBox.shrink();

    final open = _padOpenOverride ?? touch;

    if (!open) {
      return SizedBox(
        height: 44,
        child: OutlinedButton.icon(
          onPressed: () => setState(() => _padOpenOverride = true),
          icon: const Icon(Icons.dialpad, size: 18),
          label: const Text('لوحة الأرقام — إدخال الكمية'),
        ),
      );
    }

    final line = _selectedLine;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.dialpad, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  line == null ? 'اختر صنفاً من السلة' : 'الكمية: ${line.name}',
                  style: AppTextStyles.labelMd(color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!touch)
                IconButton(
                  tooltip: 'إخفاء اللوحة',
                  icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                  onPressed: () => setState(() => _padOpenOverride = false),
                ),
            ],
          ),
          const SizedBox(height: 8),
          KeypadDisplay(
            value: _padValue,
            placeholder: line == null ? '—' : _formatQuantity(line.quantity),
          ),
          const SizedBox(height: 10),
          NumericKeypad(
            value: _padValue,
            onChanged: (v) => setState(() => _padValue = v),
            size: touch ? KeypadSize.large : KeypadSize.compact,
            allowDecimal: true,
            decimalPlaces: 3,
            onSubmit: _applyPadQuantity,
            // التركيز يبقى لحقل المسح: قارئ الباركود جهاز لوحة مفاتيح،
            // ولو خطفت اللوحة التركيز لتوقف المسح عن العمل.
            autofocus: false,
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: touch ? 56 : 44,
            child: FilledButton.icon(
              onPressed: (line == null || _padValue.isEmpty) ? null : _applyPadQuantity,
              icon: const Icon(Icons.check, size: 20),
              label: Text('تثبيت الكمية', style: touch ? AppTextStyles.headlineMd(color: Colors.white) : null),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatQuantity(double value) =>
      value == value.truncateToDouble() ? value.toStringAsFixed(0) : value.toString();

  Widget _cartBuilder(BuildContext context, bool touch) {
    return AppSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Flexible: العنوان مع زر الإلغاء واسم العميل في صف واحد كان
              // يفيض على عرض سلة ضيّق (الهاتف، أو ثلث الشاشة على المكتب).
              Flexible(
                child: Text(
                  'الفاتورة الحالية',
                  style: AppTextStyles.headlineMd(),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_cart.isNotEmpty)
                IconButton(
                  tooltip: 'إلغاء الفاتورة وتفريغ السلة',
                  icon: Icon(Icons.remove_shopping_cart_outlined, size: 20, color: AppColors.danger),
                  onPressed: _confirmClearCart,
                ),
              const Spacer(),
              InkWell(
                onTap: _pickCustomer,
                child: Row(
                  children: [
                    Icon(Icons.person_outline, size: 18, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text(_customer?['fullName'] as String? ?? 'زبون نقدي', style: AppTextStyles.bodyMd()),
                    if (_customer != null)
                      IconAction(
                        icon: Icons.close,
                        iconSize: 16,
                        dense: true,
                        tooltip: 'إزالة الزبون وإرجاع الفاتورة لزبون نقدي',
                        onPressed: () => setState(() => _customer = null),
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
                  touch: touch,
                  selected: identical(_selectedLine, line),
                  onSelect: () => setState(() {
                    _selectedLine = line;
                    _padValue = '';
                  }),
                  onIncrement: () => _changeQuantity(line, 1),
                  onDecrement: () => _changeQuantity(line, -1),
                  onEditQuantity: () => _editQuantity(line),
                  onRemove: () => setState(() {
                    _cart.remove(line);
                    if (identical(_selectedLine, line)) _selectedLine = _cart.isEmpty ? null : _cart.last;
                  }),
                )),
          const Divider(height: 24),
          Row(
            children: [
              Flexible(
                child: Text(
                  'الإجمالي المستحق',
                  style: AppTextStyles.headlineMd(),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              // المبلغ لا يُقتطع أبداً: هو أهم رقم في الشاشة، والعنوان هو
              // ما يتقلّص عند الضيق.
              CurrencyBadge(amount: _subtotal),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
          ],
          const SizedBox(height: 12),
          _buildQuantityPad(touch),
          const SizedBox(height: 16),
          // أزرار الدفع أطول في وضع اللمس — آخر نقرة في العملية وأكثرها
          // تكراراً على مدار اليوم، وخطأ الضغط فيها يعني فاتورة بطريقة دفع خاطئة.
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: touch ? 64 : 44,
                  child: OutlinedButton.icon(
                    onPressed: (_placingOrder || _loadingBranch) ? null : _startCashCheckout,
                    icon: const Icon(Icons.calculate_outlined, size: 20),
                    label: Text('نقداً', style: touch ? AppTextStyles.headlineMd() : null),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: touch ? 64 : 44,
                  child: ElevatedButton(
                    onPressed: (_placingOrder || _loadingBranch) ? null : _startWalletCheckout,
                    child: _placingOrder
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            'خصم من الرصيد',
                            style: touch ? AppTextStyles.headlineMd(color: Colors.white) : null,
                          ),
                  ),
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
  const _ProductTile({required this.product, required this.onTap, this.touch = false});
  final Map<String, dynamic> product;
  final VoidCallback onTap;
  final bool touch;

  @override
  Widget build(BuildContext context) {
    final quantity = (product['quantity'] as num?)?.toDouble() ?? 0;
    // الصنف المفتوح لا يتبع المخزون، فكميته صفر دائماً ولا يجوز منع بيعه بها.
    final tracksStock = product['tracksStock'] as bool? ?? true;
    final sellable = !tracksStock || quantity > 0;
    return InkWell(
      onTap: sellable ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: AppSurface(
      padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              tracksStock ? Icons.inventory_2_outlined : Icons.edit_note_outlined,
              color: sellable ? AppColors.textMuted : AppColors.danger,
              size: touch ? 28 : 24,
            ),
            const Spacer(),
            Text(
              product['name'] as String? ?? '',
              style: touch
                  ? AppTextStyles.headlineMd(color: AppColors.textPrimary)
                  : AppTextStyles.bodyMd(color: AppColors.textPrimary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            CurrencyBadge(amount: (product['salePrice'] as num?)?.toDouble() ?? 0),
            Text(
              !tracksStock
                  ? 'قيمة حرة'
                  : (quantity > 0 ? 'متوفر: ${quantity.toStringAsFixed(0)}' : 'نفد المخزون'),
              style: AppTextStyles.labelMd(color: sellable ? AppColors.textMuted : AppColors.danger),
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
    required this.onEditQuantity,
    required this.onRemove,
    required this.onSelect,
    this.selected = false,
    this.touch = false,
  });

  final _CartLine line;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onEditQuantity;
  final VoidCallback onRemove;
  final VoidCallback onSelect;
  final bool selected;
  final bool touch;

  /// كمية موزونة (1.5 كغ) تُعرَض بكسورها، والعدد الصحيح بلا كسور زائدة —
  /// toStringAsFixed(0) السابق كان يعرض 1.5 كغ على أنها "2".
  String get _quantityLabel {
    if (line.quantity == line.quantity.truncateToDouble()) {
      return line.quantity.toStringAsFixed(0);
    }
    return line.quantity.toString();
  }

  @override
  Widget build(BuildContext context) {
    final btn = touch ? 52.0 : 34.0;
    final iconSize = touch ? 30.0 : 20.0;

    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: touch ? 8 : 6, horizontal: 6),
        decoration: BoxDecoration(
          // السطر المحدَّد هو هدف لوحة الأرقام — يجب أن يُرى أيّه بلا تفكير.
          color: selected ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.07) : null,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent,
          ),
        ),
        child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.name,
                  style: touch
                      ? AppTextStyles.headlineMd(color: AppColors.textPrimary)
                      : AppTextStyles.bodyMd(color: AppColors.textPrimary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                CurrencyBadge(amount: line.lineTotal),
              ],
            ),
          ),
          _QtyButton(icon: Icons.remove, size: btn, iconSize: iconSize, onTap: onDecrement),
          // الكمية نفسها زر: النقر عليها يفتح لوحة الأرقام لكتابتها مباشرة،
          // فبيع 24 قطعة لا يحتاج 23 نقرة على زر الزيادة.
          InkWell(
            onTap: onEditQuantity,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: touch ? 68 : 44,
              height: btn,
              alignment: Alignment.center,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                _quantityLabel,
                style: touch
                    ? AppTextStyles.displayLg(color: AppColors.textPrimary)
                    : AppTextStyles.headlineMd(color: AppColors.textPrimary),
              ),
            ),
          ),
          _QtyButton(icon: Icons.add, size: btn, iconSize: iconSize, onTap: onIncrement),
          const SizedBox(width: 4),
          _QtyButton(
            icon: Icons.delete_outline,
            size: btn,
            iconSize: touch ? 26 : 18,
            color: AppColors.danger,
            onTap: onRemove,
          ),
        ],
        ),
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  const _QtyButton({
    required this.icon,
    required this.size,
    required this.iconSize,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final double size;
  final double iconSize;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          foregroundColor: color ?? AppColors.textPrimary,
          side: BorderSide(color: color?.withValues(alpha: 0.4) ?? AppColors.border),
        ),
        onPressed: onTap,
        child: Icon(icon, size: iconSize),
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

/// اختيار صنف مفتوح القيمة من الكتالوج.
///
/// يظهر فقط عند وجود أكثر من صنف مفتوح؛ الصنف الواحد يُختار مباشرة بلا نافذة.
class _OpenProductPickerDialog extends StatelessWidget {
  const _OpenProductPickerDialog({required this.products});

  final List<Map<String, dynamic>> products;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('اختر الصنف المفتوح'),
      content: SizedBox(
        width: 360,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: products.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final p = products[i];
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              leading: const Icon(Icons.edit_note_outlined),
              title: Text(p['name'] as String? ?? '', style: AppTextStyles.bodyMd(color: AppColors.textPrimary)),
              subtitle: Text('قيمة حرة', style: AppTextStyles.labelMd()),
              onTap: () => Navigator.pop(context, p),
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
      ],
    );
  }
}
