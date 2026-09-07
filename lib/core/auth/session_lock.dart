import 'package:flutter_riverpod/flutter_riverpod.dart';

/// حالة القفل السريع: أمقفولةٌ الشاشة الآن؟
///
/// <para><b>سبب وجوده:</b> الجلسة ثماني ساعات، والشاشة تبقى مفتوحةً على
/// حساب المدير بينما يقوم من مكتبه. وتسجيلُ الخروج ثم الدخول من جديد عند
/// كل قيام يعني كتابة كلمة مرورٍ عشرين مرّة في اليوم — فلا يُفعل، فتبقى
/// الشاشة مفتوحة لمن مرّ.</para>
///
/// <para><b>وليست انتهاءً للجلسة:</b> التوكن يبقى صالحاً والتبويبات
/// المفتوحة على حالها — فاتورةٌ نصف مكتوبة لا تضيع بقفل الشاشة، وهو شرط
/// أن يُستعمل القفل أصلاً. ومن يريد إنهاء الجلسة فعلاً يسجّل الخروج.</para>
///
/// <para><b>وفي الذاكرة لا على القرص:</b> القفل يحمي جهازاً متروكاً لدقائق،
/// وإعادة تشغيل التطبيق تمرّ على شاشة الدخول أصلاً — فحفظُه يعني شاشةً
/// مقفلة فوق شاشة دخول، وسؤالين متتاليين عن الهوية.</para>
final sessionLockProvider =
    StateNotifierProvider<SessionLockNotifier, bool>((ref) => SessionLockNotifier());

class SessionLockNotifier extends StateNotifier<bool> {
  SessionLockNotifier() : super(false);

  void lock() => state = true;
  void unlock() => state = false;
}
