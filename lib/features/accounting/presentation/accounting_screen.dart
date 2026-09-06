import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../shared/widgets/adaptive_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/permissions.dart';
import '../../../core/network/api_client.dart';
import '../../../core/responsive/adaptive_scaffold.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/app_surface.dart';
import '../data/accounting_providers.dart';
import 'account_statement_dialog.dart';
import 'accounting_print.dart';

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
  late final _tabs = TabController(length: 6, vsync: this);

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
              Tab(text: 'الإقفال'),
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
                const _ClosingTab(),
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

        return _Readable(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _PrintBar(onPrint: () => printChartOfAccounts(ref)),
              for (final root in children[null] ?? const <Map<String, dynamic>>[])
                _AccountNode(
                  account: root,
                  children: children,
                  depth: 0,
                  onOpenJournal: onOpenJournal,
                  canManage: ref.perms.isSuperAdmin,
                  onChanged: () => ref.invalidate(chartOfAccountsProvider),
                ),
            ],
          ),
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
    required this.canManage,
    required this.onChanged,
  });

  final Map<String, dynamic> account;
  final Map<String?, List<Map<String, dynamic>>> children;
  final int depth;
  final void Function(String accountId) onOpenJournal;

  /// المدير العام وحده يعدّل الدليل — الخادم يشترط الدور نفسه.
  final bool canManage;

  /// يُستدعى بعد تعديلٍ أو حذف ليُعاد تحميل الشجرة.
  final VoidCallback onChanged;

  @override
  State<_AccountNode> createState() => _AccountNodeState();
}

class _AccountNodeState extends State<_AccountNode> {
  // الجذور مفتوحة والباقي مغلق: أربعة أقسام تُرى كلها، وفتحُ الشجرة كاملة
  // يعرض مئة سطر لا يريد أحدهم مئتها.
  late bool _open = widget.depth == 0;

  Future<void> _openStatement(BuildContext context, String id) => showDialog(
        context: context,
        builder: (_) => AccountStatementDialog(
          accountId: id,
          // فتحُ ابنٍ من كشف الأب يفتح كشفه في حوارٍ جديد بعد إغلاق الأوّل
          // — لا طبقاتٍ يخرج منها المستخدم بضغطاتٍ بعدد ما دخل.
          onOpenAccount: (childId) => Future.microtask(
              () => context.mounted ? _openStatement(context, childId) : null),
        ),
      );

  Future<void> _editAccount(BuildContext context, Map<String, dynamic> account) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _AccountFormDialog(account: account),
    );
    if (changed == true) widget.onChanged();
  }

  Future<void> _deleteAccount(BuildContext context, Map<String, dynamic> account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف الحساب'),
        content: Text(
          // ما سيحدث فعلاً لا وعدٌ عام: حسابٌ رُحّل إليه يُعطَّل لا يُحذف،
          // وقولُ ذلك قبل الضغط أصدق من رسالةٍ بعده.
          'إن كان قد رُحّل إلى «${account['name']}» فسيُعطَّل ويبقى في '
          'التقارير القديمة. وإن لم يُستعمل قطّ فسيُحذف نهائياً.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('تراجع')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('متابعة')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final response =
          await ApiClient.instance.dio.delete('/accounting/accounts/${account['id']}');
      final data = response.data;
      final message = data is Map && data['message'] is String
          ? data['message'] as String
          : 'حُذف الحساب';
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      widget.onChanged();
    } catch (e) {
      if (!context.mounted) return;
      final message = e is DioException && e.response?.data is Map
          ? (e.response!.data as Map)['message'] as String? ?? 'تعذّر الحذف'
          : 'تعذّر الحذف';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

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
          // الضغط يفتح **كشف الحساب** لا دفتر اليومية: من يضغط على
          // «الصندوق» يسأل كم فيه ومن أين جاء، لا يريد كل قيدٍ مسّه بسطوره
          // الأخرى. والأب يُفتح ويُغلق كما كان — وكشفُه متاح من قائمته.
          onTap: kids.isEmpty
              ? () => _openStatement(context, id)
              : () => setState(() => _open = !_open),
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
                // قائمة الصفّ: الكشف والتعديل والحذف. والتعديل والحذف
                // للمدير العام وحده — الخادم يشترطه، وزرٌّ يردّه الخادم
                // بـ403 يُعلّم المستخدم تجاهل الأزرار.
                PopupMenuButton<String>(
                  tooltip: 'إجراءات الحساب',
                  icon: Icon(Icons.more_vert, size: 16, color: AppColors.textMuted),
                  onSelected: (value) => switch (value) {
                    'statement' => _openStatement(context, id),
                    'edit' => _editAccount(context, account),
                    _ => _deleteAccount(context, account),
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'statement', child: Text('كشف الحساب')),
                    if (widget.canManage) const PopupMenuItem(value: 'edit', child: Text('تعديل')),
                    if (widget.canManage &&
                        !(account['isSystem'] as bool? ?? false))
                      const PopupMenuItem(value: 'delete', child: Text('حذف')),
                  ],
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
              canManage: widget.canManage,
              onChanged: widget.onChanged,
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

    final canWrite = ref.watch(myPermissionsProvider).valueOrNull?.isSuperAdmin ?? false;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: _PrintBar(onPrint: () => printJournal(ref)),
        ),
        if (canWrite)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _addManual(context, ref),
                icon: const Icon(Icons.post_add_outlined, size: 18),
                label: const Text('قيد يدوي'),
              ),
            ),
          ),
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

