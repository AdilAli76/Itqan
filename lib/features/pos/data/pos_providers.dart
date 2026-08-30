import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/pagination_bar.dart';

/// نفس نمط inventory_providers.dart — البحث فارغ يعني بلا نتائج بدل تحميل
/// الكتالوج كاملاً بلا داعٍ في كل مرة تُفتح فيها الشاشة.
final posProductSearchProvider = StateProvider.autoDispose<String>((ref) => '');

final posProductResultsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final search = ref.watch(posProductSearchProvider).trim();
  if (search.isEmpty) return [];
  // بحث فوري لا تصفّح: عشرون مطابقة تملأ القائمة المنسدلة، وما بعدها
  // يُضيّقه الكاشير بحرف إضافي لا بصفحة تالية.
  final response = await ApiClient.instance.dio.get('/products/inventory', queryParameters: {
    'search': search,
    'page': 1,
    'pageSize': 20,
  });
  return PagedResult.fromJson(response.data as Map<String, dynamic>).items;
});

final posCustomerSearchProvider = StateProvider.autoDispose<String>((ref) => '');

final posCustomerResultsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final search = ref.watch(posCustomerSearchProvider).trim();
  if (search.isEmpty) return [];
  // بحث فوري في نقطة البيع: أول عشرين مطابقة تكفي — الكاشير يختار من
  // القائمة المنسدلة ولا يتصفّح صفحات، وطلب أكثر من ذلك تأخير بلا فائدة.
  final response = await ApiClient.instance.dio.get('/customers', queryParameters: {
    'search': search,
    'page': 1,
    'pageSize': 20,
  });
  return PagedResult.fromJson(response.data as Map<String, dynamic>).items;
});

/// أصناف الوصول السريع — تظهر على الشاشة قبل أي كتابة.
///
/// شاشة البيع كانت فارغة تماماً حتى يكتب الكاشير حرفاً، وهو تصميم يفترض
/// قارئ باركود سلكياً في كل جهاز. وهو افتراض ينهار في حالتين شائعتين: صنف
/// بلا باركود أصلاً (الخضار، المخبوزات، الخدمات)، وجهاز لوحي أو هاتف بلا
/// قارئ. في الحالتين لا سبيل إلى الصنف إلا بكتابة اسمه كاملاً وصحيحاً.
///
/// الترتيب: الأكثر مبيعاً خلال ثلاثين يوماً أولاً (من /reports/sales-summary
/// الذي يحسبها في السيرفر أصلاً)، ثم تُكمَّل القائمة بأصناف بلا باركود —
/// وهي بالضبط التي لا يمكن مسحها. متجر جديد بلا مبيعات بعد يرى الثانية
/// وحدها بدل شاشة فارغة.
final posQuickPicksProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  const limit = 12;
  final dio = ApiClient.instance.dio;

  final now = DateTime.now();
  final from = now.subtract(const Duration(days: 30));
  String d(DateTime t) => '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

  final picks = <String, Map<String, dynamic>>{};

  // الأكثر مبيعاً: التقرير يُرجع معرّفات وأسماء لا بطاقات أصناف كاملة،
  // فتُجلب البطاقات من الجرد — نقطة البيع تحتاج السعر والرصيد لا الاسم.
  try {
    final report = await dio.get('/reports/sales-summary',
        queryParameters: {'from': d(from), 'to': d(now)});
    final top = (report.data['topProducts'] as List?) ?? const [];
    if (top.isNotEmpty) {
      final inv = await dio.get('/products/inventory',
          queryParameters: {'page': 1, 'pageSize': 200});
      final byId = {
        for (final p in PagedResult.fromJson(inv.data as Map<String, dynamic>).items)
          p['id'] as String: p
      };
      for (final t in top) {
        final id = t['productId'] as String?;
        final card = id == null ? null : byId[id];
        if (card != null && picks.length < limit) picks[id!] = card;
      }
    }
  } catch (_) {
    // التقرير قد يُمنَع على دور الكاشير — لا يُفشل الشاشة، تُكمَّل بما بعده.
  }

  // أصناف بلا باركود: لا يمكن مسحها بأي قارئ، فظهورها هنا هو طريقها الوحيد.
  if (picks.length < limit) {
    try {
      final inv = await dio.get('/products/inventory',
          queryParameters: {'page': 1, 'pageSize': 200});
      for (final p in PagedResult.fromJson(inv.data as Map<String, dynamic>).items) {
        if (picks.length >= limit) break;
        final barcode = (p['barcode'] as String?)?.trim();
        if (barcode == null || barcode.isEmpty) picks[p['id'] as String] = p;
      }
    } catch (_) {}
  }

  return picks.values.toList();
});

/// ملخّص صلاحية المخزون لشريط الإنذار على شاشة البيع.
///
/// مفتاحه رقم الفرع لأن الصلاحية خاصية دفعة في فرع بعينه: مدير يتنقّل بين
/// الفروع يجب أن يرى إنذار الفرع المعروض لا آخر فرع فتحه.
///
/// يبتلع الخطأ ويُرجع null عمداً: هذا شريط تحذيري ثانوي، وإسقاط شاشة البيع
/// كلها لأن استدعاءه فشل (شبكة، أو وحدة inventory غير مفعَّلة في إصدار
/// المنظمة فيردّ 403) يمنع البيع بسبب تحذير — وهو أسوأ من غياب التحذير.
final posExpiryAlertProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>?, String?>((ref, branchId) async {
  try {
    final response = await ApiClient.instance.dio.get(
      '/products/expiry-alerts',
      queryParameters: {
        if (branchId != null) 'branchId': branchId,
        'withinDays': 30,
        'limit': 10,
      },
    );
    return response.data as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
});

/// نشرة الدواء لصنف بعينه — لإصدار الصيدليات وحده.
///
/// تُجلَب عند الطلب لا مع قائمة الأصناف: النشرة نصوص طويلة تخصّ صنفاً واحداً
/// يسأل عنه الكاشير، وحملها مع كل صنف يُثقل شاشة تُفتح عشرات المرّات يومياً.
///
/// null يعني «لا نشرة» لا «فشل»: الصنف قد يكون غير دوائي (مستحضر تجميل،
/// حفاضات) فيردّ الخادم 204، أو تكون الوحدة غير مفعَّلة فيردّ 403. وفي
/// الحالتين الصمت هو السلوك الصحيح — لا رسالة خطأ في حالة عادية.
final medicineInfoProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>?, String>((ref, productId) async {
  try {
    final response = await ApiClient.instance.dio.get('/products/$productId/medicine');
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    return null;
  } catch (_) {
    return null;
  }
});
