import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// حاوية قسم موحّدة — بديل عن تسطيح الشاشة كلها في Column واحد بعناوين نصية
/// فقط (النمط القديم الذي أعطى انطباع "كل الحقول ملقاة في قائمة واحدة").
/// نفس اللغة البصرية المستخدَمة أصلاً في AppDataTable/StatCard (سطح +
/// حدود + زوايا 12) حتى لا تبدو بطاقة غريبة عن بقية النظام.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    this.icon,
    this.subtitle,
    this.trailing,
    required this.children,
  });

  final String title;
  final IconData? icon;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;

    return Container(
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
              if (icon != null) ...[
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                  child: Icon(icon, size: 18, color: color),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(child: Text(title, style: AppTextStyles.headlineMd())),
              if (trailing != null) trailing!,
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Padding(
              padding: EdgeInsets.only(right: icon != null ? 42 : 0),
              child: Text(subtitle!, style: AppTextStyles.bodyMd()),
            ),
          ],
          const Divider(height: 24),
          ...children,
        ],
      ),
    );
  }
}
