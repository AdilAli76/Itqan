import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/network/api_client.dart';
import '../../../core/printing/purchase_order_printer.dart';
import '../../../core/theme/branding_provider.dart';
import 'dart:typed_data';
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
import '../../../shared/widgets/pagination_bar.dart';

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
            spacing: 8,
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
  bool _printing = false;
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
        TextButton(
          onPressed: _printing ? null : () => _print(detailAsync.valueOrNull),
          child: _printing
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('طباعة'),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
      ],
    );
  }

  /// طباعة أمر الشراء على A4 بترويسة الشركة وشعارها.
  ///
  /// الشعار يُجلب هنا بايتاتٍ لا برابط: نقطة الملفات محمية بتوكن، ومحرِّك
  /// الـPDF لا يحمل ترويسة مصادقة — فرابط مباشر كان سيُنتج مستنداً بلا شعار
  /// بلا رسالة خطأ.
  Future<void> _print(Map<String, dynamic>? order) async {
    if (order == null) return;
    setState(() => _printing = true);
    try {
      final branding = ref.read(brandingProvider).valueOrNull;

      Uint8List? logo;
      final logoUrl = branding?.logoUrl;
      if (logoUrl != null && logoUrl.isNotEmpty) {
        try {
          final relative = logoUrl.startsWith('/api') ? logoUrl.substring(4) : logoUrl;
          final res = await ApiClient.instance.dio.get<List<int>>(
            relative,
            options: Options(responseType: ResponseType.bytes),
          );
          logo = Uint8List.fromList(res.data ?? const []);
        } catch (_) {
          // شعار متعذّر لا يمنع الطباعة — المستند يخرج بالاسم وحده.
        }
      }

      // بيانات تواصل الفرع للتذييل: المورّد يردّ على هاتف الفرع الطالب لا
      // على رقم عام.
      String? address;
      String? phone;
      final branches = ref.read(branchesProvider).valueOrNull;
      final branch = branches?.firstWhere(
        (b) => b['id'] == order['branchId'],
        orElse: () => <String, dynamic>{},
      );
      if (branch != null && branch.isNotEmpty) {
        address = branch['address'] as String?;
        phone = branch['phone'] as String?;
      }

      await printPurchaseOrder(
        order: order,
        orgName: branding?.displayName ?? '',
        currencySymbol: branding?.currencySymbol ?? 'د.ل',
        logoBytes: logo,
        branchAddress: address,
        branchPhone: phone,
        issuedBy: await readCurrentUserName(),
      );
    } finally {
      if (mounted) setState(() => _printing = false);
    }
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
          const Divider(height: 20),
          _PurchaseAttachments(orderId: order['id'] as String),
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
          _ReceiptsSection(orderId: widget.orderId, orderedAt: createdAt),
        ],
      ),
    );
  }

  /// نافذة الاستلام: الكمية الواصلة فعلياً لكل صنف، ومعها الدفعة والصلاحية
  /// لما يتتبّعها.
  ///
  /// الكمية تُسأل دائماً لا عند النقص فقط: المورّد قد يورّد ناقصاً بلا أن
  /// يخبر أحداً، وشاشة تفترض الاكتمال تجعل أمين المخزن يوقّع على ما لم يصل.
  Future<void> _confirmReceive(List<Map<String, dynamic>> items) async {
    final pending = items.where((i) => ((i['remainingQuantity'] as num?) ?? 0) > 0).toList();
    final target = pending.isEmpty ? items : pending;

    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ReceiveExpiryDialog(items: target),
    );
    if (payload == null) return; // ألغى المستخدم

    final lines = List<Map<String, dynamic>>.from(payload['lines'] as List);
    final full = lines.every((l) =>
        (l['quantity'] as num?) ==
        (target.firstWhere((i) => i['productId'] == l['productId'])['remainingQuantity'] as num?));

    await _act('receive',
        successMessage: full
            ? 'تم استلام البضاعة وتحديث المخزون'
            : 'تم استلام جزئي — الأمر يبقى مفتوحاً حتى يكتمل',
        body: payload);
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
  // الافتراضي هو المتبقّي كاملاً — الاستلام الكامل هو الحالة الغالبة،
  // فلا يُطالَب أمين المخزن بكتابة ما لم يتغيّر.
  late final _qtyControllers = {
    for (final i in widget.items)
      i['productId'] as String: TextEditingController(
        text: '${((i['remainingQuantity'] as num?) ?? (i['quantity'] as num?) ?? 0)}',
      )
  };
  final Map<String, DateTime> _expiryDates = {};

  // ترويسة مستند الاستلام — راجع PurchaseReceipt في Entities.cs.
  final _noteController = TextEditingController();
  // اليوم افتراضاً، وقابل للتغيير: الشحنة قد تكون وصلت قبل يومين وتُسجَّل
  // اليوم، وقياس مهلة التوريد يعتمد على التاريخ الحقيقي لا على تاريخ الإدخال.
  DateTime _receivedOn = DateTime.now();

  @override
  void dispose() {
    for (final c in _batchControllers.values) {
      c.dispose();
    }
    for (final c in _qtyControllers.values) {
      c.dispose();
    }
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('الكمية الواصلة'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // الترويسة قبل الأصناف: هي ما يجعل الاستلام **مستنداً** لا
              // مجرّد زيادة رقم — رقم الإشعار هو المرجع الوحيد عند الخلاف
              // مع المورّد، والتاريخ هو ما تُقاس به مهلة التوريد.
              TextField(
                controller: _noteController,
                decoration: const InputDecoration(
                  labelText: 'رقم إشعار المورّد (اختياري)',
                  helperText: 'كما هو مكتوب على ورقة التسليم',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text('تاريخ الوصول: ${DateFormat('yyyy-MM-dd').format(_receivedOn)}',
                        style: AppTextStyles.bodyMd()),
                  ),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _receivedOn,
                        firstDate: DateTime.now().subtract(const Duration(days: 365)),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) setState(() => _receivedOn = picked);
                    },
                    child: const Text('تغيير'),
                  ),
                ],
              ),
              const Divider(height: 24),
              ...widget.items.map((item) {
              final productId = item['productId'] as String;
              final expiry = _expiryDates[productId];
              final remaining = ((item['remainingQuantity'] as num?) ?? (item['quantity'] as num?) ?? 0);
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item['productName'] as String? ?? '', style: AppTextStyles.labelMd()),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _qtyControllers[productId],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'الكمية الواصلة',
                        helperText: 'المتبقّي من الأمر: $remaining',
                        isDense: true,
                      ),
                    ),
                    if (item['trackExpiry'] == true) ...[
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
                  ],
                ),
              );
              }),
            ],
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
                'quantity': double.tryParse(_qtyControllers[productId]!.text.trim()),
                'batchNumber': _batchControllers[productId]!.text.trim().isEmpty
                    ? null
                    : _batchControllers[productId]!.text.trim(),
                'expiryDate': _expiryDates[productId]?.toIso8601String(),
              };
            }).toList();
            Navigator.pop(context, {
              'lines': lines,
              'supplierNoteNumber':
                  _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
              'receivedOn': _receivedOn.toIso8601String(),
            });
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
      final results = PagedResult.fromJson(response.data as Map<String, dynamic>).items;
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

  /// إنشاء صنف في الكتالوج دون مغادرة أمر الشراء، ثم إضافته سطراً فيه.
  ///
  /// السعر والتكلفة يُدخلان هنا مبدئيّين: قيمتهما الحقيقية تُثبَّت عند
  /// الاستلام (Receive يحدّث CostPrice بآخر سعر شراء فعلي، وSalePrice إن
  /// حُدِّد في السطر).
  Future<void> _createProductInline() async {
    final created = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _QuickProductDialog(),
    );
    if (created != null) {
      _addLine(created);
      _searchController.clear();
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
                // صنف يُطلب من المورّد لأول مرة ليس في الكتالوج بعد.
                // إجبار المستخدم على مغادرة أمر الشراء وفتح شاشة الأصناف
                // ثم العودة يعني فقدان كل ما أدخله في الأمر — فيُنشأ هنا.
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: _createProductInline,
                    icon: const Icon(Icons.add_box_outlined, size: 18),
                    label: const Text('صنف جديد — غير موجود في الكتالوج'),
                  ),
                ),
                const SizedBox(height: 4),
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

