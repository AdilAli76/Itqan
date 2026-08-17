import 'package:dio/dio.dart';
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

  /// عنوان الـ Backend — في بيئة الإنتاج على Windows Server يُمرَّر عبر
  /// --dart-define=API_BASE_URL بدل تثبيته هنا مباشرة.
  static const String baseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: 'https://localhost:5001/api');

  static const _tokenKey = 'kinetic_jwt_token';
  final _storage = const FlutterSecureStorage();
  late final Dio _dio;

  Dio get dio => _dio;

  Future<void> saveToken(String token) => _storage.write(key: _tokenKey, value: token);
  Future<void> clearToken() => _storage.delete(key: _tokenKey);
  Future<String?> readToken() => _storage.read(key: _tokenKey);
}
