import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/customer_portal/presentation/customer_portal_screen.dart';
import '../shell/app_shell.dart';
import '../network/api_client.dart';
import '../../features/auth/presentation/server_setup_screen.dart';

/// يُبنى مرة واحدة فقط ويُعاد استخدامه — إنشاء GoRouter داخل build() كان
/// يهدم Navigator/Overlay الجذر ويعيد بناءه مع كل تغيّر في brandingProvider
/// (مثل ref.invalidate بعد تسجيل الدخول)، ما كان يسبب أخطاء عابرة من نوع
/// "No MaterialLocalizations found" لأي TextField كان يحمل الفوكس حينها.
final appRouterProvider = Provider<GoRouter>((ref) => buildAppRouter());

/// كل شاشات النظام (راجع screen_registry.dart) تُفتَح الآن كتبويبات داخل
/// AppShell الدائم بدل مسار GoRoute مستقل لكل شاشة — AppShell هو المسار
/// الوحيد بعد تسجيل الدخول؛ التنقّل الداخلي بين الوحدات يتم عبر
/// openTabsProvider (حالة Riverpod)، لا عبر context.go بعد الآن.
GoRouter buildAppRouter() {
  return GoRouter(
    // ضبط الخادم قبل الدخول: على الجوّال وسطح المكتب لا عنوان يُشتقّ من
    // شيء، فشاشة دخولٍ بلا خادم تفشل برسالة عن كلمة المرور — فيظنّ
    // المستخدم حسابه خاطئاً بينما لا خادم أصلاً.
    initialLocation: ApiClient.needsSetup ? '/server' : '/login',
    routes: [
      GoRoute(
        path: '/server',
        builder: (context, state) => ServerSetupScreen(
          onDone: () => context.go('/login'),
        ),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      // بوابة العميل — خارج AppShell عمداً: العميل ليس مستخدَم نظام ولا يرى
      // أي شاشة إدارية، فلا شريط جانبي ولا تبويبات هنا.
      GoRoute(path: '/my-account', builder: (context, state) => const CustomerPortalScreen()),
      GoRoute(
        path: '/app',
        builder: (context, state) {
          final initial = state.uri.queryParameters['route'] ?? '/dashboard';
          return AppShell(initialRoute: initial);
        },
      ),
    ],
  );
}
