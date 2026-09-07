import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// حرّاسٌ نصّية على مفاتيح المرور والقفل السريع.
///
/// <para><b>لماذا نصّية:</b> ما يُخشى هنا يقع كلّه خارج ما يبلغه اختبار
/// ودجات — تحقّقٌ في الخادم (C#)، وجسرٌ بجافاسكربت في `web/index.html`،
/// وواجهةُ متصفّحٍ لا وجود لها في بيئة الاختبار أصلاً. والحارس النصّي يمسك
/// **الانحراف**: سطرٌ يُحذف بحسن نيّة فيصير القفل مظهراً بلا حقيقة.</para>
///
/// <para>وكلُّ فحصٍ هنا يقابل بابَ دخولٍ لو انفتح لم يُلاحَظ: الميزة تبقى
/// «تعمل» في كل حالة — تُفتح الشاشة، ويُقبل المفتاح — والفرق أن الذي فتحها
/// ليس صاحبها.</para>
void main() {
  final controller = File(
    'backend/KineticEnterprise.Api/Controllers/PasskeysController.cs',
  ).readAsStringSync();

  final webAuthn = File(
    'backend/KineticEnterprise.Api/Data/WebAuthn.cs',
  ).readAsStringSync();

  final bridge = File('web/index.html').readAsStringSync();

  final gate = File('lib/core/auth/lock_screen.dart').readAsStringSync();

  group('لا سطح دخولٍ جديد قبل المصادقة', () {
    test('نقاط المفاتيح كلّها خلف [Authorize]', () {
      expect(controller, contains('[Authorize]'));
    });

    test('ولا AllowAnonymous في وحدة المفاتيح', () {
      // مفتاح المرور هنا يفتح جلسةً قائمة ولا يُصدرها. وإعفاءُ نقطةٍ واحدة
      // يحوّل الميزة إلى دخولٍ بلا كلمة مرور — وهو قرارٌ يُتخذ صراحةً لا
      // أثرٌ جانبيّ لسطرٍ أُضيف.
      expect(controller, isNot(contains('AllowAnonymous')));
    });

    test('فتح القفل لا يُصدر توكناً', () {
      // «فُتح القفل» ردٌّ لا يحمل توكناً: من انتزع رداً من الشبكة لا ينال
      // به جلسةً على جهازٍ آخر.
      expect(controller, isNot(contains('IssueToken')));
    });
  });

  group('التحقّق لا يكتفي بالحضور', () {
    test('UserVerified شرطٌ لا فحصٌ اختياري', () {
      // علم الحضور يعني أن أحداً لمس الجهاز، ولا يميّز صاحب الحساب ممّن
      // جلس مكانه. وقفلٌ يفتحه من جلس على الكرسي ليس قفلاً.
      expect(controller, contains('UserVerified'));
      expect(controller, contains('!authData.UserVerified'));
    });

    test('والجسر يطلب من المتصفّح تحقّقاً لا حضوراً', () {
      expect(bridge, contains("userVerification: 'required'"));
    });

    test('بصمة النطاق تُقارَن — مفتاح نطاقٍ آخر يُرفض', () {
      expect(controller, contains('RpIdHash'));
    });
  });

  group('المفتاح لصاحبه', () {
    test('البحث عن المفتاح مقيَّدٌ بمستخدم الجلسة', () {
      // بلا شرط UserId يفتح مفتاحُ موظّفٍ آخر جلسةَ هذا الحساب: التوقيع
      // صحيحٌ في ذاته، والخطأ أن يُقبل من غير صاحبه.
      expect(controller, contains('p.CredentialId == request.CredentialId && p.UserId == userId'));
    });

    test('والحذف كذلك', () {
      expect(controller, contains('p.Id == id && p.UserId == userId'));
    });
  });

  group('التحدّي يُستعمل مرّة واحدة', () {
    test('يُحذف من الذاكرة قبل التحقّق', () {
      // بقاؤه بعد محاولةٍ فاشلة يسمح بإعادة إرسال ردٍّ التُقط من محاولة
      // سابقة. والحذف قبل التحقّق لا بعده: التحقّق قد يخرج بـreturn.
      expect(controller, contains('_cache.Remove(ChallengeKey("register"'));
      expect(controller, contains('_cache.Remove(ChallengeKey("unlock"'));
    });

    test('ويُقارَن بزمنٍ ثابت', () {
      expect(webAuthn, contains('CryptographicOperations.FixedTimeEquals'));
    });
  });

  group('حارس الاستنساخ', () {
    test('عدّاد التوقيع يُفحص ولا يُقبل رجوعه', () {
      expect(controller, contains('authData.SignCount <= passkey.SignCount'));
    });

    test('ولا يُفحص إن كان صفراً — مفاتيح المزامنة تُبقيه صفراً دائماً', () {
      // فحصُه على الصفر كان يرفض أشيع الأجهزة: أوّل فتحٍ يقارن صفراً بصفر
      // فيُرفض، والميزة تبدو معطوبة على كل هاتف.
      expect(controller, contains('passkey.SignCount > 0 && authData.SignCount > 0'));
    });
  });

  group('الخوارزميات المقبولة', () {
    test('الخادم يتحقّق من ES256 وRS256', () {
      expect(webAuthn, contains('-7'));
      expect(webAuthn, contains('-257'));
    });

    test('والجسر يطلبهما وحدهما — وإلا مفتاحٌ يُسجَّل ثم يُرفض عند الفتح', () {
      expect(bridge, contains('alg: -7'));
      expect(bridge, contains('alg: -257'));
    });
  });

  group('الغطاء يقفل فعلاً', () {
    test('يبتلع اللمس', () {
      // غطاءٌ يُنقر من خلفه في فاتورة ليس قفلاً.
      expect(gate, contains('AbsorbPointer'));
    });

    test('ويُخرج ما تحته من شجرة الفوكس', () {
      // بلا هذا يبقى المؤشّر في حقلٍ تحت الغطاء فتذهب إليه الكتابة.
      expect(gate, contains('ExcludeFocus'));
    });
  });
}
