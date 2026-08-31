import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../shared/widgets/adaptive_form_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/network/api_client.dart';
import '../../../core/responsive/adaptive_scaffold.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/data_table_widget.dart';
import '../../branches/data/branches_providers.dart';
import '../data/stock_count_providers.dart';
import 'field_count_screen.dart';
import '../../../shared/widgets/filter_chip_button.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../core/auth/permissions.dart';
import '../../../shared/widgets/app_surface.dart';

// ux-audit: ignore UX-03 — أسطر جلسة جرد واحدة، محدودة بما يجرده الموظف
// فعلياً في الجلسة، ويجب أن تبقى كلها مرئية أمامه دفعةً واحدة: تقسيمها
// صفحات يُخفي أصنافاً لم تُعدّ بعد فتُنسى.

const _statusLabels = {
  'open': 'قيد العد',
  'pending_review': 'بانتظار اعتماد الفروقات',
  'reconciled': 'مُعتمَد',
  'cancelled': 'ملغى',
};

String _statusLabel(String s) => _statusLabels[s] ?? s;

String _dioErrorMessage(Object error, String fallback) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] is String) return data['message'] as String;
  }
  return fallback;
}

Widget _statusTag(String status) {
  Color fg;
  Color bg;
  switch (status) {
    case 'reconciled':
      fg = AppColors.success;
      bg = AppColors.successBg;
      break;
    case 'cancelled':
      fg = AppColors.danger;
      bg = AppColors.dangerBg;
      break;
    // تحذيري لا محايد: جردٌ ينتظر قراراً ليس حالةً عادية يُمرّ عليها، بل
    // عملٌ متوقّف على شخص — واللون هو ما يجعله ظاهراً في القائمة.
    case 'pending_review':
      fg = AppColors.warning;
      bg = AppColors.warningBg;
      break;
    default:
      fg = AppColors.info;
      bg = AppColors.infoBg;
  }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
    child: Text(_statusLabel(status), style: AppTextStyles.labelMd(color: fg)),
  );
}

class StockCountScreen extends ConsumerWidget {
  const StockCountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countsAsync = ref.watch(stockCountsProvider);
    final statusFilter = ref.watch(stockCountStatusFilterProvider);

