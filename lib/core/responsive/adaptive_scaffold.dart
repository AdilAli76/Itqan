import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/current_user.dart';
import '../shell/open_tabs_provider.dart';
import '../shell/shell_scope.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/branding_provider.dart';
import 'breakpoints.dart';
import '../../shared/widgets/app_navbar.dart';
import '../../shared/widgets/app_sidebar.dart';
import '../../shared/widgets/animations.dart';
import '../network/realtime_listener.dart';
import '../../shared/widgets/icon_action.dart';
import '../theme/theme_mode_provider.dart';

const _roleLabels = {
  'super_admin': 'مدير عام',
  'branch_manager': 'مدير فرع',
  'cashier': 'كاشير',
  'inventory_officer': 'مسؤول مخزون',
  'accountant': 'محاسب',
  'custom': 'دور مخصّص',
};

/// غلاف كل شاشة في النظام. عندما تُفتَح داخل AppShell (نظام النوافذ/
/// التبويبات — الحالة الطبيعية دائماً بعد تسجيل الدخول) يكتفي برسم عنوان
/// الشاشة ومحتواها فقط، فـ AppShell يرسم الـ Scaffold والشريط الجانبي/
/// العلوي وشريط التبويبات مرة واحدة لكل الشاشات معاً. خارج AppShell (شبكة
/// أمان نظرية فقط) يرسم نفسه بشكل مستقل كما كانت الحال قبل AppShell.
///
/// شارة الدور وزر تسجيل الخروج (كانا شريطاً منفصلاً 48px شبه فارغ في
/// AppShell._TopBar سابقاً) أصبحا الآن جزءاً من نفس شريط العنوان — يزيلان
/// شريطاً كاملاً من الفراغ بدل إضافة شريط جديد.
class AdaptiveScaffold extends ConsumerWidget {
  const AdaptiveScaffold({
    super.key,
    required this.title,
    required this.body,
    this.activeRoute = '',
    this.actions,
    this.floatingActionButton,
    this.scrollable = true,
  });

  final String title;
  final Widget body;
  final String activeRoute;
  final List<Widget>? actions;
  final Widget? floatingActionButton;

  /// هل تُلفّ الشاشة بمُمرِّر على الجوّال.
  ///
  /// <para><b>ولماذا يلزم إطفاؤه أحياناً:</b> المُمرِّر يعطي ارتفاعاً غير
  /// محدود، وشاشةٌ تبني تخطيطها على الارتفاع المتاح (تبويبات، قائمة تملأ ما
  /// بقي) تفيض عنده. وقع في شاشة المحاسبة: TabBarView داخل Expanded داخل
  /// مُمرِّر — تعمل على سطح المكتب وتفيض على الهاتف.</para>
  ///
  /// <para>واطفاؤه لا يُلغي التمرير بل ينقله إلى داخل الشاشة، حيث تعرف كل
  /// قائمة ما تمرّره.</para>
  final bool scrollable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDesktop = Breakpoints.isDesktop(context);
    final insideShell = ShellScope.isActive(context);

