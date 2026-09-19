import 'dart:async';
import '../local_database/local_db.dart';
import '../connectivity/connectivity_service.dart';
import '../connectivity/connectivity_state.dart';

/// محرك المزامنة — يدمج قاعدة البيانات المحلية مع الخادم
class SyncEngine {
  static final SyncEngine _instance = SyncEngine._internal();

  factory SyncEngine() {
    return _instance;
  }

  SyncEngine._internal() {
    _initialize();
  }

  // الخدمات المطلوبة
  late final LocalDatabase _db;
  late final ConnectivityService _connectivity;

  // Stream controllers
  late final StreamController<SyncStatus> _syncStatusStream;
  late StreamSubscription<ConnectivityInfo> _connectivitySubscription;

  // متغيرات الحالة
  SyncStatus _currentStatus = SyncStatus.idle;
  bool _isSyncing = false;
  int _syncedItemsCount = 0;
  int _failedItemsCount = 0;
  DateTime? _lastSyncTime;

  // Getters
  SyncStatus get status => _currentStatus;
  Stream<SyncStatus> get statusStream => _syncStatusStream.stream;
  bool get isSyncing => _isSyncing;
  int get syncedItemsCount => _syncedItemsCount;
  int get failedItemsCount => _failedItemsCount;
  DateTime? get lastSyncTime => _lastSyncTime;

  // ثوابت المزامنة
  static const Duration _syncInterval = Duration(minutes: 5);
  static const Duration _retryDelay = Duration(seconds: 30);
  static const int _maxRetries = 3;

  /// تهيئة المحرك
  void _initialize() {
    _syncStatusStream = StreamController<SyncStatus>.broadcast();
    _db = LocalDatabase();
    _connectivity = ConnectivityService();
    _setupConnectivityListener();
  }

  /// إعداد مستمع الاتصال
  void _setupConnectivityListener() {
    _connectivitySubscription =
        _connectivity.connectivityStream.listen((info) async {
      if (info.isOnline && !_isSyncing) {
        print('🌐 تم اكتشاف: الاتصال متاح - بدء المزامنة');
        await startSync();
      }
    });
  }

  /// بدء عملية المزامنة
  Future<void> startSync() async {
    if (_isSyncing) {
      print('⚠️ المزامنة جارية بالفعل');
      return;
    }

    try {
      _isSyncing = true;
      _updateStatus(SyncStatus.syncing);
      _syncedItemsCount = 0;
      _failedItemsCount = 0;

      print('🔄 بدء عملية المزامنة...');

      // فحص الاتصال أولاً
      if (!_connectivity.isOnline) {
        print('❌ بدون اتصال - لا يمكن المزامنة');
        _updateStatus(SyncStatus.offline);
        _isSyncing = false;
        return;
      }

      // الخطوة 1: جلب العناصر المعلقة
      print('1️⃣ جلب العناصر المعلقة...');
      final pendingItems = await _db.getPendingSyncItems();

      if (pendingItems.isEmpty) {
        print('✅ لا توجد عناصر للمزامنة');
        _updateStatus(SyncStatus.synced);
        _lastSyncTime = DateTime.now();
        _isSyncing = false;
        return;
      }

      print('📋 وجدنا ${pendingItems.length} عنصر معلق');

      // الخطوة 2: معالجة كل عنصر
      print('2️⃣ معالجة العناصر...');
      for (final item in pendingItems) {
        await _processItem(item);
      }

      // الخطوة 3: التلخيص
      _lastSyncTime = DateTime.now();
      print('📊 ملخص المزامنة:');
      print('   • تمت: $_syncedItemsCount');
      print('   • فشل: $_failedItemsCount');
      print('   • الوقت: $_lastSyncTime');

      // تحديد الحالة النهائية
      if (_failedItemsCount == 0) {
        _updateStatus(SyncStatus.synced);
        print('✅ اكتملت المزامنة بنجاح');
      } else {
        _updateStatus(SyncStatus.syncedWithErrors);
        print('⚠️ المزامنة اكتملت مع أخطاء');
      }

      _isSyncing = false;
    } catch (e) {
      print('❌ خطأ في المزامنة: $e');
      _updateStatus(SyncStatus.error);
      _isSyncing = false;
    }
  }

