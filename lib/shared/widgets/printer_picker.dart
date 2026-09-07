import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/printing/printer_profile_provider.dart';
import '../../core/printing/printer_profiles.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// اختيار تعريف الطابعة قبل طباعةٍ حرارية.
///
/// <para><b>سبب وجوده حواراً لا شاشة إعدادات:</b> الطابعة تُختار مرّةً على
/// الجهاز ثم لا تُمسّ. ودفنُها في شاشة إعدادات مقصورة على المديرين كان يعني
/// أن الكاشير — وهو من يقف أمام الطابعة — لا يستطيع تصحيح تعريفها حين تخرج
/// الطباعة مقصوصة. ويُعرَض مرّةً ثم يُحفظ الاختيار للجهاز.</para>
///
/// <para>ويُقال في الحوار ما لا يُعرف إلا بالتجربة: أن ٥٨ ملم لا تتّسع
/// لباركودٍ خطّيٍّ تقرؤه كاميرا هاتف، وأن QR يُطبع معه عندها.</para>
class PrinterPickerDialog extends ConsumerWidget {
  const PrinterPickerDialog({super.key, required this.codeLength});

  /// طول الرمز المراد طبعه — منه يُحسب هل يتّسع الباركود.
  final int codeLength;

  /// يعرض الحوار ويعيد التعريف المختار، أو null إن تراجع.
  static Future<PrinterProfile?> show(BuildContext context, {required int codeLength}) =>
      showDialog<PrinterProfile>(
        context: context,
        builder: (_) => PrinterPickerDialog(codeLength: codeLength),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedPrinterProfileProvider);

    return AlertDialog(
      title: const Text('الطابعة'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'يُحفظ الاختيار لهذا الجهاز وحده — فرعٌ بطابعة أخرى لا يتأثّر.',
              style: AppTextStyles.caption(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            // RadioGroup لا groupValue على كل عنصر: الأخير مهجور منذ 3.32،
            // والمجموعة تُدار من الجدّ — كما في شاشة الإعدادات.
            RadioGroup<String>(
              groupValue: selected.id,
              onChanged: (id) => id == null
                  ? null
                  : ref
                      .read(selectedPrinterProfileProvider.notifier)
                      .select(PrinterProfiles.byId(id)),
              child: Column(
                children: [
                  for (final profile in PrinterProfiles.all) _tile(profile),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('تراجع')),
        FilledButton(
          onPressed: () => Navigator.pop(context, ref.read(selectedPrinterProfileProvider)),
          child: const Text('اطبع'),
        ),
      ],
    );
  }

  Widget _tile(PrinterProfile profile) {
    final layout = profile.code128Layout(codeLength);

    return RadioListTile<String>(
      value: profile.id,
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(profile.label, style: AppTextStyles.bodyMd()),
      subtitle: Text(
        // العرض المطبوع لا عرض الورق: هو الفرق الذي يقصّ الباركود، ويُقال
        // صراحةً لأن أحداً لا يعرفه عن طابعته.
        'يطبع على ${profile.printableWidthMm.toStringAsFixed(0)} من '
        '${profile.paperWidthMm.toStringAsFixed(0)} ملم'
        '${layout.cameraReadable ? '' : ' — الباركود ضيّق على كاميرا الهاتف، فيُطبع QR معه'}',
        style: AppTextStyles.caption(
          color: layout.cameraReadable ? AppColors.textSecondary : AppColors.warning,
        ),
      ),
    );
  }
}
