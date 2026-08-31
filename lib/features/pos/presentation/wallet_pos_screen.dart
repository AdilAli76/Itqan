import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../shared/widgets/adaptive_form_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/feedback/pos_sounds.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/branch_roster_store.dart';
import '../../../core/network/offline_queue.dart';
import '../../../core/printing/wallet_receipt_printer.dart';
import '../../../core/responsive/adaptive_scaffold.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/branding_provider.dart';
import '../../../shared/widgets/currency_badge.dart';
import '../../../shared/widgets/numeric_keypad.dart';
import '../../../shared/widgets/pin_pad.dart';
import '../../../shared/widgets/section_card.dart';
import '../data/pos_providers.dart';
import '../data/pos_settings_provider.dart';
import 'barcode_scanner_sheet.dart';
import 'pos_screen.dart';

/// نقطة البيع في **إصدار المحفظة** — بلا بضاعة.
///
/// الفرق عن الشاشة القياسية ليس في الشكل بل في نموذج العمل: الجهة هنا لا
/// تبيع أصنافاً، بل تصرف على منتسبيها. فالكاشير يُدخل مبلغاً — لا يبحث في
/// كتالوج — ثم إمّا يخصمه من بطاقة العامل أو يسجّله بيعاً نقدياً للفرع.
///
/// ولذلك لا سلّة هنا ولا أسطر فاتورة ولا بحث ولا شبكة أصناف: كلها مفاهيم
/// متجرٍ يبيع بضاعة. الشاشة كلها لوحة مبلغ وزرّان.
class WalletPosScreen extends ConsumerStatefulWidget {
  const WalletPosScreen({super.key});

  @override
  ConsumerState<WalletPosScreen> createState() => _WalletPosScreenState();
}

class _WalletPosScreenState extends ConsumerState<WalletPosScreen> {
  String _amountText = '';

  /// حقل المبلغ على الهاتف — لوحة النظام لا لوحتنا.
  ///
  /// <para>لوحة الأرقام المرسومة بُنيت لشاشة كاشيرٍ ثابتة: أزرارٌ كبيرة
  /// تُضغط بالإبهام وشاشةٌ عريضة تتّسع لها. وعلى الهاتف تأكل نصف الشاشة
  /// فتدفع زرَّي الدفع تحت الطيّة — يكتب الكاشير المبلغ ثم يُمرّر ليجد
  /// الزرّ. ولوحة الهاتف الرقمية أسرع وأقرب إلى ما اعتاده إبهامه.</para>
  late final _amountController = TextEditingController();
  Map<String, dynamic>? _customer;
  String? _branchId;
  /// فروع المنظمة — تُملأ فقط لمن لا فرع مثبَّت في توكنه، ليختار منها.
  List<Map<String, dynamic>> _branches = const [];
  bool _loadingBranch = true;
  bool _busy = false;
  String? _error;