/// يفتح حوار القيد اليدوي ويُبطل ما تأثّر به.
Future<void> _addManual(BuildContext context, WidgetRef ref) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => const _ManualEntryDialog(),
  );
  if (saved == true) {
    ref.invalidate(journalProvider);
    ref.invalidate(chartOfAccountsProvider);
    ref.invalidate(trialBalanceProvider);
    ref.invalidate(incomeStatementProvider);
    ref.invalidate(balanceSheetProvider);
  }
}

/// قيد يدوي — ما لا مسار آلياً له: إهلاك، مخصّص، تسوية، تصحيح تبويب.
///
/// <para><b>والفرق يُعرَض وهو يكتب لا بعد الإرسال:</b> قيدٌ غير متوازن يرفضه
/// الخادم برسالة، لكن المحاسب حينها يكون قد ملأ عشرة سطور ولا يعرف أيّها
/// الخطأ. فيظهر المجموعان والفرق بينهما حيّاً.</para>
class _ManualEntryDialog extends ConsumerStatefulWidget {
  const _ManualEntryDialog();

  @override
  ConsumerState<_ManualEntryDialog> createState() => _ManualEntryDialogState();
}

class _ManualLineDraft {
  String? accountId;
  final debit = TextEditingController();
  final credit = TextEditingController();

  void dispose() {
    debit.dispose();
    credit.dispose();
  }

  double get debitValue => double.tryParse(debit.text.trim()) ?? 0;
  double get creditValue => double.tryParse(credit.text.trim()) ?? 0;
}

class _ManualEntryDialogState extends ConsumerState<_ManualEntryDialog> {
  final _descriptionController = TextEditingController();
  final _lines = <_ManualLineDraft>[_ManualLineDraft(), _ManualLineDraft()];
  DateTime _entryDate = DateTime.now();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _descriptionController.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(chartOfAccountsProvider);

    // الحسابات الورقية النشطة وحدها: التجميعي لا يُرحَّل إليه، والموقوف
    // يرفضه الخادم — وعرضُهما يجعل المحاسب يختار ثم يُرفَض بلا سبب ظاهر.
    final postable = accountsAsync.valueOrNull
            ?.where((a) => (a['isPostable'] as bool? ?? false) && (a['isActive'] as bool? ?? true))
            .toList() ??
        const <Map<String, dynamic>>[];

    final totalDebit = _lines.fold<double>(0, (sum, l) => sum + l.debitValue);
    final totalCredit = _lines.fold<double>(0, (sum, l) => sum + l.creditValue);
    final diff = totalDebit - totalCredit;
    final balanced = diff.abs() < 0.01 && totalDebit > 0;

