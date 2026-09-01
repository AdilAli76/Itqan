import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../shared/widgets/adaptive_form_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/permissions.dart';
import '../../../core/network/api_client.dart';
import '../../../core/responsive/adaptive_scaffold.dart';
import '../../../core/shortcuts/keyboard_shortcuts_manager.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/time/app_clock.dart';
import '../../../shared/widgets/app_surface.dart';
import '../../customers/data/customers_providers.dart';
import '../data/payroll_providers.dart';

final _money = NumberFormat('#,##0.00', 'en');
final _date = DateFormat('yyyy-MM-dd');

/// المرتَّبات والسلف.
///
/// <para><b>الفجوة التي تسدّها:</b> جهةٌ تصرف على ألف منتسب كانت تشحن ألف
/// بطاقة يدوياً كل شهر — عملُ يومٍ كامل يُخطئ فيه إدخالٌ أو اثنان، ولا
/// يُعرف أيّهما إلا حين يشتكي صاحبه. وتُسلّف منتسبها فيخرج المال بلا أثر،
/// أو يُشحن رصيده كأنه مرتَّب فيختلط ما وُهب بما يُسترجَع.</para>
class PayrollScreen extends ConsumerWidget {
  const PayrollScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage =
        ref.watch(myPermissionsProvider).valueOrNull?.can('customers.manage') ?? false;

