import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

final chartOfAccountsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final response = await ApiClient.instance.dio.get('/accounting/accounts');
  return (response.data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
});

/// الحساب المحدَّد لتصفية دفتر اليومية — null يعني كل القيود.
final journalAccountFilterProvider = StateProvider.autoDispose<String?>((ref) => null);

final journalProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final accountId = ref.watch(journalAccountFilterProvider);
  final response = await ApiClient.instance.dio.get('/accounting/journal', queryParameters: {
    if (accountId != null) 'accountId': accountId,
  });
  return (response.data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
});

final trialBalanceProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final response = await ApiClient.instance.dio.get('/accounting/trial-balance');
  return response.data as Map<String, dynamic>;
});

final incomeStatementProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final response = await ApiClient.instance.dio.get('/accounting/income-statement');
  return response.data as Map<String, dynamic>;
});

final balanceSheetProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final response = await ApiClient.instance.dio.get('/accounting/balance-sheet');
  return response.data as Map<String, dynamic>;
});

final fiscalClosingsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final response = await ApiClient.instance.dio.get('/accounting/closings');
  return (response.data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
});
