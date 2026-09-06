import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/adaptive_dialog.dart';

final _money = NumberFormat('#,##0.00', 'en');
final _date = DateFormat('yyyy-MM-dd');

/// كشف حساب: رصيدٌ افتتاحي، ثم الحركات برصيدٍ متحرّك.
///
/// <para><b>العطب الذي يصلحه:</b> الضغط على «الصندوق» كان ينقل إلى **دفتر
/// اليومية** مُرشَّحاً عليه. ومن يضغط على الصندوق يسأل: «كم فيه، ومن أين
/// جاء وإلى أين ذهب؟» — والدفتر لا يجيب: لا رصيد فيه ولا تسلسل، وسطور
/// القيود الأخرى تُغرق ما يبحث عنه.</para>
///
/// <para><b>وحسابٌ تجميعي يُفتح على أبنائه</b> لا على فراغ: لا حركة له
/// أصلاً، وشاشةٌ فارغة تُقرأ عطلاً.</para>
class AccountStatementDialog extends StatefulWidget {
  const AccountStatementDialog({super.key, required this.accountId, this.onOpenAccount});

  final String accountId;

  /// فتح حسابٍ آخر من قائمة الأبناء — بلا إغلاق الحوار وفتحه يدوياً.
  final void Function(String accountId)? onOpenAccount;

  @override
  State<AccountStatementDialog> createState() => _AccountStatementDialogState();
}

class _AccountStatementDialogState extends State<AccountStatementDialog> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _busy = true;

  DateTimeRange? _range;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await ApiClient.instance.dio.get(
        '/accounting/accounts/${widget.accountId}/statement',
        queryParameters: {
          if (_range != null) 'from': _range!.start.toIso8601String(),
          if (_range != null) 'to': _range!.end.toIso8601String(),
        },
      );
      if (!mounted) return;
      setState(() => _data = Map<String, dynamic>.from(response.data as Map));
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is DioException && e.response?.data is Map
            ? (e.response!.data as Map)['message'] as String? ?? 'تعذّر فتح الحساب'
            : 'تعذّر فتح الحساب');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;

    return AdaptiveDialog(
      title: data == null ? 'كشف الحساب' : '${data['code']} · ${data['name']}',
      maxWidth: 720,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
      ],
      body: SizedBox(
        width: 720,
        height: 480,
        child: _busy
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)))
                : _content(data!),
      ),
    );
  }

  Widget _content(Map<String, dynamic> data) {
    final isPostable = data['isPostable'] as bool? ?? true;
    final children = (data['children'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    if (!isPostable && children.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'حساب تجميعي — لا يُرحَّل إليه مباشرةً. اختر ما تحته:',
            style: AppTextStyles.bodyMd(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              itemCount: children.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final child = children[i];
                return ListTile(
                  dense: true,
                  leading: Text('${child['code']}',
                      style: AppTextStyles.currency(color: AppColors.textSecondary)),
                  title: Text('${child['name']}', style: AppTextStyles.bodyMd()),
                  trailing: const Icon(Icons.chevron_left, size: 18),
                  onTap: () {
                    // يُفتح في نفس الحوار: فتحُ حوارٍ فوق حوار يُراكم
                    // طبقاتٍ يخرج منها المستخدم بضغطات بعدد ما دخل.
                    setState(() => _data = null);
                    widget.onOpenAccount?.call(child['id'] as String);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
        ],
      );
    }

    final lines = (data['lines'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final opening = (data['openingBalance'] as num?)?.toDouble() ?? 0;
    final closing = (data['closingBalance'] as num?)?.toDouble() ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'من ${_date.format(DateTime.parse(data['from'] as String))}'
                ' إلى ${_date.format(DateTime.parse(data['to'] as String))}',
                style: AppTextStyles.bodyMd(color: AppColors.textSecondary),
              ),
            ),
            TextButton.icon(
              onPressed: _pickRange,
              icon: const Icon(Icons.date_range_outlined, size: 18),
              label: const Text('تغيير الفترة'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 20,
          runSpacing: 8,
          children: [
            _fact('رصيد افتتاحي', opening),
            _fact('مدين', (data['debit'] as num?)?.toDouble() ?? 0),
            _fact('دائن', (data['credit'] as num?)?.toDouble() ?? 0),
            _fact('الرصيد', closing, strong: true),
          ],
        ),
        const Divider(height: 20),
        if (lines.isEmpty)
          Expanded(
            child: Center(
              child: Text('لا حركة في هذه الفترة',
                  style: AppTextStyles.bodyMd(color: AppColors.textMuted)),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              itemCount: lines.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) => _line(lines[i]),
            ),
          ),
      ],
    );
  }

  Widget _line(Map<String, dynamic> line) {
    final debit = (line['debit'] as num?)?.toDouble() ?? 0;
    final credit = (line['credit'] as num?)?.toDouble() ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(_date.format(DateTime.parse(line['date'] as String)),
                style: AppTextStyles.caption(color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text('${line['description']}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyMd()),
          ),
          SizedBox(
            width: 90,
            child: Text(debit == 0 ? '' : _money.format(debit),
                textAlign: TextAlign.end, style: AppTextStyles.currency()),
          ),
          SizedBox(
            width: 90,
            child: Text(credit == 0 ? '' : _money.format(credit),
                textAlign: TextAlign.end, style: AppTextStyles.currency()),
          ),
          SizedBox(
            width: 100,
            // الرصيد المتحرّك هو عمود الكشف الذي لا يُستغنى عنه: بدونه
            // يجمع القارئ عمودين بيده ليعرف كم كان في الصندوق يوم الثلاثاء.
            child: Text(_money.format((line['balance'] as num?)?.toDouble() ?? 0),
                textAlign: TextAlign.end,
                style: AppTextStyles.currency(color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }

  Widget _fact(String label, double value, {bool strong = false}) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.caption(color: AppColors.textSecondary)),
          Text(_money.format(value),
              style: strong
                  ? AppTextStyles.headlineMd()
                  : AppTextStyles.currency(color: AppColors.textPrimary)),
        ],
      );

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _range,
    );
    if (picked == null) return;
    setState(() => _range = picked);
    await _load();
  }
}
