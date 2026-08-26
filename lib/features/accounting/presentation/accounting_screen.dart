import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/permissions.dart';
import '../../../core/network/api_client.dart';
import '../../../core/responsive/adaptive_scaffold.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/app_surface.dart';
import '../data/accounting_providers.dart';

final _money = NumberFormat('#,##0.00', 'en');
final _date = DateFormat('yyyy-MM-dd');

const _typeLabels = {
  'asset': 'أصول',
  'liability': 'التزامات',
  'equity': 'حقوق ملكية',
  'expense': 'استخدامات',
  'revenue': 'إيرادات',
};

const _sourceLabels = {
  'invoice': 'فاتورة بيع',
  'invoice_return': 'مرتجع',
  'expense': 'مصروف',
  'wallet_top_up': 'شحن رصيد',
  'payment': 'سداد',
  'manual': 'قيد يدوي',
  'reversal': 'عكس قيد',
};

/// دليل الحسابات ودفتر اليومية وميزان المراجعة.
///
/// ثلاثة تبويبات لا ثلاث شاشات: المحاسب ينتقل بينها في الدقيقة الواحدة —
/// يرى رصيداً في الشجرة فيسأل «من أين جاء» فيفتح الدفتر عليه. وشاشاتٌ
/// منفصلة تجعل كل سؤال رحلةً في القائمة الجانبية.
class AccountingScreen extends ConsumerStatefulWidget {
  const AccountingScreen({super.key});

  @override
  ConsumerState<AccountingScreen> createState() => _AccountingScreenState();
}

class _AccountingScreenState extends ConsumerState<AccountingScreen>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 5, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      title: 'المحاسبة',
      activeRoute: '/accounting',
      // التبويبات تبني تخطيطها على الارتفاع المتاح، فلا تُلفّ بمُمرِّر:
      // الارتفاع غير المحدود يجعلها تفيض على الهاتف. وكل تبويب يمرّر محتواه
      // بنفسه — راجع AdaptiveScaffold.scrollable.
      scrollable: false,
      body: Column(
        children: [
          TabBar(
            controller: _tabs,
            // قابل للتمرير: خمسة تبويبات لا تسع عرض هاتف، والثابت يضغطها
            // حتى تُقصّ نصوصها.
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(text: 'دليل الحسابات'),
              Tab(text: 'دفتر اليومية'),
              Tab(text: 'ميزان المراجعة'),
              Tab(text: 'قائمة الدخل'),
              Tab(text: 'الميزانية'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _ChartTab(onOpenJournal: (accountId) {
                  ref.read(journalAccountFilterProvider.notifier).state = accountId;
                  _tabs.animateTo(1);
                }),
                const _JournalTab(),
                const _TrialBalanceTab(),
                const _IncomeStatementTab(),
                const _BalanceSheetTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  دليل الحسابات
// ═══════════════════════════════════════════════════════════════════════════

class _ChartTab extends ConsumerWidget {
  const _ChartTab({required this.onOpenJournal});

  final void Function(String accountId) onOpenJournal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(chartOfAccountsProvider);
    final canEdit = ref.watch(myPermissionsProvider).valueOrNull?.isSuperAdmin ?? false;

    return accountsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => _ErrorView(
        error: err,
        onRetry: () => ref.invalidate(chartOfAccountsProvider),
      ),
      data: (accounts) {
        if (accounts.isEmpty) {
          return _EmptyChart(canSeed: canEdit);
        }

        // الشجرة تُبنى مرّة من القائمة المسطّحة: الخادم يُرسلها مرتّبةً
        // بالرمز، والبناء هنا يُبقي الاستجابة بسيطة.
        final children = <String?, List<Map<String, dynamic>>>{};
        for (final a in accounts) {
          children.putIfAbsent(a['parentId'] as String?, () => []).add(a);
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final root in children[null] ?? const <Map<String, dynamic>>[])
              _AccountNode(
                account: root,
                children: children,
                depth: 0,
                onOpenJournal: onOpenJournal,
              ),
          ],
        );
      },
    );
  }
}

