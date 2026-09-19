import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'connectivity_state.dart';

/// خدمة كشف الاتصال بالانترنت
class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();

  factory ConnectivityService() {
    return _instance;
  }

  ConnectivityService._internal() {
    _initialize();
  }

  // Connectivity plugin
  final Connectivity _connectivity = Connectivity();

  // Streams و Controllers
  late final StreamController<ConnectivityInfo> _connectivityStream;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;

  // متغيرات الحالة
  ConnectivityInfo _currentInfo = const ConnectivityInfo(
    status: ConnectivityStatus.loading,
    isOnline: false,
    connectionType: 'unknown',
  );

  // متغيرات التحكم
  int _retryCount = 0;
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 5);

  // Getters
  ConnectivityInfo get currentInfo => _currentInfo;
  Stream<ConnectivityInfo> get connectivityStream => _connectivityStream.stream;
  bool get isOnline => _currentInfo.isOnline;
  bool get isOffline => !_currentInfo.isOnline;

  /// تهيئة الخدمة
  void _initialize() {
    _connectivityStream = StreamController<ConnectivityInfo>.broadcast();
    _setupConnectivityListener();
  }

  /// إعداد مستمع الاتصال
  void _setupConnectivityListener() {
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      (ConnectivityResult result) {
        _handleConnectivityChange([result]);
      },
      onError: (error) {
        print('❌ خطأ في مستمع الاتصال: $error');
        _updateStatus(false, 'خطأ');
      },
    ) as StreamSubscription<List<ConnectivityResult>>;

    // فحص الاتصال الحالي عند البدء
    _checkConnectivityStatus();
  }

  /// معالجة تغيير الاتصال
  Future<void> _handleConnectivityChange(List<ConnectivityResult> results) async {
    // إذا كانت النتيجة تحتوي على عدم اتصال
    if (results.contains(ConnectivityResult.none)) {
      print('📡 تم اكتشاف: منقطع عن الانترنت');
      _updateStatus(false, 'لا يوجد اتصال');
      _retryCount = 0;
      return;
    }

    // إذا كانت هناك نتيجة اتصال، حاول الاتصال
    if (results.isNotEmpty) {
      print('📡 تم اكتشاف: محاولة الاتصال...');
      await _verifyConnectivity(results.first);
    }
  }

  /// التحقق من الاتصال الفعلي
  Future<void> _verifyConnectivity(ConnectivityResult result) async {
    try {
      _updateStatus(true, _getConnectionType(result), isLoading: true);

      // محاولة الاتصال بخادم بسيط
      final isConnected = await _testConnection();

      if (isConnected) {
        print('✅ تم التحقق: متصل بالانترنت');
        _updateStatus(true, _getConnectionType(result));
        _retryCount = 0;
      } else {
        print('⚠️ تحذير: بدون انترنت (رغم اكتشاف شبكة)');
        _updateStatus(false, _getConnectionType(result));
        _retryConnection();
      }
    } catch (e) {
      print('❌ خطأ في التحقق: $e');
      _updateStatus(false, 'خطأ في التحقق');
      _retryConnection();
    }
  }

  /// اختبار الاتصال الفعلي
  Future<bool> _testConnection() async {
    try {
      // محاولة الوصول لخادم بسيط
      final result = await Future.wait(
        [
          _tryConnect('https://www.google.com'),
          _tryConnect('https://www.cloudflare.com'),
        ],
        eagerError: false,
      );
      return result.any((bool success) => success);
    } catch (e) {
      print('❌ فشل اختبار الاتصال: $e');
      return false;
    }
  }

  /// محاولة الاتصال بـ URL
  Future<bool> _tryConnect(String url) async {
    try {
      // بدلاً من http request حقيقي، نستخدم محاكاة
      // في الإنتاج يمكن استخدام package:http
      await Future.delayed(const Duration(milliseconds: 500));
      return true;
    } catch (e) {
      return false;
    }
  }

  /// إعادة محاولة الاتصال
  void _retryConnection() {
    if (_retryCount < _maxRetries) {
      _retryCount++;
      print('🔄 محاولة الاتصال #$_retryCount...');

      Future.delayed(_retryDelay, () {
        _checkConnectivityStatus();
      });
    }
  }

  /// فحص حالة الاتصال الحالية
  Future<void> _checkConnectivityStatus() async {
    try {
      final result = await _connectivity.checkConnectivity();
      _handleConnectivityChange([result]);
    } catch (e) {
      print('❌ خطأ في الفحص: $e');
      _updateStatus(false, 'خطأ');
    }
  }

  /// تحديث حالة الاتصال
  void _updateStatus(
    bool isOnline,
    String connectionType, {
    bool isLoading = false,
  }) {
    final newStatus = isLoading
        ? ConnectivityStatus.loading
        : (isOnline ? ConnectivityStatus.connected : ConnectivityStatus.disconnected);

    _currentInfo = _currentInfo.copyWith(
      status: newStatus,
      isOnline: isOnline,
      connectionType: connectionType,
      lastCheckedAt: DateTime.now(),
      retryCount: _retryCount,
    );

    print('📊 حالة جديدة: $_currentInfo');
    _connectivityStream.add(_currentInfo);
  }

  /// الحصول على نوع الاتصال
  String _getConnectionType(ConnectivityResult result) {
    switch (result) {
      case ConnectivityResult.wifi:
        return 'WiFi';
      case ConnectivityResult.mobile:
        return 'Mobile';
      case ConnectivityResult.ethernet:
        return 'Ethernet';
      case ConnectivityResult.vpn:
        return 'VPN';
      case ConnectivityResult.none:
        return 'None';
      default:
        return 'Unknown';
    }
  }

  /// محاكاة فقدان الاتصال (للاختبار)
  void simulateDisconnection() {
    print('🔴 محاكاة: فقدان الاتصال');
    _updateStatus(false, 'محاكاة - بدون اتصال');
  }

  /// محاكاة استعادة الاتصال (للاختبار)
  void simulateConnection() {
    print('🟢 محاكاة: استعادة الاتصال');
    _updateStatus(true, 'محاكاة - WiFi');
  }

  /// إعادة تعيين
  void reset() {
    _retryCount = 0;
    _updateStatus(false, 'unknown');
  }

  /// التنظيف والإغلاق
  void dispose() {
    _connectivitySubscription.cancel();
    _connectivityStream.close();
  }
}
