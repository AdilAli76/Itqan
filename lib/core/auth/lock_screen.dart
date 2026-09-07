import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_client.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'current_user.dart';
import 'passkey.dart';
import 'session_lock.dart';

/// غطاء القفل فوق التطبيق كلّه.
///
/// <para><b>سبب وجوده غطاءً لا شاشةً في المسار:</b> القفل يجب ألّا يمسّ ما
/// تحته. شاشةٌ يُذهب إليها تعني تفكيك شجرة التبويبات المفتوحة، فتضيع فاتورةٌ
/// نصف مكتوبة عند كل قيامٍ عن المكتب — وقفلٌ يُضيّع العمل لا يُستعمل.</para>
///
/// <para><b>ويمنع اللمس والاختصارات معاً:</b> [AbsorbPointer] يبتلع النقر،
/// و[FocusScope] المعزول يمنع أن يبقى فوكس لوحة المفاتيح في حقلٍ تحته —
/// فغطاءٌ يُكتب من خلفه في فاتورة ليس قفلاً.</para>
class SessionLockGate extends ConsumerWidget {
  const SessionLockGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locked = ref.watch(sessionLockProvider);

    return Stack(
      children: [
        // مستبعدٌ من شجرة الفوكس وهو مقفول: بلا هذا يبقى المؤشّر في حقلٍ
        // تحت الغطاء فتذهب إليه الكتابة.
        ExcludeFocus(excluding: locked, child: AbsorbPointer(absorbing: locked, child: child)),
        if (locked) const Positioned.fill(child: _LockOverlay()),
      ],
    );
  }
}

class _LockOverlay extends ConsumerStatefulWidget {
  const _LockOverlay();

  @override
  ConsumerState<_LockOverlay> createState() => _LockOverlayState();
}

class _LockOverlayState extends ConsumerState<_LockOverlay> {
  final _password = TextEditingController();
  String? _userName;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    readCurrentUserName().then((name) {
      if (mounted) setState(() => _userName = name);
    });

    // ومحاولةٌ تلقائية بالمفتاح عند القفل: من سجّل مفتاحاً لا يريد أن يضغط
    // زرّاً ثم يضع إصبعه — يضع إصبعه وحسب. وإلغاؤها يترك حقل كلمة المرور
    // كما هو، فلا يُحشر أحد في طريقٍ واحد.
    if (Passkeys.isSupported) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _unlockWithPasskey(silent: true));
    }
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.paper,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.lock_outline, size: 48, color: AppColors.textMuted),
                const SizedBox(height: 16),
                Text('الشاشة مقفلة',
                    textAlign: TextAlign.center, style: AppTextStyles.headlineMd()),
                const SizedBox(height: 4),
                Text(
                  // الاسم يُعرض: من يجد شاشةً مقفلة يجب أن يعرف على حساب
                  // من هي قبل أن يحاول فتحها بكلمة مروره هو.
                  _userName ?? 'الجلسة مستمرّة — العمل المفتوح كما هو',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMd(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 24),
                if (Passkeys.isSupported) ...[
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _unlockWithPasskey(),
                    icon: const Icon(Icons.fingerprint, size: 20),
                    label: const Text('افتح بمفتاح المرور'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text('أو',
                            style: AppTextStyles.caption(color: AppColors.textMuted)),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _password,
                  obscureText: true,
                  autofocus: !Passkeys.isSupported,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'كلمة المرور',
                    prefixIcon: Icon(Icons.password_outlined),
                  ),
                  onSubmitted: (_) => _unlockWithPassword(),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _busy ? null : _unlockWithPassword,
                  child: const Text('افتح'),
                ),
                if (_busy) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyMd(color: AppColors.danger)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// <summary>
  /// فتحٌ بالمفتاح. و[silent] للمحاولة التلقائية عند القفل: من ألغى نافذة
  /// المفتاح لا يُواجَه برسالة خطأ حمراء لم يطلبها — الحقل تحتها جاهز.
  /// </summary>
  Future<void> _unlockWithPasskey({bool silent = false}) async {
    setState(() {
      _busy = true;
      if (!silent) _error = null;
    });

    try {
      final begin = await ApiClient.instance.dio.post('/passkeys/unlock/begin');
      final options = Map<String, dynamic>.from(begin.data as Map);
      final assertion = await Passkeys.unlock(options);
      await ApiClient.instance.dio.post('/passkeys/unlock/complete', data: assertion);

      if (mounted) ref.read(sessionLockProvider.notifier).unlock();
    } catch (e) {
      if (mounted && !silent) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unlockWithPassword() async {
    if (_password.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ApiClient.instance.dio
          .post('/auth/verify-password', data: {'password': _password.text});
      if (mounted) {
        _password.clear();
        ref.read(sessionLockProvider.notifier).unlock();
      }
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _message(Object error) {
    if (error is PasskeyException) return error.message;
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['message'] is String) return data['message'] as String;
    }
    return 'تعذّر الفتح — حاول مرّة أخرى';
  }
}
