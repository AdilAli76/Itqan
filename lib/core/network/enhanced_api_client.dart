import 'package:http/http.dart' as http;
import 'dart:convert';
import '../sync/sync_engine.dart';
import '../local_database/local_db.dart';

/// API Client محسّن مع دعم المزامنة
class EnhancedApiClient {
  static final EnhancedApiClient _instance = EnhancedApiClient._internal();

  factory EnhancedApiClient() {
    return _instance;
  }

  EnhancedApiClient._internal() {
    _initialize();
  }

  // المتغيرات
  late final SyncEngine _syncEngine;
  late final LocalDatabase _localDb;
  String _serverUrl = 'https://api.example.com'; // في الإنتاج
  late String _authToken;
  static const Duration _timeout = Duration(seconds: 30);

  // متغيرات الحالة
  bool _isConnected = false;
  int _requestCount = 0;
  int _successCount = 0;
  int _failureCount = 0;
  DateTime? _lastSync = null;

  // Getters
  bool get isConnected => _isConnected;
  int get requestCount => _requestCount;
  int get successCount => _successCount;
  int get failureCount => _failureCount;
  DateTime? get lastSync => _lastSync;

  /// تهيئة الـ Client
  void _initialize() {
    _syncEngine = SyncEngine();
    _localDb = LocalDatabase();
    _authToken = 'demo-token'; // في الإنتاج، سيتم جلبها من التسجيل
  }

  /// تعيين عنوان الخادم
  void setServerUrl(String url) {
    _serverUrl = url;
    print('🌐 تم تعيين الخادم: $_serverUrl');
  }

  /// تعيين توكن المصادقة
  void setAuthToken(String token) {
    _authToken = token;
    print('🔐 تم تعيين التوكن');
  }

  /// فحص الاتصال بالخادم
  Future<bool> checkConnection() async {
    try {
      print('🔗 فحص الاتصال بالخادم...');

      final response = await http
          .get(
            Uri.parse('$_serverUrl/health'),
            headers: _getHeaders(),
          )
          .timeout(_timeout);

      _isConnected = response.statusCode == 200;

      if (_isConnected) {
        print('✅ الخادم متصل');
      } else {
        print('❌ الخادم غير متاح');
      }

      return _isConnected;
    } catch (e) {
      print('❌ خطأ في الاتصال: $e');
      _isConnected = false;
      return false;
    }
  }

  /// مزامنة العناصر المعلقة مع الخادم
  Future<SyncResult> syncPendingItems() async {
    try {
      print('🔄 بدء مزامنة العناصر المعلقة...');

      // فحص الاتصال أولاً
      if (!await checkConnection()) {
        print('❌ لا يوجد اتصال');
        return SyncResult(
          success: false,
          message: 'لا يوجد اتصال بالخادم',
          itemsSynced: 0,
          itemsFailed: 0,
        );
      }

      // جلب العناصر المعلقة
      final pendingItems = await _localDb.getPendingSyncItems();

      if (pendingItems.isEmpty) {
        print('ℹ️ لا توجد عناصر للمزامنة');
        return SyncResult(
          success: true,
          message: 'لا توجد عناصر معلقة',
          itemsSynced: 0,
          itemsFailed: 0,
        );
      }

      print('📋 وجدنا ${pendingItems.length} عنصر');

      int synced = 0;
      int failed = 0;

      // معالجة كل عنصر
      for (final item in pendingItems) {
        try {
          await _syncItemToServer(item);
          synced++;
        } catch (e) {
          print('❌ فشل: ${item['record_id']} - $e');
          failed++;
        }
      }

      _lastSync = DateTime.now();

      return SyncResult(
        success: failed == 0,
        message: synced > 0 ? '✅ تمت مزامنة $synced عنصر' : '❌ فشل',
        itemsSynced: synced,
        itemsFailed: failed,
      );
    } catch (e) {
      print('❌ خطأ في المزامنة: $e');
      return SyncResult(
        success: false,
        message: 'خطأ: $e',
        itemsSynced: 0,
        itemsFailed: 0,
      );
    }
  }

