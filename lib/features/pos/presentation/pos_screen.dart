import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import '../../../shared/widgets/adaptive_form_dialog.dart';
import 'package:flutter/services.dart' show KeyDownEvent, KeyEvent, LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/feedback/pos_sounds.dart';
import '../../../core/network/api_client.dart';
import 'barcode_scanner_sheet.dart';
import 'return_invoice_sheet.dart';
import '../../../core/printing/receipt_template.dart';
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
import '../../../shared/widgets/icon_action.dart';
import '../../../core/network/offline_queue.dart';
import '../../../shared/widgets/app_surface.dart';
import '../../../shared/widgets/pagination_bar.dart';
import '../../../core/shortcuts/keyboard_shortcuts_manager.dart';

/// ما يعرضه الشريط السفلي — بنفس ترتيب [_PosScreenState._onShortcut].
const _kPosShortcuts = [
  AppShortcut('نقدي', 'F2'),
  AppShortcut('خصم من الرصيد', 'F3'),
  AppShortcut('بطاقة العميل', 'F4'),
  AppShortcut('لوحة الكمية', 'F6'),
  AppShortcut('إلغاء الفاتورة', 'F8'),
  AppShortcut('تفريغ البحث', 'Esc'),
];

class _CartLine {
  _CartLine({
    required this.productId,
    required this.name,
    required this.unitPrice,
    required this.availableQuantity,
    this.medicineRefId,
    this.requiresPrescription = false,
    this.subUnitName,
    this.subUnitsPerBase = 0,
    this.subUnitPrice = 0,
  });

  final String productId;
  final String name;
  final double unitPrice;
  final double availableQuantity;

  /// وجودها يعني أن للصنف نشرة دواء تُعرض عند الطلب — راجع
  /// [medicineInfoProvider]. تبقى null للأصناف غير الدوائية ولغير إصدار
  /// الصيدليات، فلا يظهر زر النشرة أصلاً.
  final String? medicineRefId;

  /// دواء يُصرَف بوصفة — الخادم يرفض الفاتورة بلا بيانات وصفة، فتُطلَب قبل
  /// الدفع لا بعد الرفض والزبون ينتظر.
  final bool requiresPrescription;

  // ── البيع بالوحدة الجزئية ──────────────────────────────────────────
  final String? subUnitName;
  final double subUnitsPerBase;
  final double subUnitPrice;

  /// هل يقبل هذا الصنف بيعاً جزئياً — نفس شرط الخادم (Product.AllowsSubUnitSale).
  bool get allowsSubUnit => subUnitsPerBase > 1 && subUnitPrice > 0 && subUnitName != null;

  /// الوحدة المختارة للبيع. يبدّلها الكاشير على السطر نفسه: الباركود على
  /// الشريط، فالمسح يعطي الوحدة الأساسية، والتبديل بعده أسرع من نافذة
  /// اختيار تعترض كل مسحة.
  bool soldAsSubUnit = false;

  /// السعر الفعلي حسب الوحدة المختارة.
  double get effectiveUnitPrice => soldAsSubUnit ? subUnitPrice : unitPrice;

  String get unitLabel => soldAsSubUnit ? (subUnitName ?? '') : '';
  double quantity = 1;

  double get lineTotal => effectiveUnitPrice * quantity;
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

  /// حقل الكمية على الهاتف — يُزامَن من _padValue في البناء.
  ///
  /// المصدر يبقى واحداً (_padValue) لأنه يُصفَّر في ستّة مواضع؛ ومتحكّمٌ
  /// يُصفَّر في بعضها دون بعض يُبقي رقماً قديماً معروضاً على الشاشة بينما
  /// المنطق يراه فارغاً.
  final _padFieldController = TextEditingController();

  /// المبلغ المستلَم نقداً — يُكتب على شاشة البيع نفسها لا في نافذة منفصلة.
  /// فارغ يعني «المبلغ بالضبط»، وهو الحالة الغالبة.
  final _tenderedController = TextEditingController();