/// إنشاء صنف سريع من داخل أمر الشراء — الحقول الضرورية وحدها.
///
/// بطاقة الصنف الكاملة (التصنيف، المورّد، الباركود، تتبّع الصلاحية) تبقى في
/// شاشة الأصناف. المطلوب هنا ما يكفي لإصدار أمر شراء: اسم ورمز وسعران.
class _QuickProductDialog extends StatefulWidget {
  const _QuickProductDialog();

  @override
  State<_QuickProductDialog> createState() => _QuickProductDialogState();
}

class _QuickProductDialogState extends State<_QuickProductDialog> {
  final _name = TextEditingController();
  final _sku = TextEditingController();
  final _barcode = TextEditingController();
  final _cost = TextEditingController();
  final _sale = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _sku.dispose();
    _barcode.dispose();
    _cost.dispose();
    _sale.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'اسم الصنف مطلوب');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final response = await ApiClient.instance.dio.post('/products', data: {
        'name': name,
        // رمز فارغ يعني رمزاً مشتقاً من الاسم في السيرفر — لا حاجة لأن
        // يخترع المستخدم رمزاً وهو واقف أمام المورّد.
        'sku': _sku.text.trim().isEmpty
            ? 'P-${DateTime.now().millisecondsSinceEpoch}'
            : _sku.text.trim(),
        'barcode': _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
        'costPrice': double.tryParse(_cost.text.trim()) ?? 0,
        'salePrice': double.tryParse(_sale.text.trim()) ?? 0,
        'unitBase': 'piece',
        'tracksStock': true,
        'reorderLevel': 0,
      });
      if (!mounted) return;
      Navigator.pop(context, Map<String, dynamic>.from(response.data as Map));
    } on DioException catch (e) {
      setState(() {
        _saving = false;
        _error = e.response?.data is Map
            ? (e.response!.data['message'] as String? ?? 'تعذّر إنشاء الصنف')
            : 'تعذّر إنشاء الصنف — تحقّق من صلاحية إدارة المخزون';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('صنف جديد'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'اسم الصنف *'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _sku,
              decoration: const InputDecoration(
                labelText: 'الرمز',
                hintText: 'يُولَّد تلقائياً إن تُرك فارغاً',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _barcode,
              decoration: const InputDecoration(labelText: 'الباركود'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _cost,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'تكلفة مبدئية'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _sale,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'سعر البيع'),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('إنشاء وإضافة'),
        ),
      ],
    );
  }
}


