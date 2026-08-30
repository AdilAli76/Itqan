import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

/// المورّد المختار في شاشة فواتير الموردين — null يعني كل الموردين.
final supplierInvoiceFilterProvider = StateProvider.autoDispose<String?>((ref) => null);

final supplierInvoicesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final supplierId = ref.watch(supplierInvoiceFilterProvider);
  final response = await ApiClient.instance.dio.get('/supplier-invoices', queryParameters: {
    if (supplierId != null) 'supplierId': supplierId,
  });
  return (response.data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
});

/// سطور الاستلام التي لم تُفوتر بعد لمورّدٍ بعينه.
///
/// عائلةٌ لا مزوّد واحد: الشاشة تفتح حوار الإنشاء لمورّد ثم لآخر، ومزوّدٌ
/// واحد يُبقي نتيجة الأول معروضةً للثاني لحظةً قبل التحميل.
final uninvoicedReceiptsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, supplierId) async {
  final response = await ApiClient.instance.dio
      .get('/supplier-invoices/uninvoiced', queryParameters: {'supplierId': supplierId});
  return (response.data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
});

/// تقرير مقارنة أسعار الشراء — محسوبٌ من تاريخ الاستلامات لا من عمود مخزَّن.
final purchasePriceHistoryProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final supplierId = ref.watch(supplierInvoiceFilterProvider);
  final response = await ApiClient.instance.dio
      .get('/supplier-invoices/price-history', queryParameters: {
    if (supplierId != null) 'supplierId': supplierId,
  });
  return (response.data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
});
