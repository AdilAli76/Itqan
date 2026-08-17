import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

/// null = الكل، true = المقروءة فقط، false = غير المقروءة فقط.
final notificationsFilterProvider = StateProvider.autoDispose<bool?>((ref) => null);

final notificationsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final isRead = ref.watch(notificationsFilterProvider);
  final response = await ApiClient.instance.dio.get('/notifications', queryParameters: {
    if (isRead != null) 'isRead': isRead,
  });
  return List<Map<String, dynamic>>.from(response.data as List);
});
