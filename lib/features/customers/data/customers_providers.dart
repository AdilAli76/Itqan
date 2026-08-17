import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

/// نفس نمط inventory_providers.dart — طلب HTTP عادي عبر [ApiClient]،
/// والعزل بين المنظمات يتم على مستوى قاعدة البيانات (Security Policy).
final customerSearchProvider = StateProvider.autoDispose<String>((ref) => '');

final customersProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final search = ref.watch(customerSearchProvider);
  final response = await ApiClient.instance.dio.get('/customers', queryParameters: {
    if (search.isNotEmpty) 'search': search,
  });
  return List<Map<String, dynamic>>.from(response.data as List);
});

/// الجهات الممولة — تُقرأ في نموذج العميل وفي شاشة الجهات معاً.
///
/// ليست autoDispose عمداً: نموذج العميل يفتح ويُغلق كثيراً، وإعادة تحميل
/// القائمة مع كل فتح طلبٌ زائد لبيانات نادرة التغيّر.
final sponsorsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final response = await ApiClient.instance.dio.get('/sponsors');
  return List<Map<String, dynamic>>.from(response.data as List);
});
