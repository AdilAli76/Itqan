import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/permissions.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/offline_queue.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/icon_action.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  /// يستدعي POST /api/auth/login على الـ .NET Backend، يحفظ توكن JWT،
  /// ثم يعيد تحميل brandingProvider حتى تُطبَّق ألوان المنظمة فور الدخول.
  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await ApiClient.instance.dio.post('/auth/login', data: {
        'emailOrUsername': _emailController.text.trim(),
        'password': _passwordController.text,
      });
      final token = response.data['token'] as String;
      await ApiClient.instance.saveToken(token);

      // لوح خلفية الفرع يُطبَّق قبل الانتقال: تطبيقه بعد بناء الشاشة يجعلها
      // تومض بالمحايد ثم تتبدّل أمام المستخدم. راجع BranchPalettes.
      AppColors.applyBranchPalette(response.data['branchPalette'] as String?);

      // كلُّ ما يخصّ المستخدم يُبطَل هنا لا العلامة وحدها: الصلاحيات
      // ودعوى مالك المنصّة تُخزَّن لعمر التطبيق، فمن دخل بحسابٍ آخر يبقى
      // على صلاحيات سابقه.
      invalidateUserScopedProviders(ref);

      // طابور البيع المؤجَّل يخصّ منظمةً بعينها: بلا إعادة تحميله هنا يبقى
      // طابور من دخل قبله معروضاً لمن دخل الآن — وهو ما كان يُظهر عدّاد
      // مزامنة لمنظمة أخرى على الجهاز نفسه.
      await ref.read(offlineQueueProvider.notifier).reloadForCurrentUser();

      if (mounted) context.go('/app');
    } catch (_) {
      setState(() => _error = 'بيانات الدخول غير صحيحة، أو تعذّر الاتصال بالسيرفر');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Breakpoints.isDesktop(context);

    final form = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Align ضروري: العمود يستخدم CrossAxisAlignment.stretch لتمديد
          // الحقول والزر، وهو يُلغي width: 56 فيتحوّل الشعار إلى شريط كحلي
          // بعرض النموذج كاملاً.
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.asset(
                'assets/branding/itqan_logo.png',
                width: 64,
                height: 64,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('تسجيل الدخول', style: AppTextStyles.displayLg()),
          const SizedBox(height: 4),
          Text('منظومة إتقان ERP لإدارة الموارد والمؤسسات', style: AppTextStyles.bodyMd()),
          const SizedBox(height: 32),
          Text('البريد الإلكتروني أو اسم المستخدم', style: AppTextStyles.labelMd()),
          const SizedBox(height: 6),
          TextField(controller: _emailController),
          const SizedBox(height: 16),
          Text('كلمة المرور', style: AppTextStyles.labelMd()),
          const SizedBox(height: 6),
          TextField(
            controller: _passwordController,
            obscureText: _obscure,
            decoration: InputDecoration(
              suffixIcon: IconAction(
                icon: _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                tooltip: _obscure ? 'إظهار كلمة المرور' : 'إخفاء كلمة المرور',
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
          ],
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loading ? null : _submit,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: _loading
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('دخول'),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const _ForgotPasswordDialog(),
              ),
              child: Text('نسيت كلمة المرور؟', style: AppTextStyles.bodyMd()),
            ),
          ),
          const Divider(height: 24),
          Center(
            child: TextButton.icon(
              onPressed: () => context.go('/my-account'),
              icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
              label: const Text('عميل؟ اعرض رصيد بطاقتك'),
            ),
          ),
          // تغيير الخادم من هنا: عنوانٌ كُتب خطأً كان سيحبس المستخدم في
          // شاشة دخول تفشل أبداً بلا مخرج إلا حذف التطبيق. ولا يظهر على
          // الويب ولا في نسخة مخبوزة لعميل بعينه.
          if (ApiClient.canChangeServer)
            Center(
              child: TextButton.icon(
                onPressed: () => context.go('/server'),
                icon: const Icon(Icons.dns_outlined, size: 16),
                label: Text('الخادم: ${_serverLabel()}',
                    style: AppTextStyles.caption()),
              ),
            ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: isDesktop
            ? Row(
                children: [
                  // اللوحة اليسرى للهوية البصرية — جزء من العلامة التجارية
                  // القابلة للتخصيص، وليست تدرجاً بنفسجياً جاهزاً.
                  const Expanded(child: _BrandPanel()),
                  Expanded(child: _scrollableCenter(form, 32)),
                ],
              )
            : _scrollableCenter(form, 24),
      ),
    );
  }

  /// يوسّط النموذج على الشاشات الطويلة ويجعله قابلاً للتمرير على القصيرة.
  /// بدون هذا كان النموذج يفيض على شاشات الهواتف، وأكثر عند ظهور لوحة
  /// المفاتيح فوق حقل كلمة المرور.
  Widget _scrollableCenter(Widget form, double padding) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: EdgeInsets.all(padding),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - padding * 2),
          child: Center(child: form),
        ),
      ),
    );
  }
}

