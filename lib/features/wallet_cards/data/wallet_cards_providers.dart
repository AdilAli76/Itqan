import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/pagination_bar.dart';

final cardStateFilterProvider = StateProvider.autoDispose<String?>((ref) => null);
final cardSearchProvider = StateProvider.autoDispose<String>((ref) => '');

const walletCardsPageSize = 50;

final walletCardsPageProvider = StateProvider.autoDispose<int>((ref) => 1);

final walletCardsProvider = FutureProvider.autoDispose<PagedResult>((ref) async {
  final state = ref.watch(cardStateFilterProvider);
  final search = ref.watch(cardSearchProvider);
  final page = ref.watch(walletCardsPageProvider);
  final response = await ApiClient.instance.dio.get('/wallet-cards', queryParameters: {
    if (state != null) 'state': state,
    if (search.isNotEmpty) 'search': search,
    'page': page,
    'pageSize': walletCardsPageSize,
  });
  return PagedResult.fromJson(response.data as Map<String, dynamic>);
});

/// عملاء بلا بطاقة — قائمة الاختيار عند إصدار بطاقة جديدة.
final customersWithoutCardProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  // pageSize الأقصى (200) بدل جلب الجدول كله: هذه قائمة اختيار في نموذج
  // إصدار بطاقة، ومئتا اسم أكثر مما يمكن تصفّحه بصرياً أصلاً — من تجاوزهم
  // يستخدم البحث. جلب كل العملاء هنا كان يُبطئ فتح النموذج بلا مقابل.
  final customersResponse = await ApiClient.instance.dio.get('/customers', queryParameters: {
    'page': 1,
    'pageSize': 200,
  });
  final customers = PagedResult.fromJson(customersResponse.data as Map<String, dynamic>).items;
  final cardsResponse = await ApiClient.instance.dio.get('/wallet-cards', queryParameters: {
    'page': 1,
    'pageSize': 200,
  });
  final carded = PagedResult.fromJson(cardsResponse.data as Map<String, dynamic>).items
      .map((c) => c['customerId'] as String)
      .toSet();
  return customers.where((c) => !carded.contains(c['id'] as String)).toList();
});
