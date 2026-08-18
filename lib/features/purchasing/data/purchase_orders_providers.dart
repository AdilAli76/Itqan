import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/pagination_bar.dart';

final purchaseOrderStatusFilterProvider = StateProvider.autoDispose<String?>((ref) => null);

final purchaseOrdersProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final status = ref.watch(purchaseOrderStatusFilterProvider);
  final response = await ApiClient.instance.dio.get('/purchase-orders', queryParameters: {
    if (status != null) 'status': status,
  });
  return List<Map<String, dynamic>>.from(response.data as List);
});

final purchaseOrderDetailProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) async {
  final response = await ApiClient.instance.dio.get('/purchase-orders/$id');
  return response.data as Map<String, dynamic>;
});

final purchaseOrderProductSearchProvider = StateProvider.autoDispose<String>((ref) => '');

final purchaseOrderProductResultsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final search = ref.watch(purchaseOrderProductSearchProvider).trim();
  if (search.isEmpty) return [];
  final response = await ApiClient.instance.dio.get('/products/inventory', queryParameters: {
    'search': search,
    'page': 1,
    'pageSize': 20,
  });
  return PagedResult.fromJson(response.data as Map<String, dynamic>).items;
});
