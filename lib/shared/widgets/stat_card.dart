import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import 'animations.dart';

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.trend,
    this.isPositiveTrend = true,
    this.accentColor,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final String? trend;
  final bool isPositiveTrend;
  final Color? accentColor;

  /// بطاقة قابلة للنقر (تفتح الشاشة التفصيلية). حين تكون null تبقى البطاقة
  /// عرضاً فقط ولا يظهر مؤشّر النقر — فلا تَعِد بتفاعل غير موجود.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? Theme.of(context).colorScheme.primary;

    // بلا هذا الوسم يقرأ قارئ الشاشة البطاقة ثلاث عُقَد مبعثرة: «1,250»
    // ثم «إجمالي المبيعات» ثم «+12%» — أرقام بلا سياق بترتيب مقلوب عن
    // المعنى. الوسم يدمجها في جملة واحدة مفهومة، ويُخفي الأصل حتى لا
    // تُنطق مرّتين.
    final semanticLabel = [
      label,
      value,
      if (trend != null) '${isPositiveTrend ? 'ارتفاع' : 'انخفاض'} $trend',
    ].join('، ');

    return Semantics(
      label: semanticLabel,
      button: onTap != null,
      excludeSemantics: true,
      child: HoverLift(
      onTap: onTap,
      child: Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const Spacer(),
              if (trend != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isPositiveTrend ? AppColors.successBg : AppColors.dangerBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    trend!,
                    style: AppTextStyles.labelMd(
                      color: isPositiveTrend ? AppColors.success : AppColors.danger,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(value, style: AppTextStyles.displayLg()),
          const SizedBox(height: 4),
              Text(label, style: AppTextStyles.bodyMd()),
            ],
          ),
        ),
      ),
    );
  }
}
