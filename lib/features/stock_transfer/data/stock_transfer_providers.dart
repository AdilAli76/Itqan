import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

final transferStatusFilterProvider = StateProvider.autoDispose<String?>((ref) => null);

final stockTransfersProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final status = ref.watch(transferStatusFilterProvider);
  final response = await ApiClient.instance.dio.get('/stock-transfers', queryParameters: {
    if (status != null) 'status': status,
  });
  return List<Map<String, dynamic>>.from(response.data as List);
});

final transferDetailProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) async {
  final response = await ApiClient.instance.dio.get('/stock-transfers/$id');
  return response.data as Map<String, dynamic>;
});

final transferProductSearchProvider = StateProvider.autoDispose<String>((ref) => '');

final transferProductResultsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final search = ref.watch(transferProductSearchProvider).trim();
  if (search.isEmpty) return [];
  final response = await ApiClient.instance.dio.get('/products/inventory', queryParameters: {
    'search': search,
  });
  return List<Map<String, dynamic>>.from(response.data as List);
});
