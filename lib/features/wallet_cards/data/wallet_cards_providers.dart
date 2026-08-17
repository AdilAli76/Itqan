import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

final cardStateFilterProvider = StateProvider.autoDispose<String?>((ref) => null);
final cardSearchProvider = StateProvider.autoDispose<String>((ref) => '');

final walletCardsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final state = ref.watch(cardStateFilterProvider);
  final search = ref.watch(cardSearchProvider);
  final response = await ApiClient.instance.dio.get('/wallet-cards', queryParameters: {
    if (state != null) 'state': state,
    if (search.isNotEmpty) 'search': search,
  });
  return List<Map<String, dynamic>>.from(response.data as List);
});

/// عملاء بلا بطاقة — قائمة الاختيار عند إصدار بطاقة جديدة.
final customersWithoutCardProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final customersResponse = await ApiClient.instance.dio.get('/customers');
  final customers = List<Map<String, dynamic>>.from(customersResponse.data as List);
  final cardsResponse = await ApiClient.instance.dio.get('/wallet-cards');
  final carded = List<Map<String, dynamic>>.from(cardsResponse.data as List)
      .map((c) => c['customerId'] as String)
      .toSet();
  return customers.where((c) => !carded.contains(c['id'] as String)).toList();
});
