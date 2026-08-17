import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

/// نفس نمط inventory_providers.dart — البحث فارغ يعني بلا نتائج بدل تحميل
/// الكتالوج كاملاً بلا داعٍ في كل مرة تُفتح فيها الشاشة.
final posProductSearchProvider = StateProvider.autoDispose<String>((ref) => '');

final posProductResultsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final search = ref.watch(posProductSearchProvider).trim();
  if (search.isEmpty) return [];
  final response = await ApiClient.instance.dio.get('/products/inventory', queryParameters: {
    'search': search,
  });
  return List<Map<String, dynamic>>.from(response.data as List);
});

final posCustomerSearchProvider = StateProvider.autoDispose<String>((ref) => '');

final posCustomerResultsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final search = ref.watch(posCustomerSearchProvider).trim();
  if (search.isEmpty) return [];
  final response = await ApiClient.instance.dio.get('/customers', queryParameters: {
    'search': search,
  });
  return List<Map<String, dynamic>>.from(response.data as List);
});
