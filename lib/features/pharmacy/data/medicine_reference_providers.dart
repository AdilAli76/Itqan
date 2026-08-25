import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/pagination_bar.dart';

/// نشرات الأدوية — جدول على مستوى المنصّة يديره مالك المنصّة ويقرأه كل
/// عملاء إصدار الصيدليات. راجع MedicineReferenceController.
const medicineRefPageSize = 50;

final medicineRefSearchProvider = StateProvider.autoDispose<String>((ref) => '');
final medicineRefPageProvider = StateProvider.autoDispose<int>((ref) => 1);

final medicineRefsProvider = FutureProvider.autoDispose<PagedResult>((ref) async {
  final search = ref.watch(medicineRefSearchProvider).trim();
  final page = ref.watch(medicineRefPageProvider);
  final response = await ApiClient.instance.dio.get('/medicine-reference', queryParameters: {
    if (search.isNotEmpty) 'search': search,
    'page': page,
    'pageSize': medicineRefPageSize,
  });
  return PagedResult.fromJson(response.data as Map<String, dynamic>);
});
