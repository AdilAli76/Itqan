import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/constants/app_constants.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/branding_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: KineticApp()));
}

class KineticApp extends ConsumerWidget {
  const KineticApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brandingAsync = ref.watch(brandingProvider);
    final branding = brandingAsync.valueOrNull ?? OrganizationBranding.fallback;

    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: branding.displayName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(branding.colors),
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
        return Directionality(
          textDirection: AppConstants.direction,
          child: child ?? const SizedBox.shrink(),
        );
      },
      routerConfig: router,
    );
  }
}