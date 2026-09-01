import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/printing/report_printer.dart';
import '../../../core/theme/branding_provider.dart';
import '../../../core/time/app_clock.dart';
import '../data/accounting_providers.dart';

final _money = NumberFormat('#,##0.00', 'en');

String _orgName(WidgetRef ref) =>
    ref.read(brandingProvider).valueOrNull?.displayName ?? 'إتقان ERP';

/// زرّ طباعة دفترٍ محاسبي — واحدٌ لكل تبويب.
///
/// **الفجوة التي يسدّها:** الدفاتر تُقرأ على الشاشة ولا تُطبع. ومحاسبٌ
/// يُراجَع، أو مصرفٌ يطلب ميزانية، أو مصلحةُ ضرائب تطلب ميزان مراجعة —
/// كلّهم يطلبون ورقاً. فكان الحلّ تصوير الشاشة، أو نقل الأرقام باليد إلى
/// جدول ثانٍ يُخطئ فيه الناقل ولا يُكتشف.
///
/// وهذا أشدّ في الدفاتر منه في التقارير: تقريرُ مبيعاتٍ خاطئ يُراجَع من
/// الشاشة، أمّا ميزانٌ نُقل بيد فيصير مستنداً يُعتمد عليه سنةً كاملة.
class PrintLedgerButton extends ConsumerStatefulWidget {
  const PrintLedgerButton({super.key, required this.onPrint, this.label = 'طباعة'});

  final Future<void> Function() onPrint;
  final String label;

  @override
  ConsumerState<PrintLedgerButton> createState() => _PrintLedgerButtonState();
}

class _PrintLedgerButtonState extends ConsumerState<PrintLedgerButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) => TextButton.icon(
        onPressed: _busy
            ? null
            : () async {
                setState(() => _busy = true);
                try {
                  await widget.onPrint();
                } catch (e) {
                  // المُرسِل يُلتقط قبل الانتظار: بعده قد تكون الشاشة
                  // أُغلقت، وقراءة السياق حينها استثناء.
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('تعذّرت الطباعة: $e')),
                  );
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
              },
        icon: _busy
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.print_outlined, size: 18),
        label: Text(widget.label),
      );
}

// ── الدفاتر ──────────────────────────────────────────────────────────────
//
// كلٌّ منها يقرأ من نفس المُوفِّر الذي تعرضه الشاشة — لا استعلامٍ ثانٍ.
// ورقةٌ تُطبع من مصدرٍ غير الذي على الشاشة تفترق عنه أوّل مرّة يتغيّر
// أحدهما، فيُوقَّع على ورقةٍ لا تطابق ما رآه من وقّعها.

Future<void> printChartOfAccounts(WidgetRef ref) async {
  final accounts = await ref.read(chartOfAccountsProvider.future);
  await printReport(
    title: 'دليل الحسابات',
    orgName: _orgName(ref),
    to: AppClock.now(),
    facts: [('عدد الحسابات', '${accounts.length}')],
    columns: const ['الرمز', 'الاسم', 'النوع', 'قابل للترحيل'],
    rows: [
      for (final a in accounts)
        [
          '${a['code'] ?? ''}',
          '${a['name'] ?? ''}',
          _typeLabel('${a['type'] ?? ''}'),
          (a['isPostable'] as bool? ?? false) ? 'نعم' : '—',
        ],
    ],
  );
}

