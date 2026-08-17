import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

/// نفس نمط inventory_providers.dart وcustomers_providers.dart.
final invoiceSearchProvider = StateProvider.autoDispose<String>((ref) => '');
final invoiceStatusFilterProvider = StateProvider.autoDispose<String?>((ref) => null);
final invoiceTypeFilterProvider = StateProvider.autoDispose<String?>((ref) => null);

final invoicesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final search = ref.watch(invoiceSearchProvider);
  final status = ref.watch(invoiceStatusFilterProvider);
  final type = ref.watch(invoiceTypeFilterProvider);

  final response = await ApiClient.instance.dio.get('/invoices', queryParameters: {
    if (search.isNotEmpty) 'search': search,
    if (status != null) 'status': status,
    if (type != null) 'invoiceType': type,
  });
  return List<Map<String, dynamic>>.from(response.data as List);
});

final invoiceDetailProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) async {
  final response = await ApiClient.instance.dio.get('/invoices/$id');
  return response.data as Map<String, dynamic>;
});
