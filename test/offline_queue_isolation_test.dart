import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic_enterprise/core/network/offline_queue.dart';

/// عزل طابور البيع المؤجَّل بين المنظمات.
///
/// **العطب الذي يمسكه:** كان الطابور يُحفظ تحت مفتاح عالمي واحد
/// (`kinetic_offline_sales`) لكل من يستعمل الجهاز. فمنظمةٌ باعت بلا إنترنت
/// تترك طابورها، ثم يدخل مستخدم منظمة أخرى على الجهاز نفسه فيرى **عدّاد
/// مزامنة لعمليات ليست له**. وأسوأ من العرض: المزامنة تحاول إرسالها بتوكنه
/// هو، فيرفضها الخادم فتبقى معلّقة بلا تفسير.
void main() {
  const orgA = '11111111-1111-1111-1111-111111111111';
  const orgB = '22222222-2222-2222-2222-222222222222';

  TestWidgetsFlutterBinding.ensureInitialized();

  /// حمولة بيع بالشكل الذي تُنتجه نقطة البيع.
  Map<String, dynamic> sale(String requestId) => {
        'clientRequestId': requestId,
        'branchId': '00000000-0000-0000-0000-0000000000bb',
        'paymentMethod': 'cash',
        'lines': [
          {'productId': '00000000-0000-0000-0000-0000000000cc', 'quantity': 1},
        ],
      };

  test('طابور منظمة لا يظهر لمنظمة أخرى على الجهاز نفسه', () async {
    FlutterSecureStorage.setMockInitialValues({'kinetic_jwt_token': _jwt(orgA)});

    final queueA = OfflineQueueNotifier();
    await queueA.reloadForCurrentUser();
    expect(await queueA.enqueue(sale('a-1')), isTrue);
    expect(await queueA.enqueue(sale('a-2')), isTrue);
    expect(queueA.state.pending.length, 2, reason: 'عمليتان في طابور المنظمة الأولى');

    // نفس الجهاز، مستخدم منظمة أخرى — **وما كتبته الأولى يبقى كما هو**.
    //
    // يُقرأ التخزين الفعلي ويُعاد وضعه مع التوكن الجديد. وكتابةُ قيم مُلفَّقة
    // بدلاً منه كانت ستجعل الاختبار ينجح على الكود المعطوب أيضاً: المفتاح
    // العالمي القديم لن يكون موجوداً أصلاً فيعود الطابور فارغاً بلا سبب.
    const storage = FlutterSecureStorage();
    final onDevice = Map<String, String>.from(await storage.readAll());
    onDevice['kinetic_jwt_token'] = _jwt(orgB);
    FlutterSecureStorage.setMockInitialValues(onDevice);

    final queueB = OfflineQueueNotifier();
    await queueB.reloadForCurrentUser();

    expect(queueB.state.pending, isEmpty,
        reason: 'المنظمة الثانية لا ترى شيئاً من طابور الأولى — وهو العطب الأصلي');
  });

  test('بلا توكن لا يُعرض طابور — عدّادٌ قبل الدخول لا يخصّ أحداً', () async {
    final row = json.encode([
      {
        'clientRequestId': 'a-1',
        'payload': sale('a-1'),
        'createdAt': DateTime.now().toIso8601String(),
        'attempts': 0,
      },
    ]);
    // المفتاحان معاً: بلا القديم ينجح الاختبار على الكود المعطوب أيضاً.
    FlutterSecureStorage.setMockInitialValues({
      'kinetic_offline_sales_$orgA': row,
      'kinetic_offline_sales': row,
    });

    final queue = OfflineQueueNotifier();
    await queue.reloadForCurrentUser();

    expect(queue.state.pending, isEmpty);
  });

  test('الطابور القديم يُهاجَر مرّةً ولا يُمحى — قد يحمل مبيعات لم تصل', () async {
    FlutterSecureStorage.setMockInitialValues({
      'kinetic_jwt_token': _jwt(orgA),
      // مفتاح ما قبل الإصلاح.
      'kinetic_offline_sales': json.encode([
        {
          'clientRequestId': 'legacy-1',
          'payload': sale('legacy-1'),
          'createdAt': DateTime.now().toIso8601String(),
          'attempts': 0,
        },
      ]),
    });

    final queue = OfflineQueueNotifier();
    await queue.reloadForCurrentUser();

    expect(queue.state.pending.length, 1,
        reason: 'محو الطابور القديم كان سيُضيّع مبيعات حقيقية قُبض مالها');
    expect(queue.state.pending.first.clientRequestId, 'legacy-1');

    // وبعد الهجرة لا يعود المفتاح القديم يُقرأ لأحد.
    const storage = FlutterSecureStorage();
    expect(await storage.read(key: 'kinetic_offline_sales'), isNull);
    expect(await storage.read(key: 'kinetic_offline_sales_$orgA'), isNotNull);
  });

  test('الطابور يبقى محفوظاً لصاحبه بعد إعادة التحميل', () async {
    FlutterSecureStorage.setMockInitialValues({'kinetic_jwt_token': _jwt(orgA)});

    final first = OfflineQueueNotifier();
    await first.reloadForCurrentUser();
    await first.enqueue(sale('keep-1'));

    // مثيل جديد يقرأ من التخزين نفسه — كأن التطبيق أُعيد تشغيله.
    final second = OfflineQueueNotifier();
    await second.reloadForCurrentUser();

    expect(second.state.pending.length, 1);
    expect(second.state.pending.first.clientRequestId, 'keep-1');
  });
}

/// توكن مُركَّب: الكود يفكّ الحمولة ولا يتحقّق من التوقيع (الخادم يفعل).
String _jwt(String organizationId) {
  String seg(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(json.encode(m))).replaceAll('=', '');
  return '${seg({'alg': 'none', 'typ': 'JWT'})}'
      '.${seg({'organization_id': organizationId, 'role': 'super_admin'})}'
      '.signature';
}
