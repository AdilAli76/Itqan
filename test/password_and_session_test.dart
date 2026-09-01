import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic_enterprise/core/auth/session_expiry_watch.dart';

/// حرّاسٌ نصّية على قفل الكلمة المؤقّتة وعلى إنذار الجلسة.
///
/// <para><b>لماذا نصّية:</b> الطرفان يقعان على حدود لا تُبلَغ من اختبار
/// ودجات — قائمة المُعفَين تعيش في الخادم (C#)، وجدولة المؤقّت تحتاج توكناً
/// في تخزين مشفَّر. والحارس النصّي يمسك **الانحراف** وهو ما يُخشى هنا: سطرٌ
/// يُحذف بحسن نيّة فيفتح باباً أو يُغلق الحساب على صاحبه.</para>
void main() {
  final filter = File(
    'backend/KineticEnterprise.Api/Authorization/MustChangePasswordFilter.cs',
  ).readAsStringSync();

  group('قفل الكلمة المؤقّتة', () {
    test('تغيير كلمة المرور معفًى من القفل — وإلا قفلٌ لا مخرج منه', () {
      // العطب الذي يمسكه: حذف هذا السطر يُنتج حساباً يُطالَب بتغيير كلمته
      // ويُمنَع من تغييرها. ولا يظهر إلا لأوّل مستخدم تُعاد كلمته بعد
      // النشر — أي عند العميل لا عندنا.
      expect(filter, contains('/api/auth/change-password'));
    });

    test('الدخول معفًى — لا توكن بعدُ يُفحَص', () {
      expect(filter, contains('/api/auth/login'));
    });

    test('التجديد غير معفًى — لا يمدّ حاملُ كلمةٍ مؤقّتة جلسته', () {
      // إعفاؤه كان يعني حساباً يعمل بكلمةٍ يعرفها اثنان ثمانيَ ساعات
      // متجدّدة إلى الأبد بلا أن يغيّرها.
      expect(filter, isNot(contains('/api/auth/refresh')));
    });

    test('يردّ 403 برمزٍ لا 401 — وإلا حلقةٌ لا تنتهي', () {
      // 401 تُفهَم في الواجهة «انتهت جلستك» فيُمحى التوكن ويُعاد إلى
      // الدخول، فيدخل بالكلمة المؤقّتة نفسها ويدور.
      expect(filter, contains('must_change_password'));
      expect(filter, contains('Status403Forbidden'));
    });

    test('العلم يُقرأ من القاعدة لا من التوكن', () {
      // دعوى في التوكن تبقى مرفوعةً بعد تغيير الكلمة حتى ينتهي، فيُقفل
      // الحساب على صاحبه بعد أن فعل ما طُلب منه.
      expect(filter, contains('db.AppUsers'));
    });
  });

  group('كل مسار إعادة تعيين يرفع العلم', () {
    test('إعادة مالك المنصّة لكلمة مدير عميله', () {
      final source = File(
        'backend/KineticEnterprise.Api/Controllers/PlatformController.cs',
      ).readAsStringSync();
      expect(source, contains('must_change_password = 1'));
    });

    test('إعادة مدير المنظمة لكلمة موظّفه — إلا لنفسه', () {
      // الاستثناء لازم: بلا `!= CurrentUserId()` يقع من يُعيد كلمته لنفسه
      // في حلقة — يغيّرها فتُرفع الراية عليه فيُطالَب بتغييرها.
      final source = File(
        'backend/KineticEnterprise.Api/Controllers/UsersController.cs',
      ).readAsStringSync();
      expect(source, contains('MustChangePassword = user.Id != CurrentUserId()'));
    });
  });

  group('إنذار الجلسة', () {
    test('يُنذَر قبل الانتهاء بخمس دقائق', () {
      expect(SessionExpiryWatch.warnBefore, const Duration(minutes: 5));
    });

    test('المدّة تُقرأ من التوكن لا من رقمٍ في الواجهة', () {
      // رقمٌ مكتوب في Dart يفترق عن SessionLifetime في الخادم أوّل مرّة
      // يُغيَّر أحدهما، فيُنذر قبل ساعة أو بعد الانتهاء.
      final watch = File('lib/core/auth/session_expiry_watch.dart').readAsStringSync();
      expect(watch, contains("claims?['exp']"));
      expect(watch, isNot(contains('Duration(hours: 8)')));
    });

    test('التمديد يُعيد قراءة الحساب من القاعدة', () {
      // بناء التوكن الجديد من دعاوى القديم كان يُخلّد صلاحيةً سُحبت
      // وحساباً عُطِّل — فيمدّد الموقوفُ جلسته إلى الأبد بضغطة.
      final auth = File(
        'backend/KineticEnterprise.Api/Controllers/AuthController.cs',
      ).readAsStringSync();
      expect(auth, contains('u.Id == userId && u.IsActive'));
    });

    test('مدّة الجلسة ثابتٌ واحد يقرؤه الإصدار والتجديد', () {
      final auth = File(
        'backend/KineticEnterprise.Api/Controllers/AuthController.cs',
      ).readAsStringSync();
      expect(auth, contains('SessionLifetime'));
      // ورقمٌ مكتوب مرّتين يُنتج جلسةً تُجدَّد بمدّةٍ غير التي بدأت بها.
      expect(auth, isNot(contains('AddHours(8)')));
    });
  });

  test('تغيير كلمة المرور يطلب الكلمة القديمة', () {
    // جهازٌ تُرك مفتوحاً في محلّ يكفي بلا ذلك للاستيلاء على الحساب
    // نهائياً — بينما طلبُها يجعل أسوأ ما يفعله المارّ استعمالَ الجلسة
    // حتى تنتهي.
    final auth = File(
      'backend/KineticEnterprise.Api/Controllers/AuthController.cs',
    ).readAsStringSync();
    expect(auth, contains('BCrypt.Net.BCrypt.Verify(request.CurrentPassword'));
  });
}
