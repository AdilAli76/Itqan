import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/pagination_bar.dart';

/// نفس نمط inventory_providers.dart وcustomers_providers.dart.
final invoiceSearchProvider = StateProvider.autoDispose<String>((ref) => '');
final invoiceStatusFilterProvider = StateProvider.autoDispose<String?>((ref) => null);
final invoiceTypeFilterProvider = StateProvider.autoDispose<String?>((ref) => null);

const invoicesPageSize = 50;

final invoicesPageProvider = StateProvider.autoDispose<int>((ref) => 1);

final invoicesProvider = FutureProvider.autoDispose<PagedResult>((ref) async {
  final search = ref.watch(invoiceSearchProvider);
  final status = ref.watch(invoiceStatusFilterProvider);
  final type = ref.watch(invoiceTypeFilterProvider);
  final page = ref.watch(invoicesPageProvider);

  final response = await ApiClient.instance.dio.get('/invoices', queryParameters: {
    if (search.isNotEmpty) 'search': search,
    if (status != null) 'status': status,
    if (type != null) 'invoiceType': type,
    'page': page,
    'pageSize': invoicesPageSize,
  });
  return PagedResult.fromJson(response.data as Map<String, dynamic>);
});

final invoiceDetailProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) async {
  final response = await ApiClient.instance.dio.get('/invoices/$id');
  return response.data as Map<String, dynamic>;
});
