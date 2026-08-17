import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

enum ReportPeriod { today, last7Days, last30Days, last90Days }

extension ReportPeriodLabel on ReportPeriod {
  String get label => switch (this) {
        ReportPeriod.today => 'اليوم',
        ReportPeriod.last7Days => 'آخر 7 أيام',
        ReportPeriod.last30Days => 'آخر 30 يوماً',
        ReportPeriod.last90Days => 'آخر 90 يوماً',
      };

  DateTime get fromDate {
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    return switch (this) {
      ReportPeriod.today => startOfToday,
      ReportPeriod.last7Days => startOfToday.subtract(const Duration(days: 6)),
      ReportPeriod.last30Days => startOfToday.subtract(const Duration(days: 29)),
      ReportPeriod.last90Days => startOfToday.subtract(const Duration(days: 89)),
    };
  }
}

final reportPeriodProvider = StateProvider.autoDispose<ReportPeriod>((ref) => ReportPeriod.last30Days);

final salesSummaryProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final period = ref.watch(reportPeriodProvider);
  final response = await ApiClient.instance.dio.get('/reports/sales-summary', queryParameters: {
    'from': period.fromDate.toIso8601String(),
  });
  return response.data as Map<String, dynamic>;
});

final inventorySummaryProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final response = await ApiClient.instance.dio.get('/reports/inventory-summary');
  return response.data as Map<String, dynamic>;
});
