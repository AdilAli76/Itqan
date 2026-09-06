import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/adaptive_dialog.dart';

/// أنواع الحقول الإضافية — تُطابق ما يقبله الخادم.
const accountFieldTypes = {
  'text': 'نصّ',
  'number': 'رقم',
  'date': 'تاريخ',
  'select': 'قائمة اختيار',
};

/// إدارة الحقول الإضافية لحسابات الدليل.
///
/// <para><b>سبب وجودها:</b> ما يحتاجه الحساب يختلف بالنشاط — مقاولاتٌ تريد
/// «مركز التكلفة»، وجهةٌ متعدّدة العملات تريد «عملة الحساب»، ومكتبٌ يريد
/// رقم الحساب في نظامه القديم ليطابق عند التحويل. وانتظارُ إصدارٍ جديد
/// لإضافة حقلٍ يعني أن يكتبه المحاسب في خانة «الاسم» بين قوسين.</para>
///
/// <para>وعشرة حدّاً: نموذجُ حسابٍ بعشرين حقلاً لا يملؤه أحد، فيبقى فارغاً
/// ويصير زينةً تُربك من يقرأ.</para>
class AccountFieldsDialog extends StatefulWidget {
  const AccountFieldsDialog({super.key});

  @override
  State<AccountFieldsDialog> createState() => _AccountFieldsDialogState();
}

class _AccountFieldsDialogState extends State<AccountFieldsDialog> {
  List<Map<String, dynamic>> _fields = [];
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final response = await ApiClient.instance.dio.get('/accounting/account-fields');
      if (!mounted) return;
      setState(() => _fields = (response.data as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList());
    } catch (e) {
      if (mounted) setState(() => _error = _message(e, 'تعذّر تحميل الحقول'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveDialog(
      title: 'الحقول الإضافية للحسابات',
      maxWidth: 560,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('حفظ')),
      ],
      body: SizedBox(
        width: 560,
        height: 420,
        child: _busy && _fields.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'تظهر هذه الحقول في نموذج كل حساب. وحذفُ حقلٍ لا يمحو ما '
                    'كُتب فيه — يعود إن أُعيد.',
                    style: AppTextStyles.labelMd(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
                  ],
                  const SizedBox(height: 12),
                  Expanded(
                    child: _fields.isEmpty
                        ? Center(
                            child: Text('لا حقول إضافية بعد',
                                style: AppTextStyles.bodyMd(color: AppColors.textMuted)),
                          )
                        : ListView.separated(
                            itemCount: _fields.length,
                            separatorBuilder: (_, __) => const Divider(height: 16),
                            itemBuilder: (context, i) => _row(i),
                          ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: OutlinedButton.icon(
                      onPressed: _fields.length >= 10
                          ? null
                          : () => setState(() => _fields.add({
                                'key': '',
                                'label': '',
                                'type': 'text',
                                'required': false,
                                'options': <String>[],
                              })),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(_fields.length >= 10 ? 'بلغتَ الحدّ (10)' : 'إضافة حقل'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _row(int index) {
    final field = _fields[index];
    final type = field['type'] as String? ?? 'text';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextFormField(
                initialValue: field['label'] as String? ?? '',
                decoration: const InputDecoration(labelText: 'العنوان', isDense: true),
                onChanged: (v) => field['label'] = v,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: type,
                decoration: const InputDecoration(labelText: 'النوع', isDense: true),
                items: [
                  for (final entry in accountFieldTypes.entries)
                    DropdownMenuItem(value: entry.key, child: Text(entry.value)),
                ],
                onChanged: (v) => setState(() => field['type'] = v ?? 'text'),
              ),
            ),
            IconButton(
              tooltip: 'حذف الحقل',
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => setState(() => _fields.removeAt(index)),
            ),
          ],
        ),
        if (type == 'select')
          TextFormField(
            initialValue: (field['options'] as List?)?.join('، ') ?? '',
            decoration: const InputDecoration(
              labelText: 'الخيارات — مفصولة بفاصلة',
              isDense: true,
            ),
            onChanged: (v) => field['options'] =
                v.split(RegExp('[،,]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
          ),
        CheckboxListTile(
          value: field['required'] as bool? ?? false,
          onChanged: (v) => setState(() => field['required'] = v ?? false),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
          title: Text('إلزامي', style: AppTextStyles.bodyMd(color: AppColors.textPrimary)),
        ),
      ],
    );
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiClient.instance.dio.put('/accounting/account-fields', data: {'fields': _fields});
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = _message(e, 'تعذّر الحفظ'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _message(Object error, String fallback) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['message'] is String) return data['message'] as String;
    }
    return fallback;
  }
}
