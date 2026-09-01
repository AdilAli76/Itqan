import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/permissions.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/app_surface.dart';
import '../data/license_providers.dart';

/// تفعيل النسخة المحلّية — بصمة الجهاز، ومفتاحٌ يُلصَق.
///
/// <para><b>الفجوة التي تسدّها:</b> التركيب المحلّي بلا إنترنت مبنيٌّ
/// بالكامل: التوقيع وربط المنظمة وبصمة الجهاز ومهلة السماح كلّها تُفرَض في
/// `LicenseVerification`. لكن إدخال المفتاح كان يتطلّب طرفيةً وأمراً على
/// سطر الأوامر — وصاحبُ محلٍّ لا يفتح PowerShell، ولا يصحّ أن يبقى تفعيل
/// منتجٍ يُباع رهنَ زيارة مهندس.</para>
///
/// <para><b>والبصمة بصمة الخادم لا الجهاز الذي يعرض الشاشة:</b> النسخة
/// المحلّية تعمل على جهاز المحلّ، وقد يُفتح التطبيق من جهازٍ ثانٍ على نفس
/// السويتش — وبصمةُ ذلك الجهاز لا تُرخِّص شيئاً. فتُقرأ من الخادم.</para>
class ActivationCard extends ConsumerStatefulWidget {
  const ActivationCard({super.key});

  @override
  ConsumerState<ActivationCard> createState() => _ActivationCardState();
}

class _ActivationCardState extends ConsumerState<ActivationCard> {
  final _key = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ApiClient.instance.dio.post('/license/activate', data: {
        'licenseKey': _key.text.trim(),
      });
      ref.invalidate(licenseActivationProvider);
      // وبطاقة الترخيص معها: الحدود والتواريخ تُحدَّث من الحمولة الموقَّعة
      // عند التفعيل، فتركُها متخلّفة يُظهر باقةً قديمة بعد ترقيةٍ دُفع ثمنها.
      ref.invalidate(licenseProvider);
      if (!mounted) return;
      _key.clear();
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فُعّل الترخيص')),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      final data = e.response?.data;
      setState(() {
        _saving = false;
        _error = (data is Map && data['message'] is String)
            ? data['message'] as String
            : 'تعذّر التفعيل — ردّ الخادم بالحالة ${e.response?.statusCode}.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(licenseActivationProvider);

    return async.when(
      // لا شيء أثناء القراءة ولا عند الخطأ: هذه بطاقةٌ **إضافية** أسفل
      // شاشة الترخيص. وهيكلُ تحميلٍ أو رسالة خطأ لها يُوحي بعطبٍ في
      // الترخيص نفسه، والترخيص فوقها معروضٌ سليماً.
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (data) {
        final fingerprint = data['machineFingerprint'] as String? ?? '';
        final enforced = data['enforced'] as bool? ?? false;
        final isValid = data['isValid'] as bool? ?? true;
        final message = data['message'] as String?;

        // تركيبٌ لا يفرض ترخيصاً (بلا مفتاح عامّ) لا يُعرض له تفعيل: زرٌّ
        // يقول «فعّل» على نسخةٍ لا تفحص شيئاً يَعِد بحمايةٍ لا وجود لها.
        if (!enforced) return const SizedBox.shrink();

        final canActivate = ref.perms.isSuperAdmin;

        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: AppSurface(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('تفعيل النسخة', style: AppTextStyles.headlineMd()),
                  const SizedBox(height: 6),
                  if (!isValid && message != null)
                    Text(message, style: AppTextStyles.bodyMd(color: AppColors.danger))
                  else
                    Text('الترخيص مفعَّل على هذا الجهاز.',
                        style: AppTextStyles.bodyMd(color: AppColors.success)),

                  const SizedBox(height: 14),
                  Text('بصمة هذا الجهاز — أرسلها لمزوّد النظام:',
                      style: AppTextStyles.bodyMd(color: AppColors.textSecondary)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        // قابلة للتحديد لا نصّاً جامداً: تُنسخ وتُلصق في
                        // رسالة. ونقلُها بالعين ثمانيةً وستّين حرفاً يُخطئ
                        // فيه من ينقله حتماً.
                        child: SelectableText(
                          fingerprint.isEmpty ? '—' : fingerprint,
                          style: AppTextStyles.bodyMd(),
                        ),
                      ),
                      IconButton(
                        tooltip: 'نسخ البصمة',
                        icon: const Icon(Icons.copy_outlined, size: 18),
                        onPressed: fingerprint.isEmpty
                            ? null
                            : () {
                                Clipboard.setData(ClipboardData(text: fingerprint));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('نُسخت البصمة')),
                                );
                              },
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),
                  if (!canActivate)
                    Text(
                      'إدخال المفتاح لمدير المنظمة — الترخيص عقد المنظمة كلّها.',
                      style: AppTextStyles.bodyMd(color: AppColors.textSecondary),
                    )
                  else ...[
                    TextField(
                      controller: _key,
                      maxLines: 3,
                      minLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'مفتاح الترخيص',
                        helperText: 'الصقه كما وصلك — بلا حذف أو إضافة',
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
                    ],
                    const SizedBox(height: 12),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: FilledButton(
                        onPressed: _saving ? null : _activate,
                        child: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('فعّل'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
