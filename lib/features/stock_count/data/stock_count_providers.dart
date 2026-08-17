import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

final stockCountStatusFilterProvider = StateProvider.autoDispose<String?>((ref) => null);

final stockCountsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final status = ref.watch(stockCountStatusFilterProvider);
  final response = await ApiClient.instance.dio.get('/stock-counts', queryParameters: {
    if (status != null) 'status': status,
  });
  return List<Map<String, dynamic>>.from(response.data as List);
});

final stockCountDetailProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) async {
  final response = await ApiClient.instance.dio.get('/stock-counts/$id');
  return response.data as Map<String, dynamic>;
});
