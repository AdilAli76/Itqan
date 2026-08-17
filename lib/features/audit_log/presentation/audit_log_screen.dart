import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../core/pdf/arabic_pdf_theme.dart';
import '../../../core/responsive/adaptive_scaffold.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/data_table_widget.dart';
import '../data/audit_log_providers.dart';

const _actionLabels = {
  'product.deleted': 'حذف صنف',
  'product.stock_adjusted': 'تعديل مخزون',
  'supplier.deleted': 'حذف مورد',
  'customer.deleted': 'حذف عميل',
  'customer.wallet_adjusted': 'تعديل رصيد محفظة',
  'category.deleted': 'حذف فئة',
  'invoice.refunded': 'استرجاع فاتورة',
};

const _entityTableLabels = {
  'products': 'الأصناف',
  'stock_levels': 'المخزون',
  'suppliers': 'الموردون',
  'customers': 'العملاء',
  'product_categories': 'الفئات',
  'invoices': 'الفواتير',
};

String _actionLabel(String action) => _actionLabels[action] ?? action;
String _entityTableLabel(String table) => _entityTableLabels[table] ?? table;

class AuditLogScreen extends ConsumerStatefulWidget {
  const AuditLogScreen({super.key});

  @override
  ConsumerState<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends ConsumerState<AuditLogScreen> {
  Timer? _debounce;
  bool _exporting = false;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(auditLogSearchProvider.notifier).state = value;
      ref.read(auditLogPageProvider.notifier).state = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final logsAsync = ref.watch(auditLogProvider);
    final entityTablesAsync = ref.watch(auditLogEntityTablesProvider);
    final entityFilter = ref.watch(auditLogEntityFilterProvider);
    final page = ref.watch(auditLogPageProvider);

    return AdaptiveScaffold(
      title: 'سجل التدقيق',
      activeRoute: '/audit-log',
      actions: [
        OutlinedButton.icon(
          onPressed: _exporting ? null : _exportPdf,
          icon: _exporting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.picture_as_pdf_outlined, size: 18),
          label: const Text('تصدير/طباعة PDF'),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          entityTablesAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (tables) => _EntityFilterDropdown(
              tables: tables,
              value: entityFilter,
              onChanged: (v) {
                ref.read(auditLogEntityFilterProvider.notifier).state = v;
                ref.read(auditLogPageProvider.notifier).state = 1;
              },
            ),
          ),
          const SizedBox(height: 16),
          logsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (err, _) => _ErrorBox(onRetry: () => ref.invalidate(auditLogProvider)),
            data: (result) {
              final items = List<Map<String, dynamic>>.from(result['items'] as List);
              final totalCount = result['totalCount'] as int? ?? items.length;
              final pageSize = result['pageSize'] as int? ?? auditLogPageSize;
              final totalPages = totalCount == 0 ? 1 : ((totalCount - 1) ~/ pageSize) + 1;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppDataTable(
                    title: 'سجل التدقيق ($totalCount)',
                    onSearch: _onSearch,
                    columns: const [
                      AppColumn('التاريخ'),
                      AppColumn('المستخدم'),
                      AppColumn('العملية'),
                      AppColumn('الجدول'),
                      AppColumn(''),
                    ],
                    rows: items.map((log) => _logRow(context, log)).toList(),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'الصفحة السابقة',
                        icon: const Icon(Icons.chevron_right),
                        onPressed: page > 1 ? () => ref.read(auditLogPageProvider.notifier).state = page - 1 : null,
                      ),
                      Text('صفحة $page من $totalPages', style: AppTextStyles.bodyMd()),
                      IconButton(
                        tooltip: 'الصفحة التالية',
                        icon: const Icon(Icons.chevron_left),
                        onPressed: page < totalPages ? () => ref.read(auditLogPageProvider.notifier).state = page + 1 : null,
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  List<Widget> _logRow(BuildContext context, Map<String, dynamic> log) {
    final createdAt = DateTime.tryParse(log['createdAt'] as String? ?? '');
    return [
      Text(createdAt != null ? DateFormat('yyyy-MM-dd HH:mm').format(createdAt) : '-'),
      Text(log['userName'] as String? ?? '-'),
      Text(_actionLabel(log['action'] as String? ?? '')),
      Text(_entityTableLabel(log['entityTable'] as String? ?? '')),
      IconButton(
        tooltip: 'عرض التفاصيل',
        icon: const Icon(Icons.visibility_outlined, size: 18),
        onPressed: () => showDialog(
          context: context,
          builder: (_) => _AuditLogDetailDialog(log: log),
        ),
      ),
    ];
  }

  Future<void> _exportPdf() async {
    setState(() => _exporting = true);
    try {
      final logs = await fetchAuditLogExport(
        search: ref.read(auditLogSearchProvider),
        entityTable: ref.read(auditLogEntityFilterProvider),
      );

      final doc = pw.Document(theme: await arabicPdfTheme());
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          textDirection: pw.TextDirection.rtl,
          build: (context) => [
            pw.Text('سجل التدقيق', style: const pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('عدد الحركات: ${logs.length}', style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              headers: const ['التاريخ', 'المستخدم', 'العملية', 'الجدول'],
              data: logs.map((log) {
                final createdAt = DateTime.tryParse(log['createdAt'] as String? ?? '');
                return [
                  createdAt != null ? DateFormat('yyyy-MM-dd HH:mm').format(createdAt) : '-',
                  log['userName'] as String? ?? '-',
                  _actionLabel(log['action'] as String? ?? ''),
                  _entityTableLabel(log['entityTable'] as String? ?? ''),
                ];
              }).toList(),
              cellStyle: const pw.TextStyle(fontSize: 8),
              headerStyle: const pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
              cellAlignment: pw.Alignment.centerRight,
            ),
          ],
        ),
      );

      await Printing.layoutPdf(onLayout: (format) async => doc.save());
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذّر تصدير السجل')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}

class _EntityFilterDropdown extends StatelessWidget {
  const _EntityFilterDropdown({required this.tables, required this.value, required this.onChanged});
  final List<String> tables;
  final String? value;
  final ValueChanged<String?> onChanged;

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
        child: DropdownButton<String?>(
          value: value,
          hint: const Text('كل الجداول'),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('كل الجداول')),
            ...tables.map((t) => DropdownMenuItem<String?>(value: t, child: Text(_entityTableLabel(t)))),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.onRetry});
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
          Text('تعذّر تحميل سجل التدقيق', style: AppTextStyles.bodyMd(color: AppColors.danger)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
        ],
      ),
    );
  }
}

class _AuditLogDetailDialog extends StatelessWidget {
  const _AuditLogDetailDialog({required this.log});
  final Map<String, dynamic> log;

