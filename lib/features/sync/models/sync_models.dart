import 'package:flutter_riverpod/flutter_riverpod.dart';

/// نموذج بيانات المتصل
class SyncMetadata {
  final String entityType;
  final DateTime? lastPullTime;
  final DateTime? lastPushTime;
  final int pullVersion;
  final int pushVersion;

  const SyncMetadata({
    required this.entityType,
    this.lastPullTime,
    this.lastPushTime,
    this.pullVersion = 0,
    this.pushVersion = 0,
  });

  SyncMetadata copyWith({
    String? entityType,
    DateTime? lastPullTime,
    DateTime? lastPushTime,
    int? pullVersion,
    int? pushVersion,
  }) {
    return SyncMetadata(
      entityType: entityType ?? this.entityType,
      lastPullTime: lastPullTime ?? this.lastPullTime,
      lastPushTime: lastPushTime ?? this.lastPushTime,
      pullVersion: pullVersion ?? this.pullVersion,
      pushVersion: pushVersion ?? this.pushVersion,
    );
  }

  Map<String, dynamic> toJson() => {
        'entity_type': entityType,
        'last_pull_time': lastPullTime?.toIso8601String(),
        'last_push_time': lastPushTime?.toIso8601String(),
        'pull_version': pullVersion,
        'push_version': pushVersion,
      };

  factory SyncMetadata.fromJson(Map<String, dynamic> json) {
    return SyncMetadata(
      entityType: json['entity_type'] ?? '',
      lastPullTime: json['last_pull_time'] != null
          ? DateTime.parse(json['last_pull_time'])
          : null,
      lastPushTime: json['last_push_time'] != null
          ? DateTime.parse(json['last_push_time'])
          : null,
      pullVersion: json['pull_version'] ?? 0,
      pushVersion: json['push_version'] ?? 0,
    );
  }
}

/// نموذج التغيير المعلق
enum SyncOperation { create, update, delete }

class PendingChange {
  final String id;
  final String entityType;
  final String entityId;
  final SyncOperation operation;
  final Map<String, dynamic> data;
  final DateTime timestamp;
  final String status; // PENDING, SYNCED, FAILED
  final int retryCount;

  const PendingChange({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.data,
    required this.timestamp,
    this.status = 'PENDING',
    this.retryCount = 0,
  });

  PendingChange copyWith({
    String? id,
    String? entityType,
    String? entityId,
    SyncOperation? operation,
    Map<String, dynamic>? data,
    DateTime? timestamp,
    String? status,
    int? retryCount,
  }) {
    return PendingChange(
      id: id ?? this.id,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      operation: operation ?? this.operation,
      data: data ?? this.data,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'entity_type': entityType,
        'entity_id': entityId,
        'operation': operation.name,
        'data': data,
        'timestamp': timestamp.toIso8601String(),
        'status': status,
        'retry_count': retryCount,
      };

  factory PendingChange.fromJson(Map<String, dynamic> json) {
    return PendingChange(
      id: json['id'] ?? '',
      entityType: json['entity_type'] ?? '',
      entityId: json['entity_id'] ?? '',
      operation: SyncOperation.values.firstWhere(
        (e) => e.name == json['operation'],
        orElse: () => SyncOperation.update,
      ),
      data: json['data'] ?? {},
      timestamp: DateTime.parse(json['timestamp'] ?? DateTime.now().toString()),
      status: json['status'] ?? 'PENDING',
      retryCount: json['retry_count'] ?? 0,
    );
  }
}

/// نموذج التضارب
enum ConflictResolutionStrategy {
  localWins,
  remoteWins,
  merge,
  manual,
}

class SyncConflict {
  final String id;
  final String entityType;
  final String entityId;
  final int localVersion;
  final int remoteVersion;
  final Map<String, dynamic> localData;
  final Map<String, dynamic> remoteData;
  final String resolution; // PENDING, RESOLVED
  final ConflictResolutionStrategy? strategy;
  final Map<String, dynamic>? resolvedData;

  const SyncConflict({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.localVersion,
    required this.remoteVersion,
    required this.localData,
    required this.remoteData,
    this.resolution = 'PENDING',
    this.strategy,
    this.resolvedData,
  });

  SyncConflict copyWith({
    String? id,
    String? entityType,
    String? entityId,
    int? localVersion,
    int? remoteVersion,
    Map<String, dynamic>? localData,
    Map<String, dynamic>? remoteData,
    String? resolution,
    ConflictResolutionStrategy? strategy,
    Map<String, dynamic>? resolvedData,
  }) {
    return SyncConflict(
      id: id ?? this.id,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      localVersion: localVersion ?? this.localVersion,
      remoteVersion: remoteVersion ?? this.remoteVersion,
      localData: localData ?? this.localData,
      remoteData: remoteData ?? this.remoteData,
      resolution: resolution ?? this.resolution,
      strategy: strategy ?? this.strategy,
      resolvedData: resolvedData ?? this.resolvedData,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'entity_type': entityType,
        'entity_id': entityId,
        'local_version': localVersion,
        'remote_version': remoteVersion,
        'local_data': localData,
        'remote_data': remoteData,
        'resolution': resolution,
        'strategy': strategy?.name,
        'resolved_data': resolvedData,
      };
}

/// نتيجة المزامنة
class SyncResult {
  final bool success;
  final String? message;
  final int version;
  final List<Map<String, dynamic>> changes;
  final List<SyncConflict> conflicts;
  final bool hasMore;

  const SyncResult({
    required this.success,
    this.message,
    this.version = 0,
    this.changes = const [],
    this.conflicts = const [],
    this.hasMore = false,
  });

  factory SyncResult.fromJson(Map<String, dynamic> json) {
    return SyncResult(
      success: json['success'] ?? false,
      message: json['message'],
      version: json['version'] ?? 0,
      changes: List<Map<String, dynamic>>.from(json['changes'] ?? []),
      conflicts: (json['conflicts'] as List?)
              ?.map((c) => SyncConflict(
                    id: c['id'] ?? '',
                    entityType: c['entity_type'] ?? '',
                    entityId: c['entity_id'] ?? '',
                    localVersion: c['local_version'] ?? 0,
                    remoteVersion: c['remote_version'] ?? 0,
                    localData: c['local_data'] ?? {},
                    remoteData: c['remote_data'] ?? {},
                  ))
              .toList() ??
          [],
      hasMore: json['has_more'] ?? false,
    );
  }
}

/// حالة المزامنة
class SyncState {
  final bool isLoading;
  final bool isOffline;
  final String? error;
  final DateTime? lastSyncTime;
  final int pendingChanges;
  final int conflicts;

  const SyncState({
    this.isLoading = false,
    this.isOffline = false,
    this.error,
    this.lastSyncTime,
    this.pendingChanges = 0,
    this.conflicts = 0,
  });

  SyncState copyWith({
    bool? isLoading,
    bool? isOffline,
    String? error,
    DateTime? lastSyncTime,
    int? pendingChanges,
    int? conflicts,
  }) {
    return SyncState(
      isLoading: isLoading ?? this.isLoading,
      isOffline: isOffline ?? this.isOffline,
      error: error ?? this.error,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      pendingChanges: pendingChanges ?? this.pendingChanges,
      conflicts: conflicts ?? this.conflicts,
    );
  }
}
