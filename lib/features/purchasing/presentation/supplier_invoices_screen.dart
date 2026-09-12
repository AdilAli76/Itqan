import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
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
import '../../branches/data/branches_providers.dart';
import '../../inventory/data/inventory_providers.dart';
import '../data/supplier_invoice_providers.dart';
import '../../inventory/data/inventory_providers.dart' as inventory;

final _money = NumberFormat('#,##0.00', 'en');
final _date = DateFormat('yyyy-MM-dd');

/// فواتير الموردين ومطابقتها بالاستلام.
///
/// <para><b>الفجوة التي تسدّها:</b> لم يكن للمورّد فاتورة في النظام. الدَّين
/// يُنشَأ من ورقة أمين المخزن بتكلفة أمر الشراء — بالسعر المتّفق عليه لا
/// بالمُطالَب به. فإن رفع المورّد سعره لم يكن ثمّة موضعٌ يُظهر الفرق.</para>
///
/// <para>وتبويب «مقارنة الأسعار» يجيب سؤالاً آخر: لا فرق الفاتورة عن أمرها،
/// بل ارتفاع السعر **عبر الصفقات** — وهو ما يأكل الهامش ببطء بلا أن يُلاحَظ
/// في أي صفقة بمفردها.</para>
class SupplierInvoicesScreen extends ConsumerWidget {
  const SupplierInvoicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage =
        ref.watch(myPermissionsProvider).valueOrNull?.can('inventory.manage') ?? false;

