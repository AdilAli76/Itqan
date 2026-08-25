import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:kinetic_enterprise/core/shell/screen_registry.dart';
import 'package:kinetic_enterprise/core/theme/app_colors.dart';
import 'package:kinetic_enterprise/core/theme/app_theme.dart';

import 'support/tour_data.dart';

/// مسبار تشخيصي للفيض — يترك Flutter يطبع تقريره كاملاً.
///
/// ui_audit_test يستهلك الاستثناء بـ takeException، فيضيع معه وصف الودجت
/// المسبِّب («The relevant error-causing widget was: …») وهو المعلومة
/// الوحيدة المفيدة عند المطاردة؛ ما يبقى رقمٌ مجرّد لا يدلّ على شيء.
///
/// هنا لا نلمس FlutterError.onError إطلاقاً: التقرير يُطبع في الطرفية كما
/// هو، ثم نبتلع الاستثناء في النهاية حتى لا يفشل المسبار نفسه — الغرض
/// الإظهار لا الحكم.
///
///     flutter test test/overflow_probe_test.dart --plain-name inventory
///
/// يُترك في المشروع لأن الفيض يتكرّر مع كل شاشة جديدة على مقاس صغير.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  // نفس مُعترِض جولة اللقطات. سببان لا سبب واحد:
  //
  // 1) **الصحّة:** بلا اعتراض، كل مزوّد يطلق طلباً شبكياً حقيقياً بمؤقّت
  //    مهلة. مؤقّت واحد لم ينتهِ عند اكتمال الاختبار يُفشله بـ«Pending
  //    timers» — وهذا ما كان يُفشل مسبار /pos تحديداً (posQuickPicksProvider).
  //
  // 2) **الغرض:** الفيض يقع بسبب *المحتوى* لا الهيكل الفارغ. شاشة تعرض
  //    صندوق خطأ لأن الشبكة فشلت لا تُظهر انهيار جدول بأسماء أصناف طويلة —
  //    أي أن المسبار بلا بيانات كان يُعلن «نظيف» عن شاشات لم تُختبَر أصلاً.
  setUpAll(installFixtureAdapter);

  const routes = ['/inventory', '/pos', '/invoices', '/customers'];

  for (final route in routes) {
    testWidgets('مسبار $route على الهاتف', (tester) async {
      // Galaxy A36 — نفس مقاس ui_audit_test.
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      // تقرير Flutter الكامل لا يصل الطرفية داخل testWidgets: الإطار
      // يستبدل onError ليُسجّل الاستثناءات بدل طباعتها. نلتقطه ونطبعه.
      final reports = <String>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exception.toString().contains('overflowed')) {
          reports.add(details.toString());
        }
      };

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.build(const AppColors()),
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: buildScreenForRoute(route),
            ),
          ),
        ),
      );
      // إطارات متتابعة لا إطار واحد: مزوّد الاختيارات السريعة في نقطة البيع
      // يسلسل ثلاثة طلبات (تقرير ← جرد ← جرد)، وكلٌّ منها يجدول مؤقّتاً في
      // Dio ينتظر إطاراً ليُنجَز. إطار واحد بـ400 مللي كان يترك آخر مؤقّت
      // معلّقاً عند تفكيك الشجرة فيُفشل المسبار بـ«A Timer is still pending»
      // — وهو فشل أداة لا فشل شاشة.
      //
      // ونُبقي على pump الصريح بدل pumpAndSettle: شاشات فيها لمعان هياكل
      // تحميل دائم لا تستقرّ أبداً، وpumpAndSettle عليها يرمي مهلة.
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      FlutterError.onError = previous;

      // تُبتلع كل الاستثناءات: التقرير أدناه هو الناتج المطلوب.
      dynamic e;
      do {
        e = tester.takeException();
      } while (e != null);

      for (final r in reports) {
        // ignore: avoid_print
        print('=== فيض في $route ===');
        // ignore: avoid_print
        print(r);
      }
      if (reports.isEmpty) {
        // ignore: avoid_print
        print('نظيف: $route');
      }
    });
  }
}