/// صور فواتير المورّد المرفقة بأمر الشراء.
///
/// الفاتورة الورقية هي المستند الوحيد الذي يُثبت ما ورد فعلاً وبأي سعر،
/// وبقاؤها في درج المحاسب يجعل مراجعة أمر شراء بعد شهرين مستحيلة عملياً.
class _PurchaseAttachments extends StatefulWidget {
  const _PurchaseAttachments({required this.orderId});
  final String orderId;

  @override
  State<_PurchaseAttachments> createState() => _PurchaseAttachmentsState();
}

class _PurchaseAttachmentsState extends State<_PurchaseAttachments> {
  List<Map<String, dynamic>> _files = const [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ApiClient.instance.dio.get('/files', queryParameters: {
        'entityType': 'purchase_order',
        'entityId': widget.orderId,
      });
      if (!mounted) return;
      setState(() => _files =
          (res.data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList());
    } catch (_) {
      // قائمة فارغة أهون من رسالة خطأ في قسم ثانوي داخل شاشة تفاصيل.
    }
  }

  Future<void> _upload() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'pdf'],
      withData: true,
    );
    final file = picked?.files.firstOrNull;
    if (file == null || file.bytes == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(file.bytes!, filename: file.name),
      });
      await ApiClient.instance.dio.post('/files',
          data: form,
          queryParameters: {'entityType': 'purchase_order', 'entityId': widget.orderId});
      await _load();
      if (mounted) setState(() => _busy = false);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.response?.data is Map
            ? (e.response!.data['message'] as String? ?? 'تعذّر رفع الملف')
            : 'تعذّر رفع الملف';
      });
    }
  }

  Future<void> _delete(String id) async {
    setState(() => _busy = true);
    try {
      await ApiClient.instance.dio.delete('/files/$id');
      await _load();
    } catch (_) {}
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('فاتورة المورّد', style: AppTextStyles.labelMd()),
            const Spacer(),
            TextButton.icon(
              onPressed: _busy ? null : _upload,
              icon: const Icon(Icons.attach_file, size: 18),
              label: const Text('إرفاق'),
            ),
          ],
        ),
        if (_files.isEmpty)
          Text('لا مرفقات', style: AppTextStyles.bodyMd(color: AppColors.textMuted))
        else
          ..._files.map((f) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  (f['contentType'] as String? ?? '').contains('pdf')
                      ? Icons.picture_as_pdf_outlined
                      : Icons.image_outlined,
                  size: 18,
                ),
                title: Text(f['fileName'] as String? ?? '', overflow: TextOverflow.ellipsis),
                subtitle: Text('${(((f['sizeBytes'] as num?) ?? 0) / 1024).round()} ك.ب'),
                trailing: IconAction(
                  icon: Icons.delete_outline,
                  iconSize: 18,
                  dense: true,
                  tooltip: 'حذف المرفق',
                  onPressed: _busy ? null : () => _delete(f['id'] as String),
                ),
              )),
        if (_error != null)
          Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// سجلّ الشحنات — ما وصل فعلاً، ومتى، وبأي إشعار
