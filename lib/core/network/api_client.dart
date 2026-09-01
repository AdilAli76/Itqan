import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show ValueNotifier, kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// استيرادٌ شرطي: `dart:io` غير موجود على الويب، واستيرادُه مباشرةً يُسقط
// `flutter build web` كلّه — والويب هو ما يُنشر على خادمك.
import 'installed_server_web.dart'
    if (dart.library.io) 'installed_server_io.dart';

/// عميل HTTP موحّد لكل النظام — بديل مباشر لـ Supabase.instance.client.
/// يحقن توكن JWT تلقائياً في كل طلب، ويُنشأ مرة واحدة عبر [ApiClient.instance].
class ApiClient {
  ApiClient._internal() {
    _dio = Dio(BaseOptions(baseUrl: resolvedBaseUrl, connectTimeout: const Duration(seconds: 10)));
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.read(key: _tokenKey);
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      // 401 يعني أن التوكن غاب أو انتهى أو رُفض. بلا هذه المعالجة كان كل
      // مزوّد يرمي استثناءً عادياً، فتعرض كل شاشة صندوق «تعذّر التحميل» مع
      // زر «إعادة المحاولة» يفشل أبداً لأن السبب ليس الشبكة — ولا يوجد في
      // النظام أي حارس مسار يعيد إلى تسجيل الدخول. النتيجة: المستخدم عالق
      // في شاشة لا تعمل ولا تشرح، ولا مخرج إلا أن يعرف من نفسه أن يضغط
      // «تسجيل الخروج».
      //
      // التوكن يُمسح هنا لأن إبقاء توكن مرفوض يعيد إنتاج نفس الفشل مع كل
      // طلب تالٍ؛ وإشعار [sessionExpired] يترك للطبقة العليا قرار التنقّل
      // (لا سياق تنقّل في هذه الطبقة أصلاً).
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          // العلم أولاً ثم المسح: مسح التخزين قد يفشل (تخزين الويب المشفَّر
          // يعتمد على SubtleCrypto، وقد يُرفض أو يغيب)، وترتيبه قبل العلم
          // كان يبتلع الإشارة كلّها فيبقى المستخدم عالقاً — وهو بالضبط ما
          // يفترض هذا الاعتراض أن يمنعه.
          sessionExpired.value = true;
          try {
            await _storage.delete(key: _tokenKey);
          } catch (_) {
            // توكن مرفوض باقٍ في التخزين مزعج لكنه غير قاتل: القشرة تعيد
            // إلى تسجيل الدخول، والدخول الناجح يكتب فوقه.
          }
        }
        handler.next(error);
      },
    ));
  }

  /// يرتفع إلى true عند أول 401. تستمع إليه القشرة فتعيد إلى تسجيل الدخول.
  ///
  /// ValueNotifier لا Stream: الحالة نفسها هي المطلوبة (هل الجلسة منتهية؟)
  /// لا تسلسل الأحداث، ومستمع واحد متأخّر في الاشتراك يجب أن يرى القيمة
  /// الحالية لا أن تفوته.
  final ValueNotifier<bool> sessionExpired = ValueNotifier<bool>(false);

  static final ApiClient instance = ApiClient._internal();

  /// عنوان الـ Backend.
  ///
  /// على الويب يُشتقّ من أصل الصفحة وقت التشغيل: الخادم يخدم الويب والـAPI
  /// من موقع IIS واحد، فأيّاً كان العنوان الذي فُتحت به الصفحة فهو عنوان
  /// الـAPI. وهذا يجعل حزمة نشر واحدة تعمل على أي نطاق بلا إعادة بناء —
  /// العنوان المخبوز وقت البناء كان يربط الحزمة بنطاق واحد، فتُعاد بناؤها
  /// عند كل تغيّر في العنوان (وقع فعلاً ثلاث مرّات في أول نشر: عنوان IP،
  /// ثم نطاق، ثم نفق).
  ///
  /// وسطح المكتب والأندرويد لا صفحة لهما يُشتقّ منها، فيبقى --dart-define
  /// طريقهما. ويظلّ متاحاً على الويب أيضاً ويُقدَّم على الاشتقاق، لحالة
  /// استضافة الـAPI على أصل مختلف.
  static const String _definedBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// عنوان أدخله المستخدم على هذا الجهاز — يُحمَّل قبل تشغيل التطبيق.
  ///
  /// **العطب الذي يصلحه:** الويب وحده كان يشتقّ عنوانه، والأندرويد وسطح
  /// المكتب يسقطان على <c>localhost</c> — أي أن الهاتف يكلّم نفسه فلا يدخل
  /// أحد. والبديل السابق (خبز العنوان وقت البناء) يعني **نسخة APK لكل
  /// عميل**، وإعادة بناء عند كل تغيّر نطاق.
  static String? _savedBaseUrl;

  /// العنوان الفعّال، بترتيب الأولوية.
  ///
  /// المخبوز وقت البناء يتقدّم على المحفوظ: من بنى نسخةً لعميل بعينه قصد
  /// أن تعمل على خادمه وحده، ولا يصحّ أن يُغيّره مستخدم على الجهاز.
  /// عنوانٌ كتبه المُركِّب في ملفٍّ بجوار التطبيق — للتركيب المحلّي.
  ///
  /// **الحاجة التي يسدّها:** النسخة المحلّية بلا إنترنت تعمل على جهاز
  /// المحلّ نفسه، وعنوانها معلومٌ لحظةَ التركيب. وبلا هذا كان الزبون يُقابَل
  /// بشاشة «أدخل عنوان الخادم» في أوّل فتحة — سؤالٌ لا يعرف جوابه عن
  /// جهازٍ أمامه.
  ///
  /// **ولماذا ملفٌّ لا خبزٌ وقت البناء:** الخبز يعني نسختين من التطبيق
  /// تُبنيان وتُوقَّعان وتُختبران — بينما الفرق سطرٌ نصّي. وهو عين ما
  /// أُصلح في الأندرويد من قبل: «نسخة APK لكل عميل».
  static String? _installedBaseUrl;

  /// العنوان الفعّال، بترتيب الأولوية.
  ///
  /// المخبوز وقت البناء يتقدّم على المحفوظ: من بنى نسخةً لعميل بعينه قصد
  /// أن تعمل على خادمه وحده، ولا يصحّ أن يُغيّره مستخدم على الجهاز.
  ///
  /// ثم ما اختاره المستخدم، ثم ما كتبه المُركِّب: من غيّر العنوان بيده قصد
  /// ذلك، وملفُّ التركيب افتراضٌ أوّليّ لا أمرٌ يُلغي قراره.
  static String get resolvedBaseUrl {
    if (_definedBaseUrl.isNotEmpty) return _definedBaseUrl;
    if (_savedBaseUrl != null && _savedBaseUrl!.isNotEmpty) return _savedBaseUrl!;
    if (_installedBaseUrl != null && _installedBaseUrl!.isNotEmpty) return _installedBaseUrl!;
    if (kIsWeb) return '${Uri.base.origin}/api';
    return '';
  }

  /// هل يحتاج هذا الجهاز إلى ضبط عنوان الخادم قبل أي شيء.
  static bool get needsSetup => resolvedBaseUrl.isEmpty;

  /// هل يُسمح للمستخدم بتغيير العنوان — لا في النسخ المخبوزة لعميل بعينه.
  static bool get canChangeServer => _definedBaseUrl.isEmpty && !kIsWeb;

  static const _serverKey = 'kinetic_server_url';

  /// يُستدعى مرّة قبل runApp.
  static Future<void> loadSavedServer() async {
    if (!canChangeServer) return;

    // ملفُّ التركيب أوّلاً ثم المحفوظ فوقه: القراءة بهذا الترتيب تجعل
    // اختيار المستخدم يغلب، ويبقى الملف افتراضاً حين لا اختيار.
    _installedBaseUrl = readInstalledServer();

    try {
      _savedBaseUrl = await const FlutterSecureStorage().read(key: _serverKey);
      instance._applyBaseUrl();
    } catch (_) {
      // تخزين معطّل: يبقى العنوان فارغاً فتظهر شاشة الضبط — وهي أوضح من
      // تعطّل صامت.
    }
  }

  /// يحفظ العنوان ويُطبّقه فوراً بلا إعادة تشغيل.
  static Future<void> setServer(String url) async {
    final normalized = normalizeServerUrl(url);
    _savedBaseUrl = normalized;
    instance._applyBaseUrl();
    await const FlutterSecureStorage().write(key: _serverKey, value: normalized);
  }

  /// يمحو العنوان المحفوظ — لتغيير الخادم من شاشة الدخول.
  static Future<void> clearServer() async {
    _savedBaseUrl = null;
    instance._applyBaseUrl();
    await const FlutterSecureStorage().delete(key: _serverKey);
  }

  /// يقبل ما يكتبه المستخدم فعلاً ويحوّله إلى عنوان صالح.
  ///
  /// من يُملى عليه العنوان هاتفياً يكتب «erp.droob-albayan.ly» بلا بروتوكول،
  /// أو يُلحق «/» أو ينسى «/api». ورفضُ ذلك بـ«عنوان غير صالح» يجعله يعيد
  /// المحاولة بلا أن يعرف ما ينقص.
  static String normalizeServerUrl(String raw) {
    var url = raw.trim();
    if (url.isEmpty) return '';
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      // https افتراضاً: الخوادم الحقيقية بشهادة، وhttp يُكتب صراحةً لمن
      // يستعمل تركيباً محلياً بلا شهادة.
      url = 'https://$url';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (!url.endsWith('/api')) url = '$url/api';
    return url;
  }

  void _applyBaseUrl() => _dio.options.baseUrl = resolvedBaseUrl;

  static const _tokenKey = 'kinetic_jwt_token';
  final _storage = const FlutterSecureStorage();
  late final Dio _dio;

  Dio get dio => _dio;

  Future<void> saveToken(String token) {
    // دخول ناجح يُنهي حالة «الجلسة منتهية»، وإلا بقي العلم مرفوعاً فتُعيد
    // القشرة المستخدم إلى شاشة الدخول فور دخوله.
    sessionExpired.value = false;
    return _storage.write(key: _tokenKey, value: token);
  }
  Future<void> clearToken() => _storage.delete(key: _tokenKey);
  Future<String?> readToken() => _storage.read(key: _tokenKey);
}
