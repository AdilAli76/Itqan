import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

final chartOfAccountsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final response = await ApiClient.instance.dio.get('/accounting/accounts');
  final data = response.data;
  if (data == null) return [];
  if (data is List) return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  if (data is Map) return [data as Map<String, dynamic>];
  return [];
});

/// الحساب المحدَّد لتصفية دفتر اليومية — null يعني كل القيود.
final journalAccountFilterProvider = StateProvider.autoDispose<String?>((ref) => null);

final journalProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final accountId = ref.watch(journalAccountFilterProvider);
  final response = await ApiClient.instance.dio.get('/accounting/journal', queryParameters: {
    if (accountId != null) 'accountId': accountId,
  });
  final data = response.data;
  if (data == null) return [];
  if (data is List) return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  if (data is Map) return [data as Map<String, dynamic>];
  return [];
});

final trialBalanceProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final response = await ApiClient.instance.dio.get('/accounting/trial-balance');
  final data = response.data;
  if (data is Map) return Map<String, dynamic>.from(data);
  return {};
});

final incomeStatementProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final response = await ApiClient.instance.dio.get('/accounting/income-statement');
  final data = response.data;
  if (data is Map) return Map<String, dynamic>.from(data);
  return {};
});

final balanceSheetProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final response = await ApiClient.instance.dio.get('/accounting/balance-sheet');
  final data = response.data;
  if (data is Map) return Map<String, dynamic>.from(data);
  return {};
});

final fiscalClosingsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final response = await ApiClient.instance.dio.get('/accounting/closings');
  final data = response.data;
  if (data == null) return [];
  if (data is List) return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  if (data is Map) return [data as Map<String, dynamic>];
  return [];
});
