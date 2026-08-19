import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// استيراد كتالوج الأصناف من ملف إكسل أو CSV.
///
/// الحوار على مرحلتين إلزامياً — معاينة ثم تنفيذ — ولا يمكن تخطّي المعاينة:
/// ملف فيه عمود السعر مكان عمود التكلفة يقلب أسعار كتالوج كامل، واكتشافه
/// بعد الكتابة يعني استرجاع نسخة احتياطية. المعاينة تقرأ الملف على السيرفر
/// وتتحقق من كل صف **بلا كتابة أي شيء**.
class ImportProductsDialog extends ConsumerStatefulWidget {
  const ImportProductsDialog({super.key});

  @override
  ConsumerState<ImportProductsDialog> createState() => _ImportProductsDialogState();
}

class _ImportProductsDialogState extends ConsumerState<ImportProductsDialog> {
  String? _fileName;
  List<int>? _fileBytes;
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _preview;
  bool _done = false;

  Future<void> _pickFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xlsm', 'csv'],
      // withData ضروري على الويب وعلى أندرويد: المسار قد لا يكون متاحاً
      // أصلاً، والبايتات هي الطريق الوحيد المضمون على كل المنصات.
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.bytes == null) {
      setState(() => _error = 'تعذّرت قراءة الملف');
      return;
    }
    setState(() {
      _fileName = file.name;
      _fileBytes = file.bytes;
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
        '/products/import',
        data: form,
        queryParameters: {'dryRun': dryRun},
      );
      setState(() {
        _preview = Map<String, dynamic>.from(response.data as Map);
        _done = !dryRun;
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
        '/products/import/template',
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data;
      if (bytes == null) throw Exception('empty');

      final path = await FilePicker.saveFile(
        fileName: 'قالب-استيراد-الأصناف.csv',
        bytes: Uint8List.fromList(bytes),
      );
      if (mounted && path != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('حُفظ القالب')),
        );
      }
    } catch (e) {
      setState(() => _error = 'تعذّر تنزيل القالب');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final errors = ((preview?['withErrors'] as num?) ?? 0).toInt();
    final create = ((preview?['willCreate'] as num?) ?? 0).toInt();
    final update = ((preview?['willUpdate'] as num?) ?? 0).toInt();
    final total = ((preview?['totalRows'] as num?) ?? 0).toInt();
    final newCategories =
        ((preview?['createdCategories'] as List?) ?? const []).map((e) => 'تصنيف «$e»');
    final newSuppliers =
        ((preview?['createdSuppliers'] as List?) ?? const []).map((e) => 'مورّد «$e»');
    final newLookups = [...newCategories, ...newSuppliers];

    return AlertDialog(
      title: const Text('استيراد أصناف من ملف'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'ملف ‎.xlsx أو ‎.csv، سطره الأول أسماء الأعمدة. '
                'الأعمدة المطلوبة: الاسم وسعر البيع. والبقية اختيارية.',
                style: AppTextStyles.bodyMd(),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _pickFile,
                      icon: const Icon(Icons.upload_file, size: 18),
                      label: Text(_fileName ?? 'اختر الملف'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _downloadTemplate,
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('قالب فارغ'),
                  ),
                ],
              ),
              if (_busy) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.dangerBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
                ),
              ],
              if (preview != null) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    _Stat(label: 'صفوف', value: '$total'),
                    _Stat(label: 'جديد', value: '$create', color: AppColors.success),
                    _Stat(label: 'تحديث', value: '$update', color: AppColors.warning),
                    _Stat(label: 'أخطاء', value: '$errors', color: errors > 0 ? AppColors.danger : null),
                  ],
                ),
                // تصنيفات وموردون سيُنشَأون تلقائياً — يُعرَضون قبل التأكيد
                // لا بعده: خطأ إملائي في الملف يزرع تصنيفاً شبحاً، ورؤيته
                // الآن تكلّف تصحيح خلية واحدة، ورؤيته لاحقاً تكلّف تنظيف
                // كتالوج.
                if (newLookups.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.infoBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'سيُنشأ تلقائياً: ${newLookups.join('، ')}',
                      style: AppTextStyles.bodyMd(color: AppColors.info),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                if (_done)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.successBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'تم الاستيراد: $create صنفاً جديداً و$update محدَّثاً.',
                      style: AppTextStyles.bodyMd(color: AppColors.success),
                    ),
                  )
                else if (errors > 0)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.dangerBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'لن يُستورد شيء ما دام في الملف خطأ واحد. '
                      'استيراد نصف ملف يترك الكتالوج في حالة لا تُعرف، '
                      'وإعادة المحاولة تضاعف ما نجح.',
                      style: AppTextStyles.bodyMd(color: AppColors.danger),
                    ),
                  ),
                const SizedBox(height: 12),
                _RowsTable(rows: List<Map<String, dynamic>>.from(preview['rows'] as List? ?? [])),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, _done),
          child: Text(_done ? 'إغلاق' : 'إلغاء'),
        ),
        if (preview != null && !_done)
          FilledButton(
            onPressed: (_busy || errors > 0 || (create + update) == 0)
                ? null
                : () => _upload(dryRun: false),
            child: Text('استيراد ${create + update} صنفاً'),
          ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsetsDirectional.only(end: 8),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Text(value, style: AppTextStyles.headlineMd(color: color ?? AppColors.textPrimary)),
            Text(label, style: AppTextStyles.labelMd()),
          ],
        ),
      ),
    );
  }
}

class _RowsTable extends StatelessWidget {
  const _RowsTable({required this.rows});
  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(maxHeight: 260),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: rows.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final row = rows[i];
          final action = row['action'] as String? ?? '';
          final error = row['error'] as String?;
          final isError = action == 'خطأ';

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Text('${row['row']}', style: AppTextStyles.labelMd()),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row['name'] as String? ?? '',
                        style: AppTextStyles.bodyMd(color: AppColors.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (error != null)
                        Text(error, style: AppTextStyles.labelMd(color: AppColors.danger)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isError
                        ? AppColors.dangerBg
                        : (action == 'جديد' ? AppColors.successBg : AppColors.warningBg),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    action,
                    style: AppTextStyles.labelMd(
                      color: isError
                          ? AppColors.danger
                          : (action == 'جديد' ? AppColors.success : AppColors.warning),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

String _errorMessage(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] is String) return data['message'] as String;
  }
  return 'تعذّر الاستيراد';
}
