import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../network/api_client.dart';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.latest,
    required this.current,
    required this.mandatory,
    required this.downloadUrl,
    required this.notes,
  });

  final String latest;
  final String current;
  final bool mandatory;
  final String? downloadUrl;
  final String? notes;

  bool get available => _isNewer(latest, current);
}

/// مقارنة إصدارات رقمية (1.2.10 أحدث من 1.2.9).
///
/// المقارنة النصّية المباشرة تُخطئ هنا: '1.2.10' أصغر من '1.2.9' نصّياً
/// لأن '1' قبل '9' — فيبقى العميل على نسخة أقدم وهو يظنّها الأحدث.
bool _isNewer(String latest, String current) {
  List<int> parts(String v) => v
      .split('+')
      .first
      .split('.')
      .map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
      .toList();

  final a = parts(latest);
  final b = parts(current);
  final n = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

/// يسأل الخادم عن أحدث إصدار ويقارنه بالمثبَّت.
///
/// الويب مستثنى: يُخدَم من الخادم فهو محدَّث دائماً بحكم التعريف، وعرض
/// شريط تحديث فيه إزعاج بلا معنى.
final appUpdateProvider = FutureProvider<AppUpdateInfo?>((ref) async {
  if (kIsWeb) return null;
  try {
    final info = await PackageInfo.fromPlatform();
    final response = await ApiClient.instance.dio.get('/app-version');
    final data = response.data as Map<String, dynamic>;

    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    return AppUpdateInfo(
      latest: data['latestVersion'] as String? ?? info.version,
      current: info.version,
      mandatory: data['mandatory'] as bool? ?? false,
      downloadUrl: (isAndroid ? data['androidDownloadUrl'] : data['downloadUrl']) as String?,
      notes: data['notes'] as String?,
    );
  } catch (_) {
    // الخادم غير متاح أو النقطة غير منشورة بعد — لا يُعطَّل التطبيق لأجل
    // فحص تحديث.
    return null;
  }
});
