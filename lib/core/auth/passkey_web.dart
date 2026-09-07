import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// نسخة الويب: نداءٌ مباشر للجسر المعرَّف في `web/index.html`.
///
/// الأسماء هناك لا هنا عمداً — راجع تعليق الجسر في `web/index.html`.
@JS('kineticPasskey.supported')
external bool _supported();

@JS('kineticPasskey.register')
external JSPromise<JSString> _register(JSString optionsJson);

@JS('kineticPasskey.unlock')
external JSPromise<JSString> _unlock(JSString optionsJson);

/// <summary>
/// وجود الجسر يُفحص قبل ندائه.
///
/// نسخةٌ قديمة من `index.html` بقيت في ذاكرة المتصفّح تعني كائناً غير
/// معرَّف، ونداؤه يرمي `TypeError` يوقف الشاشة كلّها. والفحص يجعل الأثر
/// الأسوأ اختفاءَ زرٍّ لا انهيارَ صفحة.
/// </summary>
bool isSupported() {
  if (!globalContext.has('kineticPasskey')) return false;
  return _supported();
}

Future<String> register(String optionsJson) async =>
    (await _register(optionsJson.toJS).toDart).toDart;

Future<String> unlock(String optionsJson) async =>
    (await _unlock(optionsJson.toJS).toDart).toDart;