/// لا يوجد إرسال بريد إلكتروني في النظام (لا خادم بريد مُعَد)، فأي زر
/// "إرسال رابط استعادة" كان سيبدو فعّالاً دون أن يرسل شيئاً. الاستعادة
/// إجراء إداري حقيقي: المدير العام يُعيد التعيين من شاشة المستخدمين.
class _ForgotPasswordDialog extends StatelessWidget {
  const _ForgotPasswordDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('استعادة كلمة المرور'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Step(
              icon: Icons.person_outline,
              title: 'إن كنت موظفاً',
              body: 'راجع المدير العام لمنظمتك — يعيد تعيين كلمة مرورك فوراً من '
                  '«الإدارة ← الصلاحيات والمستخدمون ← أيقونة إعادة تعيين كلمة المرور».',
            ),
            const SizedBox(height: 16),
            const _Step(
              icon: Icons.admin_panel_settings_outlined,
              title: 'إن كنت المدير العام',
              body: 'راجع مزوّد النظام (الدعم الفني) — لديه صلاحية إعادة التعيين '
                  'على مستوى السيرفر. بيانات التواصل داخل النظام في «النظام ← الدعم الفني».',
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.infoBg, borderRadius: BorderRadius.circular(8)),
              child: Text(
                'لا يرسل النظام رسائل بريد إلكتروني حالياً، فلا توجد استعادة ذاتية عبر البريد.',
                style: AppTextStyles.bodyMd(color: AppColors.info),
              ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('فهمت')),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.textSecondary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTextStyles.labelMd()),
              const SizedBox(height: 2),
              Text(body, style: AppTextStyles.bodyMd()),
            ],
          ),
        ),
      ],
    );
  }
}

/// لوحة الهوية على شاشة الدخول.
///
/// **لماذا ليست لوناً مسطّحاً:** كانت مستطيلاً بلون واحد فتبدو الشاشة نموذجاً
/// داخلياً لا منتجاً. والتدرّج بين لونَي المنظمة يعطي عمقاً **بلا شحن أي
/// صورة**: صورة ثابتة في الحزمة تناقض التخصيص (لكل عميل لونان مختلفان)،
/// وتزيد أول تحميل الذي خفّضناه للتوّ إلى الربع.
///
/// والعلامة المائية شفافة خلف النصّ — «صورة» مرسومة بالكود تتلوّن بهوية كل
/// عميل تلقائياً، فلا تحتاج ملفاً لكل واحد.
/// العنوان بلا بروتوكول ولا لاحقة — ما يقرؤه المستخدم لا ما يرسله العميل.
String _serverLabel() {
  final url = ApiClient.resolvedBaseUrl;
  if (url.isEmpty) return 'غير مضبوط';
  return url
      .replaceFirst('https://', '')
      .replaceFirst('http://', '')
      .replaceFirst(RegExp(r'/api$'), '');
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            scheme.primary,
            Color.lerp(scheme.primary, scheme.secondary, 0.55) ?? scheme.primary,
            scheme.primary,
          ],
          stops: const [0, 0.55, 1],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // تتجاوز حدود اللوحة عمداً فتُقصّ: الشكل المقصوص يوحي بامتداد خارج
          // الإطار، والمتمركز الكامل يبدو ملصقاً.
          Positioned(
            right: -60,
            bottom: -40,
            child: Icon(
              Icons.hub_outlined,
              size: 320,
              color: Colors.white.withValues(alpha: 0.07),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(48),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset(
                    'assets/branding/itqan_logo.png',
                    width: 100,
                    height: 100,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'إتقان في الحسابات..\nوسرعة في العمليات',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.headlineLg(color: Colors.white),
                ),
                const SizedBox(height: 12),
                Text(
                  'إدارة موحّدة وذكية لكل فروعك ومستودعاتك',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMd(color: Colors.white.withValues(alpha: 0.85)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