  Map<String, dynamic>? _customer;
  String? _branchId;
  /// فروع المنظمة — تُملأ فقط لمن لا فرع مثبَّت في توكنه، ليختار منها.
  List<Map<String, dynamic>> _branches = const [];
  bool _loadingBranch = true;
  bool _placingOrder = false;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    readCurrentBranchId().then((id) async {
      if (!mounted) return;
      if (id != null) {
        setState(() {
          _branchId = id;
          _loadingBranch = false;
        });
        return;
      }
      // مدير عام أو مالك منصة: لا فرع في توكنه لأنه غير مقيّد بفرع، لا
      // لأنه ممنوع. رفضه كان يمنع صاحب المنشأة نفسه من فتح نقطة البيع في
      // فرعه — والحلّ الوحيد أمامه أن يقيّد حسابه بفرع واحد فيفقد رؤية
      // الباقي. فيُختار الفرع هنا بدل الرفض.
      try {
        final res = await ApiClient.instance.dio.get('/branches');
        final list = (res.data as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .where((b) => b['isActive'] != false)
            .toList();
        if (!mounted) return;
        setState(() {
          _branches = list;
          // فرع واحد فقط: لا معنى لسؤال لا جواب له إلا واحد.
          if (list.length == 1) _branchId = list.first['id'] as String;
          _loadingBranch = false;
        });
      } catch (_) {
        if (mounted) setState(() => _loadingBranch = false);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _tenderedController.dispose();
    _padFieldController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// كل رفض يُعرَض ويُسمَع معاً.
  ///
  /// كان الخطأ نصاً أحمر في زاوية الشاشة لا غير، والكاشير ينظر إلى الزبون
  /// لا إلى الشاشة — فيمضي ظانّاً أن العملية تمّت.
  void _fail(String message) {
    setState(() => _error = message);
    PosSounds.error();
  }

  double get _subtotal => _cart.fold(0, (sum, line) => sum + line.lineTotal);

  double get _tendered => double.tryParse(_tenderedController.text.trim()) ?? 0;

  /// الباقي للزبون. سالبٌ يعني أن المستلَم أقل من المستحق.
  double get _changeDue => _tendered - _subtotal;

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

  /// يفتح كاميرا الجهاز، ويمرّر الرمز الممسوح إلى نفس مسار القارئ السلكي —
  /// فسلوك الجهازين واحد: باركود صنف أولاً، ثم بطاقة عميل.
  /// يفتح حوار الإرجاع، ويُنعش الشاشة بعد نجاحه.
  Future<void> _startReturn() async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => const ReturnInvoiceSheet(),
    );
    if (done == true && mounted) {
      // الكمية عادت إلى المخزون، فأرصدة شبكة الوصول السريع لم تعد صحيحة.
      ref.invalidate(posQuickPicksProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تمّ الإرجاع — عادت الكمية إلى المخزون')),
      );
    }
  }

  Future<void> _scanWithCamera() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerSheet(), fullscreenDialog: true),
    );
    if (code == null || code.isEmpty || !mounted) return;
    _searchController.text = code;
    await _onSearchSubmitted(code);
  }

  /// يحوّل المسحة إلى اختيار عميل — الكاشير يمرّر البطاقة على نفس القارئ
  /// دون فتح نافذة اختيار العميل ولا كتابة أي شيء.
  Future<bool> _tryCardScan(String code) async {
    try {
      final response = await ApiClient.instance.dio.get('/customers/by-card/$code');
      final customer = Map<String, dynamic>.from(response.data as Map);
      if (!mounted) return true;
      setState(() {
        _customer = customer;
        _error = null;
      });
      _searchController.clear();
      ref.read(posProductSearchProvider.notifier).state = '';
      _searchFocusNode.requestFocus();
      return true;
    } on DioException {
      // ليس رمز بطاقة ولا باركود صنف — تُترك الشبكة كما هي ليختار الكاشير يدوياً.
      return false;
    }
  }

  /// إدخال رمز بطاقة العميل صراحةً.
  ///
  /// المسح على مربع بحث الأصناف يعمل ويبقى كما هو، لكنه ميزة لا يعرفها من
  /// لم يقرأ الكود: لا زر لها ولا نصّ يذكرها. وعلى جهاز بلا قارئ لا سبيل
  /// إليها إطلاقاً. هذا الزر يجعلها مرئية ويجعل الإدخال اليدوي ممكناً.
  Future<void> _promptCardCode() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('بطاقة العميل'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          decoration: const InputDecoration(
            labelText: 'رمز البطاقة',
            hintText: 'امسح البطاقة أو اكتب رمزها',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('بحث'),
          ),
        ],
      ),
    );
    if (code == null || code.isEmpty) return;
    final found = await _tryCardScan(code);
    if (!found && mounted) {
      _fail('لا عميل بهذه البطاقة — تأكّد من الرمز أو أنها غير موقوفة');
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
        _fail('بيع الأصناف مفتوحة القيمة غير مفعَّل — '
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
          medicineRefId: product['medicineRefId'] as String?,
          requiresPrescription: product['requiresPrescription'] == true,
          subUnitName: product['subUnitName'] as String?,
          subUnitsPerBase: (product['subUnitsPerBase'] as num?)?.toDouble() ?? 0,
          subUnitPrice: (product['subUnitPrice'] as num?)?.toDouble() ?? 0,
        );
        _cart.add(line);
        PosSounds.scan();
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
      _fail('لا يوجد صنف مفتوح القيمة في الكتالوج — أنشئ صنفاً '
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

  /// البيع نقداً بنقرة واحدة — بلا نافذة وسيطة.
  ///
  /// كانت تُفتح حاسبة في نافذة منفصلة قبل كل عملية نقدية: نقرتان إضافيتان
  /// وانتظار انتقال، في أكثر إجراء تكراراً على مدار اليوم وأمام زبون واقف.
  /// والحاسبة نفسها لم تكن تحفظ شيئاً — تعرض الباقي ثم تنساه. فصار المبلغ
  /// المستلَم يُكتب على الشاشة نفسها اختيارياً (والباقي يظهر فوراً بجانبه)،
  /// وتركه فارغاً — وهو الغالب — يعني الدفع بالمبلغ بالضبط.
  Future<void> _startCashCheckout() async {
    if (_cart.isEmpty) {
      _fail('السلة فارغة');
      return;
    }
    // مستلَم أقلّ من المستحق = دفع جزئي، والفرق دَينٌ على العميل. يُؤكَّد
    // صراحةً لأنه ليس ما يقصده الكاشير عادةً: الغالب أن يكون خطأ إدخال،
    // لا نيّة بيع بالأجل.
    if (_tenderedController.text.trim().isNotEmpty && _changeDue < 0) {
      if (_customer == null) {
        _fail('الدفع الجزئي يحتاج عميلاً محدَّداً — امسح بطاقته أو اختره أولاً');
        return;
      }
      final remaining = -_changeDue;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('دفع جزئي'),
          content: Text(
            'المستلَم أقلّ من المستحق بمقدار ${remaining.toStringAsFixed(2)}. '
            'سيُقيَّد الباقي دَيناً على ${_customer!['fullName']}.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('تراجع')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد الدَّين')),
          ],
        ),
      );
      if (confirmed != true) return;
      await _checkout('cash', paidAmount: _tendered);
      return;
    }
    await _checkout('cash');
  }

  /// الخصم من المحفظة بحسب نمط تحقّق الحساب.
  ///
  /// النمط يأتي من الخادم مع بيانات العميل (`effectiveCardMode`) **ولا
  /// يختاره الكاشير**: من يستطيع خفض الحماية لحظة الصرف لا تحميه حمايةٌ.
  /// وما تفعله هذه الدالة عرضٌ فحسب — الخادم يُعيد الفحص كاملاً بنمطه هو
  /// وسقفه هو (راجع CardModeGate)، فتخطّي الحوار من الواجهة لا يُمرّر شيئاً.
  Future<void> _startWalletCheckout() async {
    if (_cart.isEmpty) {
      _fail('السلة فارغة');
      return;
    }
    if (_customer == null) {
      _fail('امسح بطاقة العميل أو اختره أولاً للخصم من رصيده');
      return;
    }

    final symbol = ref.read(brandingProvider).valueOrNull?.currencySymbol ?? 'د.ل';
    final name = _customer!['fullName'] as String? ?? '';
    final mode = _customer!['effectiveCardMode'] as String? ?? 'pin';

    if (mode == 'card') {
      // بلا رقم سرّي: تأكيدٌ يرى فيه الطرفان المبلغ والسقف. السقف يُعرَض لأن
      // الرفض بعد الضغط يبدو عطلاً في النظام ما لم يُعرف حدّه قبله.
      final cap = (_customer!['effectiveDailyCap'] as num?)?.toDouble() ?? 0;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => _WalletCardConfirmDialog(
          customerName: name,
          amount: _subtotal,
          dailyCap: cap,
          currencySymbol: symbol,
        ),
      );
      if (confirmed == true) await _checkout('customer_wallet');
      return;
    }

    final pin = await showDialog<String>(
      context: context,
      builder: (_) => _WalletPinDialog(
        customerName: name,
        amount: _subtotal,
        currencySymbol: symbol,
      ),
    );
    if (pin != null) await _checkout('customer_wallet', customerPin: pin);
  }

  Future<void> _checkout(String paymentMethod, {String? customerPin, double? paidAmount}) async {
    if (_cart.isEmpty) {
      _fail('السلة فارغة');
      return;
    }
    if (_branchId == null) {
      _fail(_branches.isEmpty
          ? 'لا فرع نشط في هذه المنظمة — أنشئ فرعاً من شاشة الفروع أولاً'
          : 'اختر الفرع الذي تبيع منه أولاً');
      return;
    }
    if (paymentMethod == 'customer_wallet' && _customer == null) {
      _fail('اختر عميلاً أولاً للخصم من رصيده');
      return;
    }

    // الوصفة قبل الدفع: الخادم يرفض صرف المقيَّد بلا وصفة (راجع قاعدة
    // الرفض في InvoicesController)، ومطالبة الكاشير بها بعد ضغط «دفع»
    // والزبون واقف أسوأ من مطالبته بها الآن.
    final restricted = _cart.where((l) => l.requiresPrescription).toList();
    Map<String, dynamic>? prescription;
    if (restricted.isNotEmpty) {
      prescription = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _PrescriptionDialog(
          medicines: restricted.map((l) => l.name).toList(),
        ),
      );
      // إلغاء الوصفة يُلغي البيع لا يُكمله بلا قيد — الدفتر هو المستند
      // النظامي، وصرفٌ بلا قيد مخالفة.
      if (prescription == null) return;
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
      // المدفوع فعلاً والمستلَم نقداً — يُحفظان في الفاتورة للتدقيق
      // ولتسوية الدرج، وأقلّ من الإجمالي يعني دَيناً على العميل.
      'paidAmount': paidAmount,
      'tenderedAmount': _tenderedController.text.trim().isEmpty ? null : _tendered,
      'customerPin': customerPin,
      'clientRequestId': OfflineQueueNotifier.newRequestId(),
      'lines': _cart
          .map((l) => {
                'productId': l.productId,
                'quantity': l.quantity,
                'unitPrice': l.effectiveUnitPrice,
                'soldAsSubUnit': l.soldAsSubUnit,
              })
          .toList(),
      if (prescription != null) 'prescription': prescription,
    };

    try {
      final response = await ApiClient.instance.dio.post('/invoices', data: payload);

      final invoiceId = response.data['id'] as String;
      final invoiceNumber = response.data['invoiceNumber'] as String? ?? '';
      PosSounds.success();
      setState(() {
        _cart.clear();
        _customer = null;
        _selectedLine = null;
        _padValue = '';
        _tenderedController.clear();
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
      //
      // ونمط «البطاقة وحدها» يزيد هذا إلزاماً: سقفه اليومي يُقاس بجمع ما
      // صُرف فعلاً من الدفتر، وجهازٌ مقطوع لا يعرف ما صُرف على جهاز آخر —
      // فطابورٌ يقبل هذه العمليات يجعل السقف يُتجاوَز بعدد الأجهزة.
      final offlineCapable = _isNetworkFailure(e) && paymentMethod == 'cash';
      if (offlineCapable) {
        final queued = await ref.read(offlineQueueProvider.notifier).enqueue(payload);
        if (queued) {
          setState(() {
            _cart.clear();
            _customer = null;
            _selectedLine = null;
            _padValue = '';
            _tenderedController.clear();
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('لا يوجد اتصال — حُفظت العملية وستُرسَل تلقائياً عند عودة الشبكة'),
                duration: Duration(seconds: 5),
              ),
            );
          }
        } else {
          _fail('طابور العمليات المؤجَّلة ممتلئ (${OfflineQueueNotifier.maxQueued}) — '
              'راجع الاتصال قبل متابعة البيع');
        }
      } else {
        _fail(_dioErrorMessage(e, 'تعذّر إتمام عملية البيع'));
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
      final template = await ref.read(receiptTemplateProvider.future);
      final logoBytes = await ref.read(receiptLogoProvider.future);
      await printInvoiceReceipt(
        invoice: response.data as Map<String, dynamic>,
        orgName: branding?.displayName ?? 'إتقان ERP',
        currencySymbol: branding?.currencySymbol ?? 'د.ل',
        template: template,
        logoBytes: logoBytes,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تعذّر تحضير الإيصال للطباعة')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Breakpoints.isDesktop(context);
    final touch = ref.watch(posTouchModeProvider);
    final scanner = _scannerBuilder(context, touch);
    final cart = _cartBuilder(context, touch);

    // مفاتيح الاختصار: نقطة البيع تُستعمل بيد واحدة على لوحة المفاتيح
    // والأخرى على البضاعة، والتنقّل بالفأرة بين الأزرار يبطئ كل عملية.
    // Focus لا Shortcuts/Actions: الأخيران يتطلّبان أن يكون التركيز داخل
    // شجرتهما، ومربع البحث يخطف التركيز دائماً (autofocus وإعادة تركيز بعد
    // كل مسحة) — فمعالج مستوى الشاشة هو الوحيد الذي يلتقط المفتاح حيثما كان.
    return Focus(
      autofocus: false,
      onKeyEvent: _onShortcut,
      child: _buildScaffold(context, isDesktop, touch, scanner, cart),
    );
  }

  /// المفاتيح الوظيفية — ومعروضةٌ في [_kPosShortcuts] أسفل الشاشة.
  ///
  /// <para>القائمتان تُقرآن معاً عمداً: خريطةٌ تتغيّر هنا ولا تتغيّر هناك
  /// تُنتج شريطاً يكذب، وهو أسوأ من شريطٍ لا وجود له.</para>
  ///
  /// Enter لا يُلتقط هنا: هو مفتاح القارئ السلكي — يُرسله بعد كل مسحة —
  /// ويعالجه مربع البحث نفسه عبر onSubmitted. اختطافه على مستوى الشاشة كان
  /// سيكسر المسح كله.
  KeyEventResult _onShortcut(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.f2) {
      _startCashCheckout();
    } else if (key == LogicalKeyboardKey.f3) {
      _startWalletCheckout();
    } else if (key == LogicalKeyboardKey.f4) {
      _promptCardCode();
    } else if (key == LogicalKeyboardKey.f6) {
      setState(() => _padOpenOverride = true);
    } else if (key == LogicalKeyboardKey.f8) {
      if (_cart.isNotEmpty) _confirmClearCart();
    } else if (key == LogicalKeyboardKey.escape) {
      _searchController.clear();
      ref.read(posProductSearchProvider.notifier).state = '';
      _searchFocusNode.requestFocus();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Widget _buildScaffold(
      BuildContext context, bool isDesktop, bool touch, Widget scanner, Widget cart) {
    return AdaptiveScaffold(
      title: 'نقطة البيع',
      activeRoute: '/pos',
      actions: [
        // الإرجاع من نقطة البيع نفسها.
        //
        // كان في شاشة الفواتير وحدها: الكاشير أمام زبون يُرجع بضاعة يترك
        // نقطة البيع ويبحث في الفواتير والزبون ينتظر. وهذا ما يدفع إلى
        // تسوية المرتجع نقداً من الدرج بلا فاتورة — فيخرج المال ولا يعود
        // الصنف إلى المخزون ولا أثر لشيء.
        if (ref.watch(myPermissionsProvider).valueOrNull?.can('invoices.refund') ?? false)
          TextButton.icon(
            onPressed: _startReturn,
            icon: const Icon(Icons.assignment_return_outlined, size: 18),
            label: const Text('إرجاع'),
          ),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // شريط الصلاحية فوق كلتا الحالتين (سطح مكتب وجوّال): المعلومة
            // تُعرض حيث يقع الفعل. تقرير شهري يزوره المدير لا يمنع تلف
            // البضاعة — الكاشير هو من يمسك الصنف بيده.
            _ExpiryBanner(branchId: _branchId),
            _buildLayout(isDesktop, scanner, cart),
            // على سطح المكتب وحده: شاشة اللمس بلا لوحة مفاتيح، والشريط
            // يأكل ارتفاعاً هو أثمن ما فيها. و`touch` لا `isDesktop` وحده
            // لأن جهاز الكاشير ويندوزٌ بشاشة لمس — سطح مكتب بلا لوحة.
            if (isDesktop && !touch) const ShortcutHintBar(shortcuts: _kPosShortcuts),
          ],
        ),
      ),
    );
  }

  Widget _buildLayout(bool isDesktop, Widget scanner, Widget cart) {
    return isDesktop
            // بلا IntrinsicHeight: كان يلفّ هذا الصف لتتساوى ارتفاعات
            // اللوحتين، لكنه يستدعي قياس الأبعاد الجوهرية — وشبكة الأصناف
            // داخله عارض كسول (GridView بـ shrinkWrap) يرفض ذلك صراحةً،
            // فينهار التخطيط كاملاً بـ RenderShrinkWrappingViewport does not
            // support returning intrinsic dimensions.
            //
            // العطل كامن منذ أول التزام ولم يظهر لأن بحث الأصناف كان معطوباً
            // فلم تُملأ الشبكة قط. إصلاح البحث هو ما كشفه.
            //
            // التساوي ليس مطلوباً أصلاً: سلّة فارغة لا يجب أن تمتدّ بطول
            // قائمة أصناف طويلة، وCrossAxisAlignment.start يعطي كل لوحة
            // ارتفاعها الطبيعي.
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: scanner),
                  const SizedBox(width: 20),
                  Expanded(flex: 2, child: cart),
                ],
              )
            : Column(children: [scanner, const SizedBox(height: 20), cart]);
  }

  Widget _scannerBuilder(BuildContext context, bool touch) {
    final resultsAsync = ref.watch(posProductResultsProvider);
    final allowOpen = ref.watch(posAllowOpenProductProvider).valueOrNull ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // يظهر فقط لمن لا فرع مثبَّت في توكنه (مدير عام، مالك منصة).
        // الكاشير المقيّد بفرع لا يراه أصلاً فلا يستطيع البيع من غير فرعه.
        if (_branches.length > 1) ...[
          DropdownButtonFormField<String>(
            initialValue: _branchId,
            decoration: const InputDecoration(
              labelText: 'الفرع الذي تبيع منه',
              prefixIcon: Icon(Icons.store_outlined),
            ),
            items: _branches
                .map((b) => DropdownMenuItem(
                      value: b['id'] as String,
                      child: Text(b['name'] as String? ?? ''),
                    ))
                .toList(),
            onChanged: (v) => setState(() {
              _branchId = v;
              _error = null;
            }),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          autofocus: true,
          onChanged: _onSearchChanged,
          onSubmitted: _onSearchSubmitted,
          style: touch ? AppTextStyles.headlineMd(color: AppColors.textPrimary) : null,
          decoration: InputDecoration(
            hintText: 'امسح باركود الصنف أو ابحث بالاسم...',
            // زر حقيقي لا أيقونة زخرفية: كانت prefixIcon بلا مستقبِل نقر،
            // فالضغط عليها لا يفعل شيئاً — وهو أول ما يجرّبه من لا يملك
            // قارئاً سلكياً.
            prefixIcon: IconButton(
              tooltip: 'المسح بالكاميرا',
              icon: const Icon(Icons.qr_code_scanner_outlined),
              onPressed: _scanWithCamera,
            ),
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
              // لا شيء مكتوب: تُعرض أصناف الوصول السريع بدل نصّ إرشادي.
              // شاشة فارغة أمام كاشير بلا قارئ باركود تعني عملاً متوقّفاً،
              // لا إرشاداً.
              if (_searchController.text.trim().isEmpty) {
                return _buildQuickPicks(touch);
              }
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Text('لا توجد نتائج', style: AppTextStyles.bodyMd()),
              );
            }
            // بطاقات أقل في الصف وأكبر حجماً في وضع اللمس — الهدف أن تُنقَر
            // بالإصبع دون تكبير ولا دقة، لا أن تُعرَض أكبر عدد ممكن.
            // ارتفاع خلية ثابت (mainAxisExtent) لا نسبة أبعاد.
            //
            // childAspectRatio يجعل ارتفاع الخلية تابعاً لعرضها: على شاشة
            // أضيق تضيق الخلية فيقصر ارتفاعها، بينما محتواها ثابت (أيقونة
            // واسم سطرين وسعر وحالة مخزون) — فيفيض. وهذا ما كان يحدث على
            // الجهاز اللوحي والهاتف بأربعين بكسل.
            //
            // ارتفاع المحتوى لا علاقة له بالعرض أصلاً، فتثبيته يُنهي تبعية
            // لم يكن لها مبرّر.
            return GridView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              // عرض أقصى للبطاقة بدل عدد أعمدة ثابت: ثلاثة أعمدة على هاتف
              // بعرض 420 تعطي بطاقة بـ120 بكسل — يضيق فيها اسم الصنف إلى
              // سطرين فيفيض المحتوى، وهي ضيّقة على الإصبع أصلاً. اشتقاق
              // العدد من عرض أدنى معقول يجعل الشاشة الضيقة تعرض عمودين
              // مقروءين بدل ثلاثة مزدحمة، والعريضة تعرض أكثر تلقائياً.
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: touch ? 280 : 220,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                // ارتفاع ثابت لا نسبة أبعاد: ارتفاع المحتوى (أيقونة واسم
                // سطرين وسعر وحالة) لا علاقة له بعرض البطاقة، وربطه به
                // يجعل كل تضييق للشاشة فيضاً.
                mainAxisExtent: touch ? 200 : 176,
              ),
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
  /// المبلغ المستلَم والباقي — على شاشة البيع لا في نافذة.
  ///
  /// أزرار المبالغ الجاهزة تغطّي الحالة الغالبة بنقرة: المبلغ بالضبط، ثم
  /// أقرب ورقة نقدية أعلى منه. والكتابة اليدوية تبقى متاحة لغيرها.
  Widget _buildCashRow(bool touch) {
    final symbol = ref.watch(brandingProvider).valueOrNull?.currencySymbol ?? 'د.ل';
    final total = _subtotal;
    final quick = <double>{};
    for (final step in [5, 10, 20, 50, 100]) {
      final up = (total / step).ceil() * step;
      if (up > total) quick.add(up.toDouble());
    }
    final shortcuts = quick.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _tenderedController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.center,
                style: touch ? AppTextStyles.headlineMd() : null,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'المستلَم (اختياري)',
                  hintText: 'بالضبط',
                  suffixText: symbol,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: touch ? 16 : 10),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _changeDue < 0 ? 'المتبقّي على الزبون' : 'الباقي للزبون',
                    style: AppTextStyles.bodyMd(
                      color: _changeDue < 0 ? AppColors.warning : AppColors.success,
                    ),
                  ),
                  const SizedBox(height: 2),
                  CurrencyBadge(
                    amount: _tenderedController.text.trim().isEmpty ? 0 : _changeDue.abs(),
                    currencySymbol: symbol,
                  ),
                ],
              ),
            ),
          ],
        ),
        if (shortcuts.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => setState(() => _tenderedController.clear()),
                child: const Text('بالضبط'),
              ),
              ...shortcuts.take(4).map((amount) => OutlinedButton(
                    onPressed: () => setState(() =>
                        _tenderedController.text = amount.toStringAsFixed(0)),
                    child: Text(amount.toStringAsFixed(0)),
                  )),
            ],
          ),
        ],
      ],
    );
  }

  /// شبكة الوصول السريع — الأكثر مبيعاً والأصناف بلا باركود.
  Widget _buildQuickPicks(bool touch) {
    final picksAsync = ref.watch(posQuickPicksProvider);
    return picksAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('اكتب اسم الصنف أو امسح الباركود لبدء البيع', style: AppTextStyles.bodyMd()),
      ),
      data: (picks) {
        if (picks.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text('اكتب اسم الصنف أو امسح الباركود لبدء البيع', style: AppTextStyles.bodyMd()),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('وصول سريع', style: AppTextStyles.bodyMd(color: AppColors.textSecondary)),
            ),
            GridView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: touch ? 280 : 220,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                mainAxisExtent: touch ? 200 : 176,
              ),
              children: picks
                  .map((p) => _ProductTile(product: p, touch: touch, onTap: () => _addProduct(p)))
                  .toList(),
            ),
          ],
        );
      },
    );
  }

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
          // ── على الهاتف: لوحة النظام لا لوحةٌ نرسمها ─────────────────
          //
          // لوحةٌ مرسومة داخل شاشة هاتف تتقاسم المساحة مع القائمة فتصغر
          // أزرارها، وتظهر مكرَّرةً بجانب لوحة النظام إن فُتحت. ولوحة
          // الهاتف تعرف تكبير الخطّ وأرقام لغة الجهاز بلا سطرٍ منّا.
          //
          // ويبقى المرسوم على اللوحي وسطح المكتب: الكاشير هناك على شاشة
          // لمسٍ كبيرة بلا لوحة نظام، أو على فأرة.
          if (Breakpoints.isMobile(context))
            Builder(builder: (_) {
              if (_padFieldController.text != _padValue) {
                _padFieldController.value = TextEditingValue(
                  text: _padValue,
                  selection: TextSelection.collapsed(offset: _padValue.length),
                );
              }
              return TextField(
              controller: _padFieldController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              textAlign: TextAlign.center,
              style: AppTextStyles.displayLg(),
              decoration: InputDecoration(
                labelText: 'الكمية',
                hintText: line == null ? '—' : _formatQuantity(line.quantity),
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _padValue = v),
              onSubmitted: (_) => _applyPadQuantity(),
            );
            })
          else ...[
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
          ],
          const SizedBox(height: 10),
          SizedBox(
            height: touch ? 56 : 44,
            child: FilledButton.icon(
              onPressed: (line == null || _padValue.isEmpty) ? null : _applyPadQuantity,
              icon: const Icon(Icons.check, size: 20),
              label:
                  Text('تثبيت الكمية', style: touch ? AppTextStyles.headlineMd(color: Colors.white) : null),
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
              IconButton(
                tooltip: 'بطاقة العميل — للخصم من رصيده',
                icon: Icon(Icons.credit_card_outlined, size: 20, color: AppColors.textSecondary),
                onPressed: _promptCardCode,
              ),
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
                  onToggleUnit: () => setState(() {
                    line.soldAsSubUnit = !line.soldAsSubUnit;
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
          _buildCashRow(touch),
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
                    icon: const Icon(Icons.payments_outlined, size: 20),
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
                            width: 18,
                            height: 18,
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
    required this.onToggleUnit,
    this.selected = false,
    this.touch = false,
  });

  final _CartLine line;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onEditQuantity;
  final VoidCallback onRemove;
  final VoidCallback onSelect;
  final VoidCallback onToggleUnit;
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
            // مبدّل الوحدة لا يظهر إلا لصنف مهيَّأ للبيع الجزئي.
            if (line.allowsSubUnit)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 4),
                child: Tooltip(
                  message: line.soldAsSubUnit
                      ? 'يُباع بالـ${line.subUnitName} — اضغط للعودة للوحدة الكاملة'
                      : 'اضغط للبيع بالـ${line.subUnitName}',
                  child: OutlinedButton(
                    onPressed: onToggleUnit,
                    style: OutlinedButton.styleFrom(
                      minimumSize: Size(0, btn),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      foregroundColor:
                          line.soldAsSubUnit ? AppColors.info : AppColors.textSecondary,
                    ),
                    child: Text(
                      line.soldAsSubUnit ? line.subUnitName! : 'كامل',
                      style: AppTextStyles.caption(
                          color: line.soldAsSubUnit ? AppColors.info : AppColors.textSecondary),
                    ),
                  ),
                ),
              ),
            // زر النشرة لا يظهر إلا لصنف دوائي في إصدار الصيدليات — لا مكان
            // له في سلّة بقالة أو محل قطع غيار.
            if (line.medicineRefId != null)
              _MedicineInfoButton(productId: line.productId, productName: line.name, size: btn),
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

  /// آخر ما كُتب في حقل البحث — يُستعمل لتعبئة اسم العميل الجديد مسبقاً.
  String _typed = '';

  /// الحوار نفسه يتحوّل إلى نموذج إضافة بدل فتح حوار ثانٍ فوقه: حوار فوق
  /// حوار فوق شاشة البيع يربك على شاشة لمس صغيرة، ويجعل زر الرجوع غامضاً.
  bool _adding = false;

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    _typed = value;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(posCustomerSearchProvider.notifier).state = value;
    });
  }

  void _startAdding() {
    setState(() {
      _adding = true;
      _error = null;
      // ما كتبه الكاشير بحثاً هو اسم العميل غالباً — إعادة كتابته بعد بحث
      // فاشل خطوة ضائعة والزبون واقف.
      if (_nameController.text.isEmpty) _nameController.text = _typed.trim();
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final phone = _phoneController.text.trim();
      final response = await ApiClient.instance.dio.post('/customers', data: {
        'fullName': _nameController.text.trim(),
        if (phone.isNotEmpty) 'phone': phone,
      });
      // يُعاد العميل المُنشأ فيُختار فوراً — الغرض من الإضافة هنا هو البيع
      // له الآن، لا تسجيله ثم البحث عنه من جديد.
      if (mounted) Navigator.pop(context, response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      setState(() {
        _saving = false;
        _error = e.response?.statusCode == 403
            ? 'ليست لديك صلاحية إضافة عميل'
            : (e.response?.data is Map
                ? (e.response!.data['message'] as String? ?? 'تعذّر حفظ العميل')
                : 'تعذّر حفظ العميل');
      });
    } catch (_) {
      setState(() {
        _saving = false;
        _error = 'تعذّر حفظ العميل';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_adding ? 'عميل جديد' : 'اختيار عميل'),
      content: SizedBox(
        width: 360,
        height: 380,
        child: _adding ? _buildAddForm() : _buildPicker(),
      ),
      actions: _adding
          ? [
              TextButton(
                onPressed: _saving ? null : () => setState(() => _adding = false),
                child: const Text('رجوع'),
              ),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('حفظ واختيار'),
              ),
            ]
          : [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
            ],
    );
  }

  Widget _buildPicker() {
    final resultsAsync = ref.watch(posCustomerResultsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                autofocus: true,
                onChanged: _onSearch,
                decoration: const InputDecoration(
                    hintText: 'ابحث بالاسم أو الهاتف...', prefixIcon: Icon(Icons.search, size: 18)),
              ),
            ),
            // مخفيّ لمن لا يملك الصلاحية لا معطَّلاً: الخادم يشترط
            // customers.manage على POST /customers، وزر يردّ 403 دائماً
            // إزعاج بلا فائدة لكاشير لا يملك تغيير ذلك.
            Can(
              permission: Perm.customersManage,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: 8),
                child: IconButton.filled(
                  tooltip: 'عميل جديد',
                  icon: const Icon(Icons.person_add_alt_1, size: 20),
                  onPressed: _startAdding,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: resultsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => const Center(child: Text('تعذّر البحث')),
            data: (customers) {
              if (customers.isEmpty) {
                return Center(
                  child: Text(
                    _typed.trim().isEmpty
                        ? 'اكتب للبحث عن عميل'
                        : 'لا نتائج — أضِف عميلاً جديداً بالزر أعلاه',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMd(),
                  ),
                );
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
    );
  }

  /// حقلان فقط عمداً.
  ///
  /// نموذج العملاء الكامل (بريد، ملاحظات، باركود بطاقة، سقف ائتمان، نموذج
  /// الحساب، الراعي، الاستحقاق) نموذج إدارة لا نموذج صندوق — والزبون واقف
  /// أمام الكاشير. ما ينقص يُكمَّل لاحقاً من شاشة العملاء؛ والمطلوب الآن اسم
  /// يُربط به البيع.
  Widget _buildAddForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _nameController,
            autofocus: true,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'اسم العميل *',
              hintText: 'الاسم كما يُعرَف به',
              prefixIcon: Icon(Icons.person_outline, size: 18),
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'الاسم مطلوب' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            onFieldSubmitted: (_) => _saving ? null : _save(),
            decoration: const InputDecoration(
              labelText: 'الهاتف',
              hintText: 'اختياري',
              prefixIcon: Icon(Icons.phone_outlined, size: 18),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
          ],
          const Spacer(),
          Text(
            'بقية البيانات (المحفظة، البطاقة، سقف الائتمان) تُكمَّل من شاشة العملاء.',
            style: AppTextStyles.caption(),
          ),
        ],
      ),
    );
  }
}

