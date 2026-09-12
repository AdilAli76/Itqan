import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/network/api_client.dart';
import '../../../core/printing/receipt_template.dart';
import '../../../core/printing/receipt_printer.dart';
import '../../../core/responsive/adaptive_scaffold.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/branding_provider.dart';
import '../../../shared/widgets/currency_badge.dart';
import '../../../shared/widgets/data_table_widget.dart';
import '../../../shared/widgets/list_toolbar.dart';
import '../data/invoices_providers.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/pagination_bar.dart';
import '../../../core/auth/permissions.dart';

const _statusLabels = {
  'completed': 'مكتملة',
  'pending': 'معلّقة',
  'cancelled': 'ملغاة',
  'refunded': 'مسترجعة',
};

const _typeLabels = {'sale': 'بيع', 'return': 'مرتجع'};

const _paymentLabels = {
  'cash': 'نقداً',
  'card': 'بطاقة',
  'customer_wallet': 'محفظة العميل',
  'credit': 'آجل',
  '-': '-',
  'متعدد': 'متعدد',
};

String _statusLabel(String s) => _statusLabels[s] ?? s;
String _typeLabel(String s) => _typeLabels[s] ?? s;
String _paymentLabel(String s) => _paymentLabels[s] ?? s;

class InvoicesScreen extends ConsumerStatefulWidget {
  const InvoicesScreen({super.key});

  @override
  ConsumerState<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends ConsumerState<InvoicesScreen> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// أي تغيير في البحث أو الفلاتر يُعيد الترقيم للصفحة الأولى — النتيجة
  /// الجديدة قد تكون أقصر من موضع المستخدم الحالي فيقع خارجها.
  void _resetPage() => ref.read(invoicesPageProvider.notifier).state = 1;

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(invoiceSearchProvider.notifier).state = value;
      _resetPage();
    });
  }

  @override
  Widget build(BuildContext context) {
    final invoicesAsync = ref.watch(invoicesProvider);
    final status = ref.watch(invoiceStatusFilterProvider);
    final type = ref.watch(invoiceTypeFilterProvider);

    return AdaptiveScaffold(
      title: 'الفواتير',
      activeRoute: '/invoices',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // شريط الأدوات المحسّن مع البحث والفلاتر والإجراءات
          ListToolbar(
            searchPlaceholder: 'ابحث برقم الفاتورة أو اسم العميل...',
            onSearchChanged: _onSearch,
            onAddPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('الانتقال لإنشاء فاتورة جديدة...')),
              );
            },
            onRefreshPressed: () => ref.invalidate(invoicesProvider),
            onPrintPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('جاري تحضير الطباعة...')),
              );
            },
            onExportPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('جاري تصدير البيانات...')),
              );
            },
            filterOptions: [
              FilterOption(label: 'الكل', value: ''),
              FilterOption(label: 'معلقة', value: 'pending'),
              FilterOption(label: 'مكتملة', value: 'completed'),
              FilterOption(label: 'مسترجعة', value: 'refunded'),
              FilterOption(label: 'ملغاة', value: 'cancelled'),
            ],
            onFilterChanged: (status) {
              ref.read(invoiceStatusFilterProvider.notifier).state =
                  status?.isEmpty ?? true ? null : status;
              _resetPage();
            },
            showActionButtons: true,
            showAddButton: true,
            addButtonLabel: 'فاتورة جديدة',
            isCompact: Breakpoints.isMobile(context),
          ),
          const SizedBox(height: 16),
          invoicesAsync.when(
            loading: () => const TableSkeleton(),
            error: (err, _) => _ErrorBox(
              message: 'تعذّر تحميل الفواتير',
              onRetry: () => ref.invalidate(invoicesProvider),
            ),
            data: (invoices) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppDataTable(
                  title: 'الفواتير (${invoices.totalCount})',
                  onSearch: _onSearch,
                  columns: const [
                    AppColumn('رقم الفاتورة'),
                    AppColumn('النوع'),
                    AppColumn('الحالة'),
                    AppColumn('العميل'),
                    AppColumn('عدد الأصناف'),
                    AppColumn('طريقة الدفع'),
                    AppColumn('الإجمالي'),
                    AppColumn('التاريخ'),
                    AppColumn(''),
                  ],
                  rows: invoices.items.map((i) => _invoiceRow(context, i)).toList(),
                ),
                PaginationBar(
                  page: invoices.page,
                  pageSize: invoices.pageSize,
                  totalCount: invoices.totalCount,
                  onPageChanged: (p) => ref.read(invoicesPageProvider.notifier).state = p,
                ),
              ],
            ),
          ),

          // ✅ تم تطبيق ListToolbar أعلاه
        ],
      ),
    );
  }

  List<Widget> _invoiceRow(BuildContext context, Map<String, dynamic> i) {
    final createdAt = DateTime.tryParse(i['createdAt'] as String? ?? '');
    return [
      Text(i['invoiceNumber'] as String? ?? ''),
      _tag(
          _typeLabel(i['invoiceType'] as String? ?? ''),
          i['invoiceType'] == 'return' ? AppColors.info : AppColors.textSecondary,
          i['invoiceType'] == 'return' ? AppColors.infoBg : AppColors.surfaceAlt),
      _statusTag(i['status'] as String? ?? ''),
      Text(i['customerName'] as String? ?? 'زبون نقدي'),
      Text('${i['itemCount'] ?? 0}'),
      Text(_paymentLabel(i['paymentMethod'] as String? ?? '-')),
      CurrencyBadge(amount: (i['totalAmount'] as num?)?.toDouble() ?? 0),
      Text(createdAt != null ? DateFormat('yyyy-MM-dd HH:mm').format(createdAt) : '-'),
      IconButton(
        tooltip: 'عرض التفاصيل',
        icon: const Icon(Icons.visibility_outlined, size: 18),
        onPressed: () => showDialog(
          context: context,
          builder: (_) => _InvoiceDetailDialog(invoiceId: i['id'] as String),
        ),
      ),
    ];
  }

  Widget _statusTag(String status) {
    Color fg;
    Color bg;
    switch (status) {
      case 'completed':
        fg = AppColors.success;
        bg = AppColors.successBg;
        break;
      case 'refunded':
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
    return _tag(_statusLabel(status), fg, bg);
  }

  Widget _tag(String label, Color fg, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
        child: Text(label, style: AppTextStyles.labelMd(color: fg)),
      );
}

