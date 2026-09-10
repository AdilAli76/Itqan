import 'package:dio/dio.dart';
import '../models/sync_models.dart';

/// خدمة تحميل التحديثات من السيرفر
class PullSyncService {
  final Dio dio;

  PullSyncService(this.dio);

  /// تحميل التحديثات من السيرفر
  Future<SyncResult> pullUpdates(
    String entityType, {
    int? sinceVersion,
  }) async {
    try {
      final response = await dio.get(
        '/api/sync/pull/$entityType',
        queryParameters: {
          if (sinceVersion != null) 'sinceVersion': sinceVersion,
        },
      );

      return SyncResult.fromJson(response.data);
    } on DioException catch (e) {
      return SyncResult(
        success: false,
        message: 'فشل تحميل التحديثات: ${e.message}',
      );
    }
  }

  /// تحميل تحديثات لعدة كيانات
  Future<Map<String, SyncResult>> pullMultiple(
    List<String> entityTypes,
  ) async {
    final results = <String, SyncResult>{};

    for (final entityType in entityTypes) {
      results[entityType] = await pullUpdates(entityType);
    }

    return results;
  }

  /// تحميل تحديثات مع pagination
  Future<List<Map<String, dynamic>>> pullWithPagination(
    String entityType, {
    int? sinceVersion,
    int pageSize = 100,
  }) async {
    final allChanges = <Map<String, dynamic>>[];
    var currentVersion = sinceVersion ?? 0;
    var hasMore = true;

    while (hasMore) {
      final result = await pullUpdates(entityType, sinceVersion: currentVersion);

      if (!result.success) break;

      allChanges.addAll(result.changes);
      currentVersion = result.version;
      hasMore = result.hasMore;
    }

    return allChanges;
  }
}