    return DefaultTabController(
      length: 2,
      child: AdaptiveScaffold(
        title: 'المرتَّبات والسلف',
        activeRoute: '/payroll',
        // TabBarView يطلب ارتفاعاً محدوداً — راجع AdaptiveScaffold.scrollable.
        scrollable: false,
        body: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: 'الفئات والصرف'),
                Tab(text: 'السلف'),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TabBarView(
                children: [
                  _CategoriesTab(canManage: canManage),
                  _AdvancesTab(canManage: canManage),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── الفئات والصرف ───────────────────────────────────────────────────────

class _CategoriesTab extends ConsumerWidget {
  const _CategoriesTab({required this.canManage});
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(customerCategoriesProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => _ErrorBox(
        message: _errorText(err, 'تعذّر تحميل الفئات'),
        onRetry: () => ref.invalidate(customerCategoriesProvider),
      ),
      data: (categories) => ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (canManage) _DisburseCard(categories: categories),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: Text('الفئات', style: AppTextStyles.bodyLg())),
              if (canManage)
                TextButton.icon(
                  onPressed: () => _edit(context, ref, null),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('فئة جديدة'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (categories.isEmpty)
            const _EmptyBox(
              icon: Icons.groups_outlined,
              title: 'لا فئات بعد',
              hint: 'الفئة اسمٌ ومرتَّب — ورفعُ مرتَّبها يرفع كل من فيها بصفٍّ واحد',
            )
          else
            ...categories.map((c) => _CategoryCard(
                  category: c,
                  canManage: canManage,
                  onEdit: () => _edit(context, ref, c),
                )),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Map<String, dynamic>? category) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _CategoryDialog(category: category),
    );
    if (saved == true) {
      ref.invalidate(customerCategoriesProvider);
      ref.invalidate(disbursePreviewProvider);
    }
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.canManage,
    required this.onEdit,
  });

  final Map<String, dynamic> category;
  final bool canManage;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final isActive = category['isActive'] as bool? ?? true;
    final expires = category['unspentExpires'] as bool? ?? true;
    final count = (category['customerCount'] as num?)?.toInt() ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppSurface(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('${category['name']}', style: AppTextStyles.bodyLg()),
                        if (!isActive) ...[
                          const SizedBox(width: 8),
                          Text('موقوفة',
                              style: AppTextStyles.caption(color: AppColors.danger)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$count منتسباً · '
                      // قولُ مصير الرصيد صراحةً: الفرق بين «استعمله أو
                      // تفقده» و«يتراكم» قرارُ إدارةٍ يُنسى إن لم يُكتب.
                      '${expires ? 'يسقط ما لم يُصرَف' : 'الرصيد يتراكم'}',
                      style: AppTextStyles.caption(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${_money.format(_num(category['periodAmount']))} / الدورة',
                      style: AppTextStyles.bodyMd()),
                  const SizedBox(height: 2),
                  Text('الإجمالي ${_money.format(_num(category['periodTotal']))}',
                      style: AppTextStyles.caption(color: AppColors.textSecondary)),
                ],
              ),
              if (canManage) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  tooltip: 'تعديل الفئة',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// بطاقة الصرف — المعاينة والزرّ معاً.
class _DisburseCard extends ConsumerWidget {
  const _DisburseCard({required this.categories});
  final List<Map<String, dynamic>> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(disburseCategoryFilterProvider);
    final preview = ref.watch(disbursePreviewProvider);

    return AppSurface(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('صرف مرتَّب الدورة', style: AppTextStyles.bodyLg()),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              initialValue: selected,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'الفئة'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('كل الفئات')),
                for (final c in categories.where((c) => c['isActive'] as bool? ?? true))
                  DropdownMenuItem<String?>(value: '${c['id']}', child: Text('${c['name']}')),
              ],
              onChanged: (v) =>
                  ref.read(disburseCategoryFilterProvider.notifier).state = v,
            ),
            const SizedBox(height: 12),
            preview.when(
              loading: () => const LinearProgressIndicator(),
              error: (err, _) => Text(
                _errorText(err, 'تعذّرت المعاينة'),
                style: AppTextStyles.bodyMd(color: AppColors.danger),
              ),
              data: (data) => _PreviewBody(data: data),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewBody extends ConsumerWidget {
  const _PreviewBody({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toPay = (data['toPay'] as num?)?.toInt() ?? 0;
    final alreadyPaid = (data['alreadyPaid'] as num?)?.toInt() ?? 0;
    final suspended = (data['suspended'] as num?)?.toInt() ?? 0;
    final total = _num(data['totalAmount']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 20,
          runSpacing: 8,
          children: [
            _fact('الدورة', '${data['period']}'),
            _fact('سيُصرف لهم', '$toPay'),
            _fact('الإجمالي', _money.format(total)),
            // المدفوع والموقوف رقمان يُسأل عنهما — وخلطُهما بالمتبقّي
            // يُخفي أن أحداً لم يقبض عمداً.
            if (alreadyPaid > 0) _fact('قُبض لهم سلفاً', '$alreadyPaid'),
            if (suspended > 0) _fact('موقوفون', '$suspended'),
          ],
        ),
        const SizedBox(height: 14),
        if (toPay == 0)
          Text(
            alreadyPaid > 0
                ? 'صُرفت هذه الدورة بالفعل — لا شيء يُصرَف مرّةً أخرى'
                : 'لا منتسب مستحقّ في هذا الاختيار',
            style: AppTextStyles.bodyMd(color: AppColors.textSecondary),
          )
        else
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _confirm(context, ref, toPay, total),
              icon: const Icon(Icons.payments_outlined, size: 18),
              label: Text('صرف $toPay مرتَّباً — ${_money.format(total)}'),
            ),
          ),
      ],
    );
  }

  Widget _fact(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: AppTextStyles.caption(color: AppColors.textSecondary)),
          Text(value, style: AppTextStyles.bodyLg()),
        ],
      );

  Future<void> _confirm(BuildContext context, WidgetRef ref, int count, double total) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الصرف'),
        content: Text(
          // المبلغ والعدد في نصّ التأكيد لا في الزرّ وحده: هذا مالٌ يخرج
          // على مئات البطاقات ولا يعود.
          'سيُودَع ${_money.format(total)} على $count بطاقة، وتُخصم أقساط '
          'السلف القائمة من مرتَّباتها. لا يمكن التراجع عن ذلك — التصحيح '
          'يكون بتسوية جديدة.',
          style: AppTextStyles.bodyMd(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('تراجع')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('صرف')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final response = await ApiClient.instance.dio.post(
        '/customer-categories/disburse',
        data: {'categoryId': ref.read(disburseCategoryFilterProvider)},
      );
      final paid = (response.data['customersPaid'] as num?)?.toInt() ?? 0;
      final deducted = _num(response.data['advancesDeducted']);

      ref.invalidate(disbursePreviewProvider);
      ref.invalidate(customerCategoriesProvider);
      ref.invalidate(customerAdvancesProvider);

      messenger.showSnackBar(SnackBar(
        content: Text(deducted > 0
            ? 'صُرف لـ$paid منتسباً، واستُردّ ${_money.format(deducted)} من السلف'
            : 'صُرف لـ$paid منتسباً'),
      ));
    } on DioException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_errorText(e, 'تعذّر الصرف'))));
    }
  }
}

