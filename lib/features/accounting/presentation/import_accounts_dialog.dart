import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/adaptive_dialog.dart';

/// استيراد دليل الحسابات من ملف.
///
/// <para><b>سبب وجوده:</b> الدليل المبذور واحدٌ مختصر، وكل بلدٍ دليلُه —
/// وكل مكتب محاسبة شجرتُه التي اعتادها. وانتظارُ إصدارٍ جديد ليُضاف قالب
/// بلدٍ يجعل النظام «نظامنا» لا «نظام صاحبه».</para>
///
/// <para><b>ومرحلتان</b> كما في استيراد العملاء والأصناف: معاينةٌ تقرأ
/// وتتحقّق بلا كتابة، ثم تنفيذ. ودليلٌ يُكتب فوق دليلٍ عامل بلا معاينة قد
/// يقلب أنواع الحسابات كلّها فينقلب الميزان ولا يُعرف أين الخلل.</para>
class ImportAccountsDialog extends StatefulWidget {
  const ImportAccountsDialog({super.key});

  @override
  State<ImportAccountsDialog> createState() => _ImportAccountsDialogState();
}

class _ImportAccountsDialogState extends State<ImportAccountsDialog> {
  String? _fileName;
  List<int>? _bytes;
  Map<String, dynamic>? _preview;
  bool _busy = false;
  bool _done = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final errors = (preview?['withErrors'] as num?)?.toInt() ?? 0;
    final canCommit = preview != null && !_done && errors == 0;

    return AdaptiveDialog(
      title: _done ? 'دخل الدليل' : 'استيراد دليل الحسابات',
      maxWidth: 620,
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, _done),
          child: Text(_done ? 'إغلاق' : 'تراجع'),
        ),
        if (!_done)
          FilledButton(
            onPressed: (_busy || !canCommit) ? null : () => _upload(dryRun: false),
            child: const Text('تنفيذ الاستيراد'),
          ),
      ],
      body: SizedBox(
        width: 620,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!_done) ...[
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _pick,
                    icon: const Icon(Icons.upload_file_outlined, size: 18),
                    label: Text(_fileName ?? 'اختر ملفاً'),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _busy ? null : _export,
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('تصدير الحالي'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                // الأعمدة مذكورة هنا لا في الملف وحده: من يُخرج دليله من
                // نظامٍ قديم لا يفتح قالبنا أصلاً.
                'الأعمدة: الرمز · الاسم · النوع · رمز الأب — والرمز والاسم '
                'وحدهما إلزاميان. وبلا «رمز الأب» يُشتقّ الأب من بادئة الرمز '
                '(1101 تحت 11 تحت 1). ولا يُحذف حسابٌ لأنه غاب عن الملف.',
                style: AppTextStyles.caption(color: AppColors.textSecondary),
              ),
            ],
            if (_busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
            ],
            if (preview != null) ...[
              const SizedBox(height: 12),
              _summary(preview),
              const SizedBox(height: 8),
              Expanded(child: _rows(preview)),
            ] else
              const Spacer(),
          ],
        ),
      ),
    );
  }

  Widget _summary(Map<String, dynamic> preview) {
    final errors = (preview['withErrors'] as num?)?.toInt() ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 18,
          runSpacing: 6,
          children: [
            _fact('الصفوف', '${(preview['totalRows'] as num?)?.toInt() ?? 0}'),
            _fact('إنشاء', '${(preview['willCreate'] as num?)?.toInt() ?? 0}'),
            _fact('تحديث', '${(preview['willUpdate'] as num?)?.toInt() ?? 0}'),
            _fact('أخطاء', '$errors', danger: errors > 0),
          ],
        ),
        if (errors > 0) ...[
          const SizedBox(height: 8),
          Text(
            // لا استيراد جزئي لدليل: شجرةٌ نصفُها دخل تترك حسابات بلا آباء
            // ومحاسباً لا يعرف أين وقف.
            'لا يُكتب شيء ما دام في الملف خطأ — صحّح الصفوف أدناه وأعد الرفع.',
            style: AppTextStyles.caption(color: AppColors.danger),
          ),
        ],
      ],
    );
  }

  Widget _fact(String label, String value, {bool danger = false}) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.caption(color: AppColors.textSecondary)),
          Text(value, style: AppTextStyles.bodyLg(color: danger ? AppColors.danger : null)),
        ],
      );

  Widget _rows(Map<String, dynamic> preview) {
    final rows = (preview['rows'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList()
      // الأخطاء أولاً: من رفع أربعمئة حساب وثلاثة أخطاء لا يبحث عنها
      // بالتمرير.
      ..sort((a, b) => (a['error'] != null ? 0 : 1).compareTo(b['error'] != null ? 0 : 1));

    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final row = rows[i];
        final error = row['error'] as String?;
        return ListTile(
          dense: true,
          leading: Text('${row['code']}',
              style: AppTextStyles.currency(color: AppColors.textSecondary)),
          title: Text('${row['name']}', style: AppTextStyles.bodyMd()),
          subtitle: error != null
              ? Text(error, style: AppTextStyles.caption(color: AppColors.danger))
              : Text('${row['action']}',
                  style: AppTextStyles.caption(color: AppColors.textSecondary)),
        );
      },
    );
  }

  Future<void> _pick() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xlsm', 'csv'],
    );
    if (result.isEmpty) return;

    final file = result.first;
    final bytes = await file.readAsBytes();
    setState(() {
      _fileName = file.name;
      _bytes = bytes;
      _preview = null;
      _error = null;
      _done = false;
    });
    await _upload(dryRun: true);
  }

  Future<void> _upload({required bool dryRun}) async {
    if (_bytes == null || _fileName == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(_bytes!, filename: _fileName),
      });
      final response = await ApiClient.instance.dio.post(
        '/accounting/accounts/import',
        data: form,
        queryParameters: {'dryRun': dryRun},
      );
      setState(() {
        _preview = Map<String, dynamic>.from(response.data as Map);
        _done = !dryRun && (_preview!['committed'] as bool? ?? false);
      });
    } catch (e) {
      setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final response = await ApiClient.instance.dio.get<List<int>>(
        '/accounting/accounts/export',
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) throw Exception('empty');

      final saved = await FilePicker.saveFile(
        fileName: 'دليل-الحسابات.xlsx',
        bytes: Uint8List.fromList(bytes),
      );
      if (mounted && saved != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('صُدّر الدليل')));
      }
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _message(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['message'] is String) return data['message'] as String;
    }
    return 'تعذّرت العملية';
  }
}