// ---------------------------------------------------------------------------

/// يظهر فقط حين توجد شحنة: أمرٌ لم يصل منه شيء لا يحتاج قسماً فارغاً يشغل
/// نصف الشاشة ويوحي بعطب.
class _ReceiptsSection extends ConsumerWidget {
  const _ReceiptsSection({required this.orderId, required this.orderedAt});
  final String orderId;
  final DateTime? orderedAt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receiptsAsync = ref.watch(purchaseOrderReceiptsProvider(orderId));

    return receiptsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (receipts) {
        if (receipts.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Divider(height: 28),
            Text('الشحنات الواصلة (${receipts.length})', style: AppTextStyles.labelMd()),
            const SizedBox(height: 8),
            for (final r in receipts) _tile(context, r),
          ],
        );
      },
    );
  }

  Widget _tile(BuildContext context, Map<String, dynamic> r) {
    final receivedOn = DateTime.tryParse(r['receivedOn'] as String? ?? '');
    final items = List<Map<String, dynamic>>.from(r['items'] as List? ?? []);
    final note = r['supplierNoteNumber'] as String?;

    // مهلة التوريد المقيسة: من تاريخ الأمر إلى وصول هذه الشحنة. هي الرقم
    // الذي كان LeadTimeDays يُدخَل بالظنّ بدلاً منه.
    final leadDays = (orderedAt != null && receivedOn != null)
        ? receivedOn.difference(orderedAt!).inDays
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  receivedOn != null ? DateFormat('yyyy-MM-dd').format(receivedOn) : '-',
                  style: AppTextStyles.labelMd(),
                ),
              ),
              if (leadDays != null && leadDays >= 0)
                Text('خلال $leadDays ${leadDays == 1 ? "يوم" : "يوماً"}',
                    style: AppTextStyles.labelMd(color: AppColors.textMuted)),
            ],
          ),
          if (note != null && note.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text('إشعار المورّد: $note',
                style: AppTextStyles.bodyMd(color: AppColors.textSecondary)),
          ],
          const SizedBox(height: 4),
          for (final i in items)
            Text(
              '  • ${i['productName']} × ${i['quantity']}'
              '${(i['batchNumber'] as String? ?? '').isNotEmpty ? '  (دفعة ${i['batchNumber']})' : ''}',
              style: AppTextStyles.bodyMd(color: AppColors.textSecondary),
            ),
          if (r['receivedByName'] != null) ...[
            const SizedBox(height: 4),
            Text('استلمها ${r['receivedByName']}',
                style: AppTextStyles.labelMd(color: AppColors.textMuted)),
          ],
        ],
      ),
    );
  }
}