    return AdaptiveDialog(
      title: 'قيد يدوي',
      maxWidth: 620,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed: _saving || !balanced ? null : _submit,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('ترحيل'),
        ),
      ],
      body: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _descriptionController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'وصف القيد',
                  helperText: 'قيدٌ بلا شرح لا يُفهَم بعد سنة — الآلي يشرحه مصدرُه واليدوي لا يشرحه إلا كاتبه',
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _entryDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setState(() => _entryDate = picked);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'تاريخ القيد'),
                  child: Text(_date.format(_entryDate), style: AppTextStyles.bodyMd()),
                ),
              ),
              const SizedBox(height: 16),
              for (var i = 0; i < _lines.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<String>(
                          initialValue: _lines[i].accountId,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'الحساب', isDense: true),
                          items: postable
                              .map((a) => DropdownMenuItem(
                                    value: a['id'] as String,
                                    child: Text('${a['code']} — ${a['name']}',
                                        overflow: TextOverflow.ellipsis),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() => _lines[i].accountId = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _lines[i].debit,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'مدين', isDense: true),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _lines[i].credit,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'دائن', isDense: true),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      IconButton(
                        tooltip: 'حذف السطر',
                        icon: const Icon(Icons.remove_circle_outline, size: 18),
                        // سطران حدٌّ أدنى: لكل مدين دائن.
                        onPressed: _lines.length <= 2
                            ? null
                            : () => setState(() => _lines.removeAt(i).dispose()),
                      ),
                    ],
                  ),
                ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => setState(() => _lines.add(_ManualLineDraft())),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('سطر'),
                ),
              ),
              const Divider(),
              // الفرق حيّاً وهو يكتب: الرفض بعد ملء عشرة سطور لا يقول أيّها
              // الخطأ.
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: balanced ? AppColors.successBg : AppColors.warningBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        balanced
                            ? 'متوازن'
                            : diff == 0
                                ? 'أدخل المبالغ'
                                : 'فرق ${_money.format(diff.abs())} '
                                    '${diff > 0 ? '(المدين أكبر)' : '(الدائن أكبر)'}',
                        style: AppTextStyles.bodyMd(
                            color: balanced ? AppColors.success : AppColors.warning),
                      ),
                    ),
                    Text('${_money.format(totalDebit)}  |  ${_money.format(totalCredit)}',
                        style: AppTextStyles.currency()),
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

  Future<void> _submit() async {
    if (_descriptionController.text.trim().isEmpty) {
      setState(() => _error = 'وصف القيد إلزامي');
      return;
    }
    final rows = _lines.where((l) => l.debitValue != 0 || l.creditValue != 0).toList();
    if (rows.any((l) => l.accountId == null)) {
      setState(() => _error = 'اختر حساباً لكل سطر فيه مبلغ');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ApiClient.instance.dio.post('/accounting/journal', data: {
        'entryDate': _entryDate.toIso8601String(),
        'description': _descriptionController.text.trim(),
        'lines': rows
            .map((l) => {
                  'accountId': l.accountId,
                  'debit': l.debitValue,
                  'credit': l.creditValue,
                })
            .toList(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = _errorText(e, 'تعذّر ترحيل القيد'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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

/// يحصر عرض الدفتر بما يُقرأ.
///
/// **الفجوة التي يسدّها:** الدفاتر كانت تمتدّ على عرض الشاشة كلّه — وعلى
/// سطح مكتب بعرض 1440 يقع اسم الحساب في طرف والرصيد في الطرف المقابل،
/// وبينهما ذراعٌ من الفراغ. فتقطع العين المسافة في كل سطر، ويُقرأ رقمٌ
/// في سطرٍ ويُنسَب إلى غيره.
///
/// وألفٌ ومئة حدٌّ عمليّ لا ذوق: أربعة أعمدة نصّية ورقمية تسع فيه بلا
/// ازدحام، وما زاد فراغٌ يُبعِد المرتبطَين.
class _Readable extends StatelessWidget {
  const _Readable({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: child,
        ),
      );
}

/// شريطٌ رفيع يحمل زرّ الطباعة أعلى الدفتر.
///
/// أعلاه لا أسفله: دفترٌ بمئتَي سطر يدفع زرّاً في ذيله خارج الشاشة، ومن
/// يفتح الدفتر ليطبعه لا يمرّره أوّلاً ليجد كيف.
class _PrintBar extends StatelessWidget {
  const _PrintBar({required this.onPrint});
  final Future<void> Function() onPrint;

  @override
  Widget build(BuildContext context) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: PrintLedgerButton(onPrint: onPrint),
        ),
      );
}

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

        return _Readable(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _PrintBar(onPrint: () => printTrialBalance(ref)),
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
          ),
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

        return _Readable(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _PrintBar(onPrint: () => printIncomeStatement(ref)),
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
          ),
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

        return _Readable(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _PrintBar(onPrint: () => printBalanceSheet(ref)),
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
          ),
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
//  الإقفال السنوي
// ═══════════════════════════════════════════════════════════════════════════

/// الإقفال شيئان لا واحد: قيدٌ يُصفّر الإيرادات والاستخدامات، **وقفلٌ** يمنع
/// أي قيد بتاريخ داخل المدّة. وبلا القفل لا معنى للإقفال.
class _ClosingTab extends ConsumerWidget {
  const _ClosingTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(fiscalClosingsProvider);
    final canClose = ref.watch(myPermissionsProvider).valueOrNull?.isSuperAdmin ?? false;

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => _ErrorView(
        error: err,
        onRetry: () => ref.invalidate(fiscalClosingsProvider),
      ),
      data: (closings) {
        final open = closings.where((c) => c['isReopened'] != true).toList();
        final lastEnd = open.isEmpty
            ? null
            : DateTime.tryParse('${open.first['periodEnd']}');

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lastEnd == null
                        ? 'لا مدّة مُقفَلة'
                        : 'مُقفَل حتى ${_date.format(lastEnd)}',
                    style: AppTextStyles.headlineMd(),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'الإقفال يُصفّر الإيرادات والاستخدامات ويُرحّل نتيجتها إلى '
                    '«الأرباح المحتجزة»، **ويمنع أي قيد بتاريخ داخل المدّة**. '
                    'فلا تُغيَّر أرقامٌ صدرت عنها تقارير.',
                    style: AppTextStyles.labelMd(),
                  ),
                ],
              ),
            ),
            if (canClose) ...[
              const SizedBox(height: 14),
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: () => _close(context, ref),
                  icon: const Icon(Icons.lock_outline, size: 18),
                  label: const Text('إقفال مدّة'),
                ),
              ),
            ],
            const SizedBox(height: 22),
            Text('السجلّ', style: AppTextStyles.headlineMd()),
            const Divider(),
            if (closings.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('لا إقفالات بعد.', style: AppTextStyles.labelMd()),
              )
            else
              for (final c in closings) _ClosingRow(closing: c, canReopen: canClose),
          ],
        );
      },
    );
  }

  Future<void> _close(BuildContext context, WidgetRef ref) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => const _CloseDialog(),
    );
    if (done == true) {
      ref.invalidate(fiscalClosingsProvider);
      ref.invalidate(chartOfAccountsProvider);
      ref.invalidate(trialBalanceProvider);
      ref.invalidate(journalProvider);
      ref.invalidate(incomeStatementProvider);
      ref.invalidate(balanceSheetProvider);
    }
  }
}

