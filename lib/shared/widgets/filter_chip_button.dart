import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// شريحة فلترة موحّدة لكل شاشات القوائم.
///
/// كانت مكرَّرة حرفياً (بنفس البصمة) في خمسة ملفات: الإشعارات، المشتريات،
/// الجرد، التحويلات، بطاقات العملاء. توحيدها هنا يعني أن أي إصلاح — مثل
/// ارتفاع اللمس أدناه — يسري على الشاشات الخمس مرة واحدة بدل خمس.
///
/// الارتفاع الأدنى 44 نقطة: كان 39 (حشو 10 + سطر نص)، وهو أقل من أصغر هدف
/// لمس توصي به إرشادات Material و Apple. الفرق أربع نقاط لا يُرى بالعين
/// لكنه محسوس بالإصبع على شاشة كاشير.
class FilterChipButton extends StatelessWidget {
  const FilterChipButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// أصغر هدف لمس مقبول — مشتركة ليقيس عليها بقية النظام.
  static const double minTouchHeight = 44;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: const BoxConstraints(minHeight: minTouchHeight),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? color : AppColors.border),
        ),
        child: Text(
          label,
          style: AppTextStyles.labelMd(color: selected ? color : AppColors.textSecondary)
              .copyWith(fontWeight: selected ? FontWeight.w600 : FontWeight.w500),
        ),
      ),
    );
  }
}
