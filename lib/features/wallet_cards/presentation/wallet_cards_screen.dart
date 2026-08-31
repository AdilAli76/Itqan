import 'dart:typed_data';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../shared/widgets/adaptive_form_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/network/api_client.dart';
import '../../../core/printing/card_printer.dart';
import '../../../core/responsive/adaptive_scaffold.dart';
import '../../../core/theme/branding_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/barcode_view.dart';
import '../../../shared/widgets/currency_badge.dart';
import '../../../shared/widgets/data_table_widget.dart';
import '../../../shared/widgets/pin_pad.dart';
import '../data/wallet_cards_providers.dart';
import '../../settings/data/settings_providers.dart';
import '../../../shared/widgets/filter_chip_button.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/pagination_bar.dart';

const _stateLabels = {
  'active': 'فعّالة',
  'blocked': 'محظورة',
  'expired': 'منتهية',
};

String _dioErrorMessage(Object error, String fallback) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] is String) return data['message'] as String;
  }
  return fallback;
}

/// شاشة إدارة بطاقات المحفظة — مركز عمل المدير: كل البطاقات المُصدَرة
/// وحالاتها وإجراءاتها في مكان واحد، بدل زر مدفون في صف عميل.
class WalletCardsScreen extends ConsumerStatefulWidget {
  const WalletCardsScreen({super.key});

  @override
  ConsumerState<WalletCardsScreen> createState() => _WalletCardsScreenState();
}

class _WalletCardsScreenState extends ConsumerState<WalletCardsScreen> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(cardSearchProvider.notifier).state = value;
      ref.read(walletCardsPageProvider.notifier).state = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cardsAsync = ref.watch(walletCardsProvider);
    final stateFilter = ref.watch(cardStateFilterProvider);

    return AdaptiveScaffold(
      title: 'بطاقات المحفظة',
      activeRoute: '/wallet-cards',
      actions: [
        ElevatedButton.icon(
          onPressed: () async {
            final issued = await showDialog<bool>(
              context: context,
              builder: (_) => const _IssueCardDialog(),
            );
            if (issued == true) {
              ref.invalidate(walletCardsProvider);
              ref.invalidate(customersWithoutCardProvider);
            }
          },
          icon: const Icon(Icons.add_card_outlined, size: 18),
          label: const Text('إصدار بطاقة'),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Wrap لا Row: شريط الفلاتر يفيض على عرض الهاتف. الالتفاف يبقي
          // كل فلتر ظاهراً وقابلاً للنقر بدل قصّ آخره بصمت.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterChipButton(
                label: 'الكل',
                selected: stateFilter == null,
                onTap: () {
                  ref.read(cardStateFilterProvider.notifier).state = null;
                  ref.read(walletCardsPageProvider.notifier).state = 1;
                },
              ),
              const SizedBox(width: 8),
              ..._stateLabels.entries.map((e) => Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: FilterChipButton(
                      label: e.value,
                      selected: stateFilter == e.key,
                      onTap: () {
                        ref.read(cardStateFilterProvider.notifier).state = e.key;
                        ref.read(walletCardsPageProvider.notifier).state = 1;
                      },
                    ),
                  )),
            ],
          ),
          const SizedBox(height: 16),
          cardsAsync.when(
            loading: () => const TableSkeleton(),
            error: (err, _) => Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  Text('تعذّر تحميل البطاقات', style: AppTextStyles.bodyMd(color: AppColors.danger)),
                  const SizedBox(height: 12),
                  OutlinedButton(
                      onPressed: () => ref.invalidate(walletCardsProvider),
                      child: const Text('إعادة المحاولة')),
                ],
              ),
            ),
            data: (cards) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppDataTable(
                  title: 'البطاقات (${cards.totalCount})',
                  icon: Icons.credit_card_outlined,
                  onSearch: _onSearch,
                  emptyMessage: 'لا توجد بطاقات مُصدَرة بعد — ابدأ بـ«إصدار بطاقة»',
                  emptyIcon: Icons.credit_card_off_outlined,
                  columns: const [
                    AppColumn('العميل'),
                    AppColumn('رمز البطاقة'),
                    AppColumn('الحالة'),
                    AppColumn('الرصيد'),
                    AppColumn('تاريخ الإصدار'),
                    AppColumn('الصلاحية'),
                    AppColumn(''),
                  ],
                  rows: cards.items.map((card) => _cardRow(context, card)).toList(),
                ),
                PaginationBar(
                  page: cards.page,
                  pageSize: cards.pageSize,
                  totalCount: cards.totalCount,
                  onPageChanged: (p) => ref.read(walletCardsPageProvider.notifier).state = p,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _cardRow(BuildContext context, Map<String, dynamic> card) {
    final issuedAt = DateTime.tryParse(card['issuedAt'] as String? ?? '');
    final expiry = card['expiryDate'] as String?;
    final usable = card['isUsable'] as bool? ?? false;

    return [
      Text(card['customerName'] as String? ?? ''),
      Text(card['cardCode'] as String? ?? '', style: AppTextStyles.currency(color: AppColors.textPrimary)),
      _StateTag(state: card['state'] as String? ?? '', usable: usable),
      CurrencyBadge(amount: (card['balance'] as num?)?.toDouble() ?? 0),
      Text(issuedAt != null ? DateFormat('yyyy-MM-dd').format(issuedAt) : '-'),
      Text(expiry != null ? expiry.split('T').first : 'بلا انتهاء'),
      IconButton(
        tooltip: 'إدارة البطاقة',
        icon: const Icon(Icons.tune, size: 18),
        onPressed: () async {
          final changed = await showDialog<bool>(
            context: context,
            builder: (_) => _CardDetailDialog(card: card),
          );
          if (changed == true) ref.invalidate(walletCardsProvider);
        },
      ),
    ];
  }
}

