import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/pagination_bar.dart';

final barcodeTemplateProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final response = await ApiClient.instance.dio.get('/organizations/me/barcode-template');
  return response.data as Map<String, dynamic>;
});

final barcodeProductSearchProvider = StateProvider.autoDispose<String>((ref) => '');

final barcodeProductResultsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final search = ref.watch(barcodeProductSearchProvider).trim();
  if (search.isEmpty) return [];
  final response = await ApiClient.instance.dio.get('/products/inventory', queryParameters: {
    'search': search,
    'page': 1,
    'pageSize': 20,
  });
  return PagedResult.fromJson(response.data as Map<String, dynamic>).items;
});
