import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../core/pdf/arabic_pdf_theme.dart';
import '../../../core/network/api_client.dart';
import '../../../core/responsive/adaptive_scaffold.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/data_table_widget.dart';
import '../data/audit_log_providers.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../core/auth/permissions.dart';
import '../../../shared/widgets/pagination_bar.dart';

const _actionLabels = {
  'product.deleted': 'حذف صنف',
  'product.stock_adjusted': 'تعديل مخزون',
  'supplier.deleted': 'حذف مورد',
  'customer.deleted': 'حذف عميل',
  'customer.wallet_adjusted': 'تعديل رصيد محفظة',
  'category.deleted': 'حذف فئة',
  'invoice.refunded': 'استرجاع فاتورة',
  'customer.restored': 'استرجاع عميل',
  'product.restored': 'استرجاع صنف',
  'sponsor.deleted': 'حذف جهة راعية',
  'supplier.restored': 'استرجاع مورد',
  'sponsor.restored': 'استرجاع جهة راعية',
};

/// أي عمليات حذفٍ يمكن التراجع عنها من هنا، وبأي نقطة.
///
/// <para><b>سبب وجودها:</b> نافذة الحذف تَعِد صراحةً «يمكن استرجاعه لاحقاً
/// من سجل التدقيق»، ولم يكن في السجلّ زرٌّ ولا في الخادم نقطة. فمن حذف
/// عميلاً بالخطأ وثِق بالوعد ثم لم يجد شيئاً.</para>
///
/// <para><b>وما ليس هنا صنفان لا صنف واحد:</b> محذوفٌ حذفاً ناعماً بلا
/// طريقٍ إليه — وهو عطبٌ يُصلَح بإضافة سطر هنا ونقطةٍ هناك — ومحذوفٌ
/// حذفاً فعلياً (الفئة، الحساب، المرفق) لا يُعيده سطر: صفُّه ذهب من
/// القاعدة، وملفُّ المرفق من القرص معه. فلا يُوضع في هذه القائمة ما لا
/// نقطةَ له، وإلا وعد الزرُّ بما يردّه الخادم بـ404.</para>
const _restorableActions = {
  'customer.deleted': ('/customers', 'العميل'),
  'product.deleted': ('/products', 'الصنف'),
  'supplier.deleted': ('/suppliers', 'المورّد'),
  'sponsor.deleted': ('/sponsors', 'الجهة الراعية'),
};

const _entityTableLabels = {
  'products': 'الأصناف',
  'stock_levels': 'المخزون',
  'suppliers': 'الموردون',
  'sponsors': 'الجهات الراعية',
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

    // حارس على مستوى الوحدة لا الزر: الخادم يحرس هذا الـController
    // كاملاً، فبلا الصلاحية لا توجد بيانات تُعرض أصلاً — وعرض جدول
    // فارغ هنا كان يُفهَم كـ«لا توجد سجلات» لا كـ«ليست لك صلاحية».
    if (!ref.perms.can(Perm.auditLogView)) {
      return const AdaptiveScaffold(
        title: 'سجل التدقيق',
        activeRoute: '/audit-log',
        body: NoPermissionView(moduleName: 'سجل التدقيق'),
      );
    }


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
            loading: () => const TableSkeleton(),
            error: (err, _) => _ErrorBox(onRetry: () => ref.invalidate(auditLogProvider)),
            data: (result) {
              final items = List<Map<String, dynamic>>.from(result['items'] as List);
              final totalCount = result['totalCount'] as int? ?? items.length;
              final pageSize = result['pageSize'] as int? ?? auditLogPageSize;

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
                  // الشريط المشترك بدل نسخة يدوية: النسخة السابقة كانت
                  // تستعمل chevron_right لـ«السابق»، وهي تنعكس تلقائياً في
                  // العربية فتشير يساراً — أي عكس المطلوب. وكانت تعرض رقم
                  // الصفحة وحده بلا العدد الكلي المعروض.
                  PaginationBar(
                    page: page,
                    pageSize: pageSize,
                    totalCount: totalCount,
                    onPageChanged: (p) => ref.read(auditLogPageProvider.notifier).state = p,
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
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // الاسترجاع بجوار التفاصيل لا داخلها: من يبحث عن المحذوف يمرّ
          // على السجلّ بعينه، وإخفاء الزرّ خطوةً أعمق يجعله غير موجود
          // عملياً — وهو ما كان.
          if (_restorableActions.containsKey(log['action']) && log['entityId'] != null)
            IconButton(
              tooltip: 'استرجاع',
              icon: const Icon(Icons.restore_from_trash_outlined, size: 18),
              onPressed: () => _restore(context, log),
            ),
          IconButton(
            tooltip: 'عرض التفاصيل',
            icon: const Icon(Icons.visibility_outlined, size: 18),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => _AuditLogDetailDialog(log: log),
            ),
          ),
        ],
      ),
    ];
  }

  /// يستدعي نقطة الاسترجاع ويُظهر ما قاله الخادم.
  ///
  /// <para>ورسالة الخادم تُعرض كما هي: قد يكون الهاتف صار لعميل آخر أو
  /// الباركود لصنفٍ آخر — وهي أسبابٌ يفهمها المستخدم ويعالجها، بخلاف
  /// «تعذّر الاسترجاع» التي تتركه واقفاً.</para>
  Future<void> _restore(BuildContext context, Map<String, dynamic> log) async {
    final entry = _restorableActions[log['action']]!;
    final id = log['entityId'] as String;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('استرجاع ${entry.$2}'),
        content: Text('سيعود ${entry.$2} إلى القوائم برصيده وحركاته كما كان.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('تراجع')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('استرجاع')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ApiClient.instance.dio.post('${entry.$1}/$id/restore');
      if (!context.mounted) return;
      ref.invalidate(auditLogProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('عاد ${entry.$2}')),
      );
    } catch (e) {
      if (!context.mounted) return;
      final message = e is DioException && e.response?.data is Map
          ? (e.response!.data as Map)['message'] as String? ?? 'تعذّر الاسترجاع'
          : 'تعذّر الاسترجاع';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
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

  String _formatValue(dynamic value) {
    if (value == null) return '—';
    if (value is bool) return value ? 'نعم' : 'لا';
    if (value is num) {
      if (value is int) return value.toString();
      return (value as double).toStringAsFixed(2);
    }
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    try {
      final decoded = json.decode(raw);
      if (decoded is Map<String, dynamic>) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: decoded.entries
                .map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 100,
                        child: Text(
                          '${e.key}:',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          _formatValue(e.value),
                          style: AppTextStyles.bodyMd(),
                        ),
                      ),
                    ],
                  ),
                ))
                .toList(),
          ),
        );
      }
    } catch (_) {
      // تحويل فاشل — عرض JSON مُنسّق بدلاً من النص الخام
    }

    // احتياطي: عرض JSON منسّق
    String formatted = raw;
    try {
      formatted = const JsonEncoder.withIndent('  ').convert(json.decode(raw));
    } catch (_) {}

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(
          formatted,
          style: AppTextStyles.bodyMd(color: AppColors.textPrimary),
        ),
      ),
    );
  }
}