    return AdaptiveScaffold(
      title: 'الجرد الدوري',
      activeRoute: '/stock-count',
      actions: [
        Can(
          permission: Perm.stockCountManage,
          child: ElevatedButton.icon(
            onPressed: () => _startNewCount(context, ref),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('بدء جرد جديد'),
          ),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Wrap لا Row: شرائح الفلاتر تفيض على عرض الهاتف (قياس الفحص
          // البصري: حتى 233 بكسل). الالتفاف يبقيها كلها ظاهرة وقابلة
          // للنقر بدل قصّ آخرها بصمت.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChipButton(
                  label: 'الكل',
                  selected: statusFilter == null,
                  onTap: () => ref.read(stockCountStatusFilterProvider.notifier).state = null),
              const SizedBox(width: 8),
              ..._statusLabels.entries.map((e) => Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: FilterChipButton(
                      label: e.value,
                      selected: statusFilter == e.key,
                      onTap: () => ref.read(stockCountStatusFilterProvider.notifier).state = e.key,
                    ),
                  )),
            ],
          ),
          const SizedBox(height: 16),
          countsAsync.when(
            loading: () => const TableSkeleton(),
            error: (err, _) => AppSurface(
      padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Text('تعذّر تحميل عمليات الجرد', style: AppTextStyles.bodyMd(color: AppColors.danger)),
                  const SizedBox(height: 12),
                  OutlinedButton(
                      onPressed: () => ref.invalidate(stockCountsProvider),
                      child: const Text('إعادة المحاولة')),
                ],
              ),
            ),
            data: (counts) => AppDataTable(
              title: 'عمليات الجرد (${counts.length})',
              columns: const [
                AppColumn('الفرع'),
                AppColumn('الحالة'),
                AppColumn('عدد الأصناف'),
                AppColumn('أصناف بها فرق'),
                AppColumn('التاريخ'),
                AppColumn(''),
              ],
              rows: counts.map((c) {
                final createdAt = DateTime.tryParse(c['createdAt'] as String? ?? '');
                final varianceCount = (c['varianceCount'] as num?)?.toInt() ?? 0;
                return [
                  Text(c['branchName'] as String? ?? ''),
                  _statusTag(c['status'] as String? ?? ''),
                  Text('${c['itemCount'] ?? 0}'),
                  Text(
                    '$varianceCount',
                    style: AppTextStyles.bodyMd(
                        color: varianceCount > 0 ? AppColors.warning : AppColors.textSecondary),
                  ),
                  Text(createdAt != null ? DateFormat('yyyy-MM-dd HH:mm').format(createdAt) : '-'),
                  IconButton(
                    tooltip: 'فتح الجرد',
                    icon: const Icon(Icons.checklist_outlined, size: 18),
                    onPressed: () async {
                      final changed = await showDialog<bool>(
                        context: context,
                        builder: (_) => _StockCountDetailDialog(countId: c['id'] as String),
                      );
                      if (changed == true) ref.invalidate(stockCountsProvider);
                    },
                  ),
                ];
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startNewCount(BuildContext context, WidgetRef ref) async {
    final branchId = await showDialog<String>(
      context: context,
      builder: (_) => const _PickBranchDialog(),
    );
    if (branchId == null) return;
    if (!context.mounted) return;

    final options = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _CountOptionsDialog(),
    );
    if (options == null) return;

    try {
      final response = await ApiClient.instance.dio.post('/stock-counts', data: {
        'branchId': branchId,
        ...options,
      });
      ref.invalidate(stockCountsProvider);
      if (context.mounted) {
        await showDialog<bool>(
          context: context,
          builder: (_) => _StockCountDetailDialog(countId: response.data['id'] as String),
        );
        ref.invalidate(stockCountsProvider);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_dioErrorMessage(e, 'تعذّر بدء الجرد'))));
      }
    }
  }
}

class _PickBranchDialog extends ConsumerWidget {
  const _PickBranchDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branchesAsync = ref.watch(branchesProvider);

