import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../core/network/api_client.dart';
import '../models/sync_models.dart';
import '../services/pull_sync_service.dart';
import '../services/push_sync_service.dart';
import '../services/conflict_service.dart';
import '../services/offline_queue_service.dart';

/// مزود خدمة تحميل التحديثات
final pullSyncServiceProvider = Provider((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return PullSyncService(apiClient.dio);
});

/// مزود خدمة إرسال التغييرات
final pushSyncServiceProvider = Provider((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return PushSyncService(apiClient.dio);
});

/// مزود خدمة حل التضاربات
final conflictServiceProvider = Provider((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return ConflictService(apiClient.dio);
});

/// مزود خدمة الطابور غير المتصل
final offlineQueueProvider =
    StateNotifierProvider<OfflineQueueNotifier, OfflineQueueState>(
  (ref) => OfflineQueueNotifier(),
);

/// مزود حالة الاتصال
final connectivityProvider = StreamProvider((ref) {
  return Connectivity().onConnectivityChanged;
});

/// مزود حالة المزامنة
final syncStateProvider =
    StateNotifierProvider<SyncStateNotifier, SyncState>(
  (ref) => SyncStateNotifier(ref),
);

/// Notifier لحالة الطابور غير المتصل
class OfflineQueueNotifier extends StateNotifier<OfflineQueueState> {
  final OfflineQueueService _service = OfflineQueueService();

  OfflineQueueNotifier()
      : super(const OfflineQueueState(
          pending: [],
          stats: QueueStats(total: 0, pending: 0, failed: 0, synced: 0),
        ));

  /// إضافة تغيير للطابور
  Future<void> addChange({
    required String entityType,
    required String entityId,
    required SyncOperation operation,
    required Map<String, dynamic> data,
  }) async {
    await _service.queueChange(
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      data: data,
    );
    _updateState();
  }

  /// تحديث حالة التغيير
  void updateStatus(String changeId, String status) {
    _service.updateChangeStatus(changeId, status);
    _updateState();
  }

  /// تطبيق التغييرات الناجحة
  Future<void> markAsSynced(List<String> ids) async {
    await _service.markAsSynced(ids);
    _updateState();
  }

  /// إعادة المحاولة
  void retryFailed() {
    _service.retryFailedChanges();
    _updateState();
  }

  /// تحديث الحالة الداخلية
  void _updateState() {
    state = OfflineQueueState(
      pending: _service.getPendingChanges(),
      stats: _service.getStats(),
    );
  }
}

/// حالة الطابور غير المتصل
class OfflineQueueState {
  final List<PendingChange> pending;
  final QueueStats stats;

  const OfflineQueueState({
    required this.pending,
    required this.stats,
  });
}

/// Notifier لحالة المزامنة الكلية
class SyncStateNotifier extends StateNotifier<SyncState> {
  final Ref ref;

  SyncStateNotifier(this.ref) : super(const SyncState());

  /// تنفيذ مزامنة كاملة
  Future<void> performFullSync(
    List<String> entityTypes,
  ) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      // تحقق من الاتصال
      final connectivity = ref.read(connectivityProvider);
      connectivity.whenData((result) {
        final isOnline = result != ConnectivityResult.none;
        state = state.copyWith(isOffline: !isOnline);

        if (!isOnline) {
          state = state.copyWith(
            isLoading: false,
            error: 'بلا اتصال بالإنترنت',
          );
          return;
        }
      });

      // تحميل التحديثات
      final pullService = ref.read(pullSyncServiceProvider);
      final pushService = ref.read(pushSyncServiceProvider);
      final conflictService = ref.read(conflictServiceProvider);
      final queueNotifier = ref.read(offlineQueueProvider.notifier);

      // Pull أولاً
      for (final entity in entityTypes) {
        final result = await pullService.pullUpdates(entity);
        if (!result.success) {
          state = state.copyWith(
            isLoading: false,
            error: result.message,
          );
          return;
        }
      }

      // Push التغييرات المعلقة
      final pending = ref.read(offlineQueueProvider).pending;
      if (pending.isNotEmpty) {
        final pushResult = await pushService.pushChanges(pending);

        if (pushResult.conflicts.isNotEmpty) {
          // حل التضاربات الذكية
          await conflictService.resolveSmartly(pushResult.conflicts);
          state = state.copyWith(
            error: 'تم حل ${pushResult.conflicts.length} تضارب',
          );
        } else if (pushResult.success) {
          await queueNotifier.markAsSynced(
            pending.map((c) => c.id).toList(),
          );
        }
      }

      state = state.copyWith(
        isLoading: false,
        lastSyncTime: DateTime.now(),
        error: null,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'خطأ في المزامنة: $e',
      );
    }
  }

  /// مزامنة محددة للكيان
  Future<void> syncEntity(String entityType) async {
    state = state.copyWith(isLoading: true);

    try {
      final pullService = ref.read(pullSyncServiceProvider);
      final result = await pullService.pullUpdates(entityType);

      state = state.copyWith(
        isLoading: false,
        error: result.success ? null : result.message,
        lastSyncTime: result.success ? DateTime.now() : null,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'فشل المزامنة: $e',
      );
    }
  }

  /// إعادة محاولة المزامنة
  Future<void> retry() => performFullSync([
        'products',
        'invoices',
        'customers',
      ]);
}