    return DefaultTabController(
      length: 2,
      child: AdaptiveScaffold(
        title: 'فواتير الموردين',
        activeRoute: '/supplier-invoices',
        // TabBarView يطلب ارتفاعاً محدوداً؛ المُمرِّر الخارجي يعطيه لانهائياً
        // فتنهار الشاشة بيضاء. راجع AdaptiveScaffold.scrollable.
        scrollable: false,
        actions: [
          if (canManage)
            TextButton.icon(
              onPressed: () => _create(context, ref),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('فاتورة مورّد'),
            ),
        ],
        body: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: 'الفواتير'),
                Tab(text: 'مقارنة الأسعار'),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TabBarView(
                children: [
                  _InvoicesTab(canManage: canManage),
                  const _PriceComparisonTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _CreateInvoiceDialog(),
    );
    if (created == true) {
      ref.invalidate(supplierInvoicesProvider);
      ref.invalidate(purchasePriceHistoryProvider);
    }
  }
}

// ── تبويب الفواتير ──────────────────────────────────────────────────────

class _InvoicesTab extends ConsumerWidget {
  const _InvoicesTab({required this.canManage});
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(supplierInvoicesProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => _ErrorBox(
        message: _errorText(err, 'تعذّر تحميل فواتير الموردين'),
        onRetry: () => ref.invalidate(supplierInvoicesProvider),
      ),
      data: (invoices) {
        if (invoices.isEmpty) {
          return _EmptyBox(
            icon: Icons.receipt_long_outlined,
            title: 'لا فواتير موردين بعد',
            hint: canManage
                ? 'سجّل فاتورة المورّد ليُطابَق ما طالب به بما وصل فعلاً'
                : 'لا صلاحية لديك لتسجيل فواتير الموردين',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: invoices.length,
          itemBuilder: (context, i) => _InvoiceCard(
            invoice: invoices[i],
            canManage: canManage,
          ),
        );
      },
    );
  }
}

class _InvoiceCard extends ConsumerWidget {
  const _InvoiceCard({required this.invoice, required this.canManage});
  final Map<String, dynamic> invoice;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = invoice['status'] as String? ?? 'draft';
    final lines = (invoice['lines'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final headerVariance = (invoice['headerVariance'] as num?)?.toDouble() ?? 0;
    final lineVariance =
        lines.fold<double>(0, (sum, l) => sum + ((l['amountVariance'] as num?)?.toDouble() ?? 0));

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppSurface(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${invoice['invoiceNumber']} — ${invoice['supplierName']}',
                            style: AppTextStyles.bodyLg()),
                        const SizedBox(height: 4),
                        Text(
                          _date.format(
                              DateTime.tryParse('${invoice['invoiceDate']}') ?? AppClock.now()),
                          style: AppTextStyles.caption(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Text(_money.format((invoice['totalAmount'] as num?)?.toDouble() ?? 0),
                      style: AppTextStyles.headlineMd()),
                  const SizedBox(width: 12),
                  _StatusChip(status: status),
                ],
              ),

              // الفرق أوّل ما يُقرأ لا آخره: هو سبب وجود هذه الشاشة.
              if (lineVariance.abs() > 0.005 || headerVariance.abs() > 0.005) ...[
                const SizedBox(height: 12),
                _VarianceBanner(
                  lineVariance: lineVariance,
                  headerVariance: headerVariance,
                ),
              ],

              if (lines.isNotEmpty) ...[
                const SizedBox(height: 12),
                ...lines.map(_MatchRow.new),
              ],

              if (canManage && status != 'cancelled') ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (status == 'draft')
                      FilledButton.icon(
                        onPressed: () => _post(context, ref),
                        icon: const Icon(Icons.done_all, size: 18),
                        label: const Text('ترحيل'),
                      ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => _cancel(context, ref),
                      child: Text('إلغاء', style: AppTextStyles.bodyMd(color: AppColors.danger)),
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

  Future<void> _post(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ApiClient.instance.dio.post('/supplier-invoices/${invoice['id']}/post', data: {});
      ref.invalidate(supplierInvoicesProvider);
      messenger.showSnackBar(
        const SnackBar(content: Text('رُحّلت الفاتورة — أُثبت الدَّين للمورّد')),
      );
    } on DioException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(_errorText(e, 'تعذّر ترحيل الفاتورة'))),
      );
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إلغاء فاتورة المورّد'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              // القيد لا يُحذف — يُعكَس. وقول ذلك قبل الضغط أصدق من اكتشافه
              // في دفتر اليومية بعده.
              'الفاتورة لا تُحذف. إن كانت مُرحَّلة يُنشأ لها قيدٌ عكسي يشير '
              'إليها، وتتحرّر سطور الاستلام لتُفوتر من جديد.',
              style: AppTextStyles.bodyMd(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'سبب الإلغاء',
                hintText: 'يُحفظ في سجلّ التدقيق ومع القيد العكسي',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('تراجع')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('إلغاء الفاتورة'),
          ),
        ],
      ),
    );

    if (reason == null || reason.isEmpty || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ApiClient.instance.dio
          .post('/supplier-invoices/${invoice['id']}/cancel', data: {'reason': reason});
      ref.invalidate(supplierInvoicesProvider);
      messenger.showSnackBar(const SnackBar(content: Text('أُلغيت الفاتورة')));
    } on DioException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(_errorText(e, 'تعذّر إلغاء الفاتورة'))),
      );
    }
  }
}

/// سطر المطابقة: ما وصل مقابل ما فُوتر.
class _MatchRow extends StatelessWidget {
  const _MatchRow(this.line);
  final Map<String, dynamic> line;

  @override
  Widget build(BuildContext context) {
    final variance = (line['amountVariance'] as num?)?.toDouble() ?? 0;
    final matched = variance.abs() < 0.005;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            matched ? Icons.check_circle_outline : Icons.error_outline,
            size: 16,
            color: matched ? AppColors.success : AppColors.warning,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text('${line['productName']}', style: AppTextStyles.bodyMd())),
          Text(
            // الرقمان جنباً إلى جنب: «وصل ← فُوتر». وعرض الفرق وحده يُخفي
            // أيّهما تغيّر، الكمية أم السعر.
            'وصل ${_qty(line['receivedQuantity'])}×${_money.format(_num(line['receivedUnitCost']))}'
            '  ←  '
            'فُوتر ${_qty(line['invoicedQuantity'])}×${_money.format(_num(line['invoicedUnitCost']))}',
            style: AppTextStyles.caption(
              color: matched ? AppColors.textSecondary : AppColors.warning,
            ),
          ),
        ],
      ),
    );
  }
}

