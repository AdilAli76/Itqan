import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../shared/widgets/adaptive_dialog.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../payroll/data/payroll_providers.dart';

/// إصدار بطاقات لفئةٍ كاملة دفعةً واحدة.
///
/// <para><b>الفجوة:</b> جهةٌ تُدخل ألف منتسب تحتاج ألف بطاقة. وإصدارها
/// واحدةً واحدة عملُ يومين، ويُنسى فيها من يُنسى فلا يعرف أحد من بقي بلا
/// بطاقة إلا حين يقف على الصندوق.</para>
///
/// <para><b>ولا رقم سرّي فيها:</b> رقمٌ واحد لألف بطاقة يُبطل معنى السرّ،
/// ورقمٌ لكلٍّ يحتاج تسليماً فردياً فلا يبقى للجملة معنى. والخادم يرفض نمط
/// <c>pin</c> هنا صراحةً — راجع <c>CustomersController.BulkIssueCards</c>.</para>
class BulkCardsDialog extends ConsumerStatefulWidget {
  const BulkCardsDialog({super.key});

  @override
  ConsumerState<BulkCardsDialog> createState() => _BulkCardsDialogState();
}

class _BulkCardsDialogState extends ConsumerState<BulkCardsDialog> {
  String? _categoryId;
  bool _reissue = false;
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>>? _issued;

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(customerCategoriesProvider).valueOrNull ?? const [];
    final active = categories.where((c) => c['isActive'] as bool? ?? true).toList();

    if (_issued != null) return _resultView();

    return AdaptiveDialog(
      title: 'إصدار بطاقات جماعي',
      maxWidth: 460,
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('تراجع'),
        ),
        FilledButton(
          onPressed: (_busy || _categoryId == null) ? null : _issue,
          child: Text(_busy ? 'جارٍ الإصدار…' : 'إصدار'),
        ),
      ],
      body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (active.isEmpty)
              Text(
                'لا فئات بعد — أنشئها من شاشة المرتَّبات والسلف، ثم أسنِد '
                'المنتسبين إليها.',
                style: AppTextStyles.bodyMd(),
              )
            else ...[
              DropdownButtonFormField<String>(
                initialValue: _categoryId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'الفئة',
                  helperText: 'تُصدَر بطاقة لكل من فيها بلا بطاقة',
                ),
                items: [
                  for (final c in active)
                    DropdownMenuItem(
                      value: '${c['id']}',
                      child: Text('${c['name']} — ${c['customerCount']} منتسباً'),
                    ),
                ],
                onChanged: (v) => setState(() => _categoryId = v),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _reissue,
                onChanged: (v) => setState(() => _reissue = v),
                title: const Text('إعادة إصدار لمن له بطاقة'),
                subtitle: Text(
                  // التحذير مكتوبٌ لا مفترَض: إعادةٌ بالخطأ تُبطل ألف بطاقة
                  // في جيوب أصحابها دفعةً واحدة.
                  _reissue
                      ? '⚠ ستبطل البطاقات القديمة فوراً في أيدي أصحابها'
                      : 'من له بطاقة يُتخطّى',
                  style: AppTextStyles.caption(
                      color: _reissue ? AppColors.danger : AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.infoBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'البطاقات تُصدَر بنمط «بطاقة فقط» بلا رقم سرّي — وهو ما '
                  'يجعل الإصدار الجماعي ممكناً. احرص على وضع صورة كل منتسب '
                  'على بطاقته، فهي ما يحميها.',
                  style: AppTextStyles.caption(color: AppColors.info),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
            ],
          ],
        ),
    );
  }

  /// الرموز تُعرَض مرّةً — وتُنسخ لتُطبع.
  ///
  /// <para>رمز البطاقة هو ما يُطبع عليها ويُمسح عند الصرف. وعرضُه هنا
  /// يُغني عن فتح ألف بطاقة واحدةً واحدة لقراءته.</para>
  Widget _resultView() {
    final cards = _issued!;
    return AlertDialog(
      title: Text('صدرت ${cards.length} بطاقة'),
      content: SizedBox(
        width: 460,
        height: 360,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'انسخ الرموز لطباعتها. وهي محفوظة على كل منتسب أيضاً، '
              'فلا تضيع بإغلاق هذه النافذة.',
              style: AppTextStyles.caption(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: cards.length,
                itemBuilder: (context, i) => ListTile(
                  dense: true,
                  title: Text('${cards[i]['fullName']}', style: AppTextStyles.bodyMd()),
                  subtitle: SelectableText(
                    '${cards[i]['cardCode']}',
                    // اللاتينية يساراً دائماً: رمزٌ معكوس يُطبع خطأً.
                    textDirection: TextDirection.ltr,
                    style: AppTextStyles.caption(color: AppColors.textSecondary),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(
              text: cards.map((c) => '${c['fullName']}\t${c['cardCode']}').join('\n'),
            ));
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('نُسخت الرموز')));
          },
          child: const Text('نسخ الكل'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('تمّ'),
        ),
      ],
    );
  }

  Future<void> _issue() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await ApiClient.instance.dio.post('/customers/bulk-issue-cards', data: {
        'categoryId': _categoryId,
        'reissue': _reissue,
      });
      final cards = (response.data['cards'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final skipped = (response.data['skipped'] as num?)?.toInt() ?? 0;

      if (cards.isEmpty) {
        setState(() {
          _busy = false;
          _error = skipped > 0
              // السبب لا مجرّد «لا شيء»: من يقرأ الأخير يظنّ الفئة فارغة.
              ? 'كل من في الفئة له بطاقة ($skipped) — فعّل إعادة الإصدار إن أردت استبدالها'
              : 'لا منتسب في هذه الفئة';
        });
        return;
      }

      setState(() {
        _busy = false;
        _issued = cards;
      });
    } on DioException catch (e) {
      final data = e.response?.data;
      setState(() {
        _busy = false;
        _error = data is Map && data['message'] is String
            ? data['message'] as String
            : 'تعذّر الإصدار';
      });
    }
  }
}
