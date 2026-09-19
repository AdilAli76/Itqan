import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../sync/sync_engine.dart';

/// Singleton instance من SyncEngine
final syncEngineProvider = Provider<SyncEngine>((ref) {
  return SyncEngine();
});

/// Stream provider لحالة المزامنة
final syncStatusStreamProvider = StreamProvider<SyncStatus>((ref) {
  final engine = ref.watch(syncEngineProvider);
  return engine.statusStream;
});

/// Provider للحالة الحالية للمزامنة
final currentSyncStatusProvider = Provider<SyncStatus>((ref) {
  final engine = ref.watch(syncEngineProvider);
  return engine.status;
});

/// Provider لمعرفة ما إذا كانت المزامنة جارية
final isSyncingProvider = Provider<bool>((ref) {
  final engine = ref.watch(syncEngineProvider);
  return engine.isSyncing;
});

/// Provider لآخر وقت مزامنة
final lastSyncTimeProvider = Provider<DateTime?>((ref) {
  final engine = ref.watch(syncEngineProvider);
  return engine.lastSyncTime;
});

/// Provider لإحصائيات المزامنة
final syncStatisticsProvider = Provider<SyncStatistics>((ref) {
  final engine = ref.watch(syncEngineProvider);
  return engine.getStatistics();
});

/// State notifier للتحكم في المزامنة
final syncControllerProvider = StateNotifierProvider<
    SyncController,
    SyncControllerState>((ref) {
  return SyncController(ref.watch(syncEngineProvider));
});

/// حالة التحكم في المزامنة
class SyncControllerState {
  const SyncControllerState({
    required this.isManualSyncActive,
    required this.lastManualSyncTime,
    required this.autoSyncEnabled,
  });

  final bool isManualSyncActive;
  final DateTime? lastManualSyncTime;
  final bool autoSyncEnabled;

  SyncControllerState copyWith({
    bool? isManualSyncActive,
    DateTime? lastManualSyncTime,
    bool? autoSyncEnabled,
  }) {
    return SyncControllerState(
      isManualSyncActive: isManualSyncActive ?? this.isManualSyncActive,
      lastManualSyncTime: lastManualSyncTime ?? this.lastManualSyncTime,
      autoSyncEnabled: autoSyncEnabled ?? this.autoSyncEnabled,
    );
  }
}

/// State notifier للتحكم في المزامنة
class SyncController extends StateNotifier<SyncControllerState> {
  SyncController(this._engine)
      : super(
          const SyncControllerState(
            isManualSyncActive: false,
            lastManualSyncTime: null,
            autoSyncEnabled: true,
          ),
        );

  final SyncEngine _engine;

  /// بدء المزامنة يدوياً
  Future<void> startManualSync() async {
    state = state.copyWith(isManualSyncActive: true);
    await _engine.startSync();
    state = state.copyWith(
      isManualSyncActive: false,
      lastManualSyncTime: DateTime.now(),
    );
  }

  /// توقيف المزامنة
  Future<void> stopSync() async {
    await _engine.stopSync();
    state = state.copyWith(isManualSyncActive: false);
  }

  /// إعادة محاولة العناصر الفاشلة
  Future<void> retryFailed() async {
    await _engine.retrySyncFailed();
  }

  /// تفعيل/تعطيل المزامنة التلقائية
  void toggleAutoSync() {
    state = state.copyWith(autoSyncEnabled: !state.autoSyncEnabled);
  }

  /// بدء مزامنة فورية (للاختبار)
  Future<void> triggerImmediate() async {
    await _engine.triggerImmediateSync();
  }
}