  /// مزامنة عنصر واحد إلى الخادم
  Future<void> _syncItemToServer(Map<String, dynamic> item) async {
    final operation = item['operation'] as String;
    final tableName = item['table_name'] as String;
    final recordId = item['record_id'] as String;
    final data = item['data'] ?? {};

    print('   📤 إرسال: $tableName - $operation');

    final response = await http
        .post(
          Uri.parse('$_serverUrl/sync'),
          headers: _getHeaders(),
          body: jsonEncode({
            'table': tableName,
            'operation': operation,
            'record_id': recordId,
            'data': data,
            'timestamp': DateTime.now().toIso8601String(),
          }),
        )
        .timeout(_timeout);

    _requestCount++;

    if (response.statusCode == 200 || response.statusCode == 201) {
      print('      ✅ نجح');
      _successCount++;
      // وضع علامة النجاح في DB
      await _localDb.markSyncItemAsSuccess(item['id']);
    } else {
      print('      ❌ فشل: ${response.statusCode}');
      _failureCount++;
      throw Exception('الخادم رد بـ ${response.statusCode}');
    }
  }

  /// جلب البيانات من الخادم
  Future<Map<String, dynamic>> fetchData(String endpoint) async {
    try {
      print('📥 جلب: $endpoint');

      final response = await http
          .get(
            Uri.parse('$_serverUrl$endpoint'),
            headers: _getHeaders(),
          )
          .timeout(_timeout);

      _requestCount++;

      if (response.statusCode == 200) {
        _successCount++;
        final data = jsonDecode(response.body);
        print('✅ تم الجلب بنجاح');
        return data;
      } else {
        _failureCount++;
        throw Exception('الخادم رد بـ ${response.statusCode}');
      }
    } catch (e) {
      print('❌ خطأ: $e');
      _failureCount++;
      throw Exception('خطأ في الجلب: $e');
    }
  }

  /// إرسال بيانات للخادم
  Future<Map<String, dynamic>> postData(
    String endpoint,
    Map<String, dynamic> data,
  ) async {
    try {
      print('📤 إرسال: $endpoint');

      final response = await http
          .post(
            Uri.parse('$_serverUrl$endpoint'),
            headers: _getHeaders(),
            body: jsonEncode(data),
          )
          .timeout(_timeout);

      _requestCount++;

      if (response.statusCode == 200 || response.statusCode == 201) {
        _successCount++;
        final responseData = jsonDecode(response.body);
        print('✅ تم الإرسال بنجاح');
        return responseData;
      } else {
        _failureCount++;
        throw Exception('الخادم رد بـ ${response.statusCode}');
      }
    } catch (e) {
      print('❌ خطأ: $e');
      _failureCount++;
      throw Exception('خطأ في الإرسال: $e');
    }
  }

  /// الحصول على رؤوس الطلب
  Map<String, String> _getHeaders() {
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $_authToken',
      'User-Agent': 'ItqanERP/1.0',
      'Accept': 'application/json',
    };
  }

  /// الحصول على الإحصائيات
  ApiStatistics getStatistics() {
    return ApiStatistics(
      totalRequests: _requestCount,
      successfulRequests: _successCount,
      failedRequests: _failureCount,
      lastSync: _lastSync,
      isConnected: _isConnected,
    );
  }

  /// إعادة تعيين الإحصائيات
  void resetStatistics() {
    _requestCount = 0;
    _successCount = 0;
    _failureCount = 0;
    print('🔄 تم إعادة تعيين الإحصائيات');
  }
}

/// نتيجة المزامنة
class SyncResult {
  const SyncResult({
    required this.success,
    required this.message,
    required this.itemsSynced,
    required this.itemsFailed,
  });

  final bool success;
  final String message;
  final int itemsSynced;
  final int itemsFailed;

  @override
  String toString() => 'SyncResult('
      'success: $success, '
      'message: $message, '
      'synced: $itemsSynced, '
      'failed: $itemsFailed'
      ')';
}

/// إحصائيات API
class ApiStatistics {
  const ApiStatistics({
    required this.totalRequests,
    required this.successfulRequests,
    required this.failedRequests,
    required this.lastSync,
    required this.isConnected,
  });

  final int totalRequests;
  final int successfulRequests;
  final int failedRequests;
  final DateTime? lastSync;
  final bool isConnected;

  double get successRate {
    if (totalRequests == 0) return 0;
    return (successfulRequests / totalRequests) * 100;
  }

  @override
  String toString() => 'ApiStatistics('
      'total: $totalRequests, '
      'success: $successfulRequests, '
      'failed: $failedRequests, '
      'rate: ${successRate.toStringAsFixed(2)}%'
      ')';
}
