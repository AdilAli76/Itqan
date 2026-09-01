import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/current_user.dart';
import '../auth/session_expiry_watch.dart';
import '../network/api_client.dart';
import '../network/realtime_listener.dart';
import '../network/realtime_service.dart';
import '../responsive/breakpoints.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/branding_provider.dart';
import '../../shared/widgets/app_navbar.dart';
import '../../shared/widgets/app_sidebar.dart';
import '../../shared/widgets/command_palette.dart';
import '../../shared/widgets/nav_items.dart';
import 'open_tabs_provider.dart';
import 'screen_registry.dart';
import 'shell_scope.dart';
import '../../shared/widgets/icon_action.dart';
import '../../shared/widgets/update_banner.dart';

/// الحاوية الدائمة لكل شاشات النظام بعد تسجيل الدخول — تُبنى مرة واحدة فقط
/// وتبقى حيّة طوال الجلسة. فتح شاشة جديدة = تبويب جديد في IndexedStack
/// (يبقى حيّاً بكل حالته: تمرير، فلاتر، نماذج مفتوحة)، لا استبدال الصفحة
/// كلها من الصفر كما كان الحال سابقاً — هذا تحديداً ما يحلّ شكوى "فتح شاشة
/// وحدة يشعرك وكأنك فتحت النظام من أول مرة".
///
/// شريط الحالة العلوي (الدور/تسجيل الخروج) لم يعد شريطاً مستقلاً هنا —
/// دُمج داخل AdaptiveScaffold.header نفسه (راجع تعليقه) لأن وجوده كشريط
/// منفصل كان يضيف ~48px من فراغ شبه فارغ فوق كل شاشة، إضافة لتكرار عنوان
/// الشاشة مع شريط التبويبات أدناه.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, this.initialRoute = '/dashboard'});
  final String initialRoute;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _isPlatformAdmin = false;

  @override
  void initState() {
    super.initState();
    // انتهاء الجلسة (401 من أي طلب) يعيد إلى تسجيل الدخول فوراً.
    //
    // بدونه كانت كل شاشة تعرض «تعذّر التحميل» مع زر إعادة محاولة لا ينجح
    // أبداً — السبب ليس الشبكة بل توكن مرفوض — ولا حارس مسار في النظام
    // يكتشف ذلك. فيبقى المستخدم عالقاً بلا تفسير ولا مخرج.
    ApiClient.instance.sessionExpired.addListener(_onSessionExpired);

    // وإنذارٌ **قبل** الانتهاء لا بعده: الاعتراض أعلاه يمنع الشاشة العالقة
    // ولا يمنع القذف المفاجئ إلى شاشة الدخول في منتصف فاتورة. راجع
    // [SessionExpiryWatch].
    _sessionWatch = SessionExpiryWatch(onWarn: _warnSessionEnding);
    _sessionWatch.schedule();
    readJwtClaims().then((claims) {
      if (mounted) setState(() => _isPlatformAdmin = claims?['is_platform_admin'] == 'True');
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final tabs = ref.read(openTabsProvider);
      if (tabs.tabs.isEmpty) {
        final item = kNavItems.firstWhere(
          (i) => i.route == widget.initialRoute,
          orElse: () => kNavItems.first,
        );
        ref.read(openTabsProvider.notifier).open(item.route, title: item.label, icon: item.icon);
      }
    });
  }

  @override
  void dispose() {
    ApiClient.instance.sessionExpired.removeListener(_onSessionExpired);
    // مؤقّتٌ حيّ بعد تفكيك الشجرة يُفشل الاختبارات بـ«A Timer is still
    // pending»، ويحاول عرض حوارٍ على سياقٍ ميت في التطبيق.
    _sessionWatch.dispose();
    super.dispose();
  }

  late final SessionExpiryWatch _sessionWatch;

  /// حوار «توشك جلستك أن تنتهي» — بزرّ يمدّها.
  ///
  /// <para><c>barrierDismissible: false</c> عمداً: نقرةٌ خارج النافذة
  /// تُغلقها بلا قرار، فيفقد المستخدم الإنذار الوحيد الذي سيصله.</para>
  Future<void> _warnSessionEnding() async {
    if (!mounted) return;

    final extend = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('توشك الجلسة أن تنتهي'),
        content: const Text(
          'ستنتهي جلستك خلال خمس دقائق وتعود إلى شاشة الدخول. '
          'مدِّدها إن كنت في منتصف عمل.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('اتركها تنتهي'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('مدِّد'),
          ),
        ],
      ),
    );

    if (extend != true || !mounted) return;

    final ok = await _sessionWatch.extend();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'مُدّدت الجلسة'
            // ولا يُقال «حاول مجدداً» بلا معنى: الفشل هنا غالباً حسابٌ
            // عُطِّل أو شبكةٌ انقطعت، وكلاهما ينتهي بالخروج بعد دقائق.
            : 'تعذّر تمديد الجلسة — احفظ عملك وسجّل الدخول من جديد'),
      ),
    );
  }

  void _onSessionExpired() {
    if (!mounted || !ApiClient.instance.sessionExpired.value) return;
    // التوكن مُسِح في الاعتراض نفسه؛ الباقي إغلاق التبويبات والتنقّل.
    ref.read(openTabsProvider.notifier).closeAll();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('انتهت الجلسة — سجّل الدخول من جديد')),
    );
    context.go('/login');
  }

  void _openPalette() {
    CommandPalette.show(context, isPlatformAdmin: _isPlatformAdmin);
  }

  Future<void> _logout() async {
    // إغلاق الاتصال اللحظي قبل مسح التوكن — تركه مفتوحاً يعني بقاء قناة
    // مصرَّح لها بعد خروج المستخدم حتى تنتهي مهلة الخادم.
    await ref.read(realtimeServiceProvider).disconnect();
    await performLogout(ref);
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final tabsState = ref.watch(openTabsProvider);
    final isDesktop = Breakpoints.isDesktop(context);
    final navLayout = ref.watch(brandingProvider).valueOrNull?.navLayout ?? 'sidebar';
    final useNavbar = isDesktop && navLayout == 'navbar';
    final useSidebar = isDesktop && !useNavbar;
    final activeIndex = tabsState.tabs.indexWhere((t) => t.route == tabsState.activeRoute);

    // شريط التبويبات يُخفى تلقائياً عند وجود تبويب واحد فقط (الحالة
    // الشائعة) — عندها يصبح عنوانه مطابقاً حرفياً لعنوان الشاشة في
    // AdaptiveScaffold.header فيكون تكراراً بحتاً بلا فائدة إضافية.
    final tabBar = isDesktop && tabsState.tabs.length > 1 ? _TabBar(tabsState: tabsState) : null;

    final content = ShellScope(
      child: tabsState.tabs.isEmpty
          ? const SizedBox.shrink()
          : IndexedStack(
              index: activeIndex < 0 ? 0 : activeIndex,
              children: tabsState.tabs
                  .map((t) => KeyedSubtree(key: ValueKey(t.route), child: buildScreenForRoute(t.route)))
                  .toList(),
            ),
    );

    // اختصار لوحة الأوامر مُسجَّل هنا لا داخل كل شاشة: AppShell هو الأب
    // المشترك لكل التبويبات، فيلتقط Ctrl+K أياً كانت الشاشة النشطة —
    // بشرط ألّا يكون الفوكس داخل حقل نصّي يستهلك الضغطة أولاً، وهو ما
    // يضمنه Shortcuts تلقائياً.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): _openPalette,
        // Cmd+K على macOS — نفس الاختصار الذي اعتاده المستخدم هناك.
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): _openPalette,
      },
      child: Focus(
        autofocus: true,
        // RealtimeListener هنا لا داخل كل شاشة: التبويب الخلفي يجب أن يتحدّث
        // أيضاً، وإلا عاد المستخدم إليه ليجد بيانات قديمة بلا أي إشارة.
        child: RealtimeListener(
          child: _buildScaffold(context, tabsState, isDesktop, useSidebar, useNavbar, tabBar, content),
        ),
      ),
    );
  }

  Widget _buildScaffold(
    BuildContext context,
    TabsState tabsState,
    bool isDesktop,
    bool useSidebar,
    bool useNavbar,
    Widget? tabBar,
    Widget content,
  ) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: isDesktop
          ? null
          : AppBar(
              title: Text(tabsState.tabs.isEmpty ? '' : (tabsState.tabs.firstWhere((t) => t.route == tabsState.activeRoute, orElse: () => tabsState.tabs.first)).title),
              actions: [
                IconButton(
                  onPressed: _openPalette,
                  icon: const Icon(Icons.search),
                  tooltip: 'بحث شامل عن شاشة (Ctrl+K)',
                ),
                // ونظيره في شريط سطح المكتب ([_HeaderAccountArea]): الكاشير
                // يعمل على هاتف غالباً، وهو أوّل من يحتاج تغيير كلمةٍ
                // أُمليت عليه — فوضعُه في الشريط الأوسع وحده يحرمه منه.
                IconButton(
                  onPressed: () => context.go('/change-password'),
                  icon: const Icon(Icons.password_outlined),
                  tooltip: 'تغيير كلمة المرور',
                ),
                IconButton(onPressed: _logout, icon: const Icon(Icons.logout), tooltip: 'تسجيل الخروج'),
              ],
            ),
      drawer: isDesktop ? null : Drawer(child: AppSidebar(activeRoute: tabsState.activeRoute ?? '')),
      // شريط التحديث فوق كل شيء: هو الرسالة الوحيدة التي يجب أن تُرى مهما
      // كانت الشاشة المفتوحة، ووضعه داخل شاشة بعينها يعني أن من لا يفتحها
      // لا يعلم بالتحديث أبداً.
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const UpdateBanner(),
          Expanded(
            child: useSidebar
          ? Row(
              children: [
                SizedBox(
                  width: 264,
                  child: AppSidebar(activeRoute: tabsState.activeRoute ?? ''),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (tabBar != null) tabBar,
                      Expanded(child: content),
                    ],
                  ),
                ),
              ],
            )
          : useNavbar
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppNavbar(activeRoute: tabsState.activeRoute ?? ''),
                    if (tabBar != null) tabBar,
                    Expanded(child: content),
                  ],
                )
              : content,
          ),
        ],
      ),
    );
  }
}

