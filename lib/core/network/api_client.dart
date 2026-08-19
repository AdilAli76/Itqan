import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// عميل HTTP موحّد لكل النظام — بديل مباشر لـ Supabase.instance.client.
/// يحقن توكن JWT تلقائياً في كل طلب، ويُنشأ مرة واحدة عبر [ApiClient.instance].
class ApiClient {
  ApiClient._internal() {
    _dio = Dio(BaseOptions(baseUrl: baseUrl, connectTimeout: const Duration(seconds: 10)));
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.read(key: _tokenKey);
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ));
  }

  static final ApiClient instance = ApiClient._internal();

  /// عنوان الـ Backend.
  ///
  /// على الويب يُشتقّ من أصل الصفحة وقت التشغيل: الخادم يخدم الويب والـAPI
  /// من موقع IIS واحد، فأيّاً كان العنوان الذي فُتحت به الصفحة فهو عنوان
  /// الـAPI. وهذا يجعل حزمة نشر واحدة تعمل على أي نطاق بلا إعادة بناء —
  /// العنوان المخبوز وقت البناء كان يربط الحزمة بنطاق واحد، فتُعاد بناؤها
  /// عند كل تغيّر في العنوان (وقع فعلاً ثلاث مرّات في أول نشر: عنوان IP،
  /// ثم نطاق، ثم نفق).
  ///
  /// وسطح المكتب والأندرويد لا صفحة لهما يُشتقّ منها، فيبقى --dart-define
  /// طريقهما. ويظلّ متاحاً على الويب أيضاً ويُقدَّم على الاشتقاق، لحالة
  /// استضافة الـAPI على أصل مختلف.
  static const String _definedBaseUrl = String.fromEnvironment('API_BASE_URL');

  static String get baseUrl {
    if (_definedBaseUrl.isNotEmpty) return _definedBaseUrl;
    if (kIsWeb) return '${Uri.base.origin}/api';
    return 'https://localhost:5001/api';
  }

  static const _tokenKey = 'kinetic_jwt_token';
  final _storage = const FlutterSecureStorage();
  late final Dio _dio;

  Dio get dio => _dio;

  Future<void> saveToken(String token) => _storage.write(key: _tokenKey, value: token);
  Future<void> clearToken() => _storage.delete(key: _tokenKey);
  Future<String?> readToken() => _storage.read(key: _tokenKey);
}