  /// معالجة عنصر واحد
  Future<void> _processItem(Map<String, dynamic> item) async {
    try {
      final operation = item['operation'] as String;
      final tableName = item['table_name'] as String;
      final recordId = item['record_id'] as String;
      final syncId = item['id'];

      print('   📝 معالجة: $tableName - $operation ($recordId)');

      // محاكاة الإرسال للخادم
      await _simulateServerSync(operation, tableName, recordId);

      // وضع علامة النجاح في قاعدة البيانات المحلية
      await _db.markSyncItemAsSuccess(syncId);
      _syncedItemsCount++;

      print('      ✅ نجح');
    } catch (e) {
      print('      ❌ فشل: $e');
      _failedItemsCount++;

      // سنحاول مرة أخرى في المزامنة التالية
    }
  }

  /// محاكاة مزامنة مع الخادم
  Future<void> _simulateServerSync(
    String operation,
    String tableName,
    String recordId,
  ) async {
    // في الإنتاج، ستكون هناك طلبات HTTP فعلية
    await Future.delayed(const Duration(milliseconds: 500));

    // محاكاة احتمالية الفشل العشوائية (10%)
    if (DateTime.now().millisecond % 10 == 0) {
      throw Exception('محاكاة: فشل الاتصال مع الخادم');
    }
  }

  /// توقيف المزامنة
  Future<void> stopSync() async {
    if (!_isSyncing) {
      print('⚠️ المزامنة لم تكن قيد التشغيل');
      return;
    }

    _isSyncing = false;
    _updateStatus(SyncStatus.stopped);
    print('⏹️ تم توقيف المزامنة');
  }

  /// إعادة محاولة المزامنة
  Future<void> retrySyncFailed() async {
    if (_failedItemsCount == 0) {
      print('ℹ️ لا توجد عناصر فاشلة');
      return;
    }

    print('🔄 إعادة محاولة العناصر الفاشلة...');
    await startSync();
  }

  /// الحصول على إحصائيات المزامنة
  SyncStatistics getStatistics() {
    return SyncStatistics(
      totalPending: _syncedItemsCount + _failedItemsCount,
      syncedItems: _syncedItemsCount,
      failedItems: _failedItemsCount,
      lastSyncTime: _lastSyncTime,
      isSyncing: _isSyncing,
    );
  }

  /// تحديث حالة المزامنة
  void _updateStatus(SyncStatus status) {
    _currentStatus = status;
    _syncStatusStream.add(status);
    print('📊 تحديث الحالة: $status');
  }

  /// محاكاة بدء مزامنة فورية (للاختبار)
  Future<void> triggerImmediateSync() async {
    print('⚡ بدء مزامنة فورية');
    await startSync();
  }

  /// التنظيف والإغلاق
  void dispose() {
    _connectivitySubscription.cancel();
    _syncStatusStream.close();
  }
}

/// حالات المزامنة الممكنة
enum SyncStatus {
  /// المحرك معطل
  idle,

  /// جاري المزامنة
  syncing,

  /// اكتملت بنجاح
  synced,

  /// اكتملت مع أخطاء
  syncedWithErrors,

  /// لا يوجد اتصال
  offline,

  /// تم الإيقاف
  stopped,

  /// خطأ في المزامنة
  error,
}

/// إحصائيات المزامنة
class SyncStatistics {
  const SyncStatistics({
    required this.totalPending,
    required this.syncedItems,
    required this.failedItems,
    required this.lastSyncTime,
    required this.isSyncing,
  });

  /// إجمالي العناصر المعلقة
  final int totalPending;

  /// العناصر المزامنة بنجاح
  final int syncedItems;

  /// العناصر الفاشلة
  final int failedItems;

  /// آخر وقت مزامنة
  final DateTime? lastSyncTime;

  /// هل المزامنة جاري تنفيذها؟
  final bool isSyncing;

  /// نسبة النجاح
  double get successRate {
    if (totalPending == 0) return 0;
    return (syncedItems / totalPending) * 100;
  }

  @override
  String toString() => 'SyncStatistics('
      'total: $totalPending, '
      'synced: $syncedItems, '
      'failed: $failedItems, '
      'success: ${successRate.toStringAsFixed(2)}%'
      ')';
}
