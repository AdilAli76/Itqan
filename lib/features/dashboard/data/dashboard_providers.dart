import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

/// مبيعات اليوم تحديداً (وليست مرتبطة بفلتر فترة شاشة التقارير) — لوحة
/// التحكم دائماً "الآن"، بعكس شاشة التقارير القابلة لاختيار فترة مختلفة.
final dashboardSalesProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final today = DateTime.now();
  final from = DateTime(today.year, today.month, today.day);
  final response = await ApiClient.instance.dio.get('/reports/sales-summary', queryParameters: {
    'from': from.toIso8601String(),
  });
  return response.data as Map<String, dynamic>;
});

final dashboardInventoryProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final response = await ApiClient.instance.dio.get('/reports/inventory-summary');
  return response.data as Map<String, dynamic>;
});

final dashboardBranchesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final response = await ApiClient.instance.dio.get('/branches');
  return List<Map<String, dynamic>>.from(response.data as List);
});
