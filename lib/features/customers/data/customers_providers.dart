import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/pagination_bar.dart';

/// نفس نمط inventory_providers.dart — طلب HTTP عادي عبر [ApiClient]،
/// والعزل بين المنظمات يتم على مستوى قاعدة البيانات (Security Policy).
final customerSearchProvider = StateProvider.autoDispose<String>((ref) => '');

/// حجم الصفحة: خمسون صفاً تملأ شاشة مكتب كاملة تقريباً بلا تمرير مفرط،
/// وتبقى طلباً خفيفاً على شبكة متجر ضعيفة.
const customersPageSize = 50;

final customersPageProvider = StateProvider.autoDispose<int>((ref) => 1);

final customersProvider = FutureProvider.autoDispose<PagedResult>((ref) async {
  final search = ref.watch(customerSearchProvider);
  final page = ref.watch(customersPageProvider);
  final response = await ApiClient.instance.dio.get('/customers', queryParameters: {
    if (search.isNotEmpty) 'search': search,
    'page': page,
    'pageSize': customersPageSize,
  });
  return PagedResult.fromJson(response.data as Map<String, dynamic>);
});

/// الجهات الممولة — تُقرأ في نموذج العميل وفي شاشة الجهات معاً.
///
/// ليست autoDispose عمداً: نموذج العميل يفتح ويُغلق كثيراً، وإعادة تحميل
/// القائمة مع كل فتح طلبٌ زائد لبيانات نادرة التغيّر.
final sponsorsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final response = await ApiClient.instance.dio.get('/sponsors');
  return List<Map<String, dynamic>>.from(response.data as List);
});