class _CategoryDialog extends ConsumerStatefulWidget {
  const _CategoryDialog({this.category});
  final Map<String, dynamic>? category;

  @override
  ConsumerState<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends ConsumerState<_CategoryDialog> {
  late final _name = TextEditingController(text: '${widget.category?['name'] ?? ''}');
  late final _amount = TextEditingController(
      text: widget.category == null ? '' : '${_num(widget.category!['periodAmount'])}');
  late bool _unspentExpires = widget.category?['unspentExpires'] as bool? ?? true;
  late bool _isActive = widget.category?['isActive'] as bool? ?? true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.category == null;

    return AdaptiveFormDialog(
      title: isNew ? 'فئة جديدة' : 'تعديل الفئة',
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('تراجع'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'جارٍ الحفظ…' : 'حفظ'),
        ),
      ],
      body: EnterAdvancesFocus(
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'اسم الفئة',
                  hintText: 'فئة أ · موظفون · متعاونون',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'المرتَّب لكل دورة',
                  helperText: 'يسري على الصرف القادم — ولا يمسّ ما صُرف',
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _unspentExpires,
                onChanged: (v) => setState(() => _unspentExpires = v),
                title: const Text('يسقط ما لم يُصرَف'),
                subtitle: Text(
                  _unspentExpires
                      ? 'ما بقي من مرتَّب الدورة يسقط عند صرف التالية'
                      : 'ما بقي يتراكم للمنتسب',
                  style: AppTextStyles.caption(color: AppColors.textSecondary),
                ),
              ),
              if (!isNew)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                  title: const Text('الفئة نشطة'),
                  subtitle: Text(
                    // الإيقاف لا الحذف: من فيها يشيرون إليها.
                    'الموقوفة لا تُصرَف ولا تُختار، ويبقى تاريخها',
                    style: AppTextStyles.caption(color: AppColors.textSecondary),
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim());
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'اسم الفئة إلزامي');
      return;
    }
    if (amount == null || amount < 0) {
      setState(() => _error = 'مرتَّب غير صالح');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final body = {
      'name': _name.text.trim(),
      'periodAmount': amount,
      'unspentExpires': _unspentExpires,
      'isActive': _isActive,
    };

    try {
      if (widget.category == null) {
        await ApiClient.instance.dio.post('/customer-categories', data: body);
      } else {
        await ApiClient.instance.dio
            .put('/customer-categories/${widget.category!['id']}', data: body);
      }
      if (mounted) Navigator.pop(context, true);
    } on DioException catch (e) {
      setState(() {
        _saving = false;
        _error = _errorText(e, 'تعذّر الحفظ');
      });
    }
  }
}

// ── السلف ───────────────────────────────────────────────────────────────

