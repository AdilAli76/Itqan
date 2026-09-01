import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

final platformOrganizationsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final response = await ApiClient.instance.dio.get('/platform/organizations');
  return List<Map<String, dynamic>>.from(response.data as List);
});

/// حسابات المنصّة — المالك ومهندسو البيع.
///
/// مقصورةٌ على المالك في الخادم (403 لغيره)، فلا تُستدعى إلا من شاشته.
final platformEngineersProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final response = await ApiClient.instance.dio.get('/platform/engineers');
  return List<Map<String, dynamic>>.from(response.data as List);
});

/// المهندس المختار في مُرشِّح قائمة العملاء — `null` يعني «الكلّ».
///
/// <para>الترشيح في الواجهة لا في الخادم عمداً: الخادم يُرجع لمالك المنصّة
/// كل عملائه أصلاً (وللمهندس عملاءه وحدهم — راجع `PlatformScope`)، فالمُرشِّح
/// هنا **راحةُ نظر** لا حاجز. وجعلُه نداءً بمَعلمة كان يعني رحلةً إلى
/// الخادم مع كل ضغطة على قائمةٍ منسدلة.</para>
final organizationFilterProvider = StateProvider<String?>((ref) => null);
