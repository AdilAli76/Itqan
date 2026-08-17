import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

final platformSupportInfoProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final response = await ApiClient.instance.dio.get('/platform-settings');
  return response.data as Map<String, dynamic>;
});