/// شريط التبويبات المفتوحة — نفس فكرة تبويبات المتصفح: نقرة تُنشِّط، زر ×
/// يُغلق. هذا هو "التصغير/الإخفاء" الذي طُلب: إغلاق تبويب لا يخسر باقي
/// التبويبات المفتوحة، وإعادة فتح نفس الشاشة لاحقاً يفتح تبويباً جديداً
/// نظيفاً (وليس استرجاعاً لحالة قديمة، بعكس التبديل بين تبويبات موجودة).
class _TabBar extends ConsumerWidget {
  const _TabBar({required this.tabsState});
  final TabsState tabsState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = Theme.of(context).colorScheme.primary;
    return Container(
      height: 40,
      color: AppColors.paper,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: tabsState.tabs.map((tab) {
            final active = tab.route == tabsState.activeRoute;
            return Padding(
              padding: const EdgeInsetsDirectional.only(end: 4),
              child: Material(
                color: active ? AppColors.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: () => ref.read(openTabsProvider.notifier).activate(tab.route),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: active ? color : Colors.transparent),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(tab.icon, size: 16, color: active ? color : AppColors.textSecondary),
                        const SizedBox(width: 6),
                        Text(
                          tab.title,
                          style: AppTextStyles.caption(color: active ? color : AppColors.textSecondary)
                              .copyWith(fontWeight: active ? FontWeight.w600 : FontWeight.w400),
                        ),
                        const SizedBox(width: 6),
                        IconAction(
                          icon: Icons.close,
                          iconSize: 16,
                          dense: true,
                          tooltip: 'إغلاق تبويب ${tab.title}',
                          onPressed: () => ref.read(openTabsProvider.notifier).close(tab.route),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