  double get _amount => double.tryParse(_amountText) ?? 0;

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
      // المدير العام لا فرع في توكنه لأنه غير مقيّد بفرع، لا لأنه ممنوع.
      // رفضه كان يمنع صاحب المنشأة نفسه من الخصم في فرعه — نفس علاج
      // الشاشة القياسية.
      try {
        final res = await ApiClient.instance.dio.get('/branches');
        final list = (res.data as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .where((b) => b['isActive'] != false)
            .toList();
        if (!mounted) return;
        setState(() {
          _branches = list;
          // فرع واحد: لا معنى لسؤال لا جواب له إلا واحد.
          if (list.length == 1) _branchId = list.first['id'] as String;
          _loadingBranch = false;
        });
      } catch (_) {
        if (mounted) setState(() => _loadingBranch = false);
      }
    });
  }

  void _fail(String message) {
    setState(() => _error = message);
    PosSounds.error();
  }

  // ── اختيار العامل ────────────────────────────────────────────────────

  /// مسح البطاقة بالكاميرا ثم البحث بها.
  Future<void> _scanCard() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerSheet(), fullscreenDialog: true),
    );
    if (code == null || code.isEmpty) return;
    await _lookupCard(code);
  }

  Future<void> _lookupCard(String code) async {
    try {
      final response = await ApiClient.instance.dio.get('/customers/by-card/$code');
      if (!mounted) return;
      setState(() {
        _customer = Map<String, dynamic>.from(response.data as Map);
        _error = null;
      });
      PosSounds.scan();
    } on DioException {
      _fail('لا حساب بهذه البطاقة — تأكّد من الرمز أو أنها غير موقوفة');
    }
  }

  /// إدخال رمز البطاقة يدوياً — لبطاقة تالفة لا تُقرأ.
  Future<void> _typeCard() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('رمز البطاقة'),
        content: TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          decoration: const InputDecoration(labelText: 'الرمز'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('بحث')),
        ],
      ),
    );
    if (code != null && code.isNotEmpty) await _lookupCard(code);
  }

  /// البحث بالاسم — لمن نسي بطاقته. وهي الحالة الشائعة لا النادرة، فالبطاقة
  /// تُنسى وتُفقد وتتلف، والعامل يبقى مستحقاً لرصيده.
  Future<void> _searchByName() async {
    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _WalletCustomerSearchDialog(),
    );
    if (selected != null) {
      setState(() {
        _customer = selected;
        _error = null;
      });
    }
  }

  // ── التنفيذ ──────────────────────────────────────────────────────────

  /// البيع النقدي — بعد تحديد ما استلمه الكاشير بيده.
  ///
  /// <para><b>الفجوة التي يسدّها:</b> كان النقد يُسجَّل بالمبلغ المطلوب
  /// وحده، فلا يعرف أحدٌ كم دخل الدرج فعلاً ولا كم أُعيد للزبون. وفي نهاية
  /// اليوم يُعدّ الدرج فيختلف عن النظام، ولا سبيل إلى معرفة أي عملية
  /// سبّبت الفرق.</para>
  ///
  /// <para>والمستلَم اختياري: كاشيرٌ يستلم المبلغ بالضبط لا يُجبَر على
  /// كتابته مرّتين — وإجبارُه يبطئ كل عملية ليضبط قليلاً منها.</para>
  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _chargeCash() async {
    if (_amount <= 0) {
      _fail('أدخل المبلغ أولاً');
      return;
    }

    final tendered = await showDialog<double?>(
      context: context,
      builder: (_) => _CashTenderedDialog(
        due: _amount,
        symbol: ref.read(brandingProvider).valueOrNull?.currencySymbol ?? 'د.ل',
      ),
    );
    // null من زرّ التراجع، و-1 من «بالضبط» — والفرق بينهما أن الثاني يمضي.
    if (tendered == null) return;

    await _submit('cash', tendered: tendered < 0 ? null : tendered);
  }

  Future<void> _chargeWallet() async {
    if (_customer == null) {
      _fail('امسح البطاقة أو ابحث عن العامل بالاسم أولاً');
      return;
    }
    if (_amount <= 0) {
      _fail('أدخل المبلغ أولاً');
      return;
    }
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => _WalletPinDialog(
        customerName: _customer!['fullName'] as String? ?? '',
        amountText: _amountText,
      ),
    );
    if (pin == null) return;
    await _submit('customer_wallet', pin: pin);
  }

  Future<void> _submit(String method, {String? pin, double? tendered}) async {
    if (_amount <= 0) {
      _fail('أدخل المبلغ أولاً');
      return;
    }
    if (_branchId == null) {
      _fail(_branches.isEmpty
          ? 'لا فرع نشط في هذه المنظمة — أنشئ فرعاً من شاشة الفروع أولاً'
          : 'اختر الفرع الذي تعمل منه أولاً');
      return;
    }

    // الصنف المفتوح يُزرَع عند إنشاء منظمة المحفظة، فوجوده مضمون. وإن غاب
    // (منظمة قديمة حُوِّلت يدوياً) تُقال الرسالة صراحةً بدل فشل غامض.
    final openProducts = await ref.read(posOpenProductsProvider.future).catchError(
          (_) => <Map<String, dynamic>>[],
        );
    if (!mounted) return;
    if (openProducts.isEmpty) {
      _fail('لا يوجد صنف قيمة في هذه المنظمة — راجع مزوّد النظام');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final response = await ApiClient.instance.dio.post('/invoices', data: {
        'branchId': _branchId,
        'customerId': _customer?['id'],
        'paymentMethod': method,
        'customerPin': pin,
        // الخادم يحسب الباقي من هذا الرقم — راجع InvoicesController.
        // وحسابُه في الواجهة يعني رقمين قد يفترقان.
        'tenderedAmount': tendered,
        'lines': [
          {
            'productId': openProducts.first['id'],
            'quantity': 1,
            'unitPrice': _amount,
          }
        ],
      });

      final invoice = Map<String, dynamic>.from(response.data as Map);
      PosSounds.success();

      // الرصيد بعد الخصم يُقرأ من السيرفر لا يُحسب في الواجهة: الرصيد مجموع
      // دفتر الحركات، وطرحُه هنا يعني رقمين قد يفترقان.
      double? remaining;
      if (method == 'customer_wallet' && _customer != null) {
        try {
          final c = await ApiClient.instance.dio.get('/customers/${_customer!['id']}');
          remaining = ((c.data['walletBalance'] as num?) ?? 0).toDouble();
        } catch (_) {}
      }

      if (!mounted) return;
      final amount = _amount;
      final customerName = _customer?['fullName'] as String?;
      setState(() {
        _amountText = '';
        _customer = null;
        _busy = false;
      });

      await showDialog<void>(
        context: context,
        builder: (_) => _DeductionResultDialog(
          amount: amount,
          method: method,
          customerName: customerName,
          remaining: remaining,
          invoice: invoice,
        ),
      );
    } on DioException catch (e) {
      if (!mounted) return;

      // انقطاع الشبكة لا رفضُ الخادم: الأوّل يُحاوَل محلياً، والثاني قرارٌ
      // نهائي يُقال للكاشير كما هو.
      if (_isOffline(e)) {
        final handled = await _submitOffline(method, tendered: tendered);
        if (handled) return;
      }

      if (!mounted) return;
      setState(() => _busy = false);
      final message = e.response?.data is Map
          ? (e.response!.data['message'] as String? ?? 'تعذّر إتمام العملية')
          : 'تعذّر إتمام العملية';
      _fail(message);
    }
  }

  /// زرّا الدفع — موضعُهما يختلف بالجهاز لا شكلُهما.
  Widget _actions() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 58,
            child: ElevatedButton.icon(
              onPressed: (_busy || _loadingBranch) ? null : _chargeWallet,
              icon: const Icon(Icons.credit_card_outlined),
              label: Text('خصم من الرصيد',
                  style: AppTextStyles.headlineMd(color: Colors.white)),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: (_busy || _loadingBranch) ? null : _chargeCash,
              icon: const Icon(Icons.payments_outlined),
              label: Text('بيع نقدي', style: AppTextStyles.headlineMd()),
            ),
          ),
        ],
      );

  /// أهو انقطاع شبكة أم رفضٌ من الخادم؟
  ///
  /// <para>الفرق جوهري: رفضُ الخادم قرارٌ يُقال للكاشير («رصيد غير كافٍ»)،
  /// والانقطاع حالةٌ تُعالَج محلياً. وخلطُهما يجعل رفضاً مشروعاً يُحفظ في
  /// الطابور ليُرفض ثانيةً عند المزامنة.</para>
  bool _isOffline(DioException e) =>
      e.response == null &&
      (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout);

  /// يحفظ العملية في الطابور — نقداً، أو سحباً من بطاقةٍ في كشف الفرع.
  ///
  /// <para><b>ولماذا يجوز السحب هنا وقد كان ممنوعاً:</b> المنع كان لسببين —
  /// جهلِ الرصيد، وتعذّرِ التحقّق من الرقم السرّي. والأوّل يحلّه كشف الفرع
  /// المخزَّن محلياً؛ أمّا الثاني فلا يحلّه شيء، ولذلك يُسمَح ببطاقات
  /// «بطاقة فقط» وحدها — وهي وحدها ما يُصدَّر في الكشف
  /// (راجع <c>BranchRosterController</c>).</para>
  Future<bool> _submitOffline(String method, {double? tendered}) async {
    final queue = ref.read(offlineQueueProvider.notifier);

    if (method == 'customer_wallet') {
      final code = _customer?['cardBarcode'] as String?;
      final roster = ref.read(branchRosterProvider);
      final card = code == null ? null : roster.byCode(code);

      if (card == null) {
        // القول صريحاً أن البطاقة ليست في كشف هذا الفرع: كاشيرٌ يقرأ
        // «تعذّرت العملية» يُعيد المحاولة عشر مرّات.
        setState(() => _busy = false);
        _fail('لا اتصال، وهذه البطاقة ليست في كشف الفرع — تعذّر السحب. '
            'استعمل البيع النقدي، أو انتظر عودة الشبكة.');
        return true;
      }

      if (card.balance < _amount) {
        setState(() => _busy = false);
        _fail('لا اتصال — والرصيد المعروف محلياً '
            '(${card.balance.toStringAsFixed(2)}) لا يكفي.');
        return true;
      }
    }

    final openProducts = await ref.read(posOpenProductsProvider.future).catchError(
          (_) => <Map<String, dynamic>>[],
        );
    if (openProducts.isEmpty) {
      if (mounted) setState(() => _busy = false);
      _fail('لا اتصال ولا صنف قيمة محفوظ — تعذّرت العملية');
      return true;
    }

    final queued = await queue.enqueue({
      // مفتاحٌ لكل عملية: انقطاع بعد وصول الطلب وقبل الرد حالة شائعة،
      // وبدونه تُنشأ العملية مرّتين.
      'clientRequestId': OfflineQueueNotifier.newRequestId(),
      'branchId': _branchId,
      'customerId': _customer?['id'],
      'paymentMethod': method,
      'tenderedAmount': tendered,
      'lines': [
        {
          'productId': openProducts.first['id'],
          'quantity': 1,
          'unitPrice': _amount,
        }
      ],
    });

    if (!queued) {
      if (mounted) setState(() => _busy = false);
      _fail('طابور العمليات المؤجَّلة ممتلئ (${OfflineQueueNotifier.maxQueued}) — '
          'راجع الاتصال قبل متابعة الصرف');
      return true;
    }

    // الرصيد المحلّي يُنقَص فوراً: سحبان متتاليان بلا اتصال كانا سيريان
    // الرصيد الكامل كلاهما فيخرج ضعف ما في البطاقة.
    if (method == 'customer_wallet' && _customer?['id'] != null) {
      await ref
          .read(branchRosterProvider.notifier)
          .debitLocally('${_customer!['id']}', _amount);
    }

    PosSounds.success();
    if (!mounted) return true;

    final amount = _amount;
    final customerName = _customer?['fullName'] as String?;
    setState(() {
      _amountText = '';
      _amountController.clear();
      _customer = null;
      _busy = false;
    });

    await showDialog<void>(
      context: context,
      builder: (_) => _DeductionResultDialog(
        amount: amount,
        method: method,
        customerName: customerName,
        remaining: null,
        offline: true,
      ),
    );
    return true;
  }

  /// يُحمّل كشف الفرع ثم يُحدّثه ما دامت الشبكة موصولة.
  Future<void> _loadRoster(String branchId) async {
    final notifier = ref.read(branchRosterProvider.notifier);
    await notifier.load(branchId);
    // الفشل صامت: التحديث عملٌ خلفي، والكشف القديم يبقى صالحاً.
    await notifier.refresh(branchId);
  }

  // ── العرض ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final symbol = ref.watch(brandingProvider).valueOrNull?.currencySymbol ?? 'د.ل';
    final isPhone = Breakpoints.isMobile(context);

    return AdaptiveScaffold(
      title: 'الخصم من الأرصدة',
      activeRoute: '/pos',
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // الدفع أعلى الشاشة على الهاتف: هو الفعل المقصود، ووضعُه
                // آخر الصفحة يجعله يحتاج تمريراً بعد كل مبلغ يُكتب.
                if (isPhone) ...[
                  _actions(),
                  const SizedBox(height: 14),
                ],
                if (_branches.length > 1) ...[
                  SectionCard(
                    title: 'الفرع',
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: _branchId,
                        decoration: const InputDecoration(labelText: 'الفرع الذي تعمل منه'),
                        items: _branches
                            .map((b) => DropdownMenuItem(
                                  value: b['id'] as String,
                                  child: Text(b['name'] as String? ?? ''),
                                ))
                            .toList(),
                        onChanged: (v) {
                          setState(() => _branchId = v);
                          if (v != null) _loadRoster(v);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                _customerCard(symbol),
                const SizedBox(height: 12),
                SectionCard(
                  title: 'المبلغ',
                  children: [
                    if (isPhone)
                      TextField(
                        controller: _amountController,
                        autofocus: true,
                        // لوحة النظام الرقمية بفاصلة عشرية — لا لوحة حروف
                        // يبحث فيها الكاشير عن الأرقام.
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        textInputAction: TextInputAction.done,
                        style: AppTextStyles.displayLg(),
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          labelText: 'المبلغ المطلوب',
                          suffixText: symbol,
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (v) => setState(() => _amountText = v),
                        onSubmitted: (_) => _busy ? null : _chargeWallet(),
                      )
                    else ...[
                      KeypadDisplay(value: _amountText, suffix: symbol, label: 'المبلغ المطلوب'),
                      const SizedBox(height: 12),
                      NumericKeypad(
                        value: _amountText,
                        onChanged: (v) => setState(() => _amountText = v),
                        size: KeypadSize.large,
                        onSubmit: _busy ? () {} : _chargeWallet,
                      ),
                    ],
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
                ],
                if (!isPhone) ...[
                  const SizedBox(height: 14),
                  _actions(),
                ],
                if (_busy) ...[
                  const SizedBox(height: 12),
                  const Center(child: CircularProgressIndicator()),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _customerCard(String symbol) {
    final c = _customer;
    return SectionCard(
      title: 'صاحب الرصيد',
      children: [
          if (c == null)
            Text('لم يُختَر أحد — البيع سيُسجَّل باسم «زبون نقدي»',
                style: AppTextStyles.bodyMd(color: AppColors.textSecondary))
          else
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c['fullName'] as String? ?? '', style: AppTextStyles.headlineMd()),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text('الرصيد: ', style: AppTextStyles.bodyMd()),
                          CurrencyBadge(
                            amount: ((c['walletBalance'] as num?) ?? 0).toDouble(),
                            currencySymbol: symbol,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'إزالة',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _customer = null),
                ),
              ],
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _scanCard,
                icon: const Icon(Icons.qr_code_scanner_outlined, size: 18),
                label: const Text('مسح البطاقة'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _typeCard,
                icon: const Icon(Icons.keyboard_outlined, size: 18),
                label: const Text('رمز يدوي'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _searchByName,
                icon: const Icon(Icons.person_search_outlined, size: 18),
                label: const Text('بحث بالاسم'),
              ),
            ],
          ),
      ],
    );
  }
}

/// إثبات الخصم — يُعرض بعد كل عملية ناجحة ويُطبع.
///
/// العامل يحتاج ورقةً تُثبت ما خُصم منه ومتى وكم بقي: الخصم من رصيدٍ بلا
/// إثبات هو أول ما يُتنازَع عليه آخر الشهر.
class _DeductionResultDialog extends ConsumerWidget {
  const _DeductionResultDialog({
    required this.amount,
    required this.method,
    required this.customerName,
    required this.remaining,
    this.invoice,
    this.offline = false,
  });

  final double amount;
  final String method;
  final String? customerName;
  final double? remaining;

  /// الفاتورة كما ردّها الخادم — فارغةٌ في العملية غير المتّصلة.
  ///
  /// <para>الرقم يولّده الخادم عند المزامنة لا الجهاز: توليدُه محلياً يعني
  /// تصادماً محتّماً بين جهازين يعملان بلا اتصال في المحلّ نفسه.</para>
  final Map<String, dynamic>? invoice;

  /// حُفظت في الطابور ولم تصل الخادم بعد.
  final bool offline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branding = ref.watch(brandingProvider).valueOrNull;
    final symbol = branding?.currencySymbol ?? 'د.ل';
    final isWallet = method == 'customer_wallet';

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.check_circle_outline, color: AppColors.success),
          const SizedBox(width: 8),
          Text(isWallet ? 'تمّ الخصم' : 'تمّ البيع'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (customerName != null) ...[
            Text(customerName!, style: AppTextStyles.headlineMd()),
            const SizedBox(height: 8),
          ],
          _row('المبلغ', amount, symbol),
          if (remaining != null) ...[
            const Divider(height: 20),
            _row('الرصيد المتبقي', remaining!, symbol),
          ],
          const SizedBox(height: 8),
          Text(
              offline
                  // لا رقم قبل المزامنة — وقولُه صراحةً أصدق من فراغٍ
                  // يظنّه الكاشير عطباً.
                  ? 'ستُرسَل عند عودة الشبكة — بلا رقم بعد'
                  : 'رقم العملية: ${invoice?['invoiceNumber'] ?? ''}',
              style: AppTextStyles.bodyMd(color: AppColors.textSecondary)),
        ],
      ),
      actions: [
        // لا طباعة قبل المزامنة: الإثبات يحمل رقم العملية، وطباعتُه بلا
        // رقم تُعطي المنتسب ورقةً لا تُراجَع بها.
        if (!offline && invoice != null)
        TextButton.icon(
          onPressed: () => printWalletDeduction(
            invoice: invoice!,
            orgName: branding?.displayName ?? '',
            currencySymbol: symbol,
            customerName: customerName,
            amount: amount,
            remaining: remaining,
            isWallet: isWallet,
          ),
          icon: const Icon(Icons.print_outlined, size: 18),
          label: const Text('طباعة الإثبات'),
        ),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('تمّ')),
      ],
    );
  }

  Widget _row(String label, double value, String symbol) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTextStyles.bodyMd()),
          CurrencyBadge(amount: value, currencySymbol: symbol),
        ],
      );
}

