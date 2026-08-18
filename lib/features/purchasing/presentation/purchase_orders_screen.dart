import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/network/api_client.dart';
import '../../../core/responsive/adaptive_scaffold.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/data_table_widget.dart';
import '../../branches/data/branches_providers.dart';
import '../../inventory/data/inventory_providers.dart';
import '../data/purchase_orders_providers.dart';
import '../../../shared/widgets/filter_chip_button.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/icon_action.dart';
import '../../../shared/widgets/app_surface.dart';

const _statusLabels = {
  'draft': 'مسودة',
  'ordered': 'مُرسَل للمورّد',
  'received': 'مستلَم',
  'cancelled': 'ملغى',
};

final _currencyFormat = NumberFormat('#,##0.00', 'en');

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
    case 'received':
      fg = AppColors.success;
      bg = AppColors.successBg;
      break;
    case 'ordered':
      fg = AppColors.warning;
      bg = AppColors.warningBg;
      break;
    case 'cancelled':
      fg = AppColors.danger;
      bg = AppColors.dangerBg;
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

class PurchaseOrdersScreen extends ConsumerWidget {
  const PurchaseOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(purchaseOrdersProvider);
    final statusFilter = ref.watch(purchaseOrderStatusFilterProvider);

    return AdaptiveScaffold(
      title: 'المشتريات',
      activeRoute: '/purchasing',
      actions: [
        ElevatedButton.icon(
          onPressed: () async {
            final created = await showDialog<bool>(
              context: context,
              builder: (_) => const _CreatePurchaseOrderDialog(),
            );
            if (created == true) ref.invalidate(purchaseOrdersProvider);
          },
          icon: const Icon(Icons.add, size: 18),
          label: const Text('أمر شراء جديد'),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Wrap لا Row: شرائح الفلاتر تفيض على عرض الهاتف (قياس الفحص
          // البصري: حتى 233 بكسل). الالتفاف يبقيها كلها ظاهرة وقابلة
          // للنقر بدل قصّ آخرها بصمت.
          Wrap(
            runSpacing: 8,
            children: [
              FilterChipButton(
                  label: 'الكل',
                  selected: statusFilter == null,
                  onTap: () => ref.read(purchaseOrderStatusFilterProvider.notifier).state = null),
              const SizedBox(width: 8),
              ..._statusLabels.entries.map((e) => Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: FilterChipButton(
                      label: e.value,
                      selected: statusFilter == e.key,
                      onTap: () => ref.read(purchaseOrderStatusFilterProvider.notifier).state = e.key,
                    ),
                  )),
            ],
          ),
          const SizedBox(height: 16),
          ordersAsync.when(
            loading: () => const TableSkeleton(),
            error: (err, _) => AppSurface(
      padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Text('تعذّر تحميل أوامر الشراء', style: AppTextStyles.bodyMd(color: AppColors.danger)),
                  const SizedBox(height: 12),
                  OutlinedButton(
                      onPressed: () => ref.invalidate(purchaseOrdersProvider),
                      child: const Text('إعادة المحاولة')),
                ],
              ),
            ),
            data: (orders) => AppDataTable(
              title: 'أوامر الشراء (${orders.length})',
              columns: const [
                AppColumn('الفرع'),
                AppColumn('المورّد'),
                AppColumn('الحالة'),
                AppColumn('الإجمالي'),
                AppColumn('عدد الأصناف'),
                AppColumn('التاريخ'),
                AppColumn(''),
              ],
              rows: orders.map((o) {
                final createdAt = DateTime.tryParse(o['createdAt'] as String? ?? '');
                return [
                  Text(o['branchName'] as String? ?? ''),
                  Text(o['supplierName'] as String? ?? '-'),
                  _statusTag(o['status'] as String? ?? ''),
                  Text(_currencyFormat.format((o['totalAmount'] as num?) ?? 0)),
                  Text('${o['itemCount'] ?? 0}'),
                  Text(createdAt != null ? DateFormat('yyyy-MM-dd HH:mm').format(createdAt) : '-'),
                  IconButton(
                    tooltip: 'عرض التفاصيل',
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    onPressed: () async {
                      final message = await showDialog<String>(
                        context: context,
                        builder: (_) => _PurchaseOrderDetailDialog(orderId: o['id'] as String),
                      );
                      if (message != null) {
                        ref.invalidate(purchaseOrdersProvider);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
                        }
                      }
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
}

// ---------------------------------------------------------------------------
// تفاصيل أمر الشراء + إجراءات الحالة
// ---------------------------------------------------------------------------

class _PurchaseOrderDetailDialog extends ConsumerStatefulWidget {
  const _PurchaseOrderDetailDialog({required this.orderId});
  final String orderId;

  @override
  ConsumerState<_PurchaseOrderDetailDialog> createState() => _PurchaseOrderDetailDialogState();
}

class _PurchaseOrderDetailDialogState extends ConsumerState<_PurchaseOrderDetailDialog> {
  bool _working = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(purchaseOrderDetailProvider(widget.orderId));

    return AlertDialog(
      title: const Text('تفاصيل أمر الشراء'),
      content: SizedBox(
        width: 460,
        child: detailAsync.when(
          loading: () => const SizedBox(height: 160, child: Center(child: CircularProgressIndicator())),
          error: (err, _) => const SizedBox(height: 80, child: Center(child: Text('تعذّر تحميل التفاصيل'))),
          data: (order) => _buildContent(context, order),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
      ],
    );
  }

  Widget _buildContent(BuildContext context, Map<String, dynamic> order) {
    final items = List<Map<String, dynamic>>.from(order['items'] as List? ?? []);
    final status = order['status'] as String? ?? '';
    final createdAt = DateTime.tryParse(order['createdAt'] as String? ?? '');

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${order['branchName']} — ${order['supplierName'] ?? "-"}',
                  style: AppTextStyles.headlineMd(),
                ),
              ),
              _statusTag(status),
            ],
          ),
          const SizedBox(height: 4),
          Text(createdAt != null ? DateFormat('yyyy-MM-dd HH:mm').format(createdAt) : '',
              style: AppTextStyles.bodyMd()),
          const Divider(height: 24),
          ...items.map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                        child: Text(item['productName'] as String? ?? '',
                            style: AppTextStyles.bodyMd(color: AppColors.textPrimary))),
                    Text(
                        '${NumberFormat('#,##0.###', 'en').format((item['quantity'] as num?) ?? 0)} × ${_currencyFormat.format((item['unitCost'] as num?) ?? 0)}'),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 80,
                      child: Text(_currencyFormat.format((item['lineTotal'] as num?) ?? 0),
                          textAlign: TextAlign.left),
                    ),
                  ],
                ),
              )),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('الإجمالي', style: AppTextStyles.labelMd()),
              Text(_currencyFormat.format((order['totalAmount'] as num?) ?? 0),
                  style: AppTextStyles.headlineMd()),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
          ],
          const SizedBox(height: 16),
          if (status == 'draft')
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _working ? null : () => _act('cancel', successMessage: 'تم إلغاء أمر الشراء'),
                    child: const Text('إلغاء'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed:
                        _working ? null : () => _act('order', successMessage: 'تم إرسال الأمر للمورّد'),
                    child: _working
                        ? const SizedBox(
                            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('إرسال للمورّد'),
                  ),
                ),
              ],
            )
          else if (status == 'ordered')
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _working ? null : () => _act('cancel', successMessage: 'تم إلغاء أمر الشراء'),
                    child: const Text('إلغاء'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _working ? null : () => _confirmReceive(items),
                    child: _working
                        ? const SizedBox(
                            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('تأكيد الاستلام'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// الأصناف التي تتتبّع الصلاحية تحتاج تاريخ صلاحية فعلي وقت الاستلام —
  /// الدفعة الواصلة فعلياً قد تختلف عمّا كان مفترَضاً وقت إنشاء الأمر.
  Future<void> _confirmReceive(List<Map<String, dynamic>> items) async {
    final expiryItems = items.where((i) => i['trackExpiry'] == true).toList();
    List<Map<String, dynamic>>? lines = [];

    if (expiryItems.isNotEmpty) {
      lines = await showDialog<List<Map<String, dynamic>>>(
        context: context,
        builder: (_) => _ReceiveExpiryDialog(items: expiryItems),
      );
      if (lines == null) return; // ألغى المستخدم
    }

    await _act('receive', successMessage: 'تم استلام البضاعة وتحديث المخزون', body: {'lines': lines});
  }

  Future<void> _act(String action, {required String successMessage, Object? body}) async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await ApiClient.instance.dio.post('/purchase-orders/${widget.orderId}/$action', data: body);
      ref.invalidate(purchaseOrderDetailProvider(widget.orderId));
      if (mounted) Navigator.pop(context, successMessage);
    } catch (e) {
      setState(() => _error = _dioErrorMessage(e, 'تعذّر تنفيذ العملية'));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }
}

// ---------------------------------------------------------------------------
// تاريخ صلاحية/رقم دفعة عند الاستلام (للأصناف التي تتتبّع الصلاحية فقط)
// ---------------------------------------------------------------------------

class _ReceiveExpiryDialog extends StatefulWidget {
  const _ReceiveExpiryDialog({required this.items});
  final List<Map<String, dynamic>> items;

  @override
  State<_ReceiveExpiryDialog> createState() => _ReceiveExpiryDialogState();
}

class _ReceiveExpiryDialogState extends State<_ReceiveExpiryDialog> {
  late final _batchControllers = {
    for (final i in widget.items) i['productId'] as String: TextEditingController()
  };
  final Map<String, DateTime> _expiryDates = {};

  @override
  void dispose() {
    for (final c in _batchControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تاريخ صلاحية الدفعة الواصلة'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: widget.items.map((item) {
              final productId = item['productId'] as String;
              final expiry = _expiryDates[productId];
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item['productName'] as String? ?? '', style: AppTextStyles.labelMd()),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _batchControllers[productId],
                            decoration:
                                const InputDecoration(labelText: 'رقم الدفعة (اختياري)', isDense: true),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: expiry ?? DateTime.now().add(const Duration(days: 365)),
                                firstDate: DateTime.now(),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null) setState(() => _expiryDates[productId] = picked);
                            },
                            child: Text(
                                expiry != null ? DateFormat('yyyy-MM-dd').format(expiry) : 'تاريخ الصلاحية'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () {
            final lines = widget.items.map((item) {
              final productId = item['productId'] as String;
              return {
                'productId': productId,
                'batchNumber': _batchControllers[productId]!.text.trim().isEmpty
                    ? null
                    : _batchControllers[productId]!.text.trim(),
                'expiryDate': _expiryDates[productId]?.toIso8601String(),
              };
            }).toList();
            Navigator.pop(context, lines);
          },
          child: const Text('متابعة الاستلام'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// إنشاء أمر شراء جديد
// ---------------------------------------------------------------------------

class _POLine {
  _POLine({required this.productId, required this.name, required this.unitCost, required this.salePrice});
  final String productId;
  final String name;
  double quantity = 1;
  double unitCost;
  double salePrice;
}

class _CreatePurchaseOrderDialog extends ConsumerStatefulWidget {
  const _CreatePurchaseOrderDialog();

  @override
  ConsumerState<_CreatePurchaseOrderDialog> createState() => _CreatePurchaseOrderDialogState();
}

class _CreatePurchaseOrderDialogState extends ConsumerState<_CreatePurchaseOrderDialog> {
  final _searchController = TextEditingController();
  final List<_POLine> _lines = [];
  String? _branchId;
  String? _supplierId;
  bool _saving = false;
  String? _error;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(purchaseOrderProductSearchProvider.notifier).state = value;
    });
  }

  Future<void> _onSearchSubmitted(String value) async {
    final code = value.trim();
    if (code.isEmpty) return;
    try {
      final response =
          await ApiClient.instance.dio.get('/products/inventory', queryParameters: {'search': code});
      final results = List<Map<String, dynamic>>.from(response.data as List);
      final exact = results.where((p) => p['barcode'] == code || p['sku'] == code).toList();
      final match = exact.length == 1 ? exact.first : (results.length == 1 ? results.first : null);
      if (match != null) {
        _addLine(match);
        _searchController.clear();
        ref.read(purchaseOrderProductSearchProvider.notifier).state = '';
      }
    } catch (_) {
      // تُترك الأخطاء لطلب البحث العادي عبر purchaseOrderProductResultsProvider
    }
  }

  void _addLine(Map<String, dynamic> product) {
    final id = product['id'] as String;
    final existing = _lines.where((l) => l.productId == id);
    setState(() {
      if (existing.isNotEmpty) {
        existing.first.quantity += 1;
      } else {
        _lines.add(_POLine(
          productId: id,
          name: product['name'] as String? ?? '',
          unitCost: (product['costPrice'] as num?)?.toDouble() ?? 0,
          salePrice: (product['salePrice'] as num?)?.toDouble() ?? 0,
        ));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final branchesAsync = ref.watch(branchesProvider);
    final suppliersAsync = ref.watch(suppliersProvider);
    final resultsAsync = ref.watch(purchaseOrderProductResultsProvider);

    return AlertDialog(
      title: const Text('أمر شراء جديد'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          // onUserInteraction: الخطأ يظهر عند الكتابة لا بعد الضغط على
          // «إنشاء» — في أمر بعشرة أسطر، الفارق بين تصحيح سطر واحد فور
          // كتابته وبين البحث عن السطر الخاطئ بين عشرة بعد الرفض.
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                branchesAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => const Text('تعذّر تحميل الفروع'),
                  data: (branches) => DropdownButtonFormField<String>(
                    initialValue: _branchId,
                    decoration: const InputDecoration(labelText: 'الفرع المستلِم'),
                    items: branches
                        .map((b) =>
                            DropdownMenuItem(value: b['id'] as String, child: Text(b['name'] as String)))
                        .toList(),
                    onChanged: (v) => setState(() => _branchId = v),
                  ),
                ),
                const SizedBox(height: 12),
                suppliersAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => const Text('تعذّر تحميل الموردين'),
                  data: (suppliers) => DropdownButtonFormField<String?>(
                    initialValue: _supplierId,
                    decoration: const InputDecoration(labelText: 'المورّد (اختياري)'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('بلا مورّد محدَّد')),
                      ...suppliers.map((s) =>
                          DropdownMenuItem(value: s['id'] as String, child: Text(s['name'] as String))),
                    ],
                    onChanged: (v) => setState(() => _supplierId = v),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _searchController,
                  // التركيز يبدأ عند حقل البحث عن الأصناف لا عند قائمة الفرع:
                  // القائمة تُختار بضغطة واحدة، أما الأصناف فهي العمل الفعلي
                  // في هذا الحوار وتُدخَل كتابةً أو بقارئ الباركود — والقارئ
                  // يحتاج حقلاً ممسكاً بالتركيز ليكتب فيه أصلاً.
                  autofocus: true,
                  onChanged: _onSearch,
                  onSubmitted: _onSearchSubmitted,
                  decoration: const InputDecoration(
                      hintText: 'ابحث أو امسح باركود صنف لإضافته...',
                      prefixIcon: Icon(Icons.search, size: 18)),
                ),
                const SizedBox(height: 8),
                resultsAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (products) => products.isEmpty
                      ? const SizedBox.shrink()
                      : SizedBox(
                          height: 140,
                          child: ListView.builder(
                            itemCount: products.length,
                            itemBuilder: (context, index) {
                              final p = products[index];
                              return ListTile(
                                dense: true,
                                title: Text(p['name'] as String? ?? ''),
                                subtitle: Text(
                                    'تكلفة حالية: ${_currencyFormat.format((p['costPrice'] as num?) ?? 0)}'),
                                trailing: const Icon(Icons.add_circle_outline, size: 18),
                                onTap: () => _addLine(p),
                              );
                            },
                          ),
                        ),
                ),
                const Divider(height: 24),
                if (_lines.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text('لم تُضف أصناف بعد', style: AppTextStyles.bodyMd()),
                  )
                else
                  ..._lines.map((line) => Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(8)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                    child: Text(line.name,
                                        style: AppTextStyles.bodyMd(color: AppColors.textPrimary))),
                                IconAction(
                                  icon: Icons.delete_outline,
                                  iconSize: 18,
                                  dense: true,
                                  tooltip: 'حذف ${line.name} من الأمر',
                                  onPressed: () => setState(() => _lines.remove(line)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    initialValue: line.quantity.toStringAsFixed(
                                        line.quantity.truncateToDouble() == line.quantity ? 0 : 3),
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: const InputDecoration(labelText: 'الكمية', isDense: true),
                                    validator: _validateQuantity,
                                    onChanged: (v) => line.quantity = double.tryParse(v) ?? line.quantity,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextFormField(
                                    initialValue: line.unitCost.toStringAsFixed(2),
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration:
                                        const InputDecoration(labelText: 'تكلفة الوحدة', isDense: true),
                                    validator: _validateMoney,
                                    onChanged: (v) => line.unitCost = double.tryParse(v) ?? line.unitCost,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextFormField(
                                    initialValue: line.salePrice.toStringAsFixed(2),
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: const InputDecoration(labelText: 'سعر البيع', isDense: true),
                                    validator: _validateMoney,
                                    onChanged: (v) => line.salePrice = double.tryParse(v) ?? line.salePrice,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      )),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('إنشاء'),
        ),
      ],
    );
  }

  final _formKey = GlobalKey<FormState>();

  /// الكمية: رقم موجب فعلي.
  ///
  /// كان الحقل يعتمد على `double.tryParse(v) ?? line.quantity` وحده، أي أن
  /// إدخالاً غير صالح يُتجاهَل صامتاً وتبقى القيمة القديمة: يكتب المستخدم
  /// «12» فوق «3»، يخطئ فيكتب «12ا»، فيرى ما كتبه في الحقل بينما المحفوظ
  /// فعلياً هو 3 — ويُسجَّل أمر شراء بكمية غير التي أمامه على الشاشة.
  static String? _validateQuantity(String? v) {
    final q = double.tryParse((v ?? '').trim());
    if (q == null) return 'رقم غير صالح';
    if (q <= 0) return 'يجب أن تكون أكبر من صفر';
    return null;
  }

  /// المبالغ: صفر مقبول (هدية أو عيّنة)، والسالب لا.
  static String? _validateMoney(String? v) {
    final n = double.tryParse((v ?? '').trim());
    if (n == null) return 'رقم غير صالح';
    if (n < 0) return 'لا يقبل قيمة سالبة';
    return null;
  }

  Future<void> _submit() async {
    // التحقّق أولاً: التحقّقات اليدوية أدناه تفحص الفرع والأسطر، لكنها لا
    // تفحص محتوى الحقول نفسها.
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_branchId == null) {
      setState(() => _error = 'اختر الفرع المستلِم');
      return;
    }
    if (_lines.isEmpty) {
      setState(() => _error = 'أضف صنفاً واحداً على الأقل');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await ApiClient.instance.dio.post('/purchase-orders', data: {
        'branchId': _branchId,
        'supplierId': _supplierId,
        'lines': _lines
            .map((l) => {
                  'productId': l.productId,
                  'quantity': l.quantity,
                  'unitCost': l.unitCost,
                  'salePrice': l.salePrice
                })
            .toList(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = _dioErrorMessage(e, 'تعذّر إنشاء أمر الشراء'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
