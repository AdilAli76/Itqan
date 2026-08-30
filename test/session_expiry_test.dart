import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic_enterprise/core/network/api_client.dart';

/// انتهاء الجلسة يجب أن يُكتشَف لا أن يظهر كـ«تعذّر التحميل».
///
/// العطل الذي يحرسه هذا الاختبار ظهر في تجربة حيّة: شاشتا الفواتير والعملاء
/// عرضتا «تعذّر التحميل» مع زر «إعادة المحاولة»، بينما كانت نقطة البيع تعمل
/// وتُنشئ فاتورة. الخادم لم يسجّل أي استثناء، وكل نقاط النهاية تردّ 200
/// بتوكن صالح و401 بلا توكن — أي أن الطلب وصل بلا تصريح.
///
/// وكان النظام يفتقر إلى أي معالجة لـ401: لا اعتراض ولا حارس مسار. فزرّ
/// «إعادة المحاولة» يفشل أبداً لأن السبب ليس الشبكة، ولا مخرج للمستخدم إلا
/// أن يعرف من نفسه أن يضغط «تسجيل الخروج».
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // flutter_secure_storage قناة منصّة بلا تنفيذ على Dart VM، فبدون هذا
  // المحاكي يسقط الطلب داخل onRequest نفسه (قراءة التوكن) قبل أن يصل ردّ
  // الخادم إلى onError — فيمرّ الاختبار على استثناء من نوع آخر ولا يفحص
  // مسار 401 إطلاقاً. (وقع فعلاً في أول تشغيل لهذا الاختبار.)
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final store = <String, String>{};

  setUp(() {
    ApiClient.instance.sessionExpired.value = false;
    store.clear();
    store['kinetic_jwt_token'] = 'dummy.jwt.token';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
      switch (call.method) {
        case 'read':
          return store[args['key'] as String];
        case 'write':
          store[args['key'] as String] = args['value'] as String;
          return null;
        case 'delete':
          store.remove(args['key'] as String);
          return null;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('401 يرفع علم انتهاء الجلسة', () async {
    final client = ApiClient.instance;
    expect(client.sessionExpired.value, isFalse);

    // اعتراض يسبق اعتراض المصادقة في السلسلة لا يكفي — المطلوب أن يمرّ الخطأ
    // على onError الحقيقي، فيُحاكى ردٌّ 401 من الخادم عبر محوّل وهمي.
    client.dio.httpClientAdapter = _Status401Adapter();

    await expectLater(
      client.dio.get('/invoices'),
      throwsA(isA<DioException>()),
    );

    expect(client.sessionExpired.value, isTrue,
        reason: 'بلا هذا العلم تبقى الشاشات تعرض «تعذّر التحميل» بلا مخرج');
  });

  test('غير 401 لا يرفع العلم — خطأ شبكة ليس انتهاء جلسة', () async {
    final client = ApiClient.instance;
    client.dio.httpClientAdapter = _Status500Adapter();

    await expectLater(
      client.dio.get('/invoices'),
      throwsA(isA<DioException>()),
    );

    expect(client.sessionExpired.value, isFalse,
        reason: 'إخراج المستخدم عند كل خطأ خادم يفقده عمله بلا سبب');
  });
}

class _Status401Adapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream,
          Future<void>? cancelFuture) async =>
      ResponseBody.fromString('{"message":"unauthorized"}', 401,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType]
          });
}

class _Status500Adapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream,
          Future<void>? cancelFuture) async =>
      ResponseBody.fromString('{"message":"server error"}', 500,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType]
          });
}
