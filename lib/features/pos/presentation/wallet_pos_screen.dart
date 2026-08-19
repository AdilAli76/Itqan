import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/feedback/pos_sounds.dart';
import '../../../core/network/api_client.dart';
import '../../../core/printing/wallet_receipt_printer.dart';
import '../../../core/responsive/adaptive_scaffold.dart';
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

  Future<void> _chargeCash() => _submit('cash');

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

  Future<void> _submit(String method, {String? pin}) async {
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
      setState(() => _busy = false);
      final message = e.response?.data is Map
          ? (e.response!.data['message'] as String? ?? 'تعذّر إتمام العملية')
          : 'تعذّر إتمام العملية';
      _fail(message);
    }
  }

  // ── العرض ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final symbol = ref.watch(brandingProvider).valueOrNull?.currencySymbol ?? 'د.ل';

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
                        onChanged: (v) => setState(() => _branchId = v),
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
                    KeypadDisplay(value: _amountText, suffix: symbol, label: 'المبلغ المطلوب'),
                    const SizedBox(height: 12),
                    NumericKeypad(
                      value: _amountText,
                      onChanged: (v) => setState(() => _amountText = v),
                      size: KeypadSize.large,
                      onSubmit: _busy ? () {} : _chargeWallet,
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  height: 62,
                  child: ElevatedButton.icon(
                    onPressed: (_busy || _loadingBranch) ? null : _chargeWallet,
                    icon: const Icon(Icons.credit_card_outlined),
                    label: Text('خصم من الرصيد', style: AppTextStyles.headlineMd(color: Colors.white)),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 54,
                  child: OutlinedButton.icon(
                    onPressed: (_busy || _loadingBranch) ? null : _chargeCash,
                    icon: const Icon(Icons.payments_outlined),
                    label: Text('بيع نقدي', style: AppTextStyles.headlineMd()),
                  ),
                ),
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
    required this.invoice,
  });

  final double amount;
  final String method;
  final String? customerName;
  final double? remaining;
  final Map<String, dynamic> invoice;

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
          Text('رقم العملية: ${invoice['invoiceNumber'] ?? ''}',
              style: AppTextStyles.bodyMd(color: AppColors.textSecondary)),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: () => printWalletDeduction(
            invoice: invoice,
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

    return AlertDialog(
      title: const Text('بحث عن صاحب رصيد'),
      content: SizedBox(
        width: 420,
        child: Column(
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
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
      ],
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
