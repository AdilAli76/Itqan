import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

/// مشتَرك بين أكثر من شاشة (المستخدمون، تحويل المخزون) — قائمة الفروع
/// *النشطة فقط* للاختيار منها في القوائم المنسدلة.
final branchesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final response = await ApiClient.instance.dio.get('/branches');
  return List<Map<String, dynamic>>.from(response.data as List);
});

/// لشاشة إدارة الفروع نفسها فقط — يشمل الفروع المعطَّلة أيضاً حتى يمكن
/// إعادة تفعيلها، بعكس branchesProvider أعلاه.
final allBranchesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final response = await ApiClient.instance.dio.get('/branches', queryParameters: {
    'includeInactive': true,
  });
  return List<Map<String, dynamic>>.from(response.data as List);
});