class _VarianceBanner extends StatelessWidget {
  const _VarianceBanner({required this.lineVariance, required this.headerVariance});
  final double lineVariance;
  final double headerVariance;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[];
    if (lineVariance.abs() > 0.005) {
      parts.add(lineVariance > 0
          ? 'السطور أعلى ممّا وصل بـ${_money.format(lineVariance)}'
          : 'السطور أقلّ ممّا وصل بـ${_money.format(-lineVariance)}');
    }
    if (headerVariance.abs() > 0.005) {
      parts.add(headerVariance > 0
          ? 'وإجمالي الفاتورة يزيد على سطورها بـ${_money.format(headerVariance)} '
              '— نقلٌ أو رسم لم يُنسَب إلى صنف'
          : 'وإجمالي الفاتورة ينقص عن سطورها بـ${_money.format(-headerVariance)}');
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${parts.join('. ')}. الفرق يُقيَّد على «فروق أسعار المشتريات» عند الترحيل.',
              style: AppTextStyles.caption(color: AppColors.warning),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'posted' => ('مُرحَّلة', AppColors.success),
      'cancelled' => ('مُلغاة', AppColors.danger),
      _ => ('مسوّدة', AppColors.textSecondary),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: AppTextStyles.caption(color: color)),
    );
  }
}

// ── تبويب مقارنة الأسعار ────────────────────────────────────────────────

class _PriceComparisonTab extends ConsumerWidget {
  const _PriceComparisonTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(purchasePriceHistoryProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => _ErrorBox(
        message: _errorText(err, 'تعذّر تحميل مقارنة الأسعار'),
        onRetry: () => ref.invalidate(purchasePriceHistoryProvider),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return const _EmptyBox(
            icon: Icons.trending_up,
            title: 'لا تاريخ شراء بعد',
            hint: 'يظهر هنا بعد أوّل استلام — لكل صنف آخر سعرٍ دُفع والسعر قبله',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: rows.length,
          itemBuilder: (context, i) => _PriceRow(rows[i]),
        );
      },
    );
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow(this.row);
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final change = (row['changePercent'] as num?)?.toDouble();
    final latest = _num(row['latestCost']);
    final cheapest = _num(row['cheapestCost']);
    final supplierCount = (row['supplierCount'] as num?)?.toInt() ?? 1;

    // أرخص من الأخير فعلاً: مورّدٌ أرخص بقرشٍ لا يستحقّ تنبيهاً.
    final cheaperElsewhere = supplierCount > 1 && cheapest < latest - 0.005;

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
                    child: Text('${row['productName']}', style: AppTextStyles.bodyLg()),
                  ),
                  if (change != null) _ChangeBadge(change: change),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                row['previousCost'] == null
                    // مرّةً واحدة: لا مقارنة، وقولُ ذلك أصدق من عرض 0%.
                    ? 'اشتُري مرّةً واحدة بـ${_money.format(latest)} '
                        '(${_date.format(DateTime.tryParse('${row['latestOn']}') ?? AppClock.now())})'
                    : '${_money.format(_num(row['previousCost']))} '
                        '(${_date.format(DateTime.tryParse('${row['previousOn']}') ?? AppClock.now())})'
                        '  ←  ${_money.format(latest)} '
                        '(${_date.format(DateTime.tryParse('${row['latestOn']}') ?? AppClock.now())})',
                style: AppTextStyles.caption(color: AppColors.textSecondary),
              ),
              if (row['latestSupplierName'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('آخر مورّد: ${row['latestSupplierName']}',
                      style: AppTextStyles.caption(color: AppColors.textSecondary)),
                ),
              if (cheaperElsewhere)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${row['cheapestSupplierName']} يبيعه بـ${_money.format(cheapest)} '
                    '— أرخص بـ${_money.format(latest - cheapest)}',
                    style: AppTextStyles.caption(color: AppColors.success),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChangeBadge extends StatelessWidget {
  const _ChangeBadge({required this.change});
  final double change;

  @override
  Widget build(BuildContext context) {
    // الارتفاع خطرٌ والانخفاض مكسب — واللون يقولها قبل الرقم.
    final rising = change > 0;
    final color = rising ? AppColors.danger : AppColors.success;
    final sign = rising ? '+' : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(rising ? Icons.trending_up : Icons.trending_down, size: 14, color: color),
          const SizedBox(width: 4),
          Text('$sign${change.toStringAsFixed(1)}%', style: AppTextStyles.caption(color: color)),
        ],
      ),
    );
  }
}