    return AlertDialog(
      title: const Text('بدء جرد جديد'),
      content: SizedBox(
        width: 320,
        child: branchesAsync.when(
          loading: () => const SizedBox(height: 60, child: Center(child: CircularProgressIndicator())),
          error: (_, __) => const Text('تعذّر تحميل الفروع'),
          data: (branches) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('اختر الفرع المراد جرده', style: AppTextStyles.bodyMd()),
              const SizedBox(height: 12),
              ...branches.map((b) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(b['name'] as String? ?? ''),
                    onTap: () => Navigator.pop(context, b['id'] as String),
                  )),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// تفاصيل الجرد — إدخال الكميات المعدودة
// ---------------------------------------------------------------------------

class _StockCountDetailDialog extends ConsumerStatefulWidget {
  const _StockCountDetailDialog({required this.countId});
  final String countId;

  @override
  ConsumerState<_StockCountDetailDialog> createState() => _StockCountDetailDialogState();
}

class _StockCountDetailDialogState extends ConsumerState<_StockCountDetailDialog> {
  final _searchController = TextEditingController();
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, double> _liveVariance = {};
  String _search = '';
  bool _working = false;
  String? _error;
  bool _dirty = false;

  @override
  void dispose() {
    _searchController.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(Map<String, dynamic> item) {
    final id = item['id'] as String;
    return _controllers.putIfAbsent(
        id, () => TextEditingController(text: _formatQty(item['countedQuantity'])));
  }

  String _formatQty(dynamic value) => NumberFormat('#,##0.###', 'en').format((value as num?) ?? 0);

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(stockCountDetailProvider(widget.countId));

    return AlertDialog(
      title: const Text('تفاصيل الجرد'),
      content: SizedBox(
        width: 560,
        height: 520,
        child: detailAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => const Center(child: Text('تعذّر تحميل تفاصيل الجرد')),
          data: (count) => _buildContent(context, count),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, _dirty), child: const Text('إغلاق')),
      ],
    );
  }

  Widget _buildContent(BuildContext context, Map<String, dynamic> count) {
    final status = count['status'] as String? ?? '';
    final items = List<Map<String, dynamic>>.from(count['items'] as List? ?? []);
    final visibleItems = _search.isEmpty
        ? items
        : items
            .where((i) => (i['productName'] as String? ?? '').toLowerCase().contains(_search.toLowerCase()))
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('${count['branchName']}', style: AppTextStyles.headlineMd())),
            _statusTag(status),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _searchController,
          onChanged: (v) => setState(() => _search = v),
          decoration:
              const InputDecoration(hintText: 'بحث عن صنف...', prefixIcon: Icon(Icons.search, size: 18)),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.separated(
            itemCount: visibleItems.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = visibleItems[index];
              final itemId = item['id'] as String;
              final systemQty = (item['systemQuantity'] as num?)?.toDouble() ?? 0;
              final controller = _controllerFor(item);
              final currentVariance = _liveVariance[itemId] ?? ((item['variance'] as num?)?.toDouble() ?? 0);

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(item['productName'] as String? ?? '',
                          style: AppTextStyles.bodyMd(color: AppColors.textPrimary)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('نظامي: ${_formatQty(systemQty)}',
                          style: AppTextStyles.labelMd(color: AppColors.textMuted)),
                    ),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: controller,
                        enabled: status == 'open',
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(isDense: true, labelText: 'المعدود'),
                        onChanged: (v) {
                          final parsed = double.tryParse(v);
                          if (parsed != null) {
                            setState(() => _liveVariance[itemId] = parsed - systemQty);
                          }
                        },
                        onSubmitted: (v) => _saveItem(itemId, v),
                        onEditingComplete: () => _saveItem(itemId, controller.text),
                      ),
                    ),
                    SizedBox(
                      width: 60,
                      child: Text(
                        currentVariance == 0
                            ? '-'
                            : (currentVariance > 0
                                ? '+${_formatQty(currentVariance)}'
                                : _formatQty(currentVariance)),
                        textAlign: TextAlign.end,
                        style: AppTextStyles.labelMd(
                            color: currentVariance == 0
                                ? AppColors.textMuted
                                : (currentVariance > 0 ? AppColors.success : AppColors.danger)),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
        ],
        if (status == 'open') ...[
          const SizedBox(height: 12),
          // الوضع الميداني أولاً وبعرض كامل: هذه الشاشة جدولٌ يُقرأ على مكتب،
          // والعدّ يقع بين الرفوف. من يمسك جهازاً بيد وصندوقاً بالأخرى لا
          // يتصفّح جدولاً — راجع FieldCountScreen.
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _working ? null : _startFieldMode,
              icon: const Icon(Icons.barcode_reader),
              label: const Text('ابدأ العدّ بالمسح'),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _working ? null : () => _finish('cancel', 'تم إلغاء الجرد'),
                  child: const Text('إلغاء الجرد'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                // «إنهاء العدّ» لا «اعتماد»: الزرّ لم يعد يطبّق شيئاً على
                // المخزون — يُسلّم العدّ لمن يبتّ في فروقاته. وتسميته باسم
                // فعله هي ما يمنع الضغط الآلي.
                child: FilledButton(
                  onPressed: _working ? null : _submitCount,
                  child: _working
                      ? const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('إنهاء العدّ'),
                ),
              ),
            ],
          ),
        ],
        if (status == 'pending_review') ...[
          const SizedBox(height: 12),
          _ReviewBanner(count: count),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _working ? null : () => _finish('cancel', 'تم إلغاء الجرد'),
                  child: const Text('إلغاء الجرد'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: _working ? null : _requestRecount,
                  child: const Text('إعادة العدّ'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _working ? null : () => _finish('approve', 'اعتُمدت الفروقات وحُدّث المخزون'),
                  child: _working
                      ? const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('اعتماد الفروقات'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _saveItem(String itemId, String value) async {
    final parsed = double.tryParse(value);
    if (parsed == null) return;
    try {
      await ApiClient.instance.dio.put('/stock-counts/${widget.countId}/items/$itemId', data: {
        'countedQuantity': parsed,
      });
      _dirty = true;
    } catch (e) {
      if (mounted) {
        setState(() => _error = _dioErrorMessage(e, 'تعذّر حفظ الكمية'));
      }
    }
  }

  /// يفتح الوضع الميداني.
  ///
  /// شاشة كاملة لا حوار: الحوار يترك الجدول خلفه فيغري بالعودة إليه، وهذه
  /// عمليةٌ يقف فيها العامل بين الرفوف حتى ينتهي.
  Future<void> _startFieldMode() async {
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => FieldCountScreen(countId: widget.countId)),
    );
    ref.invalidate(stockCountDetailProvider(widget.countId));
    // إنهاء العدّ يقع داخل الشاشة الميدانية نفسها، فتُغلق هذه معها بنفس
    // النتيجة — وإلا بقي المستخدم أمام جرد انتهى.
    if (done == true && mounted) Navigator.pop(context, true);
  }

  /// إنهاء العدّ. الخادم يقرّر الوجهة: بلا فروقات يُعتمد فوراً، ومعها ينتقل
  /// إلى المراجعة — فالرسالة تُشتقّ من ردّه لا تُفترض هنا.
  Future<void> _submitCount() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final res = await ApiClient.instance.dio.post('/stock-counts/${widget.countId}/submit');
      final data = res.data as Map<String, dynamic>?;
      final varianceCount = (data?['varianceCount'] as num?)?.toInt() ?? 0;
      ref.invalidate(stockCountDetailProvider(widget.countId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(varianceCount == 0
              ? 'لا فروقات — اعتُمد الجرد مباشرةً'
              : 'انتهى العدّ: $varianceCount صنفاً بفروقات تنتظر الاعتماد'),
        ));
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() => _error = _dioErrorMessage(e, 'تعذّر إنهاء العدّ'));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _requestRecount() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _RecountReasonDialog(),
    );
    if (reason == null || reason.trim().isEmpty) return;

    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await ApiClient.instance.dio.post(
        '/stock-counts/${widget.countId}/recount',
        data: {'reason': reason.trim()},
      );
      ref.invalidate(stockCountDetailProvider(widget.countId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('أُعيد الجرد إلى العدّ — الكميات المعدودة صُفِّرت')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() => _error = _dioErrorMessage(e, 'تعذّر طلب إعادة العدّ'));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _finish(String action, String successMessage) async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await ApiClient.instance.dio.post('/stock-counts/${widget.countId}/$action');
      ref.invalidate(stockCountDetailProvider(widget.countId));
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
}

