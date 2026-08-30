import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

/// فئات العملاء ومرتَّباتها الدورية.
final customerCategoriesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final response = await ApiClient.instance.dio.get('/customer-categories');
  return (response.data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
});

/// الفئة المختارة للصرف — null يعني كل الفئات.
final disburseCategoryFilterProvider = StateProvider.autoDispose<String?>((ref) => null);

/// معاينة الصرف: كم شخصاً وكم مبلغاً قبل الضغط.
///
/// <para>مالٌ يخرج على ألف بطاقة لا يُضغَط زرُّه على عمياء.</para>
final disbursePreviewProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final categoryId = ref.watch(disburseCategoryFilterProvider);
  final response = await ApiClient.instance.dio.get(
    '/customer-categories/disburse/preview',
    queryParameters: {if (categoryId != null) 'categoryId': categoryId},
  );
  return Map<String, dynamic>.from(response.data as Map);
});

/// السلف — الكل أو القائمة وحدها.
final showOpenAdvancesOnlyProvider = StateProvider.autoDispose<bool>((ref) => true);

final customerAdvancesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final openOnly = ref.watch(showOpenAdvancesOnlyProvider);
  final response = await ApiClient.instance.dio
      .get('/customer-advances', queryParameters: {'openOnly': openOnly});
  return (response.data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
});