/// تأكيد الخصم من محفظة العميل برقمه السري.
///
/// يعرض اسم صاحب البطاقة والمبلغ قبل اللوحة عمداً: الكاشير قد يكون مسح بطاقة
/// خاطئة أو بقي عميل سابق مختاراً من عملية لم تكتمل، والعميل نفسه يجب أن يرى
/// المبلغ الذي يوافق عليه قبل أن يُدخل رقمه.
/// تأكيد الخصم في نمط «البطاقة فقط» — بلا رقم سرّي.
///
/// حوارٌ لا حارس: ما يحرس فعلاً هو السقف اليومي في الخادم. وجوده لأن خصماً
/// يقع بضغطة واحدة بلا لحظة يرى فيها الطرفان المبلغ يُنتج خصوماتٍ بالخطأ
/// أكثر ممّا ينتجه أي سرقة.
class _WalletCardConfirmDialog extends StatelessWidget {
  const _WalletCardConfirmDialog({
    required this.customerName,
    required this.amount,
    required this.dailyCap,
    required this.currencySymbol,
  });

  final String customerName;
  final double amount;
  final double dailyCap;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تأكيد الخصم من البطاقة'),
      content: SizedBox(
        width: 320,
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
                  Text(customerName, style: AppTextStyles.headlineMd()),
                  const SizedBox(height: 10),
                  Text('المبلغ المخصوم', style: AppTextStyles.labelMd()),
                  const SizedBox(height: 2),
                  CurrencyBadge(amount: amount, currencySymbol: currencySymbol),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'هذا الحساب يعمل بنمط «البطاقة فقط» — لا رقم سرّي، '
              'والسقف اليومي ${dailyCap.toStringAsFixed(2)} $currencySymbol.',
              style: AppTextStyles.caption(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('تأكيد الخصم'),
        ),
      ],
    );
  }
}

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
              title:
                  Text(p['name'] as String? ?? '', style: AppTextStyles.bodyMd(color: AppColors.textPrimary)),
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

