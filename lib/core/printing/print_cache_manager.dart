import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// مدير تخزين مؤقت لموارد الطباعة — الشعارات والقوالب.
///
/// يقلل عدد الاستدعاءات الشبكية بحفظ الموارد محلياً.
class PrintCacheManager {
  static const Duration _cacheDuration = Duration(hours: 24);
  static const _storage = FlutterSecureStorage();
  static const _cacheKeyPrefix = 'print_cache_';

  /// صورة الشعار المخزنة في الذاكرة (سريعة الوصول).
  static Uint8List? _cachedLogo;
  static DateTime? _logoCachedAt;

  /// قالب الإيصال المخزن في الذاكرة.
  static Map<String, dynamic>? _cachedTemplate;
  static DateTime? _templateCachedAt;

  /// هل الذاكرة المؤقتة للشعار لا تزال صحيحة (لم تنته صلاحيتها)?
  static bool get isLogoCacheValid {
    if (_cachedLogo == null || _logoCachedAt == null) return false;
    return DateTime.now().difference(_logoCachedAt!).compareTo(_cacheDuration) < 0;
  }

  /// هل الذاكرة المؤقتة للقالب لا تزال صحيحة?
  static bool get isTemplateCacheValid {
    if (_cachedTemplate == null || _templateCachedAt == null) return false;
    return DateTime.now().difference(_templateCachedAt!).compareTo(_cacheDuration) < 0;
  }

  /// الحصول على الشعار من الذاكرة المؤقتة أو إرجاع null إن انتهت صلاحيتها.
  static Uint8List? getCachedLogo() {
    if (isLogoCacheValid) return _cachedLogo;
    _cachedLogo = null;
    _logoCachedAt = null;
    return null;
  }

  /// الحصول على القالب من الذاكرة المؤقتة أو إرجاع null إن انتهت صلاحيتها.
  static Map<String, dynamic>? getCachedTemplate() {
    if (isTemplateCacheValid) return _cachedTemplate;
    _cachedTemplate = null;
    _templateCachedAt = null;
    return null;
  }

  /// حفظ الشعار في الذاكرة المؤقتة.
  static void cacheLogo(Uint8List logoBytes) {
    _cachedLogo = logoBytes;
    _logoCachedAt = DateTime.now();
  }

  /// حفظ القالب في الذاكرة المؤقتة.
  static void cacheTemplate(Map<String, dynamic> template) {
    _cachedTemplate = Map.from(template);
    _templateCachedAt = DateTime.now();
  }

  /// حذف كل الذاكرة المؤقتة (استخدم عند تسجيل الخروج أو تبديل المستخدم).
  static void clearAll() {
    _cachedLogo = null;
    _logoCachedAt = null;
    _cachedTemplate = null;
    _templateCachedAt = null;
  }
}
