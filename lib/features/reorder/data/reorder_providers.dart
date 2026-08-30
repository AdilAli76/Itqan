import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

/// إعدادات تقرير إعادة الطلب — يضبطها المستخدم فتُعاد الحسبة على الخادم.
class ReorderSettings {
  const ReorderSettings({
    this.windowDays = 90,
    this.coverageDays = 14,
    this.onlyBelowThreshold = true,
  });

  /// نافذة قياس الاستهلاك. تسعون يوماً تستوعب تقلّب الأسابيع بلا أن تُغرِق
  /// الرقم في تاريخ قديم لم يعد يمثّل الطلب الحالي.
  final int windowDays;

  /// أيام الأمان فوق مهلة التوريد — احتياط لتأخّر المورّد أو قفزة طلب.
  final int coverageDays;

  final bool onlyBelowThreshold;

  ReorderSettings copyWith({int? windowDays, int? coverageDays, bool? onlyBelowThreshold}) =>
      ReorderSettings(
        windowDays: windowDays ?? this.windowDays,
        coverageDays: coverageDays ?? this.coverageDays,
        onlyBelowThreshold: onlyBelowThreshold ?? this.onlyBelowThreshold,
      );
}

final reorderSettingsProvider =
    StateProvider.autoDispose<ReorderSettings>((ref) => const ReorderSettings());

final reorderReportProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final s = ref.watch(reorderSettingsProvider);
  final response = await ApiClient.instance.dio.get('/reports/reorder', queryParameters: {
    'windowDays': s.windowDays,
    'coverageDays': s.coverageDays,
    'onlyBelowThreshold': s.onlyBelowThreshold,
  });
  return response.data as Map<String, dynamic>;
});