/// شريط إنذار الصلاحية أعلى شاشة البيع.
///
/// لا يظهر إلا حين يوجد ما يستحق الإنذار — شريط دائم يراه الكاشير كل يوم
/// يصير جزءاً من خلفية الشاشة ويتوقف عن التبليغ عن أي شيء.
///
/// المنتهي يسبق المقترب وبلون الخطر: المنتهي بضاعة لا تُباع أصلاً (يستبعدها
/// تخصيص الدفعات في السيرفر) فهي خسارة واقعة تحتاج إتلافاً أو تسوية، بينما
/// المقترب ما زال قابلاً للتصريف بخصم أو إرجاع للمورّد.
class _ExpiryBanner extends ConsumerWidget {
  const _ExpiryBanner({required this.branchId});

  final String? branchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(posExpiryAlertProvider(branchId)).valueOrNull;
    if (data == null) return const SizedBox.shrink();

    final expiredBatches = (data['expiredBatches'] as num?)?.toInt() ?? 0;
    final expiringBatches = (data['expiringBatches'] as num?)?.toInt() ?? 0;
    if (expiredBatches == 0 && expiringBatches == 0) return const SizedBox.shrink();

    final isExpired = expiredBatches > 0;
    final color = isExpired ? AppColors.danger : AppColors.warning;
    final background = isExpired ? AppColors.dangerBg : AppColors.warningBg;

