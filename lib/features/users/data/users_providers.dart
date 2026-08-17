import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

final userSearchProvider = StateProvider.autoDispose<String>((ref) => '');

final usersProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final search = ref.watch(userSearchProvider);
  final response = await ApiClient.instance.dio.get('/users', queryParameters: {
    if (search.isNotEmpty) 'search': search,
  });
  return List<Map<String, dynamic>>.from(response.data as List);
});

final loginHistoryProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final response = await ApiClient.instance.dio.get('/users/login-history');
  return List<Map<String, dynamic>>.from(response.data as List);
});
