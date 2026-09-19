import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// ضبط عنوان الخادم — أول شاشة على الجوّال وسطح المكتب.
///
/// <para><b>العطب الذي تصلحه:</b> الويب وحده كان يشتقّ عنوانه من أصل
/// الصفحة، والأندرويد وسطح المكتب يسقطان على <c>localhost</c> — أي أن
/// الهاتف يكلّم نفسه، فلا يدخل أحد **حتى بحساب مالك المنصّة**، ولا رسالة
/// تشرح لماذا.</para>
///
/// <para><b>ولماذا شاشة لا عنوان مخبوز وقت البناء:</b> الخبز يعني نسخة APK
/// لكل عميل، وإعادة بناء عند كل تغيّر نطاق. وهو ما تجنّبه الويب صراحةً —
/// راجع ApiClient.resolvedBaseUrl. أمّا من بنى نسخةً لعميل بعينه بـ
/// `--dart-define` فتتقدّم نسختُه على أي إدخال هنا ولا تظهر هذه الشاشة.</para>
class ServerSetupScreen extends StatefulWidget {
  const ServerSetupScreen({super.key, this.onDone});

  /// يُستدعى بعد الحفظ الناجح. null = العودة بـ Navigator.
  final VoidCallback? onDone;

  @override
  State<ServerSetupScreen> createState() => _ServerSetupScreenState();
}

class _ServerSetupScreenState extends State<ServerSetupScreen> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.dns_outlined, size: 56, color: AppColors.textSecondary),
                const SizedBox(height: 20),
                Text('عنوان الخادم',
                    style: AppTextStyles.displayLg(), textAlign: TextAlign.center),
                const SizedBox(height: 10),
                Text(
                  'هذا التطبيق يعمل على خادم متجرك — لا يحمل بياناتك بنفسه. '
                  'اكتب عنوانه مرّة واحدة.',
                  style: AppTextStyles.bodyMd(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.done,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(
                    labelText: 'العنوان',
                    hintText: 'erp.droob-albayan.ly',
                    prefixIcon: Icon(Icons.link),
                  ),
                  onSubmitted: (_) => _connect(),
                ),
                const SizedBox(height: 8),
                Text(
                  'يكفي اسم النطاق. تُضاف https و/api تلقائياً. '
                  'وللتركيب المحلّي داخل المحل اكتب مثلاً: http://192.168.1.10:5000',
                  style: AppTextStyles.caption(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.dangerBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
                  ),
                ],
                const SizedBox(height: 22),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: _busy ? null : _connect,
                    child: _busy
                        ? const SizedBox(
                            width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('اتّصال'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 52,
                  child: FilledButton.tonal(
                    onPressed: _busy ? null : _useLocalDatabase,
                    child: const Text('استخدام قاعدة البيانات المحلية'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// يتحقّق من العنوان **قبل** حفظه.
  ///
  /// حفظُه بلا فحص يجعل المستخدم يمرّ إلى شاشة الدخول ثم يفشل هناك برسالة
  /// عن كلمة المرور — فيظنّ حسابه خاطئاً بينما العنوان هو الخطأ. والفشل
  /// يجب أن يُقال في مكانه.
  Future<void> _connect() async {
    final input = _controller.text.trim();
    if (input.isEmpty) {
      setState(() => _error = 'اكتب عنوان الخادم');
      return;
    }

    final url = ApiClient.normalizeServerUrl(input);
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      // نقطة نهاية مفتوحة بلا توكن — الغرض إثبات أن هناك خادم Kinetic في
      // الطرف الآخر، لا تسجيل دخول.
      final probe = Dio(BaseOptions(
        baseUrl: url,
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ));
      final response = await probe.get('/app-version');

      if (response.statusCode != 200) {
        setState(() => _error = 'الخادم ردّ بالحالة ${response.statusCode} — تأكّد من العنوان.');
        return;
      }

      await ApiClient.setServer(url);
      if (!mounted) return;
      if (widget.onDone != null) {
        widget.onDone!();
      } else {
        Navigator.of(context).pop(true);
      }
    } on DioException catch (e) {
      setState(() => _error = _diagnose(e, url));
    } catch (_) {
      setState(() => _error = 'تعذّر الاتصال بالعنوان $url');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// رسالة تقول **ما الذي يُفعَل**، لا «حدث خطأ».
  String _diagnose(DioException e, String url) {
    if (e.response?.statusCode == 404) {
      return 'وصلنا إلى $url لكنه ليس خادم Kinetic — تأكّد من العنوان.';
    }
    return switch (e.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout =>
        'انتهت المهلة. تأكّد أن الجهاز على نفس الشبكة، وأن الخادم يعمل.',
      DioExceptionType.badCertificate =>
        'شهادة الخادم غير موثوقة. للتركيب المحلّي استعمل http:// صراحةً.',
      _ => 'تعذّر الوصول إلى $url. تحقّق من الاتصال ومن كتابة العنوان.',
    };
  }

  /// استخدم قاعدة البيانات المحلية بدون فحص الاتصال بالخادم البعيد
  Future<void> _useLocalDatabase() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      // استخدم عنوان محلي مباشر — لا فحص اتصال، تفتح التطبيق فوراً
      // يمكن تشغيل الـ Backend محلياً أو عبر localhost:5000
      await ApiClient.setServer('http://localhost:5000');
      if (!mounted) return;
      if (widget.onDone != null) {
        widget.onDone!();
      } else {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() => _error = 'تعذّر تفعيل الوضع المحلي: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
