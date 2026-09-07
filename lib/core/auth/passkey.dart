import 'dart:convert';

import 'passkey_unsupported.dart' if (dart.library.js_interop) 'passkey_web.dart' as platform;

/// مفاتيح المرور كما تراها بقية التطبيق: ثلاث دوالّ لا أكثر.
///
/// <para><b>سبب وجود هذه الطبقة:</b> نداء المفتاح يختلف اختلافاً كاملاً بين
/// الويب والأجهزة، ولا يوجد على سطح المكتب أصلاً. وبلا واجهةٍ واحدة تُخفي
/// ذلك، تنتشر فحوص المنصّة في شاشتين وثلاث — ويُنسى واحدٌ منها فتنكسر
/// الشاشة على ويندوز بخطأ «دالّة غير معرّفة» لا يفهمه أحد.</para>
///
/// <para><b>وما يعبر الجسر نصٌّ بترميز base64url لا بايتات:</b> واجهة
/// المتصفّح تتكلّم بـArrayBuffer، وتحويلُه في دارت سطحٌ واسع لخطأٍ صامت.
/// فالتحويل كلّه في <c>web/index.html</c>، وما يصل هنا هو عين ما يفهمه
/// الخادم — فيُمرَّر كما هو بلا تفسير.</para>
class Passkeys {
  const Passkeys._();

  /// أيدعم هذا الجهاز مفاتيح المرور أصلاً؟
  ///
  /// تُسأل قبل عرض الزرّ: زرٌّ يفتح نافذةً تُغلق فوراً أسوأ من زرٍّ غائب.
  static bool get isSupported => platform.isSupported();

  /// تسجيل مفتاح جديد. تُعيد ما يُرسَل إلى الخادم كما هو.
  static Future<Map<String, dynamic>> register(Map<String, dynamic> options) =>
      _call(platform.register(jsonEncode(options)));

  /// توقيعٌ يفتح القفل. تُعيد ما يُرسَل إلى الخادم كما هو.
  static Future<Map<String, dynamic>> unlock(Map<String, dynamic> options) =>
      _call(platform.unlock(jsonEncode(options)));

  /// <summary>
  /// الخطأ يعبر الجسر في حقل <c>error</c> لا كاستثناء.
  ///
  /// استثناءٌ يُرمى من جافاسكربت يصل إلى دارت بلا رسالة، فيرى المستخدم
  /// «تعذّرت العملية» بينما المتصفّح قال له بالضبط ما المشكلة: نافذةٌ
  /// أُلغيت، أو مفتاحٌ مسجَّل، أو جهازٌ بلا بصمة.
  /// </summary>
  static Future<Map<String, dynamic>> _call(Future<String> raw) async {
    final decoded = jsonDecode(await raw) as Map<String, dynamic>;
    final error = decoded['error'];
    if (error is String && error.isNotEmpty) throw PasskeyException(error);
    return decoded;
  }
}

/// خطأٌ نصّه من المتصفّح أو النظام — يُعرَض كما هو.
class PasskeyException implements Exception {
  const PasskeyException(this.message);
  final String message;

  @override
  String toString() => message;
}
