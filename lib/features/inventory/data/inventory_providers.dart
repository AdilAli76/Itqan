import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/pagination_bar.dart';

/// نفس نمط brandingProvider: طلب HTTP عادي عبر [ApiClient] بدل بيانات
/// تجريبية ثابتة — العزل بين المنظمات يتم على مستوى قاعدة البيانات
/// (Security Policy)، فلا حاجة لأي فلترة يدوية هنا.
final productSearchProvider = StateProvider.autoDispose<String>((ref) => '');
final supplierSearchProvider = StateProvider.autoDispose<String>((ref) => '');

const productsPageSize = 50;

final productsPageProvider = StateProvider.autoDispose<int>((ref) => 1);

final productsInventoryProvider = FutureProvider.autoDispose<PagedResult>((ref) async {
  final search = ref.watch(productSearchProvider);
  final page = ref.watch(productsPageProvider);
  final response = await ApiClient.instance.dio.get('/products/inventory', queryParameters: {
    if (search.isNotEmpty) 'search': search,
    'page': page,
    'pageSize': productsPageSize,
  });
  return PagedResult.fromJson(response.data as Map<String, dynamic>);
});

final suppliersProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final search = ref.watch(supplierSearchProvider);
  final response = await ApiClient.instance.dio.get('/suppliers', queryParameters: {
    if (search.isNotEmpty) 'search': search,
  });
  return List<Map<String, dynamic>>.from(response.data as List);
});

final categoriesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final response = await ApiClient.instance.dio.get('/categories');
  return List<Map<String, dynamic>>.from(response.data as List);
});