class _AdvancesTab extends ConsumerWidget {
  const _AdvancesTab({required this.canManage});
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final openOnly = ref.watch(showOpenAdvancesOnlyProvider);
    final async = ref.watch(customerAdvancesProvider);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: openOnly,
                onChanged: (v) =>
                    ref.read(showOpenAdvancesOnlyProvider.notifier).state = v,
                title: const Text('القائمة وحدها'),
              ),
            ),
            if (canManage)
              TextButton.icon(
                onPressed: () => _create(context, ref),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('سلفة جديدة'),
              ),
          ],
        ),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => _ErrorBox(
              message: _errorText(err, 'تعذّر تحميل السلف'),
              onRetry: () => ref.invalidate(customerAdvancesProvider),
            ),
            data: (advances) {
              if (advances.isEmpty) {
                return _EmptyBox(
                  icon: Icons.request_quote_outlined,
                  title: openOnly ? 'لا سلف قائمة' : 'لا سلف بعد',
                  hint: 'السلفة مالٌ يُقرَض على البطاقة ويُخصم من المرتَّب تلقائياً',
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: advances.length,
                itemBuilder: (context, i) =>
                    _AdvanceCard(advance: advances[i], canManage: canManage),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => const _AdvanceDialog(),
    );
    if (saved == true) ref.invalidate(customerAdvancesProvider);
  }
}

class _AdvanceCard extends ConsumerWidget {
  const _AdvanceCard({required this.advance, required this.canManage});
  final Map<String, dynamic> advance;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outstanding = _num(advance['outstanding']);
    final amount = _num(advance['amount']);
    final installment = _num(advance['installmentAmount']);
    final cancelled = advance['isCancelled'] as bool? ?? false;
    final settled = outstanding <= 0.005;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppSurface(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${advance['customerName']}', style: AppTextStyles.bodyLg()),
                        const SizedBox(height: 4),
                        Text(
                          'أصلها ${_money.format(amount)} · '
                          '${installment > 0 ? 'قسط ${_money.format(installment)}' : 'تُخصم كاملة'}'
                          ' · ${_date.format(DateTime.tryParse('${advance['issuedOn']}') ?? AppClock.now())}',
                          style: AppTextStyles.caption(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        cancelled
                            ? 'مُلغاة'
                            : settled
                                ? 'مسدَّدة'
                                : 'المتبقّي ${_money.format(outstanding)}',
                        style: AppTextStyles.bodyMd(
                          color: cancelled
                              ? AppColors.textSecondary
                              : settled
                                  ? AppColors.success
                                  : AppColors.warning,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (canManage && !cancelled && !settled) ...[
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _repay(context, ref, outstanding),
                      icon: const Icon(Icons.payments_outlined, size: 16),
                      label: const Text('سداد نقدي'),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => _cancel(context, ref),
                      child: Text('إلغاء',
                          style: AppTextStyles.bodyMd(color: AppColors.danger)),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _repay(BuildContext context, WidgetRef ref, double outstanding) async {
    final controller = TextEditingController(text: outstanding.toStringAsFixed(2));
    final amount = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('سداد نقدي'),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('المتبقّي ${_money.format(outstanding)}', style: AppTextStyles.bodyMd()),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'المبلغ المسدَّد'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('تراجع')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(controller.text.trim())),
            child: const Text('تسجيل'),
          ),
        ],
      ),
    );

    if (amount == null || amount <= 0 || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ApiClient.instance.dio
          .post('/customer-advances/${advance['id']}/repay', data: amount);
      ref.invalidate(customerAdvancesProvider);
      messenger.showSnackBar(const SnackBar(content: Text('سُجّل السداد')));
    } on DioException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_errorText(e, 'تعذّر التسجيل'))));
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إلغاء السلفة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              // الإلغاء إعفاءٌ لا محو: المال دخل البطاقة وأُنفق.
              'الإلغاء يوقف خصم الأقساط القادمة ولا يسترجع ما صُرف — '
              'فهو إعفاءٌ من المتبقّي.',
              style: AppTextStyles.bodyMd(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'سبب الإلغاء'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('تراجع')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('إلغاء السلفة'),
          ),
        ],
      ),
    );

    if (reason == null || reason.isEmpty || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ApiClient.instance.dio
          .post('/customer-advances/${advance['id']}/cancel', data: {'reason': reason});
      ref.invalidate(customerAdvancesProvider);
      messenger.showSnackBar(const SnackBar(content: Text('أُلغيت السلفة')));
    } on DioException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_errorText(e, 'تعذّر الإلغاء'))));
    }
  }
}