Future<void> printJournal(WidgetRef ref) async {
  final entries = await ref.read(journalProvider.future);
  final rows = <ReportRow>[];
  for (final e in entries) {
    final lines = (e['lines'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    for (final l in lines) {
      rows.add([
        '${e['number'] ?? ''}',
        _date(e['entryDate']),
        '${l['accountCode'] ?? ''} ${l['accountName'] ?? ''}',
        _amount(l['debit']),
        _amount(l['credit']),
        '${e['description'] ?? ''}',
      ]);
    }
  }
  await printReport(
    title: 'دفتر اليومية',
    orgName: _orgName(ref),
    to: AppClock.now(),
    facts: [('عدد القيود', '${entries.length}')],
    columns: const ['القيد', 'التاريخ', 'الحساب', 'مدين', 'دائن', 'البيان'],
    rows: rows,
    note: 'القيود لا تُعدَّل ولا تُحذف — التصحيح بقيدٍ عكسي.',
  );
}

Future<void> printTrialBalance(WidgetRef ref) async {
  final data = await ref.read(trialBalanceProvider.future);
  final rows = (data['rows'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  final debit = (data['totalDebit'] as num?)?.toDouble() ?? 0;
  final credit = (data['totalCredit'] as num?)?.toDouble() ?? 0;
  await printReport(
    title: 'ميزان المراجعة',
    orgName: _orgName(ref),
    to: AppClock.now(),
    facts: [
      ('إجمالي المدين', _money.format(debit)),
      ('إجمالي الدائن', _money.format(credit)),
      // الحكم على الورقة لا في رأس قارئها: من يستلمها يسأل «هل يوازن؟».
      ('الحالة', (debit - credit).abs() < 0.01 ? 'متوازن' : 'غير متوازن'),
    ],
    columns: const ['الرمز', 'الحساب', 'مدين', 'دائن'],
    rows: [
      for (final r in rows)
        [
          '${r['code'] ?? ''}',
          '${r['name'] ?? ''}',
          _amount(r['debit']),
          _amount(r['credit']),
        ],
    ],
  );
}

Future<void> printIncomeStatement(WidgetRef ref) async {
  final data = await ref.read(incomeStatementProvider.future);
  final revenue = (data['revenues'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  final expenses = (data['expenses'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  final net = (data['netIncome'] as num?)?.toDouble() ?? 0;

  final rows = <ReportRow>[
    for (final r in revenue)
      ['إيراد', '${r['code'] ?? ''}', '${r['name'] ?? ''}', _amount(r['amount'])],
    for (final r in expenses)
      ['استخدام', '${r['code'] ?? ''}', '${r['name'] ?? ''}', _amount(r['amount'])],
  ];

  await printReport(
    title: 'قائمة الدخل',
    orgName: _orgName(ref),
    from: _parse(data['from']),
    to: _parse(data['to']) ?? AppClock.now(),
    facts: [
      // «خسارة» كلمةً لا رقماً سالباً: السالب يُقرأ مرّتين قبل أن يُفهَم.
      (net < 0 ? 'صافي الخسارة' : 'صافي الربح', _money.format(net.abs())),
    ],
    columns: const ['البند', 'الرمز', 'الحساب', 'المبلغ'],
    rows: rows,
  );
}

Future<void> printBalanceSheet(WidgetRef ref) async {
  final data = await ref.read(balanceSheetProvider.future);
  final assets = (data['assets'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  final liabilities = (data['liabilities'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  final equity = (data['equity'] as List?)?.cast<Map<String, dynamic>>() ?? const [];

  await printReport(
    title: 'الميزانية العمومية',
    orgName: _orgName(ref),
    to: _parse(data['asOf']) ?? AppClock.now(),
    facts: [
      ('الأصول', _amount(data['totalAssets'])),
      ('الخصوم', _amount(data['totalLiabilities'])),
      ('حقوق الملكية', _amount(data['totalEquity'])),
    ],
    columns: const ['القسم', 'الرمز', 'الحساب', 'المبلغ'],
    rows: [
      for (final r in assets)
        ['أصول', '${r['code'] ?? ''}', '${r['name'] ?? ''}', _amount(r['amount'])],
      for (final r in liabilities)
        ['خصوم', '${r['code'] ?? ''}', '${r['name'] ?? ''}', _amount(r['amount'])],
      for (final r in equity)
        ['ملكية', '${r['code'] ?? ''}', '${r['name'] ?? ''}', _amount(r['amount'])],
    ],
  );
}

// ── مساعدات ──────────────────────────────────────────────────────────────

String _typeLabel(String t) => switch (t) {
      'asset' => 'أصول',
      'liability' => 'خصوم',
      'equity' => 'حقوق ملكية',
      'revenue' => 'إيرادات',
      'expense' => 'مصروفات',
      _ => t,
    };

String _amount(Object? v) {
  final n = (v as num?)?.toDouble() ?? 0;
  return n == 0 ? '—' : _money.format(n);
}

DateTime? _parse(Object? v) => v == null ? null : DateTime.tryParse('$v');

String _date(Object? v) {
  final d = _parse(v);
  return d == null ? '' : DateFormat('yyyy-MM-dd').format(d);
}
