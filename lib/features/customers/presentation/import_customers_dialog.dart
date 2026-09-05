import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../shared/widgets/adaptive_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// استيراد المنتسبين من ملف إكسل أو CSV.
///
/// <para><b>سبب وجوده:</b> جهةٌ تصرف على ألف منتسب لا تُدخلهم واحداً واحداً
/// — أربعة آلاف إدخال يدوي كانت وحدها تمنع تسليم النظام لجهةٍ عندها كشفٌ
/// قائم.</para>
///
/// <para><b>ومرحلتان إلزاميتان</b> كما في استيراد الأصناف: معاينةٌ تقرأ
/// الملف على الخادم وتتحقّق من كل صفّ **بلا كتابة**، ثم تنفيذ. وملفٌ فيه
/// عمود الهاتف مكان عمود الاسم يزرع ألف عميل بأسماء أرقام.</para>
class ImportCustomersDialog extends ConsumerStatefulWidget {
  const ImportCustomersDialog({super.key});

  @override
  ConsumerState<ImportCustomersDialog> createState() => _ImportCustomersDialogState();
}

class _ImportCustomersDialogState extends ConsumerState<ImportCustomersDialog> {
  String? _fileName;
  List<int>? _fileBytes;
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _preview;
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final errors = (preview?['withErrors'] as num?)?.toInt() ?? 0;
    final canCommit = preview != null && !_done && errors == 0;

    return AdaptiveDialog(
      title: _done ? 'تمّ الاستيراد' : 'استيراد المنتسبين',
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
        height: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!_done) ...[
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _pickFile,
                    icon: const Icon(Icons.upload_file_outlined, size: 18),
                    label: Text(_fileName ?? 'اختر ملفاً'),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _busy ? null : _downloadTemplate,
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('القالب'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                // الأعمدة مذكورة هنا لا في القالب وحده: من يبني ملفه من
                // كشفٍ قديم لا يفتح القالب أصلاً.
                'الأعمدة: الاسم · الهاتف · الفئة · الفرع · المبلغ · ملاحظات — '
                'والاسم وحده إلزامي. وصفوف «مثال:» في القالب تُتجاهَل.',
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
    final total = (preview['totalRows'] as num?)?.toInt() ?? 0;
    final create = (preview['willCreate'] as num?)?.toInt() ?? 0;
    final update = (preview['willUpdate'] as num?)?.toInt() ?? 0;
    final errors = (preview['withErrors'] as num?)?.toInt() ?? 0;
    final unknown = (preview['unknownCategories'] as List? ?? const []).cast<String>();
    final examples = (preview['exampleRowsSkipped'] as num?)?.toInt() ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 18,
          runSpacing: 6,
          children: [
            _fact('الصفوف', '$total'),
            _fact('إنشاء', '$create'),
            _fact('تحديث', '$update'),
            _fact('أخطاء', '$errors', danger: errors > 0),
          ],
        ),
        if (examples > 0) ...[
          const SizedBox(height: 6),
          Text(
            // تُعلَن ولا تُخفى: من ترك صفّ المثال يجب أن يعرف أنه لم
            // يدخل، وإلا بحث عن «محمد علي» في الكشف ولم يجده.
            'صفوف المثال المتجاهَلة: $examples',
            style: AppTextStyles.caption(color: AppColors.textSecondary),
          ),
        ],
        if (errors > 0) ...[
          const SizedBox(height: 8),
          Text(
            // لا استيراد جزئي: استيرادٌ ينجح نصفه يترك المستخدم لا يعرف من
            // دخل، فيُعيد الملف كلّه فيتضاعف من دخل.
            'لا يُكتب شيء ما دام في الملف خطأ — صحّح الصفوف أدناه وأعد الرفع.',
            style: AppTextStyles.caption(color: AppColors.danger),
          ),
        ],
        if (unknown.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            // الفئة تحمل مرتَّباً، وإنشاؤها ضمناً بصفر يُنتج منتسبين لا
            // يقبضون شيئاً ولا يعرف أحدٌ لماذا.
            'فئات غير معرَّفة: ${unknown.join('، ')} — أنشئها بمرتَّبها أولاً.',
            style: AppTextStyles.caption(color: AppColors.warning),
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
          Text(value,
              style: AppTextStyles.bodyLg(color: danger ? AppColors.danger : null)),
        ],
      );

  Widget _rows(Map<String, dynamic> preview) {
    final rows = (preview['rows'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    // الأخطاء أولاً: من رفع ملفاً بألف صفّ وثلاثة أخطاء لا يبحث عنها
    // بالتمرير.
    rows.sort((a, b) {
      final ae = a['error'] != null ? 0 : 1;
      final be = b['error'] != null ? 0 : 1;
      return ae.compareTo(be);
    });

    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final row = rows[i];
        final error = row['error'] as String?;
        return ListTile(
          dense: true,
          leading: Text('${row['row']}',
              style: AppTextStyles.caption(color: AppColors.textSecondary)),
          title: Text('${row['name']}', style: AppTextStyles.bodyMd()),
          subtitle: error != null
              ? Text(error, style: AppTextStyles.caption(color: AppColors.danger))
              : Text('${row['action']}${row['category'] != null ? ' · ${row['category']}' : ''}',
                  style: AppTextStyles.caption(color: AppColors.textSecondary)),
        );
      },
    );
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xlsm', 'csv'],
    );
    if (result.isEmpty) return;

    // البايتات لا المسار: الويب وأندرويد قد لا يعطيان مساراً على القرص.
    final file = result.first;
    final bytes = await file.readAsBytes();

    setState(() {
      _fileName = file.name;
      _fileBytes = bytes;
      _preview = null;
      _error = null;
      _done = false;
    });
    await _upload(dryRun: true);
  }

  Future<void> _upload({required bool dryRun}) async {
    if (_fileBytes == null || _fileName == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(_fileBytes!, filename: _fileName),
      });
      final response = await ApiClient.instance.dio.post(
        '/customers/import',
        data: form,
        queryParameters: {'dryRun': dryRun},
      );
      setState(() {
        _preview = Map<String, dynamic>.from(response.data as Map);
        _done = !dryRun && (_preview!['committed'] as bool? ?? false);
      });
    } catch (e) {
      setState(() => _error = _errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadTemplate() async {
    setState(() => _busy = true);
    try {
      final response = await ApiClient.instance.dio.get<List<int>>(
        '/customers/import/template',
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data;
      if (bytes == null) throw Exception('empty');

      final path = await FilePicker.saveFile(
        fileName: 'قالب-استيراد-العملاء.csv',
        bytes: Uint8List.fromList(bytes),
      );
      if (mounted && path != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('حُفظ القالب')));
      }
    } catch (e) {
      if (mounted) setState(() => _error = _errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _errorMessage(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['message'] is String) return data['message'] as String;
    }
    return 'تعذّرت العملية';
  }
}
