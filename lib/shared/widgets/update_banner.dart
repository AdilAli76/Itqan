import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/update/update_checker.dart';

/// شريط «تحديث متاح» أعلى التطبيق.
///
/// نسخة مثبَّتة على جهاز لا تعرف أن أحدث منها صدر، فتبقى أجهزة العملاء على
/// نسخ قديمة شهوراً. وأول ما يكسر ذلك هو تغيّر عقد الـAPI: الخادم يردّ
/// بشكل جديد وتطبيق قديم لا يفهمه، فتظهر أعطال لا يربطها أحد بقِدَم النسخة.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(appUpdateProvider).valueOrNull;
    if (info == null || !info.available) return const SizedBox.shrink();

    // الإلزامي بلون تحذير لا معلومة: يُستعمل حين يتغيّر عقد الـAPI بحيث
    // تصير النسخة القديمة عاطلة فعلاً لا متأخّرة فحسب.
    final color = info.mandatory ? AppColors.danger : AppColors.info;

    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(info.mandatory ? Icons.priority_high : Icons.system_update_outlined,
              size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              info.mandatory
                  ? 'تحديث إلزامي: النسخة ${info.latest} مطلوبة للاستمرار (المثبَّتة ${info.current}).'
                  : 'تحديث متاح: النسخة ${info.latest} (المثبَّتة ${info.current}).'
                      '${info.notes != null ? ' — ${info.notes}' : ''}',
              style: AppTextStyles.bodyMd(color: color),
            ),
          ),
          if (info.downloadUrl != null && info.downloadUrl!.isNotEmpty)
            TextButton(
              onPressed: () => launchUrl(
                Uri.parse(info.downloadUrl!),
                mode: LaunchMode.externalApplication,
              ),
              child: const Text('تنزيل'),
            ),
        ],
      ),
    );
  }
}