    final expiredQty = (data['expiredQuantity'] as num?) ?? 0;
    final expiringQty = (data['expiringQuantity'] as num?) ?? 0;
    final withinDays = (data['withinDays'] as num?)?.toInt() ?? 30;

    final parts = <String>[
      if (expiredBatches > 0)
        'منتهية الصلاحية: $expiredBatches دفعة ($expiredQty) — لا تُباع',
      if (expiringBatches > 0)
        'تنتهي خلال $withinDays يوماً: $expiringBatches دفعة ($expiringQty)',
    ];

    final batches = (data['batches'] as List?) ?? const [];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(isExpired ? Icons.dangerous_outlined : Icons.schedule_outlined,
              color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(parts.join('  •  '),
                    style: AppTextStyles.bodyMd(color: color).copyWith(fontWeight: FontWeight.w600)),
                if (batches.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  // الأقرب انتهاءً وحده: الكاشير يحتاج أن يعرف أي صنف يمسكه
                  // الآن، لا قائمة يقرأها. البقية في غرفة الإشعارات.
                  Text(_describe(batches.first),
                      style: AppTextStyles.caption(color: color)),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'تحديث',
            icon: Icon(Icons.refresh, size: 18, color: color),
            onPressed: () => ref.invalidate(posExpiryAlertProvider(branchId)),
          ),
        ],
      ),
    );
  }

  String _describe(dynamic batch) {
    final map = batch as Map<String, dynamic>;
    final name = map['productName'] ?? '';
    final code = (map['batchNumber'] as String?)?.trim() ?? '';
    final days = (map['daysRemaining'] as num?)?.toInt() ?? 0;
    final qty = map['quantity'] ?? 0;
    final label = code.isEmpty ? '$name' : '$name (دفعة $code)';
    // اليوم صفر «تنتهي اليوم» لا «خلال 0 يوم»، والسالب مضى لا متبقٍّ.
    final when = days < 0
        ? 'انتهت منذ ${-days} يوماً'
        : days == 0
            ? 'تنتهي اليوم'
            : 'تنتهي خلال $days يوماً';
    return 'الأقرب: $label — $when، الكمية $qty';
  }
}

