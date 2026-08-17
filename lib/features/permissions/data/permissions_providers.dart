import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

/// كتالوج ثابت (لا يتغيّر باختيار الدور) — كل الصلاحيات المتاحة في النظام.
final permissionsCatalogProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final response = await ApiClient.instance.dio.get('/permissions/catalog');
  return List<Map<String, dynamic>>.from(response.data as List);
});

/// خريطة دور ← قائمة أكواد الصلاحيات الممنوحة له *لهذه المنظمة تحديداً*.
final permissionsMatrixProvider =
    FutureProvider.autoDispose<Map<String, List<String>>>((ref) async {
  final response = await ApiClient.instance.dio.get('/permissions/matrix');
  final data = response.data as Map<String, dynamic>;
  return data.map((role, codes) => MapEntry(role, List<String>.from(codes as List)));
});