class _StateTag extends StatelessWidget {
  const _StateTag({required this.state, required this.usable});
  final String state;
  final bool usable;

  @override
  Widget build(BuildContext context) {
    // بطاقة حالتها 'active' لكنها منتهية الصلاحية تُعرَض كمنتهية فعلاً —
    // عرضها "فعّالة" بينما البوابة ترفضها كان سيربك المدير.
    final effective = !usable && state == 'active' ? 'expired' : state;
    final (fg, bg) = switch (effective) {
      'active' => (AppColors.success, AppColors.successBg),
      'blocked' => (AppColors.danger, AppColors.dangerBg),
      _ => (AppColors.warning, AppColors.warningBg),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(_stateLabels[effective] ?? effective, style: AppTextStyles.labelMd(color: fg)),
    );
  }
}

// ---------------------------------------------------------------------------
// تفاصيل البطاقة وإجراءاتها
// ---------------------------------------------------------------------------

class _CardDetailDialog extends ConsumerStatefulWidget {
  const _CardDetailDialog({required this.card});
  final Map<String, dynamic> card;

  @override
  ConsumerState<_CardDetailDialog> createState() => _CardDetailDialogState();
}

class _CardDetailDialogState extends ConsumerState<_CardDetailDialog> {
  bool _working = false;
  String? _error;
  bool _changed = false;

  String get _code => widget.card['cardCode'] as String? ?? '';
  String get _state => widget.card['state'] as String? ?? '';
  String get _mode => widget.card['cardMode'] as String? ?? 'pin';