class _AccountNode extends StatefulWidget {
  const _AccountNode({
    required this.account,
    required this.children,
    required this.depth,
    required this.onOpenJournal,
  });

  final Map<String, dynamic> account;
  final Map<String?, List<Map<String, dynamic>>> children;
  final int depth;
  final void Function(String accountId) onOpenJournal;

  @override
  State<_AccountNode> createState() => _AccountNodeState();
}

class _AccountNodeState extends State<_AccountNode> {
  // الجذور مفتوحة والباقي مغلق: أربعة أقسام تُرى كلها، وفتحُ الشجرة كاملة
  // يعرض مئة سطر لا يريد أحدهم مئتها.
  late bool _open = widget.depth == 0;

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    final id = account['id'] as String;
    final kids = widget.children[id] ?? const <Map<String, dynamic>>[];
    final balance = (account['balance'] as num?)?.toDouble() ?? 0;
    final isPostable = account['isPostable'] as bool? ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: kids.isEmpty ? () => widget.onOpenJournal(id) : () => setState(() => _open = !_open),
          child: Padding(
            padding: EdgeInsetsDirectional.only(
              start: widget.depth * 20.0, top: 10, bottom: 10, end: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: kids.isEmpty
                      ? null
                      : Icon(_open ? Icons.expand_more : Icons.chevron_left, size: 18),
                ),
                SizedBox(
                  width: 64,
                  child: Text(account['code'] as String? ?? '',
                      style: AppTextStyles.currency(color: AppColors.textSecondary)),
                ),
                Expanded(
                  child: Text(
                    account['name'] as String? ?? '',
                    style: widget.depth == 0
                        ? AppTextStyles.headlineMd()
                        : AppTextStyles.bodyMd(color: AppColors.textPrimary),
                  ),
                ),
                // الرصيد بإشارة طبيعة الحساب — الالتزام رصيدُه الدائن موجب.
                // عرض الجميع بإشارة المدين يجعل كل الالتزامات سالبة، وهو
                // صحيح حسابياً ومربك لكل من يقرأ.
                Text(_money.format(balance),
                    style: AppTextStyles.currency(
                        color: balance == 0 ? AppColors.textMuted : AppColors.textPrimary)),
                if (!isPostable && kids.isNotEmpty)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 8),
                    child: Tooltip(
                      message: 'حساب تجميعي — لا يُرحَّل إليه مباشرةً',
                      child: Icon(Icons.folder_outlined, size: 14, color: AppColors.textMuted),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (_open)
          for (final child in kids)
            _AccountNode(
              account: child,
              children: widget.children,
              depth: widget.depth + 1,
              onOpenJournal: widget.onOpenJournal,
            ),
        if (widget.depth == 0) const Divider(height: 1),
      ],
    );
  }
}

class _EmptyChart extends ConsumerStatefulWidget {
  const _EmptyChart({required this.canSeed});
  final bool canSeed;

  @override
  ConsumerState<_EmptyChart> createState() => _EmptyChartState();
}