/// زر نشرة الدواء على سطر السلّة، ولوحة عرضها.
///
/// موضعه على السطر نفسه لا في شاشة منفصلة: الصيدلي يُسأل «هل يصلح مع الضغط؟»
/// والزبون واقف، فالجواب يجب أن يكون على بعد نقرة من الصنف الذي بيده. نشرة
/// في شاشة أخرى تُقرأ بعد انصراف الزبون — أي لا تُقرأ.
class _MedicineInfoButton extends ConsumerWidget {
  const _MedicineInfoButton({
    required this.productId,
    required this.productName,
    required this.size,
  });

  final String productId;
  final String productName;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: size,
      height: size,
      child: IconButton(
        tooltip: 'نشرة الدواء',
        padding: EdgeInsets.zero,
        icon: Icon(Icons.medical_information_outlined, size: size * 0.5, color: AppColors.info),
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => _MedicineInfoDialog(productId: productId, productName: productName),
        ),
      ),
    );
  }
}

class _MedicineInfoDialog extends ConsumerWidget {
  const _MedicineInfoDialog({required this.productId, required this.productName});

  final String productId;
  final String productName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final infoAsync = ref.watch(medicineInfoProvider(productId));

    return AlertDialog(
      title: Text(productName),
      content: SizedBox(
        width: 420,
        child: infoAsync.when(
          loading: () => const SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
          error: (_, __) => const Text('تعذّر تحميل النشرة'),
          data: (info) {
            if (info == null) return const Text('لا توجد نشرة لهذا الصنف.');
            final requiresPrescription = info['requiresPrescription'] == true;
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // المقيَّد بوصفة أولاً وبلون الخطر: صرفه بلا وصفة مخالفة
                  // نظامية لا مجرّد خطأ بيع، والكاشير يجب أن يراها قبل أي
                  // تفصيل آخر.
                  if (requiresPrescription)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.dangerBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.danger.withValues(alpha: 0.45)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.assignment_late_outlined, size: 18, color: AppColors.danger),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text('يُصرَف بوصفة طبية',
                                style: AppTextStyles.bodyMd(color: AppColors.danger)
                                    .copyWith(fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ),
                  _InfoLine(label: 'المادة الفعّالة', value: info['activeIngredient'] as String?),
                  _InfoLine(label: 'التركيز', value: info['strength'] as String?),
                  _InfoLine(label: 'الشكل الصيدلي', value: info['form'] as String?),
                  _InfoLine(label: 'دواعي الاستعمال', value: info['indications'] as String?),
                  // موانع الاستعمال والتحذيرات بلون التحذير: هي ما يُسأل عنه
                  // فعلاً عند الصرف، وطمسها وسط بقية النصّ يُفقدها غرضها.
                  _InfoLine(
                      label: 'موانع الاستعمال',
                      value: info['contraindications'] as String?,
                      color: AppColors.danger),
                  _InfoLine(label: 'تحذيرات', value: info['cautions'] as String?, color: AppColors.warning),
                  _InfoLine(label: 'أعراض جانبية', value: info['sideEffects'] as String?),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
      ],
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value, this.color});

  final String label;
  final String? value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final text = value?.trim();
    // الحقل الفارغ يُحذف لا يُعرض فارغاً: نشرة نصفها «-» توحي بأن البيانات
    // ناقصة في النظام، بينما الواقع أن الدواء لا مانع معروفاً له.
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.caption()),
          const SizedBox(height: 2),
          Text(text, style: AppTextStyles.bodyMd(color: color ?? AppColors.textPrimary)),
        ],
      ),
    );
  }
}