// ── حوار الإنشاء ────────────────────────────────────────────────────────

class _CreateInvoiceDialog extends ConsumerStatefulWidget {
  const _CreateInvoiceDialog();

  @override
  ConsumerState<_CreateInvoiceDialog> createState() => _CreateInvoiceDialogState();
}

class _CreateInvoiceDialogState extends ConsumerState<_CreateInvoiceDialog> {
  String? _supplierId;
  String? _branchId;
  final _number = TextEditingController();
  final _total = TextEditingController();
  DateTime _invoiceDate = AppClock.now();

  /// سطور الاستلام المختارة ← السعر المُفوتر لكلٍّ منها.
  ///
  /// الكمية لا تُحرَّر: تفويتر كميةٍ غير التي وصلت يترك رصيداً في «وردت ولم
  /// تُفوتَر» لا يُصفَّر أبداً. والفرق الحقيقي في السوق فرقُ سعر لا كمية.
  final Map<String, TextEditingController> _selected = {};

  /// منتجات جديدة (غير موجودة في الوارد) — كل واحد: ID → {qty, supplierCost, sellingPrice}
  final Map<String, Map<String, dynamic>> _newProducts = {};

  /// مصاريف الفاتورة — كل واحد: اسم → مبلغ
  final Map<String, TextEditingController> _expenses = {};

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _number.dispose();
    _total.dispose();
    for (final c in _selected.values) {
      c.dispose();
    }
    for (final exp in _expenses.values) {
      exp.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final suppliers = ref.watch(suppliersProvider).valueOrNull ?? const [];
    final branches = ref.watch(branchesProvider).valueOrNull ?? const [];

    return AlertDialog(
      title: const Text('فاتورة مورّد جديدة'),
      // Enter ينتقل إلى الحقل التالي: المورّد ← الفرع ← الرقم ← الإجمالي
      // ثم أسعار السطور. من يُدخل عشرين سطراً كان يمدّ يده إلى الفأرة
      // أربعين مرّة. ولا تُستعمل في نقطة البيع — راجع [EnterAdvancesFocus].
      content: EnterAdvancesFocus(
        child: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _supplierId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'المورّد'),
                  items: [
                    for (final s in suppliers)
                      DropdownMenuItem(
                        value: '${s['id']}',
                        child: Text('${s['name']}'),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    _supplierId = v;
                    for (final c in _selected.values) {
                      c.dispose();
                    }
                    _selected.clear();
                  }),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _branchId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'الفرع'),
                  items: [
                    for (final b in branches)
                      DropdownMenuItem(value: '${b['id']}', child: Text('${b['name']}')),
                  ],
                  onChanged: (v) => setState(() => _branchId = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _number,
                  decoration: const InputDecoration(
                    labelText: 'رقم الفاتورة',
                    hintText: 'كما كتبه المورّد — هو المرجع عند الخلاف',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: _pickDate,
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: 'تاريخ الفاتورة'),
                          child: Text(_date.format(_invoiceDate)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _total,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'إجمالي الفاتورة',
                          // يُدخَل ولا يُحسب: حسابُه من السطور يجعل النظام
                          // يُصحّح المورّد بدل أن يطابقه.
                          hintText: 'كما هو مكتوب عليها',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_supplierId != null) ...[
                  _uninvoicedList(),
                  const SizedBox(height: 16),
                  _newProductsSection(),
                  const SizedBox(height: 16),
                  _expensesSection(),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('تراجع'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'جارٍ الحفظ…' : 'حفظ مسوّدة'),
        ),
      ],
    );
  }

  Widget _uninvoicedList() {
    final async = ref.watch(uninvoicedReceiptsProvider(_supplierId!));

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (err, _) => Text(
        _errorText(err, 'تعذّر تحميل الوارد غير المُفوتر'),
        style: AppTextStyles.bodyMd(color: AppColors.danger),
      ),
      data: (items) {
        if (items.isEmpty) {
          return Text(
            'لا وارد غير مُفوتر من هذا المورّد — كل ما استُلم منه فُوتر بالفعل.',
            style: AppTextStyles.bodyMd(color: AppColors.textSecondary),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ما وصل ولم يُفوتر', style: AppTextStyles.bodyLg()),
            const SizedBox(height: 4),
            Text(
              // الاختيار من الوارد لا من الكتالوج: فلا تُفوتر بضاعة لم تصل.
              'اختر ما تُفوتره، واكتب السعر كما في ورقة المورّد إن خالف ما استُلم به.',
              style: AppTextStyles.caption(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            for (final item in items) _uninvoicedRow(item),
          ],
        );
      },
    );
  }

  Widget _newProductsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('منتجات إضافية', style: AppTextStyles.bodyLg()),
            TextButton.icon(
              onPressed: () => _addNewProduct(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('إضافة منتج'),
            ),
          ],
        ),
        if (_newProducts.isEmpty)
          Text(
            'لا منتجات إضافية — أضف من الكتالوج إن لزم',
            style: AppTextStyles.caption(color: AppColors.textSecondary),
          )
        else ...[
          const SizedBox(height: 8),
          for (final entry in _newProducts.entries) _newProductRow(entry.key, entry.value),
        ],
      ],
    );
  }

  Widget _newProductRow(String productId, Map<String, dynamic> data) {
    final product = data['product'] as Map<String, dynamic>?;
    if (product == null) return const SizedBox.shrink();

    final qtyCtrl = data['qtyCtrl'] as TextEditingController;
    final costCtrl = data['costCtrl'] as TextEditingController;
    final priceCtrl = data['priceCtrl'] as TextEditingController;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(product['name'] as String? ?? '', style: AppTextStyles.bodyMd()),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => setState(() {
                  _newProducts.remove(productId);
                  qtyCtrl.dispose();
                  costCtrl.dispose();
                  priceCtrl.dispose();
                }),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: qtyCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'الكمية',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: costCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'سعر المورد',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: priceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'سعر البيع',
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _expensesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('مصاريف الفاتورة', style: AppTextStyles.bodyLg()),
            TextButton.icon(
              onPressed: () => _addExpense(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('إضافة مصروف'),
            ),
          ],
        ),
        if (_expenses.isEmpty)
          Text(
            'بلا مصاريف إضافية',
            style: AppTextStyles.caption(color: AppColors.textSecondary),
          )
        else ...[
          const SizedBox(height: 8),
          for (final entry in _expenses.entries) _expenseRow(entry.key, entry.value),
        ],
      ],
    );
  }

  Widget _expenseRow(String name, TextEditingController ctrl) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(name, style: AppTextStyles.bodyMd()),
          ),
          Expanded(
            child: TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'المبلغ',
                isDense: true,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() {
              _expenses.remove(name);
              ctrl.dispose();
            }),
          ),
        ],
      ),
    );
  }

  Future<void> _addNewProduct() async {
    // جلب أول صفحة من المنتجات — في إنتاج حقيقي يجب pagination كاملة
    final productsAsync = ref.watch(inventory.productsInventoryProvider);

    final products = productsAsync.whenData((pagedResult) {
      final items = pagedResult.items as List?;
      if (items == null) return const <Map<String, dynamic>>[];
      return items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }).valueOrNull ?? const [];

    if (products.isEmpty) {
      setState(() => _error = 'لا منتجات في الكتالوج');
      return;
    }

    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _SelectProductDialog(products: products),
    );
    if (selected == null) return;

    final productId = '${selected['id']}';
    if (_newProducts.containsKey(productId)) {
      setState(() => _error = 'المنتج موجود بالفعل');
      return;
    }

    setState(() {
      _newProducts[productId] = {
        'product': selected,
        'qtyCtrl': TextEditingController(text: '1'),
        'costCtrl': TextEditingController(text: '${selected['costPrice'] ?? 0}'),
        'priceCtrl': TextEditingController(text: '${selected['salePrice'] ?? 0}'),
      };
      _error = null;
    });
  }

  Future<void> _addExpense() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _ExpenseNameDialog(),
    );
    if (name == null || name.isEmpty) return;

    setState(() {
      if (!_expenses.containsKey(name)) {
        _expenses[name] = TextEditingController();
      }
    });
  }

  Widget _uninvoicedRow(Map<String, dynamic> item) {
    final id = '${item['purchaseReceiptItemId']}';
    final selected = _selected.containsKey(id);
    final receivedCost = _num(item['unitCost']);

    return CheckboxListTile(
      dense: true,
      value: selected,
      onChanged: (on) => setState(() {
        if (on == true) {
          _selected[id] = TextEditingController(text: receivedCost.toStringAsFixed(2));
        } else {
          _selected.remove(id)?.dispose();
        }
      }),
      title: Text('${item['productName']}', style: AppTextStyles.bodyMd()),
      subtitle: Text(
        'إشعار ${item['supplierNoteNumber'] ?? '—'} · '
        '${_qty(item['quantity'])} × ${_money.format(receivedCost)} · '
        '${_date.format(DateTime.tryParse('${item['receivedOn']}') ?? AppClock.now())}',
        style: AppTextStyles.caption(color: AppColors.textSecondary),
      ),
      secondary: selected
          ? SizedBox(
              width: 110,
              child: TextField(
                controller: _selected[id],
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'سعر الفاتورة'),
              ),
            )
          : null,
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _invoiceDate,
      firstDate: DateTime(2020),
      lastDate: AppClock.now(),
    );
    if (picked != null) setState(() => _invoiceDate = picked);
  }

  Future<void> _save() async {
    final total = double.tryParse(_total.text.trim());

    if (_supplierId == null || _branchId == null) {
      setState(() => _error = 'اختر المورّد والفرع');
      return;
    }
    if (_number.text.trim().isEmpty) {
      setState(() => _error = 'رقم الفاتورة إلزامي');
      return;
    }
    if (total == null || total <= 0) {
      setState(() => _error = 'أدخل إجمالي الفاتورة كما هو مكتوب عليها');
      return;
    }

    final hasSelectedReceipts = _selected.isNotEmpty;
    final hasNewProducts = _newProducts.isNotEmpty;

    if (!hasSelectedReceipts && !hasNewProducts) {
      setState(() => _error = 'اختر ما تُفوتره من الوارد أو أضف منتجات جديدة');
      return;
    }

    // معالجة سطور الوارد المختارة
    final lines = <Map<String, dynamic>>[];
    if (hasSelectedReceipts) {
      final items = ref.read(uninvoicedReceiptsProvider(_supplierId!)).valueOrNull ?? const [];
      for (final entry in _selected.entries) {
        final source = items.firstWhere(
          (i) => '${i['purchaseReceiptItemId']}' == entry.key,
          orElse: () => const {},
        );
        final cost = double.tryParse(entry.value.text.trim());
        if (cost == null || cost < 0) {
          setState(() => _error = 'سعرٌ غير صالح في أحد السطور');
          return;
        }
        lines.add({
          'purchaseReceiptItemId': entry.key,
          'quantity': source['quantity'],
          'unitCost': cost,
        });
      }
    }

    // معالجة المنتجات الجديدة
    final newProductLines = <Map<String, dynamic>>[];
    for (final entry in _newProducts.entries) {
      final data = entry.value;
      final qtyCtrl = data['qtyCtrl'] as TextEditingController;
      final costCtrl = data['costCtrl'] as TextEditingController;
      final priceCtrl = data['priceCtrl'] as TextEditingController;

      final qty = double.tryParse(qtyCtrl.text.trim());
      final cost = double.tryParse(costCtrl.text.trim());
      final price = double.tryParse(priceCtrl.text.trim());

      if (qty == null || qty <= 0) {
        setState(() => _error = 'كمية غير صالحة في المنتجات الجديدة');
        return;
      }
      if (cost == null || cost < 0) {
        setState(() => _error = 'سعر مورد غير صالح');
        return;
      }

      newProductLines.add({
        'productId': entry.key,
        'quantity': qty,
        'supplierCost': cost,
        if (price != null && price > 0) 'sellingPrice': price,
      });
    }

    // معالجة المصاريف
    final expenses = <Map<String, dynamic>>[];
    for (final entry in _expenses.entries) {
      final amount = double.tryParse(entry.value.text.trim());
      if (amount != null && amount > 0) {
        expenses.add({
          'name': entry.key,
          'amount': amount,
        });
      }
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await ApiClient.instance.dio.post('/supplier-invoices', data: {
        'branchId': _branchId,
        'supplierId': _supplierId,
        'invoiceNumber': _number.text.trim(),
        'invoiceDate': _invoiceDate.toIso8601String(),
        'totalAmount': total,
        if (lines.isNotEmpty) 'lines': lines,
        if (newProductLines.isNotEmpty) 'newProductLines': newProductLines,
        if (expenses.isNotEmpty) 'expenses': expenses,
      });
      if (mounted) Navigator.pop(context, true);
    } on DioException catch (e) {
      setState(() {
        _saving = false;
        _error = _errorText(e, 'تعذّر حفظ الفاتورة');
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

// ── حوارات إضافية ────────────────────────────────────────────────────────

class _SelectProductDialog extends StatefulWidget {
  const _SelectProductDialog({required this.products});
  final List<Map<String, dynamic>> products;

  @override
  State<_SelectProductDialog> createState() => _SelectProductDialogState();
}

class _SelectProductDialogState extends State<_SelectProductDialog> {
  late List<Map<String, dynamic>> _filtered = widget.products;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _filter(String query) {
    setState(() {
      if (query.isEmpty) {
        _filtered = widget.products;
      } else {
        final q = query.toLowerCase();
        _filtered = widget.products
            .where((p) =>
                ((p['name'] as String?)?.toLowerCase() ?? '').contains(q) ||
                ((p['sku'] as String?)?.toLowerCase() ?? '').contains(q))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('اختر منتج'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                labelText: 'ابحث حسب الاسم أو الرمز',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _filter,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _filtered.isEmpty
                  ? Center(
                      child: Text(
                        'لا منتجات تطابق البحث',
                        style: AppTextStyles.bodyMd(color: AppColors.textSecondary),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, idx) {
                        final product = _filtered[idx];
                        return ListTile(
                          dense: true,
                          title: Text(product['name'] as String? ?? ''),
                          subtitle: Text(
                            'الرمز: ${product['sku'] ?? "—"} · التكلفة: ${_money.format(product['costPrice'] ?? 0)}',
                            style: AppTextStyles.caption(),
                          ),
                          onTap: () => Navigator.pop(context, product),
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

class _ExpenseNameDialog extends StatefulWidget {
  const _ExpenseNameDialog();

  @override
  State<_ExpenseNameDialog> createState() => _ExpenseNameDialogState();
}

class _ExpenseNameDialogState extends State<_ExpenseNameDialog> {
  final _controller = TextEditingController();
  static const _defaults = ['الشحن', 'الضرائب', 'التأمين', 'الرسوم'];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إضافة مصروف'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.send,
              decoration: const InputDecoration(labelText: 'اسم المصروف'),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            Text('خيارات سريعة:', style: AppTextStyles.labelMd()),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final d in _defaults)
                  ActionChip(
                    label: Text(d),
                    onPressed: () => Navigator.pop(context, d),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(onPressed: _submit, child: const Text('إضافة')),
      ],
    );
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, name);
  }
}

double _num(Object? value) => (value as num?)?.toDouble() ?? 0;

String _qty(Object? value) {
  final q = _num(value);
  return q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toStringAsFixed(2);
}

String _errorText(Object error, String fallback) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] is String) return data['message'] as String;
  }
  return fallback;
}
