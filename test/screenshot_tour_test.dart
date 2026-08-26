import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:kinetic_enterprise/core/auth/permissions.dart';
import 'package:kinetic_enterprise/core/shell/screen_registry.dart';
import 'package:kinetic_enterprise/core/theme/app_colors.dart';
import 'package:kinetic_enterprise/core/time/app_clock.dart';
import 'package:kinetic_enterprise/core/theme/app_theme.dart';

import 'support/tour_data.dart';

/// جولة لقطات لكل شاشات النظام.
///
/// سبب وجودها: الوصف يضلّل. «الشاشة تعمل» جملة تصدُق ما دام أحد لم ينظر —
/// وقد ثبت ذلك مراراً في هذا المشروع: بحث الأصناف كان «يعمل» بينما ينهار
/// التخطيط، وشرائح الفلترة «موجودة» بينما تظهر قائمةً رأسية.
///
/// التشغيل:
///     flutter test test/screenshot_tour_test.dart --update-goldens
///
/// يكتب PNG لكل شاشة × كل مقاس في test/screenshots/. من دون
/// ‎--update-goldens تُقارَن اللقطات بالمحفوظة، فتكشف أي تغيّر بصري غير
/// مقصود — أي أنها جولة توثيق وحارس انحدار في آن.
///
/// ## من أين تأتي البيانات
///
/// من عيّنات ملتقطة من الخادم الحقيقي (tool/capture_fixtures.py) تُخدَم عبر
/// اعتراض طبقة نقل Dio. أي أن كل شاشة تمرّ بمسار التحليل الحقيقي في
/// مزوّدها — وهو المسار الذي انكسر فعلاً حين تغيّر عقد نقاط النهاية. حقن
/// المزوّدات مباشرةً كان سيتجاوز ذلك المسار فيُخفي الصنف نفسه من الأعطال.
///
/// وثباتها يجعل اللقطات قابلة للمقارنة بين التشغيلات، بخلاف بيانات حيّة
/// تتغيّر فتُفشل المقارنة بلا سبب حقيقي.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // الخط مضمَّن في assets الآن (راجع pubspec.yaml)، فيحمّله flutter test
    // من حزمة الأصول مباشرةً — لا شبكة ولا خط نظام ولا مربّعات فارغة.
    //
    // allowRuntimeFetching = false يمنع google_fonts من محاولة الجلب
    // الشبكي: الحزمة موجودة محلياً، وأي محاولة شبكية في بيئة الاختبار
    // ترمي استثناءً غير متزامن يُفشل الاختبار بعد اكتماله.
    GoogleFonts.config.allowRuntimeFetching = false;

    final data = await rootBundle.load('assets/fonts/IBMPlexSansArabic-Regular.ttf');
    // أسماء العائلات التي يطلبها google_fonts لكل وزن — تسجيلها يجعله
    // يجدها محمّلة فلا يحاول الجلب أصلاً.
    // أيقونات Material أيضاً: بلا تحميلها تظهر كل أيقونة مربّعاً فارغاً في
    // اللقطة، فتفقد الجولة نصف قيمتها — الأيقونة نصف لغة الواجهة، وشاشة
    // بلا أيقونات لا يمكن الحكم على وضوحها.
    // المسار يُشتقّ من موقع Flutter SDK لا يُثبَّت: يختلف بين الأجهزة.
    final flutterRoot = Platform.environment['FLUTTER_ROOT'] ??
        (File(Platform.resolvedExecutable).parent.parent.path);
    final iconCandidates = [
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      '$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
      r'C:\srclutterin\cachertifacts\material_fonts\materialicons-regular.otf',
    ];
    final iconPath = iconCandidates.firstWhere((p) => File(p).existsSync(), orElse: () => '');
    // ignore: avoid_print
    print('خط الأيقونات: ${iconPath.isEmpty ? "غير موجود — ستظهر مربّعات" : iconPath}');
    final iconsFile = File(iconPath.isEmpty ? 'nonexistent' : iconPath);
    if (iconsFile.existsSync()) {
      // sublistView لا ByteData.view(.buffer): الأخيرة تأخذ المخزن الأساسي
      // كاملاً متجاهلةً إزاحة العرض وطوله، فيصل إلى FontLoader بايت زائد أو
      // ناقص فيرفض الخط صامتاً — وتبقى الأيقونات مربّعات فارغة بلا أي خطأ.
      final iconBytes = ByteData.sublistView(iconsFile.readAsBytesSync());
      await (FontLoader('MaterialIcons')..addFont(Future.value(iconBytes))).load();
    }

    for (final family in [
      'IBMPlexSansArabic',
      'IBMPlexSansArabic_regular',
      'IBMPlexSansArabic_medium',
      'IBMPlexSansArabic_semibold',
      'IBMPlexSansArabic_bold',
      'Roboto',
    ]) {
      await (FontLoader(family)..addFont(Future.value(data))).load();
    }
  });

  setUpAll(() {
    // flutter_secure_storage قناة أصلية لا تنفيذ لها في بيئة الاختبار،
    // فترمي MissingPluginException عند أول قراءة توكن. الردّ الفارغ يكفي:
    // الشاشات تُصوَّر ببيانات العيّنات لا بتوكن حقيقي.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => call.method == 'readAll' ? <String, String>{} : null,
    );

    final outDir = Directory('test/screenshots');
    if (!outDir.existsSync()) outDir.createSync(recursive: true);
    // اعتراض طبقة النقل مرّة واحدة لكل الجولة.
    // الوقت مثبَّت: شاشتا التقارير والمخزون تعرضان «عدد الأيام منذ كذا» و
    // «تنتهي خلال كذا يوماً» — محسوبَين من الآن على عيّنات ثابتة التواريخ.
    // فبلا التثبيت تتغيّر اللقطة كل منتصف ليل بلا أن يتغيّر سطر من الكود،
    // ويصير الفشل اليومي الكاذب عادةً يُتجاهَل معها الفشل الحقيقي.
    AppClock.freeze(DateTime(2026, 8, 25, 12));

    installFixtureAdapter();
  });

  for (final device in kTourDevices) {
    group(device.label, () {
      for (final screen in kTourScreens) {
        testWidgets('${screen.route} — ${screen.label}', (tester) async {
          tester.view.physicalSize = device.size;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                // صلاحيات كاملة: الغرض تصوير الشاشات لا اختبار الحجب.
                myPermissionsProvider.overrideWith((ref) async => const UserPermissions(
                      role: 'super_admin',
                      isSuperAdmin: true,
                      codes: {},
                    )),
              ],
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
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
                  child: buildScreenForRoute(screen.route),
                ),
              ),
            ),
          );

          // pumpAndSettle لا pump: حركات الدخول المتتابعة (FadeSlideIn مع
          // staggerDelay) تجدول مؤقّتات، وأي مؤقّت معلّق عند تفكيك الشجرة
          // يُفشل الاختبار بـ«A Timer is still pending». والانتظار حتى
          // الاستقرار يضمن أيضاً أن اللقطة تُلتقط بعد اكتمال الحركة لا في
          // منتصفها — وإلا خرجت الشاشات نصف شفافة ومزاحة.
          await tester.pump();
          try {
            await tester.pumpAndSettle(const Duration(milliseconds: 100));
          } on FlutterError {
            // شاشة فيها حركة دائمة (لمعان هياكل التحميل) لا تستقرّ أبداً؛
            // نكتفي بإطارات كافية لاكتمال حركات الدخول.
            for (var i = 0; i < 12; i++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
          }

          // الاستثناءات تُسجَّل ولا تُفشل الجولة: الغرض تصوير كل الشاشات في
          // مرور واحد، وشاشة معطوبة يجب أن تُصوَّر بعطبها لا أن توقف البقية.
          final error = tester.takeException();
          if (error != null) {
            kTourFindings.add('${device.label} ← ${screen.route}: $error');
          }

          final name = screen.route.replaceAll('/', '').replaceAll('-', '_');
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('screenshots/${device.slug}__$name.png'),
          );
        });
      }
    });
  }

  tearDownAll(() {
    final missing = fixtureAdapter?.missing ?? const <String>{};
    if (missing.isNotEmpty) {
      // ignore: avoid_print
      print('=== مسارات بلا عيّنة (${missing.length}) ===');
      for (final m in missing) {
        // ignore: avoid_print
        print('  • $m');
      }
      // ignore: avoid_print
      print('  أضِفها إلى PATHS في tool/capture_fixtures.py ثم أعد الالتقاط.');
    }
    if (kTourFindings.isEmpty) {
      // ignore: avoid_print
      print('\nلا استثناءات في أي شاشة.');
      return;
    }
    // ignore: avoid_print
    print('\n=== استثناءات أثناء الجولة (${kTourFindings.length}) ===');
    for (final f in kTourFindings) {
      // ignore: avoid_print
      print('  • $f');
    }
  });
}
