import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/section_card.dart';
// استيرادٌ شرطي: `dart:io` غير موجود على الويب واستيرادُه مباشرةً يُسقط
// `flutter build web` كلّه — كما في [ApiClient].
import '../data/backup_folder_web.dart'
    if (dart.library.io) '../data/backup_folder_io.dart';

/// النسخة الاحتياطية — تنزيلٌ يخرج من الجهاز.
///
/// <para><b>سبب وجوده:</b> لم يكن في النظام أي طريق يُخرج البيانات، فكل ما
/// أدخلته الجهة كان يعيش على قرص خادمٍ واحد. والقرص يتلف، والاستضافة
/// تُغلق، والخادم يُسرَق.</para>
///
/// <para><b>ولماذا التنزيل اليدوي أوّلاً:</b> لا يحتاج حساباً خارجياً ولا
/// موافقة مزوّد، ويعمل في اليوم الأول من التركيب — والنسخة التي تُحفظ على
/// فلاشة اليوم خيرٌ من رفعٍ تلقائي يُنتظر شهراً. والرفع التلقائي يُبنى
/// فوق نفس النقطة لا بدلاً منها.</para>
class BackupSection extends StatefulWidget {
  const BackupSection({super.key});

  @override
  State<BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends State<BackupSection> {
  Map<String, dynamic>? _summary;
  bool _loadingSummary = true;
  bool _busy = false;
  String? _error;
  int _received = 0;

  /// مجلّد النسخ المحفوظ — على هذا الجهاز لا في إعدادات المنظمة.
  ///
  /// <para>مسارُ قرصٍ لا معنى له على جهازٍ آخر: «D:\نسخ» عند المحاسب لا
  /// وجود له على حاسوب المدير. فيُحفظ محلياً، ولكل جهاز مجلّده.</para>
  String? _folder;

  static const _storage = FlutterSecureStorage();
  static const _folderKey = 'backup_folder';

  @override
  void initState() {
    super.initState();
    _loadSummary();
    _loadFolder();
  }

  Future<void> _loadFolder() async {
    if (!supportsFolderSave) return;
    try {
      final saved = await _storage.read(key: _folderKey);
      if (mounted && saved != null && saved.isNotEmpty) setState(() => _folder = saved);
    } catch (_) {
      // تعذّر قراءة التفضيل ليس عطلاً يستحق رسالة: الميزة كلّها اختصارٌ
      // لنافذة الحفظ، وغيابها يعيدنا إليها لا أكثر.
    }
  }

  Future<void> _pickFolder() async {
    final chosen = await FilePicker.getDirectoryPath(
      dialogTitle: 'اختر مجلّد النسخ الاحتياطية',
    );
    if (chosen == null || chosen.isEmpty) return;
    await _storage.write(key: _folderKey, value: chosen);
    if (mounted) setState(() => _folder = chosen);
  }

  Future<void> _forgetFolder() async {
    await _storage.delete(key: _folderKey);
    if (mounted) setState(() => _folder = null);
  }

  Future<void> _loadSummary() async {
    try {
      final response = await ApiClient.instance.dio.get('/backup/summary');
      if (!mounted) return;
      setState(() => _summary = Map<String, dynamic>.from(response.data as Map));
    } catch (e) {
      if (mounted) setState(() => _error = _message(e, 'تعذّر قراءة حجم النسخة'));
    } finally {
      if (mounted) setState(() => _loadingSummary = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    final rows = (summary?['totalRows'] as num?)?.toInt() ?? 0;
    final tables = (summary?['tables'] as num?)?.toInt() ?? 0;
    final missing = (summary?['missingTables'] as List? ?? const []).cast<String>();

    return SectionCard(
      title: 'النسخة الاحتياطية',
      icon: Icons.backup_outlined,
      children: [
        Text(
          'ملفٌ واحد فيه كل بيانات المنظمة: العملاء والأرصدة والفواتير '
          'والحركات. احفظه خارج هذا الجهاز — على فلاشة أو قرص آخر — '
          'فنسخةٌ على نفس الخادم تضيع معه.',
          style: AppTextStyles.labelMd(),
        ),
        const SizedBox(height: 12),
        if (_loadingSummary)
          const LinearProgressIndicator()
        else if (summary != null) ...[
          Text(
            // الرقم قبل الضغط على الزرّ: تنزيلٌ يبدأ بلا حجمٍ معلوم يترك
            // المستخدم أمام شريط لا يعرف أينتهي بعد ثانية أم بعد ربع ساعة.
            'الحالة: $tables جدولاً · ${_thousands(rows)} صفّاً',
            style: AppTextStyles.bodyMd(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          // آخر نسخة: السؤال الحقيقي ليس «أيمكنني أخذ نسخة؟» بل «هل أنا
          // محميّ اليوم؟». ونسخةٌ لم تُؤخذ قطّ — أو عمرها شهور — تُقال
          // بلون التحذير لا كسطر رمادي يمرّ عليه النظر.
          Text(
            _lastExportLabel(summary['lastExportAt'] as String?),
            style: AppTextStyles.bodyMd(
                color: _lastExportStale(summary['lastExportAt'] as String?)
                    ? AppColors.warning
                    : AppColors.textSecondary),
          ),
        ],
        if (missing.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            // نقصٌ يُقال قبل التنزيل: نسخةٌ تُظنّ كاملة وهي ناقصة أخطر من
            // ألّا تكون هناك نسخة أصلاً.
            'تنبيه: ${missing.length} جدولاً في النظام ولا وجود لها في قاعدة هذا الخادم '
            '— النسخة ستخرج بدونها. راجع ترقية القاعدة قبل الاعتماد عليها.',
            style: AppTextStyles.caption(color: AppColors.warning),
          ),
        ],
        if (_busy) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
          const SizedBox(height: 6),
          Text('نُزّل ${_megabytes(_received)} — لا تُغلق الشاشة',
              style: AppTextStyles.caption(color: AppColors.textSecondary)),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
        ],
        if (supportsFolderSave) ...[
          const SizedBox(height: 12),
          _folderRow(),
        ],
        const SizedBox(height: 12),
        // زرٌّ بعرض القسم لا داخل Row: الزرّ بأيقونته ونصّه يتجاوز عرض
        // البطاقة على هاتف بعرض 360 فيفيض 18 بكسل — أمسكه ui_audit_test.
        FilledButton.icon(
          onPressed: _busy ? null : _download,
          icon: Icon(_folder == null ? Icons.download_outlined : Icons.save_outlined, size: 18),
          label: Text(_folder == null ? 'تنزيل نسخة احتياطية' : 'حفظ نسخة في المجلّد'),
        ),
        if (_folder != null) ...[
          const SizedBox(height: 4),
          // ويبقى «حفظ باسم» متاحاً: المجلّد اختصارٌ لا حبس. نسخةٌ تُطلب
          // على فلاشة مرّةً لا يجوز أن تلزم تغيير الإعداد ثم إعادته.
          TextButton.icon(
            onPressed: _busy ? null : () => _download(toFolder: false),
            icon: const Icon(Icons.download_outlined, size: 18),
            label: const Text('حفظ باسم…'),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          // تحذيرٌ صريح: الملف ليس تقريراً يُرسَل بالبريد.
          'الملف يحوي كل شيء ولا يُشارَك — من يملكه يملك بيانات الجهة كاملة.',
          style: AppTextStyles.caption(color: AppColors.warning),
        ),
        if (summary != null) ...[
          const Divider(height: 32),
          _autoSection(Map<String, dynamic>.from(summary['auto'] as Map? ?? const {})),
        ],
      ],
    );
  }

  /// الرفع الليلي إلى Google Drive.
  ///
  /// <para><b>سبب وجوده:</b> النسخة اليدوية تعتمد على أن يتذكّرها إنسان —
  /// يتذكّرها شهراً ثم ينسى، ولا يكتشف نسيانه إلا يوم يحتاجها.</para>
  ///
  /// <para><b>وثلاث حالات لا حالتان:</b> «غير مهيّأ على الخادم» ليست
  /// «غير مربوط». الأولى ليست بيد المالك أصلاً — وزرُّ ربطٍ يفشل بلا سبب
  /// يجعله يظنّ العطب في حسابه فيعيد المحاولة عشراً.</para>
  Widget _autoSection(Map<String, dynamic> auto) {
    final configured = auto['serverConfigured'] as bool? ?? false;
    final connected = auto['connected'] as bool? ?? false;
    final enabled = auto['enabled'] as bool? ?? false;
    final hour = (auto['hour'] as num?)?.toInt() ?? 3;
    final email = auto['accountEmail'] as String?;
    final lastStatus = auto['lastStatus'] as String?;
    final lastError = auto['lastError'] as String?;
    final lastAt = auto['lastAt'] as String?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.cloud_upload_outlined, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Text('الرفع التلقائي إلى Google Drive', style: AppTextStyles.bodyLg()),
          ],
        ),
        const SizedBox(height: 6),
        if (!configured)
          Text(
            'غير مهيّأ على هذا الخادم — يلزم تسجيل التطبيق لدى قوقل مرّةً واحدة. '
            'راجع مزوّد النظام.',
            style: AppTextStyles.caption(color: AppColors.textSecondary),
          )
        else ...[
          Text(
            connected
                ? 'مربوط بحساب ${email ?? '—'} — تُرفع النسخة إلى مجلّد خاص بالنظام في درايفك.'
                : 'اربط حساب قوقل فتُرفع نسخةٌ كل ليلة بلا أن يفتح أحد التطبيق. '
                    'ولا يصل النظام إلا إلى الملفات التي ينشئها هو.',
            style: AppTextStyles.caption(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          if (!connected)
            OutlinedButton.icon(
              onPressed: _busy ? null : _connectGoogle,
              icon: const Icon(Icons.link, size: 18),
              label: const Text('ربط حساب قوقل'),
            )
          else ...[
            SwitchListTile(
              value: enabled,
              onChanged: _busy ? null : (v) => _saveAuto(enabled: v, hour: hour),
              contentPadding: EdgeInsets.zero,
              title: Text('نسخة كل ليلة', style: AppTextStyles.bodyMd(color: AppColors.textPrimary)),
              subtitle: Text('بتوقيت المنظمة لا بتوقيت غرينتش',
                  style: AppTextStyles.labelMd()),
            ),
            DropdownButtonFormField<int>(
              isExpanded: true,
              initialValue: hour,
              decoration: const InputDecoration(labelText: 'ساعة الرفع'),
              // ساعاتٌ محدّدة لا أربع وعشرون: الخيار الحقيقي «بعد إغلاق
              // المحلّ»، وقائمةٌ بأربعة وعشرين سطراً تجعل القرار أثقل بلا
              // أن تجعله أدقّ.
              items: const [0, 1, 2, 3, 4, 5, 22, 23]
                  .map((h) => DropdownMenuItem(
                      value: h, child: Text('${h.toString().padLeft(2, '0')}:00')))
                  .toList(),
              onChanged: _busy ? null : (v) => _saveAuto(enabled: enabled, hour: v ?? hour),
            ),
            const SizedBox(height: 4),
            if (lastStatus == 'failed')
              Text(
                // الفشل يُقال بصوتٍ عالٍ: رفعٌ يفشل ليلةً بعد ليلة بلا أثر
                // في الشاشة يترك المالك يظنّ نفسه محميّاً.
                'آخر محاولة فشلت: ${lastError ?? 'سبب غير معروف'}',
                style: AppTextStyles.caption(color: AppColors.danger),
              )
            else if (lastAt != null)
              Text('آخر رفع تلقائي: ${lastAt.substring(0, 16).replaceAll('T', ' ')}',
                  style: AppTextStyles.caption(color: AppColors.textSecondary)),
            TextButton(
              onPressed: _busy ? null : _disconnectGoogle,
              child: const Text('فكّ الارتباط'),
            ),
          ],
        ],
      ],
    );
  }

  Future<void> _connectGoogle() async {
    setState(() => _busy = true);
    try {
      final response = await ApiClient.instance.dio.get('/backup/google/authorize');
      final url = (response.data as Map)['url'] as String;
      // يُفتح في المتصفّح لا داخل التطبيق: قوقل ترفض شاشة الموافقة داخل
      // WebView مدمج (سياسة تمنع اختطاف كلمات المرور).
      await launchUrlString(url, mode: LaunchMode.externalApplication);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أكمل الموافقة في المتصفّح ثم عُد وحدّث الشاشة')),
      );
    } catch (e) {
      if (mounted) setState(() => _error = _message(e, 'تعذّر بدء الربط'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnectGoogle() async {
    setState(() => _busy = true);
    try {
      await ApiClient.instance.dio.post('/backup/google/disconnect');
      await _loadSummary();
    } catch (e) {
      if (mounted) setState(() => _error = _message(e, 'تعذّر فكّ الارتباط'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveAuto({required bool enabled, required int hour}) async {
    setState(() => _busy = true);
    try {
      await ApiClient.instance.dio.put('/backup/auto', data: {'enabled': enabled, 'hour': hour});
      await _loadSummary();
    } catch (e) {
      if (mounted) setState(() => _error = _message(e, 'تعذّر حفظ الإعداد'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// سطر المجلّد: أين تُحفظ النسخ، وكيف يُغيَّر.
  ///
  /// <para><b>سبب وجوده:</b> أقصر طريق إلى «نسخة خارج الجهاز» بلا حسابٍ
  /// خارجي ولا موافقة مزوّد: مجلّد Google Drive أو OneDrive المزامَن على
  /// هذا الحاسوب مجلّدٌ عادي — ما يُكتب فيه يُرفع إلى السحابة من تلقائه.
  /// فاختيارُه مرّةً يجعل النسخة الأسبوعية ضغطةً واحدة.</para>
  Widget _folderRow() {
    final folder = _folder;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.folder_outlined, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                folder == null ? 'لم يُختَر مجلّد — يُحفظ بنافذة النظام' : folderLabel(folder),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyMd(color: AppColors.textSecondary),
              ),
            ),
            TextButton(
              onPressed: _busy ? null : _pickFolder,
              child: Text(folder == null ? 'اختر مجلّداً' : 'تغيير'),
            ),
            if (folder != null)
              IconButton(
                tooltip: 'إلغاء المجلّد',
                icon: const Icon(Icons.close, size: 18),
                onPressed: _busy ? null : _forgetFolder,
              ),
          ],
        ),
        if (folder == null)
          Text(
            'اختر مجلّد Google Drive أو OneDrive المزامَن على هذا الجهاز، '
            'فتُرفع كل نسخة إلى السحابة من تلقائها.',
            style: AppTextStyles.caption(color: AppColors.textSecondary),
          ),
      ],
    );
  }

  /// <param name="toFolder">
  /// يحفظ في المجلّد المحفوظ إن وُجد. و`false` يفرض نافذة النظام — راجع
  /// زرّ «حفظ باسم».
  /// </param>
  Future<void> _download({bool toFolder = true}) async {
    setState(() {
      _busy = true;
      _error = null;
      _received = 0;
    });

    try {
      final response = await ApiClient.instance.dio.get<List<int>>(
        '/backup/export',
        options: Options(responseType: ResponseType.bytes),
        onReceiveProgress: (received, _) {
          if (mounted) setState(() => _received = received);
        },
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) throw Exception('empty');

      final stamp = DateTime.now()
          .toIso8601String()
          .substring(0, 16)
          .replaceAll(':', '')
          .replaceAll('T', '-');

      final fileName = 'kinetic-backup-$stamp.zip';
      final folder = _folder;

      if (toFolder && folder != null && supportsFolderSave) {
        final path = await writeBackupFile(folder, fileName, Uint8List.fromList(bytes));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حُفظت النسخة (${_megabytes(bytes.length)}) في $path')),
        );
        // آخر نسخة تغيّر — والرقم على الشاشة يجب أن يوافق ما حدث للتوّ.
        await _loadSummary();
        return;
      }

      final saved = await FilePicker.saveFile(
        fileName: fileName,
        bytes: Uint8List.fromList(bytes),
      );
      if (!mounted) return;
      if (saved != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حُفظت النسخة (${_megabytes(bytes.length)})')),
        );
        await _loadSummary();
      }
    } catch (e) {
      if (mounted) setState(() => _error = _message(e, 'تعذّر إنشاء النسخة'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// «منذ ثلاثة أيام» لا تاريخٌ مطلق: المدّة هي ما يقول إن كانت النسخة
  /// تكفي، والتاريخ يحتاج من يطرحه من اليوم في رأسه.
  static String _lastExportLabel(String? raw) {
    final at = raw == null ? null : DateTime.tryParse(raw)?.toLocal();
    if (at == null) return 'لم تُؤخذ نسخة من قبل';

    final days = DateTime.now().difference(at).inDays;
    final when = switch (days) {
      0 => 'اليوم',
      1 => 'أمس',
      < 30 => 'منذ $days يوماً',
      _ => 'منذ ${(days / 30).floor()} شهراً',
    };
    return 'آخر نسخة: $when (${at.toIso8601String().substring(0, 10)})';
  }

  /// أسبوعان حدّاً: ليس رقماً مقدَّساً، لكنه يفصل بين «نسخةٌ قريبة» و«نسخةٌ
  /// لو استُرجعت اليوم لضاع منها عملُ أسابيع».
  static bool _lastExportStale(String? raw) {
    final at = raw == null ? null : DateTime.tryParse(raw)?.toLocal();
    if (at == null) return true;
    return DateTime.now().difference(at).inDays >= 14;
  }

  static String _megabytes(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} كيلوبايت';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} ميغابايت';
  }

  static String _thousands(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  static String _message(Object error, String fallback) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['message'] is String) return data['message'] as String;
    }
    return fallback;
  }
}
