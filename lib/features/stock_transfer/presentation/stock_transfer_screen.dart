import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../shared/widgets/adaptive_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/network/api_client.dart';
import '../../../core/responsive/adaptive_scaffold.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/data_table_widget.dart';
import '../../branches/data/branches_providers.dart';
import '../data/stock_transfer_providers.dart';
import '../../../shared/widgets/filter_chip_button.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/icon_action.dart';
import '../../../core/auth/permissions.dart';
import '../../../shared/widgets/app_surface.dart';
import '../../../shared/widgets/pagination_bar.dart';

const _statusLabels = {
  'pending': 'معلّق',
  'in_transit': 'قيد النقل',
  'received': 'مستلم',
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
    case 'received':
      fg = AppColors.success;
      bg = AppColors.successBg;
      break;
    case 'in_transit':
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

class StockTransferScreen extends ConsumerWidget {
  const StockTransferScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transfersAsync = ref.watch(stockTransfersProvider);
    final statusFilter = ref.watch(transferStatusFilterProvider);

    return AdaptiveScaffold(
      title: 'تحويل المخزون بين الفروع',
      activeRoute: '/stock-transfer',
      actions: [
        Can(
          permission: Perm.stockTransferManage,
          child: ElevatedButton.icon(
            onPressed: () async {
              final created = await showDialog<bool>(
                context: context,
                builder: (_) => const _CreateTransferDialog(),
              );
              if (created == true) ref.invalidate(stockTransfersProvider);
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('إنشاء تحويل'),
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
                  onTap: () => ref.read(transferStatusFilterProvider.notifier).state = null),
              const SizedBox(width: 8),
              ..._statusLabels.entries.map((e) => Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: FilterChipButton(
                      label: e.value,
                      selected: statusFilter == e.key,
                      onTap: () => ref.read(transferStatusFilterProvider.notifier).state = e.key,
                    ),
                  )),
            ],
          ),
          const SizedBox(height: 16),
          transfersAsync.when(
            loading: () => const TableSkeleton(),
            error: (err, _) => AppSurface(
      padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Text('تعذّر تحميل تحويلات المخزون', style: AppTextStyles.bodyMd(color: AppColors.danger)),
                  const SizedBox(height: 12),
                  OutlinedButton(
                      onPressed: () => ref.invalidate(stockTransfersProvider),
                      child: const Text('إعادة المحاولة')),
                ],
              ),
            ),
            data: (transfers) => AppDataTable(
              title: 'التحويلات (${transfers.length})',
              columns: const [
                AppColumn('من فرع'),
                AppColumn('إلى فرع'),
                AppColumn('الحالة'),
                AppColumn('عدد الأصناف'),
                AppColumn('التاريخ'),
                AppColumn(''),
              ],
              rows: transfers.map((t) {
                final createdAt = DateTime.tryParse(t['createdAt'] as String? ?? '');
                return [
                  Text(t['fromBranchName'] as String? ?? ''),
                  Text(t['toBranchName'] as String? ?? ''),
                  _statusTag(t['status'] as String? ?? ''),
                  Text('${t['itemCount'] ?? 0}'),
                  Text(createdAt != null ? DateFormat('yyyy-MM-dd HH:mm').format(createdAt) : '-'),
                  IconButton(
                    tooltip: 'عرض التفاصيل',
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    onPressed: () async {
                      final message = await showDialog<String>(
                        context: context,
                        builder: (_) => _TransferDetailDialog(transferId: t['id'] as String),
                      );
                      if (message != null) {
                        ref.invalidate(stockTransfersProvider);
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
// تفاصيل التحويل + إجراءات الحالة
// ---------------------------------------------------------------------------

class _TransferDetailDialog extends ConsumerStatefulWidget {
  const _TransferDetailDialog({required this.transferId});
  final String transferId;

  @override
  ConsumerState<_TransferDetailDialog> createState() => _TransferDetailDialogState();
}

class _TransferDetailDialogState extends ConsumerState<_TransferDetailDialog> {
  bool _working = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(transferDetailProvider(widget.transferId));

    return AlertDialog(
      title: const Text('تفاصيل التحويل'),
      content: SizedBox(
        width: 420,
        child: detailAsync.when(
          loading: () => const SizedBox(height: 160, child: Center(child: CircularProgressIndicator())),
          error: (err, _) => const SizedBox(height: 80, child: Center(child: Text('تعذّر تحميل التفاصيل'))),
          data: (transfer) => _buildContent(context, transfer),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
      ],
    );
  }

  Widget _buildContent(BuildContext context, Map<String, dynamic> transfer) {
    final items = List<Map<String, dynamic>>.from(transfer['items'] as List? ?? []);
    final status = transfer['status'] as String? ?? '';
    final createdAt = DateTime.tryParse(transfer['createdAt'] as String? ?? '');

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${transfer['fromBranchName']}  ←  ${transfer['toBranchName']}',
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
                    Text(NumberFormat('#,##0.###', 'en').format((item['quantity'] as num?) ?? 0)),
                  ],
                ),
              )),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
          ],
          const SizedBox(height: 16),
          if (status == 'pending')
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _working ? null : () => _act('cancel', successMessage: 'تم إلغاء التحويل'),
                    child: const Text('إلغاء التحويل'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _working ? null : () => _act('ship', successMessage: 'تم شحن التحويل'),
                    child: _working
                        ? const SizedBox(
                            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('شحن الآن'),
                  ),
                ),
              ],
            )
          else if (status == 'in_transit')
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton(
                onPressed: _working ? null : () => _act('receive', successMessage: 'تم تأكيد الاستلام'),
                child: _working
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('تأكيد الاستلام'),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _act(String action, {required String successMessage}) async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await ApiClient.instance.dio.post('/stock-transfers/${widget.transferId}/$action');
      ref.invalidate(transferDetailProvider(widget.transferId));
      if (mounted) Navigator.pop(context, successMessage);
    } catch (e) {
      setState(() => _error = _dioErrorMessage(e, 'تعذّر تنفيذ العملية'));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }
}

// ---------------------------------------------------------------------------
// إنشاء تحويل جديد
// ---------------------------------------------------------------------------

class _TransferLine {
  _TransferLine({required this.productId, required this.name});
  final String productId;
  final String name;
  double quantity = 1;
}

class _CreateTransferDialog extends ConsumerStatefulWidget {
  const _CreateTransferDialog();

  @override
  ConsumerState<_CreateTransferDialog> createState() => _CreateTransferDialogState();
}

class _CreateTransferDialogState extends ConsumerState<_CreateTransferDialog> {
  final _searchController = TextEditingController();
  final List<_TransferLine> _lines = [];
  String? _fromBranchId;
  String? _toBranchId;
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
      ref.read(transferProductSearchProvider.notifier).state = value;
    });
  }

  /// دعم قارئ الباركود (جهاز HID يكتب الرمز ثم يضغط Enter): عند تطابق وحيد
  /// يُضاف الصنف مباشرة بدل انتظار نقرة يدوية — نفس نمط شاشة نقطة البيع.
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
        ref.read(transferProductSearchProvider.notifier).state = '';
      }
    } catch (_) {
      // تُترك الأخطاء لطلب البحث العادي عبر transferProductResultsProvider
    }
  }

  void _addLine(Map<String, dynamic> product) {
    final id = product['id'] as String;
    final existing = _lines.where((l) => l.productId == id);
    setState(() {
      if (existing.isNotEmpty) {
        existing.first.quantity += 1;
      } else {
        _lines.add(_TransferLine(productId: id, name: product['name'] as String? ?? ''));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final branchesAsync = ref.watch(branchesProvider);
    final resultsAsync = ref.watch(transferProductResultsProvider);

    return AdaptiveDialog(
      title: 'إنشاء تحويل مخزون',
      maxWidth: 460,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('إنشاء'),
        ),
      ],
      body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              branchesAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => const Text('تعذّر تحميل الفروع'),
                data: (branches) => Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _fromBranchId,
                        decoration: const InputDecoration(labelText: 'من فرع'),
                        items: branches
                            .map((b) =>
                                DropdownMenuItem(value: b['id'] as String, child: Text(b['name'] as String)))
                            .toList(),
                        onChanged: (v) => setState(() => _fromBranchId = v),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _toBranchId,
                        decoration: const InputDecoration(labelText: 'إلى فرع'),
                        items: branches
                            .map((b) =>
                                DropdownMenuItem(value: b['id'] as String, child: Text(b['name'] as String)))
                            .toList(),
                        onChanged: (v) => setState(() => _toBranchId = v),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _searchController,
                onChanged: _onSearch,
                onSubmitted: _onSearchSubmitted,
                decoration: const InputDecoration(
                    hintText: 'ابحث أو امسح باركود صنف لإضافته...', prefixIcon: Icon(Icons.search, size: 18)),
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
                              subtitle: Text('متوفر: ${(p['quantity'] as num?) ?? 0}'),
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
                ..._lines.map((line) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                              child:
                                  Text(line.name, style: AppTextStyles.bodyMd(color: AppColors.textPrimary))),
                          IconAction(
                            icon: Icons.remove_circle_outline,
                            iconSize: 18,
                            dense: true,
                            tooltip: line.quantity > 1
                                ? 'إنقاص كمية ${line.name}'
                                : 'إزالة ${line.name} من التحويل',
                            onPressed: () => setState(() {
                              if (line.quantity > 1) {
                                line.quantity -= 1;
                              } else {
                                _lines.remove(line);
                              }
                            }),
                          ),
                          SizedBox(
                              width: 32,
                              child: Text(line.quantity.toStringAsFixed(0), textAlign: TextAlign.center)),
                          IconAction(
                            icon: Icons.add_circle_outline,
                            iconSize: 18,
                            dense: true,
                            tooltip: 'زيادة كمية ${line.name}',
                            onPressed: () => setState(() => line.quantity += 1),
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
    );
  }

  Future<void> _submit() async {
    if (_fromBranchId == null || _toBranchId == null) {
      setState(() => _error = 'اختر الفرعين');
      return;
    }
    if (_fromBranchId == _toBranchId) {
      setState(() => _error = 'لا يمكن التحويل لنفس الفرع');
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
      await ApiClient.instance.dio.post('/stock-transfers', data: {
        'fromBranchId': _fromBranchId,
        'toBranchId': _toBranchId,
        'lines': _lines.map((l) => {'productId': l.productId, 'quantity': l.quantity}).toList(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = _dioErrorMessage(e, 'تعذّر إنشاء التحويل'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