    // الشريط يُرسَم على كل المقاسات عمداً (راجع تعليق insideShell أدناه)،
    // فيجب أن يضيق لا أن يفيض. عنوان مثل «إدارة المخزون والموردين» مع زرَّي
    // إجراء يتجاوز عرض الهاتف بنحو سبعين بكسل — وهو ما كان يكسر التخطيط.
    //
    // ترتيب التنازل مقصود: العنوان يتقلّص أولاً لأنه معروف من التبويب
    // النشط ومن محتوى الشاشة، ثم تتمرّر الأزرار أفقياً إن ضاق العرض أكثر —
    // فلا يختفي زر إجراء أبداً، وهو الشرط الذي بُني عليه هذا الشريط أصلاً.
    final header = Container(
      height: 64,
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 24 : 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              title,
              style: Theme.of(context).textTheme.headlineMedium,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          const SizedBox(width: 12),
          // يظهر فقط عند انقطاع الاتصال اللحظي أو إعادته — ملاصقاً للعنوان
          // لا في طرف الشريط، لأنه تحذير عن صحّة البيانات المعروضة نفسها.
          const RealtimeIndicator(),
          const OfflineQueueIndicator(),
          const Spacer(),
          if (actions != null)
            Flexible(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                // reverse: يبدأ التمرير من نهاية الصف، أي أن آخر زر —
                // وهو الإجراء الأساسي دائماً («إضافة صنف») — يبقى ظاهراً
                // بلا تمرير، ويُخفى الثانوي أولاً.
                reverse: true,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: actions!.reversed.toList(),
                ),
              ),
            ),
          if (insideShell && isDesktop) ...[
            if (actions != null && actions!.isNotEmpty) ...[
              const SizedBox(width: 16),
              SizedBox(height: 24, child: VerticalDivider(width: 1, color: AppColors.border)),
              const SizedBox(width: 16),
            ] else
              const SizedBox(width: 16),
            const _ThemeToggle(),
            const SizedBox(width: 8),
            const _HeaderAccountArea(),
          ],
        ],
      ),
    );

    // الشاشة التي تدير تمريرها بنفسها تُعطى الارتفاع كما هو — بلا مُمرِّر
    // ولا توسيط رأسي. راجع [scrollable].
    final content = !scrollable
        ? Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1440),
                child: body,
              ),
            ),
          )
        : Expanded(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            // يُوسِّط المحتوى القصير رأسياً بدل تركه ملتصقاً بالأعلى فوق فراغ
            // رمادي طويل (شكوى "الشريط الفارغ") — وبلا أي أثر على الشاشات
            // التي محتواها أطول من الشاشة أصلاً (الجداول تتجاوز الحد فتُمرَّر
            // عادياً من الأعلى كما كانت دائماً).
            constraints: BoxConstraints(minHeight: (constraints.maxHeight - 48).clamp(0, double.infinity)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // دخول المحتوى بظهور تدريجي — يُشغَّل مرّة واحدة عند فتح
                // التبويب لا مع كل إعادة بناء (راجع FadeSlideIn)، فلا يرمش
                // الجدول عند البحث أو التصفية.
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1440),
                  child: FadeSlideIn(child: body),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (insideShell) {
      // header يحمل أزرار actions (مثل "إضافة فاتورة"/"أمر شراء جديد") —
      // AppShell لا يعرف عنها إطلاقاً (هي خاصة بكل شاشة على حدة)، فلا بد
      // من رسمها هنا دائماً بصرف النظر عن حجم الشاشة، وإلا اختفت أزرار
      // الإجراءات كلياً على أي نافذة تُصنَّف "غير ديسكتوب" — وهذا بالضبط
      // ما كان يمنع إنشاء فاتورة شراء/بيع قبل هذا التصحيح.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [header, content],
      );
    }

    // شبكة أمان: شاشة تُفتَح خارج AppShell (لا يُفترض أن يحدث فعلياً).
    final navLayout = ref.watch(brandingProvider).valueOrNull?.navLayout ?? 'sidebar';
    final useNavbar = isDesktop && navLayout == 'navbar';
    final useSidebar = isDesktop && !useNavbar;

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: isDesktop
          ? null
          // بلا actions هنا: أزرار الإجراءات في هذا النظام أزرار بنصوص
          // كاملة («استيراد من ملف»، «إضافة صنف») لا أيقونات مجرّدة، وصفّ
          // AppBar لا يتّسع لها مع العنوان على عرض هاتف — فتفيض. تُرسَم
          // أسفله في header الذي يتقلّص ويتمرّر بدل أن ينكسر.
          : AppBar(title: Text(title, overflow: TextOverflow.ellipsis)),
      drawer: isDesktop ? null : Drawer(child: AppSidebar(activeRoute: activeRoute)),
      floatingActionButton: floatingActionButton,
      body: useSidebar
          ? Row(
              children: [
                SizedBox(
                  width: 264,
                  child: AppSidebar(activeRoute: activeRoute),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [header, content],
                  ),
                ),
              ],
            )
          : useNavbar
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppNavbar(activeRoute: activeRoute),
                    header,
                    content,
                  ],
                )
              // المسار الضيّق: الشريط العلوي يحمل العنوان والدرج، وheader
              // أسفله يحمل الإجراءات. كانت الإجراءات تُفقَد هنا كلياً لأن
              // body وحده كان يُعرض.
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (actions != null && actions!.isNotEmpty) header,
                    Expanded(
                      child: scrollable
                          ? SingleChildScrollView(
                              padding: const EdgeInsets.all(16),
                              child: body,
                            )
                          : body,
                    ),
                  ],
                ),
    );
  }
}

class _HeaderAccountArea extends ConsumerWidget {
  const _HeaderAccountArea();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: readJwtClaims(),
      builder: (context, snapshot) {
        final role = snapshot.data?['role'] as String?;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (role != null) ...[
              Text(_roleLabels[role] ?? role, style: AppTextStyles.bodyMd(color: AppColors.textSecondary)),
              const SizedBox(width: 8),
            ],
            IconButton(
              onPressed: () async {
                await performLogout(ref);
                if (context.mounted) context.go('/login');
              },
              icon: const Icon(Icons.logout, size: 20),
              tooltip: 'تسجيل الخروج',
            ),
          ],
        );
      },
    );
  }
}

/// تبديل الوضع النهاري/الليلي.
///
/// في الشريط العلوي لا في شاشة الإعدادات: الوضع الليلي يُبدَّل حين تتغيّر
/// الإضاءة حول المستخدم — عند غروب أو دخول وردية مسائية — لا حين يفتح
/// الإعدادات. دفنه في شاشة إعدادات يعني أن أحداً لن يستعمله.
class _ThemeToggle extends ConsumerWidget {
  const _ThemeToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return IconAction(
      icon: isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
      iconSize: 18,
      dense: true,
      tooltip: isDark ? 'التبديل إلى الوضع النهاري' : 'التبديل إلى الوضع الليلي',
      onPressed: () => ref.read(themeModeProvider.notifier).toggle(
            Theme.of(context).brightness,
          ),
    );
  }
}
