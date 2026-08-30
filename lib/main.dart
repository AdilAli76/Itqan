import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'core/constants/app_constants.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/branding_provider.dart';
import 'core/theme/theme_mode_provider.dart';
import 'core/network/api_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // مسارات بلا # — erp.droob-albayan.ly/pos بدل .../#/pos.
  //
  // **ليست تحسين سرعة:** التوجيه بالهاشتاق يقع داخل المتصفّح بلا أي طلب
  // شبكي، فلا فرق في الأداء بينه وبين المسار. لكن الرابط النظيف يُنسَخ
  // ويُرسَل ويُفهرَس، والرابط بـ# يُقطع في كثير من تطبيقات المراسلة عند
  // علامة الهاشتاق فيصل ناقصاً.
  //
  // وشرطه على الخادم قائم أصلاً: MapFallbackToFile("index.html") في
  // Program.cs يردّ التطبيق لأي مسار غير معروف — وبدونه كان فتح
  // /pos مباشرةً يعطي 404.
  usePathUrlStrategy();

  // عنوان الخادم المحفوظ على هذا الجهاز — قبل runApp لا بعده: أول طلب قد
  // ينطلق مع أول إطار، وتحميلٌ متأخّر يجعله يذهب إلى عنوان فارغ ثم ينجح
  // الطلب التالي — فيظهر عطلٌ متقطّع لا يُفسَّر.
  await ApiClient.loadSavedServer();

  runApp(const ProviderScope(child: KineticApp()));
}

class KineticApp extends ConsumerWidget {
  const KineticApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brandingAsync = ref.watch(brandingProvider);
    final branding = brandingAsync.valueOrNull ?? OrganizationBranding.fallback;

    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: branding.displayName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(branding.colors),
      darkTheme: AppTheme.build(branding.colors, brightness: Brightness.dark),
      themeMode: themeMode,
      locale: AppConstants.locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      
      // ----- التعديل الجديد: إضافة مندوبي التدويل لدعم العربية والإنجليزية -----
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // -----------------------------------------------------------------

      builder: (context, child) {
        // مزامنة اللوحة النشطة مع السمة المطبَّقة فعلياً.
        //
        // ضرورية لأن AppTheme.build يُستدعى مرّتين (نهارية وليلية) عند كل
        // بناء لـ MaterialApp، فآخر استدعاء هو من يترك أثره في اللوحة —
        // وهو الليلي دائماً بحكم الترتيب. هنا، وبعد أن يحسم Flutter أي
        // سمة تُطبَّق فعلاً، نضبط اللوحة على سطوعها الحقيقي. والموضع
        // مضمون: builder يُنفَّذ قبل بناء أي شاشة تحته.
        AppColors.applyBrightness(Theme.of(context).brightness);
        return Directionality(
          textDirection: AppConstants.direction,
          child: child ?? const SizedBox.shrink(),
        );
      },
      routerConfig: router,
    );
  }
}