  @override
  Widget build(BuildContext context) {
    final createdAt = DateTime.tryParse(log['createdAt'] as String? ?? '');

    return AlertDialog(
      title: Text(_actionLabel(log['action'] as String? ?? '')),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'بواسطة: ${log['userName'] as String? ?? '-'} — ${createdAt != null ? DateFormat('yyyy-MM-dd HH:mm').format(createdAt) : ''}',
                style: AppTextStyles.bodyMd(),
              ),
              const SizedBox(height: 4),
              Text('الجدول: ${_entityTableLabel(log['entityTable'] as String? ?? '')}', style: AppTextStyles.bodyMd()),
              if (log['oldValues'] != null) ...[
                const SizedBox(height: 12),
                Text('قبل', style: AppTextStyles.labelMd()),
                const SizedBox(height: 4),
                _JsonBlock(raw: log['oldValues'] as String),
              ],
              if (log['newValues'] != null) ...[
                const SizedBox(height: 12),
                Text('بعد', style: AppTextStyles.labelMd()),
                const SizedBox(height: 4),
                _JsonBlock(raw: log['newValues'] as String),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
      ],
    );
  }
}

class _JsonBlock extends StatelessWidget {
  const _JsonBlock({required this.raw});
  final String raw;

  @override
  Widget build(BuildContext context) {
    String formatted = raw;
    try {
      formatted = const JsonEncoder.withIndent('  ').convert(json.decode(raw));
    } catch (_) {
      // نص غير قابل للتحليل كـ JSON (حالة غير متوقَّعة) — يُعرض كما هو.
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(8)),
      child: Text(formatted, style: AppTextStyles.bodyMd(color: AppColors.textPrimary)),
    );
  }
}
