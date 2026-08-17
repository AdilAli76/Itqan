import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/api_client.dart';

/// عرض إيصال الطابعة الحرارية المُعدّ في شاشة الإعدادات العامة — تحتاجه أي
/// عملية طباعة إيصال (نقطة البيع، إعادة طباعة من شاشة الفواتير)، بصرف
/// النظر عن دور المستخدم، فالقراءة هنا مفتوحة لأي مستخدم مسجَّل دخول
/// (راجع OrganizationsController.GetSettings).
final receiptWidthMmProvider = FutureProvider.autoDispose<double>((ref) async {
  try {
    final response = await ApiClient.instance.dio.get('/organizations/me/settings');
    return (response.data['receiptWidthMm'] as num?)?.toDouble() ?? 80;
  } catch (_) {
    return 80;
  }
});
