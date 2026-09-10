import 'package:dio/dio.dart';
import '../models/sync_models.dart';

/// خدمة إرسال التغييرات للسيرفر
class PushSyncService {
  final Dio dio;

  PushSyncService(this.dio);

  /// إرسال التغييرات المعلقة
  Future<SyncResult> pushChanges(
    List<PendingChange> changes,
  ) async {
    if (changes.isEmpty) {
      return const SyncResult(success: true, message: 'لا توجد تغييرات للإرسال');
    }

    try {
      final response = await dio.post(
        '/api/sync/push',
        data: {
          'changes': changes.map((c) => {
                'entityType': c.entityType,
                'entityId': c.entityId,
                'operation': c.operation.name,
                'data': c.data,
              }).toList(),
        },
      );

      return SyncResult.fromJson(response.data);
    } on DioException catch (e) {
      return SyncResult(
        success: false,
        message: 'فشل إرسال التغييرات: ${e.message}',
      );
    }
  }

  /// إرسال التغييرات على دفعات
  Future<SyncResult> pushChangesBatch(
    List<PendingChange> changes, {
    int batchSize = 50,
  }) async {
    final allConflicts = <SyncConflict>[];
    var allSuccess = true;

    for (var i = 0; i < changes.length; i += batchSize) {
      final batch = changes.sublist(
        i,
        i + batchSize > changes.length ? changes.length : i + batchSize,
      );

      final result = await pushChanges(batch);

      if (!result.success) {
        allSuccess = false;
        break;
      }

      allConflicts.addAll(result.conflicts);
    }

    return SyncResult(
      success: allSuccess,
      conflicts: allConflicts,
      message: allSuccess
          ? 'تم إرسال ${changes.length} تغيير بنجاح'
          : 'فشل الإرسال عند الدفعة',
    );
  }

  /// التحقق من توفر الاتصال ثم الإرسال
  Future<SyncResult> pushIfOnline(
    List<PendingChange> changes, {
    required Future<bool> Function() isOnline,
  }) async {
    final online = await isOnline();

    if (!online) {
      return const SyncResult(
        success: false,
        message: 'لا يوجد اتصال بالإنترنت',
      );
    }

    return pushChanges(changes);
  }
}
