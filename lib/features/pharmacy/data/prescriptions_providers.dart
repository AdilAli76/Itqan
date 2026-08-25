import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/pagination_bar.dart';

/// دفتر الوصفات — قراءة فقط. القيد يُكتب لحظة الصرف مع الفاتورة داخل معاملة
/// واحدة (راجع InvoicesController)، ولا واجهة كتابة له عمداً.
const prescriptionsPageSize = 50;

final prescriptionSearchProvider = StateProvider.autoDispose<String>((ref) => '');
final prescriptionsPageProvider = StateProvider.autoDispose<int>((ref) => 1);

final prescriptionsProvider = FutureProvider.autoDispose<PagedResult>((ref) async {
  final search = ref.watch(prescriptionSearchProvider).trim();
  final page = ref.watch(prescriptionsPageProvider);
  final response = await ApiClient.instance.dio.get('/prescriptions', queryParameters: {
    if (search.isNotEmpty) 'search': search,
    'page': page,
    'pageSize': prescriptionsPageSize,
  });
  return PagedResult.fromJson(response.data as Map<String, dynamic>);
});