class _EmptyChartState extends ConsumerState<_EmptyChart> {
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('لا دليل حسابات بعد', style: AppTextStyles.headlineMd()),
            const SizedBox(height: 10),
            Text(
              'يُبذَر دليل عامل على الدليل المحاسبي الموحّد: الأصول، '
              'والالتزامات وحقوق الملكية، والاستخدامات، والإيرادات — '
              'مربوطاً بالبيع والمخزون جاهزاً. يوسّعه محاسبك بعد ذلك.',
              style: AppTextStyles.bodyMd(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
            ],
            const SizedBox(height: 20),
            if (widget.canSeed)
              FilledButton.icon(
                onPressed: _busy ? null : _seed,
                icon: const Icon(Icons.account_tree_outlined, size: 18),
                label: const Text('إنشاء الدليل الافتراضي'),
              )
            else
              Text('يُنشئه مدير النظام.', style: AppTextStyles.labelMd()),
          ],
        ),
      ),
    );
  }

  Future<void> _seed() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiClient.instance.dio.post('/accounting/accounts/seed');
      ref.invalidate(chartOfAccountsProvider);
    } catch (e) {
      setState(() => _error = _errorText(e, 'تعذّر إنشاء الدليل'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  دفتر اليومية
// ═══════════════════════════════════════════════════════════════════════════

class _JournalTab extends ConsumerWidget {
  const _JournalTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(journalProvider);
    final filter = ref.watch(journalAccountFilterProvider);

    return Column(
      children: [
        if (filter != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                const Icon(Icons.filter_alt_outlined, size: 16),
                const SizedBox(width: 6),
                Expanded(child: Text('قيود حساب واحد', style: AppTextStyles.labelMd())),
                TextButton(
                  onPressed: () =>
                      ref.read(journalAccountFilterProvider.notifier).state = null,
                  child: const Text('كل القيود'),
                ),
              ],
            ),
          ),
        Expanded(
          child: entriesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => _ErrorView(
              error: err,
              onRetry: () => ref.invalidate(journalProvider),
            ),
            data: (entries) {
              if (entries.isEmpty) {
                return Center(
                  child: Text('لا قيود بعد — تُنشأ آلياً مع أول فاتورة.',
                      style: AppTextStyles.bodyMd()),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: entries.length,
                itemBuilder: (_, i) => _EntryCard(entry: entries[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _EntryCard extends ConsumerWidget {
  const _EntryCard({required this.entry});
  final Map<String, dynamic> entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lines = (entry['lines'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final isReversed = entry['isReversed'] as bool? ?? false;
    final isReversal = entry['reversesEntryId'] != null;
    final canReverse = ref.watch(myPermissionsProvider).valueOrNull?.isSuperAdmin ?? false;

    return AppSurface(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('قيد ${entry['number']}', style: AppTextStyles.headlineMd()),
              const SizedBox(width: 10),
              _Chip(
                text: _sourceLabels[entry['source']] ?? '${entry['source']}',
                color: AppColors.info,
                background: AppColors.infoBg,
              ),
              // القيد المعكوس يبقى في الدفتر ويُوسَم — حرمة القيد: ما كُتب
              // لا يُمحى، ومن يقرأ يرى ما حدث لا ما بقي.
              if (isReversed) ...[
                const SizedBox(width: 6),
                _Chip(text: 'معكوس', color: AppColors.danger, background: AppColors.dangerBg),
              ],
              if (isReversal) ...[
                const SizedBox(width: 6),
                _Chip(text: 'قيد عكسي', color: AppColors.warning, background: AppColors.warningBg),
              ],
              const Spacer(),
              Text(_date.format(DateTime.tryParse('${entry['entryDate']}') ?? DateTime.now()),
                  style: AppTextStyles.labelMd()),
            ],
          ),
          const SizedBox(height: 4),
          Text(entry['description'] as String? ?? '', style: AppTextStyles.bodyMd()),
          const SizedBox(height: 12),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 60,
                    child: Text(line['accountCode'] as String? ?? '',
                        style: AppTextStyles.currency(color: AppColors.textSecondary)),
                  ),
                  Expanded(child: Text(line['accountName'] as String? ?? '',
                      style: AppTextStyles.bodyMd())),
                  SizedBox(
                    width: 100,
                    child: Text(
                      (line['debit'] as num?) != 0 ? _money.format(line['debit']) : '',
                      textAlign: TextAlign.end,
                      style: AppTextStyles.currency(),
                    ),
                  ),
                  SizedBox(
                    width: 100,
                    child: Text(
                      (line['credit'] as num?) != 0 ? _money.format(line['credit']) : '',
                      textAlign: TextAlign.end,
                      style: AppTextStyles.currency(),
                    ),
                  ),
                ],
              ),
            ),
          if (canReverse && !isReversed && !isReversal) ...[
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => _reverse(context, ref),
                icon: const Icon(Icons.undo, size: 16),
                label: const Text('عكس القيد'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _reverse(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('عكس القيد'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'لا يُعدَّل القيد ولا يُحذف. يُكتب قيدٌ مقابل يشير إليه، '
              'فيبقى الخطأ مرئياً وتصحيحه معه.',
              style: AppTextStyles.bodyMd(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'سبب العكس'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('عكس'),
          ),
        ],
      ),
    );
    if (reason == null || reason.isEmpty) return;

    try {
      await ApiClient.instance.dio
          .post('/accounting/journal/${entry['id']}/reverse', data: {'reason': reason});
      ref.invalidate(journalProvider);
      ref.invalidate(chartOfAccountsProvider);
      ref.invalidate(trialBalanceProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_errorText(e, 'تعذّر عكس القيد'))),
        );
      }
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  ميزان المراجعة
// ═══════════════════════════════════════════════════════════════════════════

class _TrialBalanceTab extends ConsumerWidget {
  const _TrialBalanceTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(trialBalanceProvider);

    return balanceAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => _ErrorView(
        error: err,
        onRetry: () => ref.invalidate(trialBalanceProvider),
      ),
      data: (data) {
        final rows = (data['rows'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
        final totalDebit = (data['totalDebit'] as num?)?.toDouble() ?? 0;
        final totalCredit = (data['totalCredit'] as num?)?.toDouble() ?? 0;
        final balanced = (totalDebit - totalCredit).abs() < 0.01;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // الحكم أولاً لا آخراً: من يفتح ميزان المراجعة يسأل سؤالاً
            // واحداً — «هل يوازن؟». وضعُه في الأسفل يعني تمريراً لمعرفته.
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: balanced ? AppColors.successBg : AppColors.dangerBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(balanced ? Icons.check_circle_outline : Icons.error_outline,
                      color: balanced ? AppColors.success : AppColors.danger),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      balanced
                          ? 'الميزان متوازن'
                          : 'الميزان مختلّ — فرق ${_money.format(totalDebit - totalCredit)}',
                      style: AppTextStyles.headlineMd(
                          color: balanced ? AppColors.success : AppColors.danger),
                    ),
                  ),
                ],
              ),
            ),
            if (!balanced) ...[
              const SizedBox(height: 8),
              Text(
                'النظام يمنع كتابة قيد غير متوازن، فاختلال الميزان يعني أن '
                'شيئاً دخل الدفتر من خارج النظام. راجع سجل التدقيق.',
                style: AppTextStyles.labelMd(),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                const SizedBox(width: 60),
                Expanded(child: Text('الحساب', style: AppTextStyles.labelMd())),
                SizedBox(width: 110,
                    child: Text('مدين', textAlign: TextAlign.end, style: AppTextStyles.labelMd())),
                SizedBox(width: 110,
                    child: Text('دائن', textAlign: TextAlign.end, style: AppTextStyles.labelMd())),
              ],
            ),
            const Divider(),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    SizedBox(width: 60,
                        child: Text(row['code'] as String? ?? '',
                            style: AppTextStyles.currency(color: AppColors.textSecondary))),
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(child: Text(row['name'] as String? ?? '',
                              style: AppTextStyles.bodyMd())),
                          const SizedBox(width: 8),
                          // النوع يُعرض هنا لا في الشجرة: الشجرة تقوله بموقع
                          // الحساب تحت جذره، والميزان قائمة مسطّحة لا موقع فيها.
                          Text(_typeLabels[row['type']] ?? '',
                              style: AppTextStyles.labelMd(color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                    SizedBox(width: 110,
                        child: Text((row['debit'] as num?) != 0 ? _money.format(row['debit']) : '',
                            textAlign: TextAlign.end, style: AppTextStyles.currency())),
                    SizedBox(width: 110,
                        child: Text((row['credit'] as num?) != 0 ? _money.format(row['credit']) : '',
                            textAlign: TextAlign.end, style: AppTextStyles.currency())),
                  ],
                ),
              ),
            const Divider(thickness: 2),
            Row(
              children: [
                const SizedBox(width: 60),
                Expanded(child: Text('الإجمالي', style: AppTextStyles.headlineMd())),
                SizedBox(width: 110,
                    child: Text(_money.format(totalDebit),
                        textAlign: TextAlign.end,
                        style: AppTextStyles.currency(color: AppColors.textPrimary))),
                SizedBox(width: 110,
                    child: Text(_money.format(totalCredit),
                        textAlign: TextAlign.end,
                        style: AppTextStyles.currency(color: AppColors.textPrimary))),
              ],
            ),
          ],
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  قائمة الدخل
// ═══════════════════════════════════════════════════════════════════════════

/// «كم ربحتُ في هذه المدّة» — أوّل ما يسأله صاحب المحلّ.
class _IncomeStatementTab extends ConsumerWidget {
  const _IncomeStatementTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(incomeStatementProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => _ErrorView(
        error: err,
        onRetry: () => ref.invalidate(incomeStatementProvider),
      ),
      data: (data) {
        final revenues = (data['revenues'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
        final expenses = (data['expenses'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
        final totalRevenue = (data['totalRevenue'] as num?)?.toDouble() ?? 0;
        final totalExpense = (data['totalExpense'] as num?)?.toDouble() ?? 0;
        final net = (data['netIncome'] as num?)?.toDouble() ?? 0;
        final profit = net >= 0;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // النتيجة أولاً: من يفتح قائمة الدخل يسأل سؤالاً واحداً، ووضعُها
            // في الأسفل يعني تمريراً لمعرفته.
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: profit ? AppColors.successBg : AppColors.dangerBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(profit ? Icons.trending_up : Icons.trending_down,
                      color: profit ? AppColors.success : AppColors.danger),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(profit ? 'صافي الربح' : 'صافي الخسارة',
                        style: AppTextStyles.headlineMd(
                            color: profit ? AppColors.success : AppColors.danger)),
                  ),
                  Text(_money.format(net.abs()),
                      style: AppTextStyles.displayLg(
                          color: profit ? AppColors.success : AppColors.danger)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'من ${_date.format(DateTime.tryParse('${data['from']}') ?? DateTime.now())} '
              'إلى ${_date.format(DateTime.tryParse('${data['to']}') ?? DateTime.now())}',
              style: AppTextStyles.labelMd(),
            ),
            const SizedBox(height: 20),
            _section('الإيرادات', revenues, totalRevenue),
            const SizedBox(height: 20),
            // «الاستخدامات» لا «المصروفات»: هي تسمية القسم الثالث في الدليل
            // الموحّد، وتشمل تكلفة البضاعة المباعة لا المصروفات وحدها.
            _section('الاستخدامات', expenses, totalExpense),
            if (revenues.isEmpty && expenses.isEmpty) ...[
              const SizedBox(height: 24),
              Center(
                child: Text('لا حركة في هذه المدّة.',
                    style: AppTextStyles.bodyMd(color: AppColors.textSecondary)),
              ),
            ],
          ],
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  الميزانية
// ═══════════════════════════════════════════════════════════════════════════

class _BalanceSheetTab extends ConsumerWidget {
  const _BalanceSheetTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(balanceSheetProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => _ErrorView(
        error: err,
        onRetry: () => ref.invalidate(balanceSheetProvider),
      ),
      data: (data) {
        final assets = (data['assets'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
        final liabilities = (data['liabilities'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
        final equity = (data['equity'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
        final totalAssets = (data['totalAssets'] as num?)?.toDouble() ?? 0;
        final totalLiabilities = (data['totalLiabilities'] as num?)?.toDouble() ?? 0;
        final totalEquity = (data['totalEquity'] as num?)?.toDouble() ?? 0;
        final retained = (data['retainedResult'] as num?)?.toDouble() ?? 0;
        final diff = (data['difference'] as num?)?.toDouble() ?? 0;
        final balanced = diff.abs() < 0.01;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: balanced ? AppColors.successBg : AppColors.dangerBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(balanced ? Icons.check_circle_outline : Icons.error_outline,
                      color: balanced ? AppColors.success : AppColors.danger),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      balanced
                          ? 'الميزانية متوازنة'
                          : 'الميزانية مختلّة — فرق ${_money.format(diff)}',
                      style: AppTextStyles.headlineMd(
                          color: balanced ? AppColors.success : AppColors.danger),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text('حتى ${_date.format(DateTime.tryParse('${data['asOf']}') ?? DateTime.now())}',
                style: AppTextStyles.labelMd()),
            const SizedBox(height: 20),
            _section('الأصول', assets, totalAssets),
            const SizedBox(height: 20),
            _section('الالتزامات', liabilities, totalLiabilities),
            const SizedBox(height: 20),
            _section('حقوق الملكية', equity, totalEquity),
            const SizedBox(height: 12),
            // النتيجة الجارية تُعرَض صراحةً لا تُخفى في الفرق.
            //
            // الإقفال السنوي غير مبنيّ، فأرباح المدّة تبقى في حسابات الإيراد
            // والاستخدام ولا تُرحَّل إلى «الأرباح المحتجزة». ولولا إضافتها هنا
            // لما توازنت الميزانية أبداً — والفرق هو الربح بالضبط.
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.infoBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('نتيجة الفترة (غير مُقفَلة)',
                            style: AppTextStyles.bodyMd(color: AppColors.info)),
                      ),
                      Text(_money.format(retained),
                          style: AppTextStyles.currency(color: AppColors.info)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'الإقفال السنوي غير مبنيّ بعد، فأرباح المدّة تبقى في حسابات '
                    'الإيراد والاستخدام. تُضاف هنا إلى حقوق الملكية لتتوازن الميزانية.',
                    style: AppTextStyles.caption(),
                  ),
                ],
              ),
            ),
            const Divider(thickness: 2, height: 28),
            Row(
              children: [
                Expanded(child: Text('إجمالي الأصول', style: AppTextStyles.headlineMd())),
                Text(_money.format(totalAssets),
                    style: AppTextStyles.currency(color: AppColors.textPrimary)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text('الالتزامات + حقوق الملكية + النتيجة',
                      style: AppTextStyles.headlineMd()),
                ),
                Text(_money.format(totalLiabilities + totalEquity + retained),
                    style: AppTextStyles.currency(color: AppColors.textPrimary)),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// قسمٌ في قائمة مالية: سطوره ومجموعه.
Widget _section(String title, List<Map<String, dynamic>> lines, double total) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: AppTextStyles.headlineMd()),
        const Divider(),
        if (lines.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text('—', style: AppTextStyles.labelMd()),
          )
        else
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 60,
                    child: Text(l['code'] as String? ?? '',
                        style: AppTextStyles.currency(color: AppColors.textSecondary)),
                  ),
                  Expanded(child: Text(l['name'] as String? ?? '', style: AppTextStyles.bodyMd())),
                  Text(_money.format(l['amount']), style: AppTextStyles.currency()),
                ],
              ),
            ),
        const Divider(),
        Row(
          children: [
            const SizedBox(width: 60),
            Expanded(child: Text('المجموع', style: AppTextStyles.labelMd())),
            Text(_money.format(total),
                style: AppTextStyles.currency(color: AppColors.textPrimary)),
          ],
        ),
      ],
    );

// ═══════════════════════════════════════════════════════════════════════════

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.color, required this.background});
  final String text;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: AppTextStyles.labelMd(color: color)),
      );
}

/// رسالة الخادم كما هي — بما فيها الرمز المرجعي إن كان عطباً غير متوقّع.
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_errorText(error, 'تعذّر التحميل'),
                  style: AppTextStyles.bodyMd(color: AppColors.danger),
                  textAlign: TextAlign.center),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('أعد المحاولة'),
              ),
            ],
          ),
        ),
      );
}

String _errorText(Object e, String fallback) {
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map && data['message'] is String) return data['message'] as String;
    if (e.response == null) return 'لا اتصال بالخادم';
  }
  return fallback;
}