/// بيانات الوصفة لحظة صرف دواء مقيَّد.
///
/// تُطلَب قبل الدفع لا بعده: الخادم يرفض الفاتورة بلا وصفة، ومطالبة الكاشير
/// بها بعد ضغط «دفع» والزبون واقف تُضيّع الوقت في أسوأ لحظة.
///
/// ولا يُغلَق إلا بحفظ أو إلغاء صريح (barrierDismissible: false): الإغلاق
/// بنقرة خارج النافذة يُلغي البيع بلا أن يفهم الكاشير لماذا.
class _PrescriptionDialog extends StatefulWidget {
  const _PrescriptionDialog({required this.medicines});

  /// أسماء الأدوية المقيَّدة في السلّة — تُعرض ليعرف الكاشير سبب المطالبة.
  final List<String> medicines;

  @override
  State<_PrescriptionDialog> createState() => _PrescriptionDialogState();
}

class _PrescriptionDialogState extends State<_PrescriptionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _doctor = TextEditingController();
  final _patient = TextEditingController();
  final _number = TextEditingController();
  final _license = TextEditingController();
  final _phone = TextEditingController();
  DateTime? _issuedOn;

  @override
  void dispose() {
    for (final c in [_doctor, _patient, _number, _license, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    String? t(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    Navigator.pop(context, <String, dynamic>{
      'doctorName': _doctor.text.trim(),
      'patientName': _patient.text.trim(),
      'prescriptionNumber': t(_number),
      'doctorLicense': t(_license),
      'patientPhone': t(_phone),
      if (_issuedOn != null)
        'issuedOn': '${_issuedOn!.year.toString().padLeft(4, '0')}-'
            '${_issuedOn!.month.toString().padLeft(2, '0')}-'
            '${_issuedOn!.day.toString().padLeft(2, '0')}',
    });
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveFormDialog(
      title: 'وصفة طبية مطلوبة',
      maxWidth: 460,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء البيع'),
        ),
        FilledButton(onPressed: _submit, child: const Text('تسجيل الوصفة وإتمام البيع')),
      ],
      body: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.dangerBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.danger.withValues(alpha: 0.45)),
                  ),
                  child: Text(
                    'يُصرَف بوصفة: ${widget.medicines.join('، ')}',
                    style: AppTextStyles.bodyMd(color: AppColors.danger)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _doctor,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'اسم الطبيب *'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'اسم الطبيب مطلوب' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _patient,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'اسم المريض *'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'اسم المريض مطلوب' : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _number,
                        decoration: const InputDecoration(
                            labelText: 'رقم الوصفة', hintText: 'اختياري'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _license,
                        decoration: const InputDecoration(
                            labelText: 'ترخيص الطبيب', hintText: 'اختياري'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                            labelText: 'هاتف المريض', hintText: 'اختياري'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final now = DateTime.now();
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _issuedOn ?? now,
                            // وصفة بتاريخ مستقبلي لا معنى لها، والقديمة جداً
                            // تستحق مراجعة الصيدلي لا الاختيار بالخطأ.
                            firstDate: now.subtract(const Duration(days: 365)),
                            lastDate: now,
                          );
                          if (picked != null) setState(() => _issuedOn = picked);
                        },
                        icon: const Icon(Icons.event_outlined, size: 18),
                        label: Text(_issuedOn == null
                            ? 'تاريخ الوصفة'
                            : '${_issuedOn!.year}-${_issuedOn!.month}-${_issuedOn!.day}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'يُسجَّل في دفتر الوصفات مرتبطاً بهذه الفاتورة، ولا يُعدَّل بعد الصرف.',
                  style: AppTextStyles.caption(),
                ),
              ],
            ),
          ),
    );
  }
}
