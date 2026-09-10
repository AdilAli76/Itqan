import 'package:uuid/uuid.dart';
import '../models/sync_models.dart';

/// خدمة إدارة الطابور غير المتصل
class OfflineQueueService {
  final List<PendingChange> _queue = [];

  /// إضافة تغيير للطابور
  Future<void> queueChange({
    required String entityType,
    required String entityId,
    required SyncOperation operation,
    required Map<String, dynamic> data,
  }) async {
    final change = PendingChange(
      id: const Uuid().v4(),
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      data: data,
      timestamp: DateTime.now(),
    );

    // إذا كان هناك تغيير سابق لنفس الكيان → دمج
    final existingIndex = _queue.indexWhere(
      (c) => c.entityType == entityType && c.entityId == entityId,
    );

    if (existingIndex != -1) {
      _queue.removeAt(existingIndex);
    }

    _queue.add(change);
  }

  /// الحصول على جميع التغييرات المعلقة
  List<PendingChange> getPendingChanges() => List.unmodifiable(_queue);

  /// الحصول على التغييرات المعلقة لكيان معين
  List<PendingChange> getPendingChangesForEntity(
    String entityType,
  ) =>
      _queue.where((c) => c.entityType == entityType).toList();

  /// عدد التغييرات المعلقة
  int get pendingCount => _queue.length;

  /// تحديث حالة التغيير
  void updateChangeStatus(
    String changeId,
    String status, {
    int? newRetryCount,
  }) {
    final index = _queue.indexWhere((c) => c.id == changeId);
    if (index != -1) {
      _queue[index] = _queue[index].copyWith(
        status: status,
        retryCount: newRetryCount ?? _queue[index].retryCount,
      );
    }
  }

  /// حذف تغيير من الطابور
  void removeChange(String changeId) {
    _queue.removeWhere((c) => c.id == changeId);
  }

  /// تطبيق التغييرات الناجحة
  Future<void> markAsSynced(List<String> successfulIds) async {
    for (final id in successfulIds) {
      removeChange(id);
    }
  }

  /// إعادة محاولة التغييرات الفاشلة
  void retryFailedChanges() {
    for (var i = 0; i < _queue.length; i++) {
      if (_queue[i].status == 'FAILED' && _queue[i].retryCount < 3) {
        _queue[i] = _queue[i].copyWith(
          status: 'PENDING',
          retryCount: _queue[i].retryCount + 1,
        );
      }
    }
  }

  /// تفريغ الطابور
  void clear() {
    _queue.clear();
  }

  /// الحصول على إحصائيات الطابور
  QueueStats getStats() {
    final pending = _queue.where((c) => c.status == 'PENDING').length;
    final failed = _queue.where((c) => c.status == 'FAILED').length;
    final synced = _queue.where((c) => c.status == 'SYNCED').length;

    return QueueStats(
      total: _queue.length,
      pending: pending,
      failed: failed,
      synced: synced,
    );
  }
}

/// إحصائيات الطابور
class QueueStats {
  final int total;
  final int pending;
  final int failed;
  final int synced;

  const QueueStats({
    required this.total,
    required this.pending,
    required this.failed,
    required this.synced,
  });

  bool get hasFailures => failed > 0;
  bool get isPending => pending > 0;
  bool get isComplete => pending == 0 && failed == 0;
}
