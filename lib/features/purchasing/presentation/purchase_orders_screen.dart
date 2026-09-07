import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../shared/widgets/adaptive_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/network/api_client.dart';
import '../../../core/purchasing/landed_cost.dart';
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

    return AdaptiveDialog(
      title: 'تفاصيل أمر الشراء',
      maxWidth: 460,
      actions: [
        // إرسالٌ بجوار الطباعة: أكثر ما يُفعل بأمر الشراء أن يُرسَل إلى
        // المورّد لا أن يُطبع على ورق. ولوحة مشاركة النظام تُوصله إلى
        // واتساب أو البريد بلا تكاملٍ مع أيٍّ منهما.
        PopupMenuButton<String>(
          enabled: !_printing,
          tooltip: 'إرسال',
          icon: const Icon(Icons.share_outlined, size: 20),
          onSelected: (value) => _print(
            detailAsync.valueOrNull,
            share: true,
            showPrices: value == 'priced',
          ),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'priced', child: Text('إرسال بالأسعار (أمر شراء)')),
            // بلا أسعار: ما يُرسَل قبل الاتفاق طلبُ تسعير، وإرسالُه
            // بأسعارنا القديمة يقول للمورّد بكم اشترينا آخر مرّة فيبني
            // عرضه عليها ولا ينزل تحتها.
            PopupMenuItem(value: 'quote', child: Text('طلب عرض سعر (بلا أسعار)')),
          ],
        ),
        TextButton(
          onPressed: _printing ? null : () => _print(detailAsync.valueOrNull),
          child: _printing
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('طباعة'),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
      ],
      body: detailAsync.when(
          loading: () => const SizedBox(height: 160, child: Center(child: CircularProgressIndicator())),
          error: (err, _) => const SizedBox(height: 80, child: Center(child: Text('تعذّر تحميل التفاصيل'))),
          data: (order) => _buildContent(context, order),
        ),
    );
  }

  /// طباعة أمر الشراء على A4 بترويسة الشركة وشعارها.
  ///
  /// الشعار يُجلب هنا بايتاتٍ لا برابط: نقطة الملفات محمية بتوكن، ومحرِّك
  /// الـPDF لا يحمل ترويسة مصادقة — فرابط مباشر كان سيُنتج مستنداً بلا شعار
  /// بلا رسالة خطأ.
  Future<void> _print(
    Map<String, dynamic>? order, {
    bool share = false,
    bool showPrices = true,
  }) async {
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
        showPrices: showPrices,
        share: share,
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
                        '${NumberFormat('#,##0.###', 'en').format((item['quantity'] as num?) ?? 0)} × ${_currencyFormat.format((item['unitCost'] as num?) ?? 0)}'
                        '${((item['chargeShare'] as num?) ?? 0) > 0 ? ' ← ${_currencyFormat.format((item['landedUnitCost'] as num?) ?? 0)}' : ''}'),
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
          // المصاريف تحت البضاعة لا داخلها: الإجمالي هو ما يطالب به المورّد
          // وتُطابَق به فاتورته، والشحن يطالب به غيره.
          ...((order['charges'] as List? ?? const []).map((c) {
            final charge = Map<String, dynamic>.from(c as Map);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${charge['label']}',
                      style: AppTextStyles.caption(color: AppColors.textSecondary)),
                  Text(_currencyFormat.format((charge['amount'] as num?) ?? 0),
                      style: AppTextStyles.caption(color: AppColors.textSecondary)),
                ],
              ),
            );
          })),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('الإجمالي (بضاعة)', style: AppTextStyles.labelMd()),
              Text(_currencyFormat.format((order['totalAmount'] as num?) ?? 0),
                  style: AppTextStyles.headlineMd()),
            ],
          ),
          if (((order['chargesTotal'] as num?) ?? 0) > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'ومصاريف شحنة ${_currencyFormat.format((order['chargesTotal'] as num?) ?? 0)} '
                'موزَّعةً بالقيمة — التكلفة المحمَّلة أعلى من سعر المورّد.',
                style: AppTextStyles.caption(color: AppColors.textSecondary),
              ),
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
          // الإرجاع متاح ما دام شيء قد استُلم — لا يُشترط اكتمال الأمر:
          // شحنةٌ وصل نصفها تالفاً تُعاد اليوم ويبقى الأمر منتظِراً بقيّته.
          if (status == 'ordered' || status == 'received')
            if (items.any((i) => ((i['receivedQuantity'] as num?) ?? 0) > 0)) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _working ? null : () => _confirmReturn(items),
                  icon: const Icon(Icons.assignment_return_outlined, size: 18),
                  label: const Text('إرجاع إلى المورّد'),
                ),
              ),
            ],
          _ReceiptsSection(orderId: widget.orderId, orderedAt: createdAt),
        ],
      ),
    );
  }

  /// نافذة الإرجاع إلى المورّد.
  ///
  /// بضاعة تالفة أو خاطئة تعود إلى المورّد، فتخرج من المخزون ويُنقص دَينه.
  /// وبلا هذا الطريق تبقى في مخزون النظام إلى الأبد، أو تُخرَج بتعديل يدوي
  /// بلا سبب ولا أثر على الدَّين.
  Future<void> _confirmReturn(List<Map<String, dynamic>> items) async {
    final returnable = items.where((i) => ((i['receivedQuantity'] as num?) ?? 0) > 0).toList();
    if (returnable.isEmpty) return;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ReturnToSupplierDialog(items: returnable),
    );
    if (result == null) return;

    await _act('return-to-supplier',
        body: result, successMessage: 'تم الإرجاع — خرجت الكمية من المخزون ونقص دَين المورّد');
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
  /// سعر المورّد الفعلي لكل سطر — مبدوءاً بالسعر المطلوب به.
  ///
  /// <para><b>سبب وجوده:</b> الأمر يُرسَل بسعر الكتالوج يوم الطلب، ثم يصل
  /// المورّد بسعرٍ آخر — وهو الغالب لا النادر. ولم يكن في الشاشة مكانٌ
  /// يُكتب فيه السعر الحقيقي، فتدخل البضاعة بسعرٍ لم يُدفَع: مخزونٌ مقوَّم
  /// بالخطأ، وربحٌ محسوب على تكلفةٍ خاطئة، وفاتورة مورّد لا تطابق
  /// الدفتر.</para>
  late final _costControllers = {
    for (final i in widget.items)
      i['productId'] as String: TextEditingController(
        text: '${((i['unitCost'] as num?) ?? 0)}',
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
    for (final c in _costControllers.values) {
      c.dispose();
    }
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveDialog(
      title: 'الكمية الواصلة',
      maxWidth: 400,
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
                'unitCost': double.tryParse(_costControllers[productId]!.text.trim()),
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
      body: Column(
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
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _qtyControllers[productId],
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText: 'الكمية الواصلة',
                              helperText: 'المتبقّي: $remaining',
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _costControllers[productId],
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            // مبدوءاً بالسعر المطلوب: أمين المخزن لا يكتب
                            // شيئاً إن لم يتغيّر، ويصحّح رقماً واحداً إن
                            // تغيّر — والفرق يُسجَّل في سجلّ التدقيق.
                            decoration: InputDecoration(
                              labelText: 'سعر المورّد',
                              helperText: 'المطلوب: ${_currencyFormat.format((item['unitCost'] as num?) ?? 0)}',
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
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

/// مصروفٌ على الشحنة كما يُكتب في الحوار — راجع [LandedCost].
///
/// بلا معاملات إنشاء: يُضاف فارغاً دائماً ثم يُملأ في الحقلين، ومعاملٌ
/// اختياري لا يُمرَّر أبداً يُبلّغ عنه التحليل الساكن بحقّ.
class _POCharge {
  String label = '';
  double amount = 0;
}

class _CreatePurchaseOrderDialogState extends ConsumerState<_CreatePurchaseOrderDialog> {
  final _searchController = TextEditingController();
  final List<_POLine> _lines = [];
  final List<_POCharge> _charges = [];

  /// آخر هامشٍ سعّر به — يُقترح في المرّة التالية.
  double _margin = 25;

  double get _chargesTotal => _charges.fold<double>(0, (a, c) => a + c.amount);

  /// نصيب الوحدة من المصاريف لكل سطر، بترتيب [_lines].
  List<double> get _shares => LandedCost.perUnitShares(
        lines: _lines.map((l) => (quantity: l.quantity, unitCost: l.unitCost)).toList(),
        totalCharges: _chargesTotal,
      );
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

    return AdaptiveDialog(
      title: 'أمر شراء جديد',
      maxWidth: 480,
      body: Form(
          key: _formKey,
          // onUserInteraction: الخطأ يظهر عند الكتابة لا بعد الضغط على
          // «إنشاء» — في أمر بعشرة أسطر، الفارق بين تصحيح سطر واحد فور
          // كتابته وبين البحث عن السطر الخاطئ بين عشرة بعد الرفض.
          autovalidateMode: AutovalidateMode.onUserInteraction,
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
                                    // setState لأن التكلفة المحمَّلة تُعاد
                                    // قسمتها بالقيمة عند كل تغيّر — ورقمٌ
                                    // معروضٌ قديم أسوأ من لا رقم.
                                    onChanged: (v) => setState(
                                        () => line.quantity = double.tryParse(v) ?? line.quantity),
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
                                    onChanged: (v) => setState(
                                        () => line.unitCost = double.tryParse(v) ?? line.unitCost),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextFormField(
                                    key: ValueKey('sale-${line.productId}-${line.salePrice}'),
                                    initialValue: line.salePrice.toStringAsFixed(2),
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: const InputDecoration(labelText: 'سعر البيع', isDense: true),
                                    validator: _validateMoney,
                                    onChanged: (v) => line.salePrice = double.tryParse(v) ?? line.salePrice,
                                  ),
                                ),
                              ],
                            ),
                            // التكلفة المحمَّلة تحت السطر مباشرةً: الرقم الذي
                            // يُسعَّر عليه يجب أن يكون أمام عين من يسعّر، لا
                            // في شاشةٍ أخرى بعد الحفظ.
                            if (_chargesTotal > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'التكلفة المحمَّلة: '
                                  '${(line.unitCost + _shareOf(line)).toStringAsFixed(2)}'
                                  ' (شحن ${_shareOf(line).toStringAsFixed(2)} للوحدة)',
                                  style: AppTextStyles.caption(color: AppColors.textSecondary),
                                ),
                              ),
                          ],
                        ),
                      )),
                if (_lines.isNotEmpty) _chargesSection(),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
                ],
              ],
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

  double _shareOf(_POLine line) {
    final index = _lines.indexOf(line);
    final shares = _shares;
    return index < 0 || index >= shares.length ? 0 : shares[index];
  }

  /// <summary>
  /// مصاريف الشحنة والتسعير منها.
  ///
  /// <para><b>سبب وجودها في هذا الحوار:</b> هنا يُكتب عرض المورّد، وهنا
  /// يُسعَّر. وسؤالُ «كم الشحن؟» في شاشةٍ أخرى بعد الحفظ يعني أن التسعير
  /// وقع على سعر المورّد وحده — وهو الخطأ الذي بُنيت له.</para>
  /// </summary>
  Widget _chargesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 28),
        Row(
          children: [
            Expanded(
              child: Text('مصاريف الشحنة', style: AppTextStyles.bodyMd()),
            ),
            TextButton.icon(
              onPressed: () => setState(() => _charges.add(_POCharge())),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('أضف مصروفاً'),
            ),
          ],
        ),
        Text(
          // ما تفعله ولا تفعله يُقال مرّة: من يظنّها تُضاف إلى ما يطالب به
          // المورّد يبحث عن الفرق في كل فاتورة.
          'تُوزَّع بالقيمة على الأصناف فتصير تكلفتها المحمَّلة. ولا تدخل في '
          'إجمالي الأمر — ذاك ما يطالب به المورّد وتُطابَق به فاتورته.',
          style: AppTextStyles.caption(color: AppColors.textSecondary),
        ),
        for (final charge in _charges) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextFormField(
                  initialValue: charge.label,
                  decoration: const InputDecoration(
                      labelText: 'البيان', hintText: 'شحن، تخليص، جمارك', isDense: true),
                  onChanged: (v) => charge.label = v,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  initialValue: charge.amount == 0 ? '' : charge.amount.toStringAsFixed(2),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'المبلغ', isDense: true),
                  onChanged: (v) => setState(() => charge.amount = double.tryParse(v) ?? 0),
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _charges.remove(charge)),
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'احذف المصروف',
              ),
            ],
          ),
        ],
        if (_chargesTotal > 0) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text('مجموع المصاريف: ${_chargesTotal.toStringAsFixed(2)}',
                    style: AppTextStyles.bodyMd()),
              ),
              SizedBox(
                width: 96,
                child: TextFormField(
                  initialValue: _margin.toStringAsFixed(0),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'هامش ٪', isDense: true),
                  onChanged: (v) => _margin = double.tryParse(v) ?? _margin,
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _priceByMargin,
                child: const Text('سعّر'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// <summary>
  /// تسعير كل السطور بهامشٍ **من التكلفة المحمَّلة**.
  ///
  /// <para>وهذا هو بيت القصيد: هامش ٢٥٪ على سعر مورّدٍ عشرة يُخرج ١٢٫٥٠،
  /// والتكلفة الحقيقية ١١٫٥٠ — فالربح دينارٌ لا اثنان ونصف، وقد يصير خسارة
  /// مع أول خصم. والتسعير من المحمَّلة يُخرج ١٤٫٣٨.</para>
  ///
  /// <para>ويبقى كل سعرٍ قابلاً للتعديل بعده: الهامش نقطة بداية لا حكم.</para>
  /// </summary>
  void _priceByMargin() {
    final shares = _shares;
    setState(() {
      for (var i = 0; i < _lines.length; i++) {
        final landed = _lines[i].unitCost + (i < shares.length ? shares[i] : 0);
        _lines[i].salePrice = double.parse((landed * (1 + _margin / 100)).toStringAsFixed(2));
      }
    });
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
        'charges': _charges
            .where((c) => c.amount > 0)
            .map((c) => {'label': c.label, 'amount': c.amount})
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
    return AdaptiveDialog(
      title: 'صنف جديد',
      maxWidth: 420,
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
      body: Column(
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
    );
    final file = picked.firstOrNull;
    if (file == null) return;
    final bytes = await file.readAsBytes();

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: file.name),
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

  /// يفتح المرفق — بتنزيله إلى حيث يختار المستخدم.
  ///
  /// <para><b>ولماذا لا يُفتح برابط مباشر:</b> نقطة <c>/api/files/{id}</c>
  /// محميّة بتوكن، و<c>launchUrl</c> يفتح المتصفّح بلا ترويسة تفويض —
  /// فيردّ الخادم 401 ويرى المستخدم صفحة خطأ. فالبايتات تُجلَب بالعميل
  /// نفسه الذي يحمل التوكن، ثم تُسلَّم للنظام.</para>
  Future<void> _open(Map<String, dynamic> file) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await ApiClient.instance.dio.get<List<int>>(
        '/files/${file['id']}',
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) throw Exception('empty');

      final saved = await FilePicker.saveFile(
        fileName: file['fileName'] as String? ?? 'مرفق',
        bytes: Uint8List.fromList(bytes),
      );
      if (mounted && saved != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('حُفظ المرفق')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'تعذّر فتح المرفق');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
                // ⚠ الفتح كان غائباً تماماً: المرفق يُرفَع ويُحذَف ولا
                // يُقرأ. فصورة فاتورة المورّد تُخزَّن ولا يراها أحد بعد
                // رفعها — وهي كل غرضها.
                onTap: _busy ? null : () => _open(f),
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


/// اختيار ما يُعاد إلى المورّد وكمّه وسببه.
class _ReturnToSupplierDialog extends StatefulWidget {
  const _ReturnToSupplierDialog({required this.items});
  final List<Map<String, dynamic>> items;

  @override
  State<_ReturnToSupplierDialog> createState() => _ReturnToSupplierDialogState();
}

class _ReturnToSupplierDialogState extends State<_ReturnToSupplierDialog> {
  final _reasonController = TextEditingController();
  // الكميات تبدأ **فارغة لا كاملة**: الإرجاع الكامل ليس الحالة الغالبة
  // (بخلاف الاستلام)، وحقلٌ مملوء سلفاً يجعل ضغطةً واحدة تُخرج شحنة كاملة.
  final _quantities = <String, TextEditingController>{};
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final item in widget.items) {
      _quantities[item['productId'] as String] = TextEditingController();
    }
  }

  @override
  void dispose() {
    _reasonController.dispose();
    for (final c in _quantities.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveDialog(
      title: 'إرجاع إلى المورّد',
      maxWidth: 460,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(onPressed: _submit, child: const Text('تأكيد الإرجاع')),
      ],
      body: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _reasonController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'سبب الإرجاع',
                  hintText: 'بضاعة تالفة، صنف خاطئ، قرب انتهاء الصلاحية…',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'السبب إلزامي: بضاعة تخرج من المخزون بلا سبب مكتوب هي أوسع باب '
                'لإخفاء نقص.',
                style: AppTextStyles.caption(),
              ),
              const SizedBox(height: 16),
              for (final item in widget.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item['productName'] as String? ?? '',
                                style: AppTextStyles.bodyMd(color: AppColors.textPrimary)),
                            Text('المستلَم: ${item['receivedQuantity']}',
                                style: AppTextStyles.labelMd()),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 110,
                        child: TextField(
                          controller: _quantities[item['productId'] as String],
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'يُعاد'),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
              ],
            ],
          ),
    );
  }

  void _submit() {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'السبب إلزامي');
      return;
    }

    final lines = <Map<String, dynamic>>[];
    for (final item in widget.items) {
      final productId = item['productId'] as String;
      final raw = _quantities[productId]!.text.trim();
      if (raw.isEmpty) continue;

      final quantity = double.tryParse(raw);
      if (quantity == null || quantity <= 0) {
        setState(() => _error = 'كمية غير صالحة عند «${item['productName']}»');
        return;
      }
      final received = (item['receivedQuantity'] as num?)?.toDouble() ?? 0;
      if (quantity > received) {
        setState(() => _error = 'لا يمكن إرجاع أكثر من المستلَم عند «${item['productName']}»');
        return;
      }
      lines.add({'productId': productId, 'batchNumber': '', 'quantity': quantity});
    }

    if (lines.isEmpty) {
      setState(() => _error = 'أدخل كمية لصنف واحد على الأقل');
      return;
    }

    Navigator.pop(context, {'lines': lines, 'reason': reason});
  }
}