/// بحث عن صاحب رصيد بالاسم — بديل البطاقة المنسيّة.
class _WalletCustomerSearchDialog extends ConsumerStatefulWidget {
  const _WalletCustomerSearchDialog();

  @override
  ConsumerState<_WalletCustomerSearchDialog> createState() => _WalletCustomerSearchDialogState();
}

class _WalletCustomerSearchDialogState extends ConsumerState<_WalletCustomerSearchDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final symbol = ref.watch(brandingProvider).valueOrNull?.currencySymbol ?? 'د.ل';
    final resultsAsync = ref.watch(posCustomerResultsProvider);

    return AdaptiveFormDialog(
      title: 'بحث عن صاحب رصيد',
      maxWidth: 420,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
      ],
      body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              onChanged: (v) => ref.read(posCustomerSearchProvider.notifier).state = v,
              decoration: const InputDecoration(
                hintText: 'الاسم أو رقم الهاتف...',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 280,
              child: resultsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => const Center(child: Text('تعذّر البحث')),
                data: (customers) {
                  if (customers.isEmpty) {
                    return Center(
                      child: Text(
                        _controller.text.trim().isEmpty ? 'اكتب للبحث' : 'لا نتائج',
                        style: AppTextStyles.bodyMd(),
                      ),
                    );
                  }
                  return ListView.builder(
                    itemCount: customers.length,
                    itemBuilder: (_, i) {
                      final c = customers[i];
                      return ListTile(
                        title: Text(c['fullName'] as String? ?? ''),
                        subtitle: Text(c['phone'] as String? ?? ''),
                        trailing: CurrencyBadge(
                          amount: ((c['walletBalance'] as num?) ?? 0).toDouble(),
                          currencySymbol: symbol,
                        ),
                        onTap: () => Navigator.pop(context, Map<String, dynamic>.from(c)),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
    );
  }
}


/// الرقم السري إلزامي للخصم — بطاقة بلا رقم سري نقودٌ لحاملها.
class _WalletPinDialog extends StatefulWidget {
  const _WalletPinDialog({required this.customerName, required this.amountText});
  final String customerName;
  final String amountText;

  @override
  State<_WalletPinDialog> createState() => _WalletPinDialogState();
}

class _WalletPinDialogState extends State<_WalletPinDialog> {
  String _pin = '';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('الرقم السري'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.customerName, style: AppTextStyles.headlineMd()),
            const SizedBox(height: 4),
            Text(widget.amountText, style: AppTextStyles.bodyMd()),
            const SizedBox(height: 12),
            PinPad(value: _pin, onChanged: (v) => setState(() => _pin = v)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed: _pin.length >= 4 ? () => Navigator.pop(context, _pin) : null,
          child: const Text('تأكيد'),
        ),
      ],
    );
  }
}