  @override
  Widget build(BuildContext context) {
    final usable = widget.card['isUsable'] as bool? ?? false;
    final blockedReason = widget.card['blockedReason'] as String?;
    final issuedBy = widget.card['issuedByName'] as String?;

    return AlertDialog(
      title: Text('بطاقة: ${widget.card['customerName']}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // شريط الحالة — نمط أودو: المراحل ظاهرة والمرحلة الحالية مميّزة.
              _StatusBar(current: usable ? 'active' : (_state == 'blocked' ? 'blocked' : 'expired')),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    BarcodeView(data: _code, height: 56),
                    const SizedBox(height: 6),
                    SelectableText(_code, style: AppTextStyles.currency(color: AppColors.textPrimary)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _DetailRow(
                  label: 'الرصيد الحالي',
                  value: NumberFormat('#,##0.000', 'en').format((widget.card['balance'] as num?) ?? 0)),
              _DetailRow(
                label: 'نمط التحقّق',
                value: _mode == 'card'
                    ? 'البطاقة وحدها — سقف يومي ${(( widget.card['dailyCap'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}'
                    : 'بطاقة + رقم سرّي',
              ),
              if (issuedBy != null) _DetailRow(label: 'أصدرها', value: issuedBy),
              if (blockedReason != null) _DetailRow(label: 'سبب الحظر', value: blockedReason),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
              ],
              const Divider(height: 28),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (_state == 'blocked')
                    FilledButton.icon(
                      onPressed: _working ? null : _unblock,
                      icon: const Icon(Icons.lock_open_outlined, size: 18),
                      label: const Text('رفع الحظر'),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: _working ? null : _block,
                      icon: const Icon(Icons.block_outlined, size: 18),
                      label: const Text('حظر البطاقة'),
                    ),
                  OutlinedButton.icon(
                    onPressed: _working ? null : _resetPin,
                    icon: const Icon(Icons.password_outlined, size: 18),
                    // في نمط «بطاقة فقط» ضبطُ رقم يعني تحويل الحساب إلى النمط
                    // الأشدّ — وهذا ما يفعله الخادم فعلاً، فالنصّ يقوله صراحةً
                    // بدل أن يُفاجَأ المدير بتغيّر النمط.
                    label: Text(_mode == 'card' ? 'تفعيل رقم سرّي' : 'رقم سري جديد'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _working ? null : _changeMode,
                    icon: const Icon(Icons.tune_outlined, size: 18),
                    label: const Text('نمط التحقّق'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _working ? null : _reissue,
                    icon: const Icon(Icons.autorenew, size: 18),
                    label: const Text('إعادة إصدار'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _printCard,
                    icon: const Icon(Icons.print_outlined, size: 18),
                    label: const Text('طباعة البطاقة (وجهان)'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, _changed), child: const Text('إغلاق')),
      ],
    );
  }

  Future<void> _run(Future<void> Function() action, String successMessage) async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await action();
      _changed = true;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successMessage)));
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() => _error = _dioErrorMessage(e, 'تعذّر تنفيذ العملية'));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _block() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _ReasonDialog(),
    );
    if (reason == null) return;
    await _run(
      () => ApiClient.instance.dio.post('/wallet-cards/$_code/block', data: {'reason': reason}),
      'تم حظر البطاقة',
    );
  }

  Future<void> _unblock() => _run(
        () => ApiClient.instance.dio.post('/wallet-cards/$_code/unblock'),
        'تم رفع الحظر',
      );

  Future<void> _printCard() async {
    final expiryRaw = widget.card['expiryDate'] as String?;
    final branding = ref.read(brandingProvider).valueOrNull ?? OrganizationBranding.fallback;
    await printWalletCard(
      cardCode: _code,
      // الاسم المطبوع يغلب اسم العميل إن حُدِّد وقت الإصدار.
      holderName: (widget.card['holderName'] as String?)?.trim().isNotEmpty == true
          ? widget.card['holderName'] as String
          : widget.card['customerName'] as String? ?? '',
      orgName: branding.displayName,
      // البطاقة تحمل هوية المنظمة المُصدِرة لا هوية النظام — نفس اللون الذي
      // اختاره الزبون في «الفروع والهوية» يُطبَع على بطاقات عملائه.
      brandColor: branding.colors.primary,
      expiryDate: expiryRaw == null ? null : DateTime.tryParse(expiryRaw),
      logoBytes: await _fetchLogo(branding.logoUrl),
      // هاتف الجهة المُصدِرة: هاتف الفرع. بطاقة ضائعة بلا رقم يُتّصل به
      // تُرمى — ومن يجدها لا يعرف إلى من يعيدها.
      supportPhone: await _issuerPhone(),
      holderPhone: widget.card['customerPhone'] as String?,
    );
  }

  /// الشعار بايتاتٍ لا برابط: نقطة الملفات محمية بتوكن ومحرّك PDF لا يحمل
  /// ترويسة مصادقة، فرابط مباشر كان يُنتج بطاقة بلا شعار بلا رسالة خطأ.
  Future<Uint8List?> _fetchLogo(String? logoUrl) async {
    if (logoUrl == null || logoUrl.isEmpty) return null;
    try {
      final relative = logoUrl.startsWith('/api') ? logoUrl.substring(4) : logoUrl;
      final res = await ApiClient.instance.dio.get<List<int>>(
        relative,
        options: Options(responseType: ResponseType.bytes),
      );
      return Uint8List.fromList(res.data ?? const []);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _issuerPhone() async {
    try {
      final res = await ApiClient.instance.dio.get('/branches');
      final list = (res.data as List).map((e) => Map<String, dynamic>.from(e as Map));
      for (final b in list) {
        final phone = (b['phone'] as String?)?.trim();
        if (phone != null && phone.isNotEmpty) return phone;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _resetPin() async {
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => const _PinDialog(title: 'رقم سري جديد'),
    );
    if (pin == null) return;
    await _run(
      () => ApiClient.instance.dio.post('/wallet-cards/$_code/reset-pin', data: {'pin': pin}),
      'تم تغيير الرقم السري',
    );
  }

  /// تغيير نمط التحقّق لهذا الحساب.
  ///
  /// يمرّ بنقطة نهاية تشترط صلاحية `cards.issue` — **وهي ليست صلاحية
  /// كاشير**: من يستطيع خفض الحماية على محفظة يستطيع إنفاقها.
  ///
  /// والتحوّل إلى «بطاقة فقط» يمحو الرقم السرّي: النمط قائم على أن لا سرّ
  /// يُحفَظ أصلاً، وإبقاؤه يترك ما يُسرَّب بلا أن يستعمله أحد.
  Future<void> _changeMode() async {
    final settings = ref.read(settingsProvider).valueOrNull ?? const <String, dynamic>{};
    final allowed = ((settings['cardModesAllowed'] as String?) ?? 'pin')
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final orgCap = (settings['cardOpenModeDailyCap'] as num?)?.toDouble() ?? 0;

    if (allowed.length < 2) {
      setState(() => _error = 'إعدادات المنظمة تسمح بنمط واحد فقط — غيّرها من شاشة الإعدادات أولاً.');
      return;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _CardModeDialog(
        current: _mode,
        allowed: allowed,
        orgCap: orgCap,
        currentCap: (widget.card['dailyCap'] as num?)?.toDouble() ?? 0,
        hasPin: _mode == 'pin',
      ),
    );
    if (result == null) return;

    final customerId = widget.card['customerId'] as String?;
    if (customerId == null) return;

    await _run(
      () => ApiClient.instance.dio.put('/customers/$customerId/card-mode', data: result),
      'تم تغيير نمط التحقّق',
    );
  }

  Future<void> _reissue() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إعادة إصدار البطاقة'),
        content: const Text('سيُلغى الرمز الحالي فوراً ويُصدر رمز جديد. هل تريد المتابعة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('متابعة')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final issued = await showDialog<bool>(
      context: context,
      builder: (_) => _IssueCardDialog(fixedCustomerId: widget.card['customerId'] as String?),
    );
    if (issued == true && mounted) Navigator.pop(context, true);
  }
}

/// شريط مراحل البطاقة — المرحلة الحالية مميّزة والباقي باهت، نفس فكرة
/// statusbar في أودو.
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.current});
  final String current;

  @override
  Widget build(BuildContext context) {
    const stages = ['active', 'blocked', 'expired'];
    return Row(
      children: stages.map((stage) {
        final isCurrent = stage == current;
        final (fg, bg) = switch (stage) {
          'active' => (AppColors.success, AppColors.successBg),
          'blocked' => (AppColors.danger, AppColors.dangerBg),
          _ => (AppColors.warning, AppColors.warningBg),
        };
        return Expanded(
          child: Container(
            margin: const EdgeInsetsDirectional.only(end: 6),
            padding: const EdgeInsets.symmetric(vertical: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isCurrent ? bg : AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: isCurrent ? fg : AppColors.border),
            ),
            child: Text(
              _stateLabels[stage] ?? stage,
              style: AppTextStyles.labelMd(color: isCurrent ? fg : AppColors.textMuted),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
              width: 120, child: Text(label, style: AppTextStyles.labelMd(color: AppColors.textSecondary))),
          Expanded(child: Text(value, style: AppTextStyles.bodyMd(color: AppColors.textPrimary))),
        ],
      ),
    );
  }
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog();

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveFormDialog(
      title: 'سبب الحظر',
      maxWidth: 320,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
            onPressed: () => Navigator.pop(context, _controller.text.trim()), child: const Text('حظر')),
      ],
      body: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'السبب (اختياري)', hintText: 'مثال: بلاغ فقدان'),
        ),
    );
  }
}

