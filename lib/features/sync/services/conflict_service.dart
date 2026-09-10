import 'package:dio/dio.dart';
import '../models/sync_models.dart';

/// خدمة حل التضاربات
class ConflictService {
  final Dio dio;

  ConflictService(this.dio);

  /// حل تضارب واحد
  Future<bool> resolveConflict(
    SyncConflict conflict,
    ConflictResolutionStrategy strategy,
  ) async {
    try {
      final resolvedData = _applyStrategy(
        conflict.localData,
        conflict.remoteData,
        strategy,
      );

      await dio.post(
        '/api/sync/conflicts/resolve',
        data: {
          'conflictId': conflict.id,
          'strategy': strategy.name,
          'resolvedData': resolvedData,
        },
      );

      return true;
    } on DioException {
      return false;
    }
  }

  /// حل عدة تضاربات
  Future<int> resolveMultiple(
    List<SyncConflict> conflicts,
    ConflictResolutionStrategy strategy,
  ) async {
    var resolvedCount = 0;

    for (final conflict in conflicts) {
      final success = await resolveConflict(conflict, strategy);
      if (success) resolvedCount++;
    }

    return resolvedCount;
  }

  /// الحل الذكي للتضاربات
  /// - إذا كانت التغييرات في حقول مختلفة → MERGE
  /// - إذا كان التحديث المحلي حديث → LOCAL_WINS
  /// - وإلا → REMOTE_WINS
  Future<int> resolveSmartly(List<SyncConflict> conflicts) async {
    var resolvedCount = 0;

    for (final conflict in conflicts) {
      final strategy = _determineStrategy(conflict);
      final success = await resolveConflict(conflict, strategy);
      if (success) resolvedCount++;
    }

    return resolvedCount;
  }

  /// تطبيق استراتيجية الحل
  Map<String, dynamic> _applyStrategy(
    Map<String, dynamic> localData,
    Map<String, dynamic> remoteData,
    ConflictResolutionStrategy strategy,
  ) {
    switch (strategy) {
      case ConflictResolutionStrategy.localWins:
        return localData;
      case ConflictResolutionStrategy.remoteWins:
        return remoteData;
      case ConflictResolutionStrategy.merge:
        return _merge(localData, remoteData);
      case ConflictResolutionStrategy.manual:
        return localData; // الاختيار اليدوي يتطلب تدخل المستخدم
    }
  }

  /// دمج البيانات الذكي
  Map<String, dynamic> _merge(
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
  ) {
    final result = Map<String, dynamic>.from(remote);

    for (final key in local.keys) {
      if (local[key] != remote[key]) {
        // إذا كانت القيمتان مختلفتان وكلاهما ليس null
        if (local[key] != null && remote[key] != null) {
          // حاول دمجهما (مثلاً: إذا كانت أرقاماً، خذ الأكبر)
          if (local[key] is num && remote[key] is num) {
            result[key] = (local[key] as num) > (remote[key] as num)
                ? local[key]
                : remote[key];
          } else if (local[key] is String && remote[key] is String) {
            // للنصوص، أبق على الأطول
            result[key] = (local[key] as String).length >
                    (remote[key] as String).length
                ? local[key]
                : remote[key];
          }
        } else if (local[key] != null) {
          result[key] = local[key];
        }
      }
    }

    return result;
  }

  /// تحديد الاستراتيجية الأنسب
  ConflictResolutionStrategy _determineStrategy(
    SyncConflict conflict,
  ) {
    // إذا كانت جميع الحقول مختلفة → دمج
    if (_hasDifferentFields(conflict.localData, conflict.remoteData)) {
      return ConflictResolutionStrategy.merge;
    }

    // إذا كان التحديث المحلي حديث → الفوز المحلي
    if (conflict.localVersion > conflict.remoteVersion) {
      return ConflictResolutionStrategy.localWins;
    }

    // وإلا → الفوز البعيد
    return ConflictResolutionStrategy.remoteWins;
  }

  /// التحقق من وجود حقول مختلفة
  bool _hasDifferentFields(
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
  ) {
    final allKeys = {...local.keys, ...remote.keys};
    var differentCount = 0;

    for (final key in allKeys) {
      if (local[key] != remote[key]) {
        differentCount++;
      }
    }

    // إذا كانت أقل من 50% من الحقول مختلفة → دمج آمن
    return differentCount < allKeys.length / 2;
  }
}
