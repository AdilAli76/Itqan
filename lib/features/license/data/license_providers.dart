import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

final licenseProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final response = await ApiClient.instance.dio.get('/license/me');
  return response.data as Map<String, dynamic>;
});

/// حال التفعيل: بصمة **جهاز الخادم** وصلاحية المفتاح الحالي.
///
/// <para>مستقلٌّ عن [licenseProvider]: ذاك يقرأ ما في الجدول (باقة وحدود
/// وتواريخ)، وهذا يقرأ ما يقوله **التحقّق من التوقيع** — والاثنان قد
/// يفترقان، وهو بالضبط ما تريد الشاشة أن تعرضه: صفٌّ يقول «فعّال» ومفتاحٌ
/// لا يُقبَل.</para>
final licenseActivationProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final response = await ApiClient.instance.dio.get('/license/activation');
  return Map<String, dynamic>.from(response.data as Map);
});