class _ClosingRow extends ConsumerWidget {
  const _ClosingRow({required this.closing, required this.canReopen});
  final Map<String, dynamic> closing;
  final bool canReopen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reopened = closing['isReopened'] == true;
    final periodEnd = DateTime.tryParse('${closing['periodEnd']}') ?? DateTime.now();
    final net = (closing['netResult'] as num?)?.toDouble() ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('حتى ${_date.format(periodEnd)}', style: AppTextStyles.bodyMd()),
              const SizedBox(width: 8),
              if (reopened)
                _Chip(text: 'مفتوح', color: AppColors.warning, background: AppColors.warningBg)
              else
                _Chip(text: 'مُقفَل', color: AppColors.success, background: AppColors.successBg),
              const Spacer(),
              Text(_money.format(net), style: AppTextStyles.currency()),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            [
              if (closing['closedByName'] != null) 'أقفلها ${closing['closedByName']}',
              if (reopened && closing['reopenedByName'] != null)
                'فتحها ${closing['reopenedByName']}',
            ].join(' · '),
            style: AppTextStyles.caption(),
          ),
          // السبب يبقى ظاهراً: من راجع الدفتر يجب أن يرى أن السنة أُقفلت ثم
          // فُتحت **ولماذا** — لا أن يجدها مفتوحة كأن شيئاً لم يكن.
          if (reopened && closing['reopenReason'] != null)
            Text('السبب: ${closing['reopenReason']}',
                style: AppTextStyles.caption(color: AppColors.warning)),
          if (canReopen && !reopened)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => _reopen(context, ref),
                icon: const Icon(Icons.lock_open_outlined, size: 16),
                label: const Text('فتح'),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _reopen(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('فتح الإقفال'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'يُعكَس قيد الإقفال فتعود الأرصدة كما كانت، ويُرفع القفل عن المدّة. '
              'ويبقى الصفّ في السجلّ موسوماً بأنه فُتح — لا يُحذف.',
              style: AppTextStyles.bodyMd(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'سبب الفتح'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('فتح'),
          ),
        ],
      ),
    );
    if (reason == null || reason.isEmpty) return;

    try {
      await ApiClient.instance.dio
          .post('/accounting/closings/${closing['id']}/reopen', data: {'reason': reason});
      ref.invalidate(fiscalClosingsProvider);
      ref.invalidate(trialBalanceProvider);
      ref.invalidate(incomeStatementProvider);
      ref.invalidate(balanceSheetProvider);
      ref.invalidate(journalProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_errorText(e, 'تعذّر فتح الإقفال'))),
        );
      }
    }
  }
}