class _PinDialog extends StatefulWidget {
  const _PinDialog({required this.title});
  final String title;

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  String _pin = '';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'من 4 إلى 6 أرقام — لا يُقبَل مكرَّر (1111) ولا متسلسل (1234)',
              style: AppTextStyles.caption(),
            ),
            const SizedBox(height: 10),
            PinPad(value: _pin, onChanged: (v) => setState(() => _pin = v)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed: _pin.length >= 4 ? () => Navigator.pop(context, _pin) : null,
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// إصدار بطاقة جديدة
// ---------------------------------------------------------------------------

class _IssueCardDialog extends ConsumerStatefulWidget {
  const _IssueCardDialog({this.fixedCustomerId});

  /// عند إعادة الإصدار يكون العميل محدَّداً سلفاً فلا تُعرض قائمة الاختيار.
  final String? fixedCustomerId;

  @override
  ConsumerState<_IssueCardDialog> createState() => _IssueCardDialogState();
}

class _IssueCardDialogState extends ConsumerState<_IssueCardDialog> {
  late String? _customerId = widget.fixedCustomerId;
  final _holderNameController = TextEditingController();
  final _capController = TextEditingController();
  String _pin = '';
  /// النمط المختار — null حتى تصل إعدادات المنظمة، فيصير افتراضها.
  String? _mode;
  DateTime? _expiryDate;
  bool _saving = false;
  String? _error;
  String? _issuedCode;

  @override
  void dispose() {
    _holderNameController.dispose();
    _capController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveFormDialog(
      title: _issuedCode == null ? 'إصدار بطاقة محفظة' : 'تم إصدار البطاقة',
      maxWidth: 400,
      body: _issuedCode == null ? _buildForm() : _buildResult(),
      actions: _issuedCode == null
          ? [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
              FilledButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('إصدار'),
              ),
            ]
          : [FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('تم'))],
    );
  }

  Widget _buildForm() {
    final customersAsync = ref.watch(customersWithoutCardProvider);
    final settingsAsync = ref.watch(settingsProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.fixedCustomerId == null)
          customersAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, __) =>
                Text('تعذّر تحميل العملاء', style: AppTextStyles.bodyMd(color: AppColors.danger)),
            data: (customers) => customers.isEmpty
                ? Container(
                    padding: const EdgeInsets.all(12),
                    decoration:
                        BoxDecoration(color: AppColors.infoBg, borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      'كل العملاء لديهم بطاقات. أضف عميلاً جديداً من شاشة العملاء أولاً، أو أعد إصدار بطاقة قائمة.',
                      style: AppTextStyles.bodyMd(color: AppColors.info),
                    ),
                  )
                : DropdownButtonFormField<String>(
                    initialValue: _customerId,
                    decoration: const InputDecoration(labelText: 'العميل'),
                    items: customers
                        .map((c) => DropdownMenuItem(
                              value: c['id'] as String,
                              child: Text('${c['fullName']}${c['phone'] != null ? ' — ${c['phone']}' : ''}'),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _customerId = v),
                  ),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _holderNameController,
          decoration: const InputDecoration(
            labelText: 'الاسم المطبوع على البطاقة (اختياري)',
            helperText: 'اتركه فارغاً ليُطبع اسم العميل',
          ),
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: _pickExpiry,
          borderRadius: BorderRadius.circular(8),
          child: InputDecorator(
            decoration: const InputDecoration(labelText: 'تاريخ انتهاء الصلاحية'),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _expiryDate == null ? 'بلا تاريخ انتهاء' : DateFormat('yyyy-MM-dd').format(_expiryDate!),
                    style: AppTextStyles.bodyMd(
                      color: _expiryDate == null ? AppColors.textMuted : AppColors.textPrimary,
                    ),
                  ),
                ),
                if (_expiryDate != null)
                  InkWell(
                    onTap: () => setState(() => _expiryDate = null),
                    child: const Icon(Icons.close, size: 16),
                  )
                else
                  const Icon(Icons.calendar_today_outlined, size: 16),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // نمط التحقّق — من مظروف المنظمة وحده. نمطٌ لم يسمح به المدير لا
        // يُعرَض أصلاً: عرضه معطّلاً يدفع الكاشير لسؤال الدعم عن سببه.
        settingsAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => Text('تعذّر تحميل إعدادات البطاقة',
              style: AppTextStyles.bodyMd(color: AppColors.danger)),
          data: (settings) {
            final allowed = ((settings['cardModesAllowed'] as String?) ?? 'pin')
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();
            final mode = _mode ?? (settings['cardModeDefault'] as String? ?? 'pin');
            final orgCap = (settings['cardOpenModeDailyCap'] as num?)?.toDouble() ?? 0;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('نمط التحقّق عند الصرف', style: AppTextStyles.labelMd()),
                const SizedBox(height: 8),
                if (allowed.length == 1)
                  Text(
                    allowed.first == 'card'
                        ? 'البطاقة وحدها بسقف يومي — النمط الوحيد المسموح في إعدادات المنظمة.'
                        : 'بطاقة + رقم سرّي — النمط الوحيد المسموح في إعدادات المنظمة.',
                    style: AppTextStyles.caption(),
                  )
                else
                  SegmentedButton<String>(
                    segments: [
                      if (allowed.contains('pin'))
                        const ButtonSegment(value: 'pin', label: Text('رقم سرّي')),
                      if (allowed.contains('card'))
                        const ButtonSegment(value: 'card', label: Text('بطاقة فقط')),
                    ],
                    selected: {allowed.contains(mode) ? mode : allowed.first},
                    onSelectionChanged: (v) => setState(() => _mode = v.first),
                  ),
                const SizedBox(height: 12),
                if ((allowed.contains(mode) ? mode : allowed.first) == 'card') ...[
                  Text(
                    'لا رقم سرّي لهذه البطاقة — لا شيء يُحفَظ فلا شيء يُسرَّب، '
                    'والحدّ سقفٌ يوميّ. سقف المنظمة ${orgCap.toStringAsFixed(2)}.',
                    style: AppTextStyles.caption(),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _capController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'سقف يومي أقلّ لهذا الزبون (اختياري)',
                      helperText: 'اتركه فارغاً لاتّباع سقف المنظمة. '
                          'ولا يُقبَل أعلى من ${orgCap.toStringAsFixed(2)}.',
                    ),
                  ),
                ] else ...[
                  Text('الرقم السري', style: AppTextStyles.labelMd()),
                  const SizedBox(height: 2),
                  Text(
                    'من 4 إلى 6 أرقام — لا يُقبَل مكرَّر (1111) ولا متسلسل (1234)',
                    style: AppTextStyles.caption(),
                  ),
                  const SizedBox(height: 8),
                  PinPad(value: _pin, onChanged: (v) => setState(() => _pin = v)),
                ],
              ],
            );
          },
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
        ],
      ],
    );
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? DateTime(now.year + 1, now.month, now.day),
      firstDate: now.add(const Duration(days: 1)),
      lastDate: DateTime(now.year + 20),
    );
    if (picked != null) setState(() => _expiryDate = picked);
  }

  Widget _buildResult() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.warningBg, borderRadius: BorderRadius.circular(8)),
          child: Text(
            'سلّم هذا الرمز للعميل الآن — لن يُعرض مرة أخرى.',
            style: AppTextStyles.bodyMd(color: AppColors.warning),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              BarcodeView(data: _issuedCode!, height: 64),
              const SizedBox(height: 8),
              SelectableText(_issuedCode!, style: AppTextStyles.displayLg()),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'نفس الرمز هو باركود البطاقة ورمز الدخول للبوابة معاً.',
          style: AppTextStyles.bodyMd(color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (_customerId == null) {
      setState(() => _error = 'اختر العميل');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final settings = ref.read(settingsProvider).valueOrNull ?? const <String, dynamic>{};
      final mode = _mode ?? (settings['cardModeDefault'] as String? ?? 'pin');
      final cap = double.tryParse(_capController.text.trim());

      final response = await ApiClient.instance.dio.post('/wallet-cards/issue', data: {
        'customerId': _customerId,
        // الرقم في نمطه وحده: إرساله في «بطاقة فقط» يرفضه الخادم صراحةً،
        // لأن سرّاً لا يستعمله أحد يبقى قابلاً للتسريب بلا فائدة.
        'pin': mode == 'pin' ? _pin : null,
        'cardMode': mode,
        'dailyCap': mode == 'card' ? cap : null,
        'expiryDate': _expiryDate == null ? null : DateFormat('yyyy-MM-dd').format(_expiryDate!),
        'holderName': _holderNameController.text.trim(),
      });
      setState(() => _issuedCode = (response.data as Map<String, dynamic>)['cardCode'] as String?);
    } catch (e) {
      setState(() => _error = _dioErrorMessage(e, 'تعذّر إصدار البطاقة'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

/// اختيار نمط التحقّق لحساب قائم.
///
/// **التحويل إلى «رقم سرّي» لا يتمّ من هنا**: النمط يحتاج رقماً مضبوطاً،
/// وضبطه له حواره الخاص («تفعيل رقم سرّي»). خيارٌ يقود إلى حسابٍ لا يُصرَف
/// منه أبداً أسوأ من غيابه.
class _CardModeDialog extends StatefulWidget {
  const _CardModeDialog({
    required this.current,
    required this.allowed,
    required this.orgCap,
    required this.currentCap,
    required this.hasPin,
  });

  final String current;
  final List<String> allowed;
  final double orgCap;
  final double currentCap;
  final bool hasPin;

  @override
  State<_CardModeDialog> createState() => _CardModeDialogState();
}

class _CardModeDialogState extends State<_CardModeDialog> {
  late String _mode = widget.current;
  late final _capController = TextEditingController(
      text: widget.currentCap > 0 ? widget.currentCap.toStringAsFixed(2) : '');
  String? _error;

  @override
  void dispose() {
    _capController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveFormDialog(
      title: 'نمط التحقّق',
      maxWidth: 380,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(onPressed: _submit, child: const Text('حفظ')),
      ],
      body: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<String>(
                segments: [
                  if (widget.allowed.contains('pin'))
                    ButtonSegment(
                      value: 'pin',
                      label: const Text('رقم سرّي'),
                      enabled: widget.hasPin,
                    ),
                  if (widget.allowed.contains('card'))
                    const ButtonSegment(value: 'card', label: Text('بطاقة فقط')),
                ],
                selected: {_mode},
                onSelectionChanged: (v) => setState(() => _mode = v.first),
              ),
              if (!widget.hasPin) ...[
                const SizedBox(height: 8),
                Text(
                  'لا رقم سرّي لهذا الحساب. لتحويله إلى نمط الرقم السرّي '
                  'استعمل «تفعيل رقم سرّي».',
                  style: AppTextStyles.caption(),
                ),
              ],
              if (_mode == 'card') ...[
                const SizedBox(height: 16),
                Text(
                  'البطاقة وحدها: لا رقم يُدخَل ولا رقم يُحفَظ، والحدّ سقفٌ '
                  'يوميّ. سقف المنظمة ${widget.orgCap.toStringAsFixed(2)}.',
                  style: AppTextStyles.caption(),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _capController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'سقف يومي أقلّ لهذا الزبون (اختياري)',
                    helperText: 'اتركه فارغاً لاتّباع سقف المنظمة. الأعلى منه لا يُقبَل.',
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
              ],
            ],
          ),
    );
  }

  void _submit() {
    double? cap;
    if (_mode == 'card') {
      final raw = _capController.text.trim();
      if (raw.isNotEmpty) {
        cap = double.tryParse(raw);
        if (cap == null || cap < 0) {
          setState(() => _error = 'سقف غير صالح');
          return;
        }
        // يُرفض هنا لا صامتاً في الخادم: مسؤولٌ ظنّ أنه رفع سقفاً وهو لم
        // يرتفع سيكتشف ذلك يوم يُرفَض بيع.
        if (cap > widget.orgCap) {
          setState(() => _error = 'لا يتجاوز سقف المنظمة (${widget.orgCap.toStringAsFixed(2)})');
          return;
        }
      }
    }
    Navigator.pop(context, {'cardMode': _mode, 'dailyCap': cap ?? 0});
  }
}
