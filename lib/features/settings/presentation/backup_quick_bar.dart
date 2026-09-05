import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/auth/permissions.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/backup_folder_web.dart'
    if (dart.library.io) '../data/backup_folder_io.dart';

/// زرّا النسخ الاحتياطي في لوحة التحكّم: على الجهاز، وإلى درايف.
///
/// <para><b>سبب وجوده:</b> النسخة كانت في «الإعدادات ← النسخة الاحتياطية»
/// — أي في شاشةٍ تُفتح مرّةً عند التركيب ثم لا تُفتح. وما لا يُرى لا
/// يُفعَل: صاحب المحلّ يأخذ نسخته حين يتذكّر، ولا يتذكّر إلا وهو يبحث
/// عنها بعد فوات الأوان.</para>
///
/// <para>فمكانها لوحة التحكّم — الشاشة التي تُفتح كل صباح — وبضغطةٍ
/// واحدة، كما في التطبيقات التي اعتادها المستخدم.</para>
///
/// <para><b>والتفاصيل تبقى في الإعدادات:</b> الجدولة وربط الحساب واختيار
/// المجلّد قراراتٌ تُتخذ مرّة. هنا الفعل اليومي وحده.</para>
class BackupQuickBar extends StatefulWidget {
  const BackupQuickBar({super.key});

  @override
  State<BackupQuickBar> createState() => _BackupQuickBarState();
}

class _BackupQuickBarState extends State<BackupQuickBar> {
  static const _storage = FlutterSecureStorage();
  static const _folderKey = 'backup_folder';

  bool _busy = false;
  bool _driveReady = false;
  String? _lastLabel;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    try {
      final response = await ApiClient.instance.dio.get('/backup/summary');
      final data = Map<String, dynamic>.from(response.data as Map);
      final auto = Map<String, dynamic>.from(data['auto'] as Map? ?? const {});
      if (!mounted) return;
      setState(() {
        // زرّ درايف لا يظهر إلا وهو قادر على العمل: زرٌّ يفشل دائماً
        // يُعلِّم المستخدم أن يتجاهل الأزرار.
        _driveReady = (auto['serverConfigured'] as bool? ?? false) &&
            (auto['connected'] as bool? ?? false);
        _lastLabel = _sinceLabel(data['lastExportAt'] as String?);
      });
    } catch (_) {
      // لوحة التحكّم لا تُعطَّل لأجل شريطٍ مساعد — يبقى زرّ الجهاز عاملاً.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Can(
      permission: Perm.backupManage,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.backup_outlined, size: 18, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Text('النسخة الاحتياطية', style: AppTextStyles.bodyMd()),
                if (_lastLabel != null) ...[
                  const SizedBox(width: 8),
                  Text(_lastLabel!, style: AppTextStyles.caption(color: AppColors.textSecondary)),
                ],
              ],
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _saveLocal,
              icon: const Icon(Icons.save_alt_outlined, size: 18),
              label: const Text('نسخة على الجهاز'),
            ),
            if (_driveReady)
              OutlinedButton.icon(
                onPressed: _busy ? null : _uploadDrive,
                icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                label: const Text('إلى Google Drive'),
              ),
            if (_busy)
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ),
      ),
    );
  }

  Future<void> _saveLocal() async {
    setState(() => _busy = true);
    try {
      final response = await ApiClient.instance.dio.get<List<int>>(
        '/backup/export',
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = Uint8List.fromList(response.data ?? const []);
      if (bytes.isEmpty) throw Exception('empty');

      final stamp = DateTime.now()
          .toIso8601String()
          .substring(0, 16)
          .replaceAll(':', '')
          .replaceAll('T', '-');
      final fileName = 'kinetic-backup-$stamp.zip';

      // المجلّد المحفوظ من شاشة الإعدادات — نفس المفتاح، فالاختيار يُتخذ
      // مرّةً ويخدم الزرّين.
      final folder = supportsFolderSave ? await _storage.read(key: _folderKey) : null;
      if (folder != null && folder.isNotEmpty) {
        final path = await writeBackupFile(folder, fileName, bytes);
        _say('حُفظت النسخة في $path');
      } else {
        final saved = await FilePicker.saveFile(fileName: fileName, bytes: bytes);
        if (saved != null) _say('حُفظت النسخة');
      }
      await _loadState();
    } catch (e) {
      _say(_message(e, 'تعذّرت النسخة'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uploadDrive() async {
    setState(() => _busy = true);
    try {
      final response = await ApiClient.instance.dio.post('/backup/google/upload');
      final bytes = ((response.data as Map)['bytes'] as num?)?.toInt() ?? 0;
      _say('رُفعت النسخة إلى درايف (${(bytes / (1024 * 1024)).toStringAsFixed(1)} ميغابايت)');
      await _loadState();
    } catch (e) {
      _say(_message(e, 'تعذّر الرفع إلى درايف'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// «آخر نسخة: أمس» — المدّة لا التاريخ: هي ما يقول إن كانت النسخة تكفي.
  static String? _sinceLabel(String? raw) {
    final at = raw == null ? null : DateTime.tryParse(raw)?.toLocal();
    if (at == null) return 'لم تُؤخذ نسخة بعد';
    final days = DateTime.now().difference(at).inDays;
    return switch (days) {
      0 => 'آخر نسخة: اليوم',
      1 => 'آخر نسخة: أمس',
      < 30 => 'آخر نسخة: منذ $days يوماً',
      _ => 'آخر نسخة: منذ ${(days / 30).floor()} شهراً',
    };
  }

  static String _message(Object error, String fallback) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['message'] is String) return data['message'] as String;
    }
    return fallback;
  }
}