class _CloseDialog extends StatefulWidget {
  const _CloseDialog();

  @override
  State<_CloseDialog> createState() => _CloseDialogState();
}

class _CloseDialogState extends State<_CloseDialog> {
  // أمس افتراضاً: إقفال اليوم يمنع بيع اليوم نفسه.
  DateTime _periodEnd = DateTime.now().subtract(const Duration(days: 1));
  bool _saving = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إقفال مدّة'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'كل قيد بتاريخ هذا اليوم أو قبله سيُمنع بعد الإقفال. '
              'وأرصدة الإيرادات والاستخدامات تُصفَّر وتُرحَّل نتيجتها إلى '
              '«الأرباح المحتجزة».',
              style: AppTextStyles.bodyMd(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _periodEnd,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().subtract(const Duration(days: 1)),
                );
                if (picked != null) setState(() => _periodEnd = picked);
              },
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'آخر يوم في المدّة'),
                child: Text(_date.format(_periodEnd), style: AppTextStyles.bodyMd()),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('إقفال'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ApiClient.instance.dio.post('/accounting/closings', data: {
        'periodEnd': _periodEnd.toIso8601String(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = _errorText(e, 'تعذّر الإقفال'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

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


/// نموذج تعديل حساب — الاسم والرمز والتفعيل.
///
/// <para><b>سبب وجوده:</b> كان الدليل يُنشأ ولا يُعدَّل: اسمٌ كُتب بخطأ
/// يبقى في كل تقرير إلى الأبد، وحسابٌ لا يخصّ النشاط يبقى في الشجرة
/// يُربك من يقرأها. والنشاط يختلف: محلُّ ملابس يريد «مصروفات دعاية»
/// ومخبزٌ يريد «دقيق وخميرة».</para>
///
/// <para>والقيود التي يفرضها الخادم مشروحةٌ هنا قبل المحاولة لا بعدها:
/// رمزُ حسابٍ رُحّل إليه لا يُغيَّر، وحسابُ النظام لا يُعطَّل.</para>
class _AccountFormDialog extends StatefulWidget {
  const _AccountFormDialog({required this.account});
  final Map<String, dynamic> account;

  @override
  State<_AccountFormDialog> createState() => _AccountFormDialogState();
}

class _AccountFormDialogState extends State<_AccountFormDialog> {
  late final _code = TextEditingController(text: widget.account['code'] as String? ?? '');
  late final _name = TextEditingController(text: widget.account['name'] as String? ?? '');
  late bool _active = widget.account['isActive'] as bool? ?? true;

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSystem = widget.account['isSystem'] as bool? ?? false;

    return AdaptiveDialog(
      title: 'تعديل الحساب',
      maxWidth: 420,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('حفظ')),
      ],
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _code,
            enabled: !isSystem,
            decoration: InputDecoration(
              labelText: 'الرمز',
              helperText: isSystem
                  ? 'حساب يعتمد عليه الترحيل الآلي — رمزه ثابت'
                  : 'لا يُغيَّر بعد أوّل قيد: التقارير القديمة تذكره',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'الاسم'),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _active,
            onChanged: isSystem ? null : (v) => setState(() => _active = v),
            contentPadding: EdgeInsets.zero,
            title: const Text('مفعَّل'),
            subtitle: Text(
              isSystem
                  ? 'لا يُعطَّل — تعطيله يُوقف الترحيل الآلي'
                  : 'المعطَّل يبقى في التقارير القديمة ويختفي من قوائم الاختيار',
              style: AppTextStyles.labelMd(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
          ],
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiClient.instance.dio.put(
        '/accounting/accounts/${widget.account['id']}',
        data: {
          'code': _code.text.trim(),
          'name': _name.text.trim(),
          'isActive': _active,
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = e is DioException && e.response?.data is Map
          ? (e.response!.data as Map)['message'] as String? ?? 'تعذّر الحفظ'
          : 'تعذّر الحفظ');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
