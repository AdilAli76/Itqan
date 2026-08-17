import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

const auditLogPageSize = 50;

final auditLogSearchProvider = StateProvider.autoDispose<String>((ref) => '');
final auditLogEntityFilterProvider = StateProvider.autoDispose<String?>((ref) => null);
final auditLogPageProvider = StateProvider.autoDispose<int>((ref) => 1);

final auditLogEntityTablesProvider = FutureProvider.autoDispose<List<String>>((ref) async {
  final response = await ApiClient.instance.dio.get('/audit-log/entity-tables');
  return List<String>.from(response.data as List);
});

/// {items, totalCount, page, pageSize} — راجع AuditLogsController.GetAll.
final auditLogProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final search = ref.watch(auditLogSearchProvider);
  final entityTable = ref.watch(auditLogEntityFilterProvider);
  final page = ref.watch(auditLogPageProvider);
  final response = await ApiClient.instance.dio.get('/audit-log', queryParameters: {
    if (search.isNotEmpty) 'search': search,
    if (entityTable != null) 'entityTable': entityTable,
    'page': page,
    'pageSize': auditLogPageSize,
  });
  return response.data as Map<String, dynamic>;
});

/// كل النتائج المطابقة للفلتر الحالي (حتى 2000) — للتصدير/الطباعة فقط،
/// وليست للعرض العادي المُقسَّم صفحات.
Future<List<Map<String, dynamic>>> fetchAuditLogExport({
  required String search,
  required String? entityTable,
}) async {
  final response = await ApiClient.instance.dio.get('/audit-log/export', queryParameters: {
    if (search.isNotEmpty) 'search': search,
    if (entityTable != null) 'entityTable': entityTable,
  });
  return List<Map<String, dynamic>>.from(response.data as List);
}