class _FilterDropdown<T> extends StatelessWidget {
  const _FilterDropdown(
      {required this.label, required this.value, required this.items, required this.onChanged});
  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          hint: Text(label),
          items: items.entries.map((e) => DropdownMenuItem<T>(value: e.key, child: Text(e.value))).toList(),
          onChanged: (v) => onChanged(v as T),
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Text(message, style: AppTextStyles.bodyMd(color: AppColors.danger)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
        ],
      ),
    );
  }
}

String _dioErrorMessage(Object error, String fallback) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] is String) return data['message'] as String;
  }
  return fallback;
}

// ---------------------------------------------------------------------------
// تفاصيل الفاتورة + الاسترجاع
// ---------------------------------------------------------------------------

class _InvoiceDetailDialog extends ConsumerStatefulWidget {
  const _InvoiceDetailDialog({required this.invoiceId});
  final String invoiceId;

  @override
  ConsumerState<_InvoiceDetailDialog> createState() => _InvoiceDetailDialogState();
}

class _InvoiceDetailDialogState extends ConsumerState<_InvoiceDetailDialog> {
  bool _refunding = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(invoiceDetailProvider(widget.invoiceId));

    return AlertDialog(
      title: const Text('تفاصيل الفاتورة'),
      content: SizedBox(
        width: 480,
        child: detailAsync.when(
          loading: () => const SizedBox(
            height: 160,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (err, _) => const SizedBox(
            height: 80,
            child: Center(child: Text('تعذّر تحميل تفاصيل الفاتورة')),
          ),
          data: (invoice) => _buildContent(context, invoice),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
      ],
    );
  }

  Widget _buildContent(BuildContext context, Map<String, dynamic> invoice) {
    final items = List<Map<String, dynamic>>.from(invoice['items'] as List? ?? []);
    final payments = List<Map<String, dynamic>>.from(invoice['payments'] as List? ?? []);
    final createdAt = DateTime.tryParse(invoice['createdAt'] as String? ?? '');
    final canRefund = invoice['invoiceType'] == 'sale' && invoice['status'] != 'refunded';

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(invoice['invoiceNumber'] as String? ?? '', style: AppTextStyles.headlineMd()),
              ),
              Text(_typeLabel(invoice['invoiceType'] as String? ?? ''), style: AppTextStyles.bodyMd()),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'العميل: ${invoice['customerName'] as String? ?? 'زبون نقدي'} — '
            '${createdAt != null ? DateFormat('yyyy-MM-dd HH:mm').format(createdAt) : ''}',
            style: AppTextStyles.bodyMd(),
          ),
          const Divider(height: 24),
          ...items.map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${item['productName']}  x${NumberFormat('#,##0.###', 'en').format((item['quantity'] as num?) ?? 0)}',
                        style: AppTextStyles.bodyMd(color: AppColors.textPrimary),
                      ),
                    ),
                    CurrencyBadge(amount: (item['lineTotal'] as num?)?.toDouble() ?? 0),
                  ],
                ),
              )),
          const Divider(height: 24),
          _summaryRow('الإجمالي الفرعي', (invoice['subtotal'] as num?)?.toDouble() ?? 0),
          _summaryRow('الضريبة', (invoice['taxAmount'] as num?)?.toDouble() ?? 0),
          _summaryRow('الخصم', (invoice['discountAmount'] as num?)?.toDouble() ?? 0),
          const SizedBox(height: 4),
          Row(
            children: [
              Text('الإجمالي المستحق', style: AppTextStyles.headlineMd()),
              const Spacer(),
              CurrencyBadge(amount: (invoice['totalAmount'] as num?)?.toDouble() ?? 0),
            ],
          ),
          if (payments.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('الدفع', style: AppTextStyles.labelMd()),
            ...payments.map((p) => Text(
                  '${_paymentLabel(p['method'] as String? ?? '')} — ${NumberFormat('#,##0.00', 'en').format((p['amount'] as num?) ?? 0)}',
                  style: AppTextStyles.bodyMd(),
                )),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => _printReceipt(invoice),
                icon: const Icon(Icons.print_outlined, size: 18),
                label: const Text('طباعة الإيصال'),
              ),
              if (canRefund) ...[
                const SizedBox(width: 10),
                Can(
                  permission: Perm.invoicesRefund,
                  child: OutlinedButton.icon(
                    onPressed: _refunding ? null : () => _confirmRefund(context),
                    icon: _refunding
                        ? const SizedBox(
                            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.keyboard_return, size: 18),
                    label: const Text('استرجاع الفاتورة'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _printReceipt(Map<String, dynamic> invoice) async {
    final branding = ref.read(brandingProvider).valueOrNull;
    try {
      final template = await ref.read(receiptTemplateProvider.future);
      final logoBytes = await ref.read(receiptLogoProvider.future);
      await printInvoiceReceipt(
        invoice: invoice,
        orgName: branding?.displayName ?? 'إتقان ERP',
        currencySymbol: branding?.currencySymbol ?? 'د.ل',
        template: template,
        logoBytes: logoBytes,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تعذّر تحضير الإيصال للطباعة')));
      }
    }
  }

  Widget _summaryRow(String label, double amount) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Text(label, style: AppTextStyles.bodyMd()),
            const Spacer(),
            CurrencyBadge(amount: amount),
          ],
        ),
      );

  Future<void> _confirmRefund(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('استرجاع الفاتورة'),
        content: const Text(
            'سيتم إنشاء فاتورة مرتجع وإعادة الكمية للمخزون، ورد المبلغ لمحفظة العميل إن كان الدفع منها. الدفع نقداً/بطاقة يُرد يدوياً. متابعة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('استرجاع')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _refunding = true;
      _error = null;
    });

    try {
      await ApiClient.instance.dio.post('/invoices/${widget.invoiceId}/refund');
      ref.invalidate(invoicesProvider);
      ref.invalidate(invoiceDetailProvider(widget.invoiceId));
      if (context.mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = _dioErrorMessage(e, 'تعذّر استرجاع الفاتورة'));
    } finally {
      if (mounted) setState(() => _refunding = false);
    }
  }
}