/// شريط المراجعة: من عدّ، وكم صنفاً اختلف، وهل سبق أن أُعيد العدّ.
///
/// يسبق الأزرار لا يليها: القرار يُتخذ بعد قراءته، فوضعه تحت الزرّين كان
/// يجعله تفسيراً لما فُعل لا أساساً له.
class _ReviewBanner extends StatelessWidget {
  const _ReviewBanner({required this.count});
  final Map<String, dynamic> count;

  @override
  Widget build(BuildContext context) {
    final items = List<Map<String, dynamic>>.from(count['items'] as List? ?? []);
    final varianceCount = items.where((i) => ((i['variance'] as num?)?.toDouble() ?? 0) != 0).length;
    final rounds = (count['recountRounds'] as num?)?.toInt() ?? 0;
    final submittedBy = count['submittedByName'] as String?;
    final reason = count['recountReason'] as String?;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        border: Border.all(color: AppColors.warning),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$varianceCount صنفاً بفروقات تنتظر قراراً'
            '${submittedBy != null ? ' — عدّها $submittedBy' : ''}',
            style: AppTextStyles.labelMd(color: AppColors.warning),
          ),
          const SizedBox(height: 4),
          Text(
            'الاعتماد يطبّق الفروقات على المخزون فوراً. وإن كان العدّ مشكوكاً فيه فأعده.',
            style: AppTextStyles.bodyMd(color: AppColors.textSecondary),
          ),
          if (rounds > 0) ...[
            const SizedBox(height: 6),
            // مرّتان أو أكثر ليستا دقّة بل مؤشّر على خلل في العدّ أو المخزون.
            Text(
              'أُعيد العدّ $rounds ${rounds == 1 ? 'مرة' : 'مرات'}'
              '${reason != null && reason.isNotEmpty ? ' — آخر سبب: $reason' : ''}',
              style: AppTextStyles.labelMd(color: AppColors.danger),
            ),
          ],
        ],
      ),
    );
  }
}

