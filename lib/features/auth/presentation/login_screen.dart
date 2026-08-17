import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_client.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/branding_provider.dart';

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
      ref.invalidate(brandingProvider);
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
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.hub_outlined, color: Colors.white),
            ),
          ),
          const SizedBox(height: 20),
          Text('تسجيل الدخول', style: AppTextStyles.displayLg()),
          const SizedBox(height: 4),
          Text('نظام Kinetic Enterprise لإدارة الموارد', style: AppTextStyles.bodyMd()),
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
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
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
        ],
      ),
    );

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: isDesktop
            ? Row(
                children: [
                  // اللوحة اليسرى للهوية البصرية - جزء من العلامة التجارية
                  // القابلة للتخصيص، وليست تدرجاً بنفسجياً جاهزاً.
                  Expanded(
                    child: Container(
                      color: Theme.of(context).colorScheme.primary,
                      alignment: Alignment.center,
                      child: Padding(
                        padding: const EdgeInsets.all(48),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.hub_outlined, color: Colors.white, size: 48),
                            const SizedBox(height: 20),
                            Text(
                              'إدارة موحّدة لكل فروعك\nمن لوحة تحكم واحدة',
                              textAlign: TextAlign.center,
                              style: AppTextStyles.headlineLg(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
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
            const SizedBox(height: 14),
            const _Step(
              icon: Icons.admin_panel_settings_outlined,
              title: 'إن كنت المدير العام',
              body: 'راجع مزوّد النظام (الدعم الفني) — لديه صلاحية إعادة التعيين '
                  'على مستوى السيرفر. بيانات التواصل داخل النظام في «النظام ← الدعم الفني».',
            ),
            const SizedBox(height: 14),
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