/// يختار شاشة نقطة البيع بحسب إصدار المنظمة.
///
/// الاختيار في ودجت لا في buildScreenForRoute: الأخيرة دالة عادية بلا ref،
/// وقراءة الإصدار تحتاج مزوّد الهوية.
class PosScreenSwitcher extends ConsumerWidget {
  const PosScreenSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWallet = ref.watch(brandingProvider).valueOrNull?.isWallet ?? false;
    return isWallet ? const WalletPosScreen() : const PosScreen();
  }
}


/// كم استلم الكاشير بيده — وكم يُعيد.
///
/// <para>الباقي يُحسب وهو يكتب، فلا يحسبه في رأسه أمام زبونٍ ينتظر. وهو
/// أشيع مصدر لفروق الدرج في نهاية اليوم.</para>
class _CashTenderedDialog extends StatefulWidget {
  const _CashTenderedDialog({required this.due, required this.symbol});

  final double due;
  final String symbol;

  @override
  State<_CashTenderedDialog> createState() => _CashTenderedDialogState();
}

class _CashTenderedDialogState extends State<_CashTenderedDialog> {
  String _text = '';
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _tendered => double.tryParse(_text) ?? 0;
  double get _change => _tendered - widget.due;

  @override
  Widget build(BuildContext context) {
    final short = _text.isNotEmpty && _change < 0;

    return AdaptiveFormDialog(
      title: 'المستلَم من الزبون',
      maxWidth: 340,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('تراجع')),
        // «بالضبط» تمرّ بلا رقم: كاشيرٌ يستلم المبلغ تماماً لا يكتبه مرّتين.
        TextButton(
          onPressed: () => Navigator.pop(context, -1.0),
          child: const Text('بالضبط'),
        ),
        FilledButton(
          // الناقص يُمنع: بيعٌ نقدي بمالٍ لم يُستلَم كلّه ليس بيعاً نقدياً،
          // وتسجيلُه كذلك يُخفي عجزاً في الدرج.
          onPressed: (_text.isEmpty || short) ? null : () => Navigator.pop(context, _tendered),
          child: const Text('تأكيد'),
        ),
      ],
      body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('المطلوب', style: AppTextStyles.bodyMd()),
                CurrencyBadge(amount: widget.due, currencySymbol: widget.symbol),
              ],
            ),
            const SizedBox(height: 12),
            KeypadDisplay(value: _text, suffix: widget.symbol, label: 'المستلَم'),
            const SizedBox(height: 10),
            if (_text.isNotEmpty)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    // ناقصٌ لا «باقٍ سالب»: الكاشير يقرأ كلمةً تقول ما يفعل.
                    short ? 'ناقص' : 'الباقي للزبون',
                    style: AppTextStyles.bodyMd(
                        color: short ? AppColors.danger : AppColors.success),
                  ),
                  CurrencyBadge(
                    amount: _change.abs(),
                    currencySymbol: widget.symbol,
                  ),
                ],
              ),
            const SizedBox(height: 10),
            // على الهاتف: لوحة النظام. حوارٌ صغير تفتح فوقه لوحةُ الهاتف
            // فتزاحمه لوحةٌ مرسومة داخله — اثنتان على شاشةٍ واحدة.
            if (Breakpoints.isMobile(context))
              TextField(
                controller: _controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done,
                textAlign: TextAlign.center,
                style: AppTextStyles.displayLg(),
                decoration: InputDecoration(
                  labelText: 'المبلغ المستلَم',
                  suffixText: widget.symbol,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _text = v),
                onSubmitted: (_) => Navigator.pop(context, _tendered),
              )
            else
              NumericKeypad(
                value: _text,
                onChanged: (v) => setState(() => _text = v),
                size: KeypadSize.compact,
                onSubmit: () {},
              ),
          ],
        ),
    );
  }
}