/// سبب إعادة العدّ — إلزامي. «أعد العدّ» بلا سبب تصل العادّ بلا ما يوجّهه،
/// فيعيد الرقم نفسه.
class _RecountReasonDialog extends StatefulWidget {
  const _RecountReasonDialog();

  @override
  State<_RecountReasonDialog> createState() => _RecountReasonDialogState();
}

class _RecountReasonDialogState extends State<_RecountReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveFormDialog(
      title: 'سبب إعادة العدّ',
      maxWidth: 360,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('إعادة العدّ'),
        ),
      ],
      body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'يعود الجرد إلى العدّ، وتُصفَّر الكميات المعدودة إلى النظامية — '
              'فيُدخَل الرقم من الرفّ من جديد لا يُؤكَّد من الشاشة.',
              style: AppTextStyles.bodyMd(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: 'السبب',
                hintText: 'مثال: فرق كبير في الرفّ الثالث — يُعاد عدّه بحضور المشرف',
              ),
              onSubmitted: (v) => Navigator.pop(context, v),
            ),
          ],
        ),
    );
  }
}

// ---------------------------------------------------------------------------
// خيارات الجرد: نوعه، ونطاقه
// ---------------------------------------------------------------------------

/// خطوة ثانية بعد اختيار الفرع، لا حقول مضافة إليه: اختيار الفرع قرار
/// واحد واضح، وحشو نافذته بخيارين آخرين يجعل الثلاثة تُتخطّى معاً.
class _CountOptionsDialog extends StatefulWidget {
  const _CountOptionsDialog();

  @override
  State<_CountOptionsDialog> createState() => _CountOptionsDialogState();
}

class _CountOptionsDialogState extends State<_CountOptionsDialog> {
  bool _initial = false;
  int? _notCountedDays;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('نطاق الجرد'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _initial,
                onChanged: (v) => setState(() => _initial = v),
                title: const Text('جرد ابتدائي'),
                subtitle: Text(
                  'لإدخال مخزون قائم إلى النظام لأول مرّة. تبدأ الكميات '
                  'بأصفار فتُدخِل ما على الرفّ فعلاً.',
                  style: AppTextStyles.bodyMd(color: AppColors.textSecondary),
                ),
              ),
              const Divider(height: 24),
              Text('الأصناف المشمولة', style: AppTextStyles.labelMd()),
              const SizedBox(height: 4),
              // الجرد الموزَّع: يُعدّ ما لم يُعدّ منذ مدّة بدل إغلاق المحل
              // يوماً كاملاً. وما لم يُعدّ قطّ يدخل دائماً.
              Text(
                'الجرد الموزَّع يقسّم العدّ على السنة بدل يوم واحد يُغلق فيه المحل.',
                style: AppTextStyles.bodyMd(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in const [
                    (null, 'كل الأصناف'),
                    (30, 'لم يُعدّ منذ 30 يوماً'),
                    (90, 'لم يُعدّ منذ 90 يوماً'),
                    (180, 'لم يُعدّ منذ 180 يوماً'),
                  ])
                    ChoiceChip(
                      label: Text(option.$2),
                      selected: _notCountedDays == option.$1,
                      onSelected: (_) => setState(() => _notCountedDays = option.$1),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () => Navigator.pop(context, {
            if (_initial) 'kind': 'initial',
            if (_notCountedDays != null)
              'notCountedSince': DateTime.now()
                  .subtract(Duration(days: _notCountedDays!))
                  .toIso8601String(),
          }),
          child: const Text('بدء الجرد'),
        ),
      ],
    );
  }
}
