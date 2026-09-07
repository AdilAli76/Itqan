import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import 'passkeys_section.dart';

/// تغيير المستخدم كلمة مروره هو.
///
/// <para><b>الفجوة التي تسدّها:</b> لم تكن في النظام كلّه شاشةٌ لهذا. ما
/// كان موجوداً «أعِد تعيين كلمة مرور <b>شخصٍ آخر</b>»: مالك المنصّة على
/// مديري عملائه، ومدير المنظمة على موظّفيه — والكلمة في الحالتين يعرفها
/// من أعادها. فحسابٌ أُعيدت كلمته يعرف كلمتَه اثنان إلى الأبد.</para>
///
/// <para><b>وتُفتح إجباراً أوّل دخولٍ بكلمة مؤقّتة</b> ([forced])، فلا زرّ
/// رجوع ولا تخطٍّ. والخادم يرفض كل شيء آخر حتى تُغيَّر — راجع
/// `MustChangePasswordFilter`: شاشةٌ تُلحّ وحدها تُتجاوَز بفتح مسارٍ آخر.
/// </para>
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key, this.forced = false});

  /// أدخلها المستخدم مُجبَراً بعد كلمةٍ مؤقّتة؟
  final bool forced;

  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // التطابق يُفحَص هنا لا على الخادم: خطأٌ مطبعيّ في التأكيد يجب أن
    // يُقال فوراً لا بعد رحلةٍ إلى الخادم — والخادم لا يرى الحقلين أصلاً.
    if (_next.text != _confirm.text) {
      setState(() => _error = 'الكلمة الجديدة وتأكيدها غير متطابقين');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ApiClient.instance.dio.post('/auth/change-password', data: {
        'currentPassword': _current.text,
        'newPassword': _next.text,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تغيّرت كلمة المرور')),
      );
      // إلى التطبيق لا رجوعاً: من دخل مُجبَراً لا شاشة خلفه يعود إليها،
      // ومن دخل طوعاً كانت شاشته وراءه فتُعاد بناؤها بلا حالةٍ عالقة.
      context.go('/app');
    } on DioException catch (e) {
      if (!mounted) return;
      final data = e.response?.data;
      setState(() {
        _saving = false;
        _error = (data is Map && data['message'] is String)
            ? data['message'] as String
            : 'تعذّر تغيير كلمة المرور — ردّ الخادم بالحالة ${e.response?.statusCode}.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final form = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.forced ? 'غيّر كلمة المرور المؤقّتة' : 'تغيير كلمة المرور',
            style: AppTextStyles.headlineMd(),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          if (widget.forced)
            Text(
              'كلمتك الحالية مؤقّتة سلّمها لك مشغّل النظام — يعرفها هو أيضاً. '
              'اختر كلمةً لا يعرفها غيرك لتستعمل النظام.',
              style: AppTextStyles.bodyMd(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: 20),
          TextField(
            controller: _current,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'كلمة المرور الحالية'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _next,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'الكلمة الجديدة'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirm,
            obscureText: true,
            onSubmitted: (_) => _saving ? null : _submit(),
            decoration: const InputDecoration(labelText: 'تأكيد الكلمة الجديدة'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: AppTextStyles.bodyMd(color: AppColors.danger),
                textAlign: TextAlign.center),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('احفظ'),
          ),
          // ولا زرّ «لاحقاً» في الحالة الإجبارية: الخادم يرفض كل شيء آخر،
          // فزرٌّ يُخرج المستخدم إلى نظامٍ يردّ كل طلب بـ403 يُحوّل قفلاً
          // مفهوماً إلى عطبٍ غامض.
          if (!widget.forced) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _saving ? null : () => context.go('/app'),
              child: const Text('إلغاء'),
            ),
          ],
          // ولا تُعرض المفاتيح في الحالة الإجبارية: من دخل بكلمةٍ مؤقّتة
          // يجب أن يخرج من هنا بكلمةٍ جديدة لا بمفتاحٍ يعلّق الكلمة المؤقّتة
          // على جهازه — والخادم يرفض كل شيء آخر حتى تُغيَّر أصلاً.
          if (!widget.forced) const PasskeysSection(),
        ],
      ),
    );

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(Breakpoints.isDesktop(context) ? 32 : 20),
            child: form,
          ),
        ),
      ),
    );
  }
}
