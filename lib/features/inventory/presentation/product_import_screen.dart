import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

class ProductImportScreen extends ConsumerStatefulWidget {
  const ProductImportScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<ProductImportScreen> createState() => _ProductImportScreenState();
}

class _ProductImportScreenState extends ConsumerState<ProductImportScreen> {
  bool _isLoading = false;
  String? _selectedFilePath;
  Map<String, dynamic>? _previewData;
  String? _error;
  String? _successMessage;

  Future<void> _pickFile() async {
    _error = null;
    _previewData = null;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
    );

    if (result == null || result.files.isEmpty) return;

    setState(() {
      _selectedFilePath = result.files.first.path;
      _successMessage = null;
    });

    await _previewFile();
  }

  Future<void> _previewFile() async {
    if (_selectedFilePath == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final file = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );

      if (file == null || file.files.isEmpty) return;

      final fileData = file.files.first;
      final multipartFile = MultipartFile.fromFileSync(
        fileData.path!,
        filename: fileData.name,
      );

      final formData = FormData.fromMap({
        'file': multipartFile,
      });

      final response = await ApiClient.instance.dio
          .post('/product-import/preview', data: formData);

      setState(() {
        _previewData = response.data;
      });
    } catch (e) {
      setState(() => _error = 'خطأ في معاينة الملف: ${e.toString()}');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _importFile() async {
    if (_selectedFilePath == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _successMessage = null;
    });

    try {
      final file = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );

      if (file == null || file.files.isEmpty) return;

      final fileData = file.files.first;
      final multipartFile = MultipartFile.fromFileSync(
        fileData.path!,
        filename: fileData.name,
      );

      final formData = FormData.fromMap({
        'file': multipartFile,
      });

      final response = await ApiClient.instance.dio
          .post('/product-import/import', data: formData);

      if (mounted) {
        setState(() {
          _successMessage = response.data['message'] ?? 'تم الاستيراج بنجاح!';
          _selectedFilePath = null;
          _previewData = null;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_successMessage!),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      setState(
        () => _error = 'خطأ في الاستيراج: ${e.toString()}',
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('استيراج المنتجات'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // التعليمات
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'كيفية الاستيراج',
                      style: AppTextStyles.headlineSm(),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '1. جهز ملف Excel بالمنتجات (مثل ملف ابوصالح)\n'
                      '2. تأكد من وجود الأعمدة: اسم المنتج، الباركود، السعر\n'
                      '3. اضغط "اختر الملف" ثم "استيراج"',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // زر اختيار الملف
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _pickFile,
              icon: const Icon(Icons.upload_file),
              label: const Text('اختر ملف Excel'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 12),

            if (_selectedFilePath != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  border: Border.all(color: Colors.green),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _selectedFilePath!.split('/').last,
                        style: AppTextStyles.bodyMd(),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // معاينة البيانات
            if (_previewData != null) ...[
              Text(
                'معاينة: ${_previewData!['totalRows']} منتج',
                style: AppTextStyles.headlineSm(),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('المنتج')),
                      DataColumn(label: Text('الباركود')),
                      DataColumn(label: Text('السعر')),
                    ],
                    rows: List.generate(
                      ((_previewData!['sampleRows'] as List).length),
                      (i) {
                        final row = _previewData!['sampleRows'][i];
                        return DataRow(cells: [
                          DataCell(
                            SizedBox(
                              width: 150,
                              child: Text(row['productName'] ?? ''),
                            ),
                          ),
                          DataCell(Text(row['barcode'] ?? '')),
                          DataCell(Text(row['sellingPrice'] ?? '0')),
                        ]);
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // رسائل الخطأ
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error, color: Colors.red),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _error!,
                        style: AppTextStyles.bodyMd(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // رسائل النجاح
            if (_successMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  border: Border.all(color: Colors.green),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _successMessage!,
                        style: AppTextStyles.bodyMd(color: Colors.green.shade700),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // زر الاستيراج
            if (_selectedFilePath != null)
              FilledButton(
                onPressed: _isLoading ? null : _importFile,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.green,
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'استيراج المنتجات',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}
