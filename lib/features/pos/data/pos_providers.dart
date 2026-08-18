import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/pagination_bar.dart';

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
  // بحث فوري في نقطة البيع: أول عشرين مطابقة تكفي — الكاشير يختار من
  // القائمة المنسدلة ولا يتصفّح صفحات، وطلب أكثر من ذلك تأخير بلا فائدة.
  final response = await ApiClient.instance.dio.get('/customers', queryParameters: {
    'search': search,
    'page': 1,
    'pageSize': 20,
  });
  return PagedResult.fromJson(response.data as Map<String, dynamic>).items;
});