class _AdvanceDialog extends ConsumerStatefulWidget {
  const _AdvanceDialog();

  @override
  ConsumerState<_AdvanceDialog> createState() => _AdvanceDialogState();
}

class _AdvanceDialogState extends ConsumerState<_AdvanceDialog> {
  String? _customerId;
  final _amount = TextEditingController();
  final _installment = TextEditingController(text: '0');
  final _note = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _installment.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // العملاء صفحةٌ مرقَّمة لا قائمةً — والحوار يعرض الصفحة الأولى.
    // قائمةٌ بألف اسم في قائمة منسدلة لا تُستعمل أصلاً؛ والبحث بالاسم هو
    // الطريق الصحيح حين يكبر العدد.
    final customers = ref.watch(customersProvider).valueOrNull?.items ?? const [];

    return AdaptiveFormDialog(
      title: 'سلفة جديدة',
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('تراجع'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'جارٍ الصرف…' : 'صرف السلفة'),
        ),
      ],
      body: EnterAdvancesFocus(
        child: SizedBox(
          width: 440,
          child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _customerId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'المنتسب'),
                  items: [
                    for (final c in customers)
                      DropdownMenuItem(
                        value: '${c['id']}',
                        child: Text('${c['fullName']}'),
                      ),
                  ],
                  onChanged: (v) => setState(() => _customerId = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'مبلغ السلفة',
                    helperText: 'يُودَع على البطاقة فوراً ويبقى ديناً',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _installment,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'القسط الشهري',
                    // الصفر خيارٌ لا قيمة ناقصة.
                    helperText: 'صفر = تُخصم كاملةً من أوّل مرتَّب',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _note,
                  decoration: const InputDecoration(labelText: 'ملاحظة'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
                ],
              ],
            ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim());
    final installment = double.tryParse(_installment.text.trim()) ?? 0;

    if (_customerId == null) {
      setState(() => _error = 'اختر المنتسب');
      return;
    }
    if (amount == null || amount <= 0) {
      setState(() => _error = 'مبلغ غير صالح');
      return;
    }
    if (installment > amount) {
      setState(() => _error = 'القسط أكبر من السلفة نفسها');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await ApiClient.instance.dio.post('/customer-advances', data: {
        'customerId': _customerId,
        'amount': amount,
        'installmentAmount': installment,
        'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } on DioException catch (e) {
      setState(() {
        _saving = false;
        _error = _errorText(e, 'تعذّر صرف السلفة');
      });
    }
  }
}

// ── مشتركات ─────────────────────────────────────────────────────────────

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, style: AppTextStyles.bodyMd(color: AppColors.danger)),
              const SizedBox(height: 12),
              TextButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
            ],
          ),
        ),
      );
}

class _EmptyBox extends StatelessWidget {
  const _EmptyBox({required this.icon, required this.title, required this.hint});
  final IconData icon;
  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: AppColors.textSecondary),
              const SizedBox(height: 12),
              Text(title, style: AppTextStyles.bodyLg()),
              const SizedBox(height: 6),
              Text(hint,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.caption(color: AppColors.textSecondary)),
            ],
          ),
        ),
      );
}

double _num(Object? value) => (value as num?)?.toDouble() ?? 0;

String _errorText(Object error, String fallback) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] is String) return data['message'] as String;
  }
  return fallback;
}
