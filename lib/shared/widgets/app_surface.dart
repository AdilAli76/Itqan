import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// سطح البطاقة الموحَّد في النظام: خلفية + حدّ + نصف قطر.
///
/// يبدو مجرّد اختصار لـ Container بزخرفة، لكنه يحلّ عطلاً حقيقياً متكرّراً.
///
/// النمط الذي يحلّ محلّه:
///
/// ```dart
/// Container(
///   decoration: BoxDecoration(
///     color: AppColors.surface,
///     borderRadius: BorderRadius.circular(12),
///     border: Border.all(color: AppColors.border),
///   ),
///   child: ...  // ← أي ListTile أو SwitchListTile هنا يفقد أثر نقره
/// )
/// ```
///
/// ودجت Material (ListTile وSwitchListTile وInkWell) ترسم خلفيتها وأثر
/// نقرها على أقرب Material فوقها. حاوية ملوّنة تعترض الطريق تُخفي الأثر
/// تماماً: يضغط المستخدم فلا يرى شيئاً، فيظنّ الزر معطّلاً ويضغط ثانيةً.
/// وFlutter يؤكّد على هذا صراحةً في وضع التطوير — وهو ما كان يُفشل ثلاثين
/// اختباراً في ui_audit_test.
///
/// [Material] يوفّر اللون والحدّ ونصف القطر عبر [shape] فيؤدي الدور نفسه
/// بلا اعتراض. جعلُه ودجتاً مشتركاً يمنع عودة العطل مع أول بطاقة جديدة.
class AppSurface extends StatelessWidget {
  const AppSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 12,
    this.color,
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// يُترك null ليتبع السطح لون السمة الحالية — وهو ما يجعل البطاقة تعمل
  /// في الوضعين النهاري والليلي بلا تعديل.
  final Color? color;

  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final surface = Material(
      color: color ?? AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: AppColors.border),
      ),
      // clipBehavior يقصّ أثر النقر عند الحواف المستديرة؛ بدونه يمتدّ
      // التموّج خارج الزوايا فيبدو مربّعاً داخل بطاقة مستديرة.
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    );

    if (margin == null) return surface;
    return Padding(padding: margin!, child: surface);
  }
}
