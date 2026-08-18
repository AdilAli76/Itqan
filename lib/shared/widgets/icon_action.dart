import 'package:flutter/material.dart';

/// زر أيقونة مضغوط بصرياً وسليم لمسياً — بديل النمط المتكرّر في النظام:
///
/// ```dart
/// IconButton(
///   icon: const Icon(Icons.remove_circle_outline, size: 18),
///   padding: EdgeInsets.zero,
///   constraints: const BoxConstraints(),   // ← يُلغي هدف اللمس بالكامل
/// )
/// ```
///
/// ذلك النمط كان يُبطل عمداً ما يضبطه الثيم مركزياً
/// (materialTapTargetSize.padded = 48 نقطة)، فينتهي زر «إنقاص الكمية» في
/// أمر شراء بمساحة نقر 18×18 نقطة — أصغر من طرف الإصبع، فيخطئ المستخدم
/// ويحذف السطر بدل إنقاصه. المشكلة ليست جمالية: هي إدخال بيانات خاطئ.
///
/// هذا الودجت يفصل الحجمين اللذين خُلط بينهما: حجم الأيقونة المرسومة (يمكن
/// أن يكون صغيراً لأسباب تخطيطية) ومساحة النقر (لا يجوز أن تصغر). ويجعل
/// [tooltip] مطلوباً لا اختيارياً — فالزر الذي لا يمكن تسميته لا يمكن
/// لقارئ الشاشة نطقه أصلاً، ووجوب التسمية يمنع تكرار الثغرة في كل شاشة
/// جديدة بدل مطاردتها بعد وقوعها.
class IconAction extends StatelessWidget {
  const IconAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.iconSize = 20,
    this.color,
    this.dense = false,
  });

  final IconData icon;

  /// يُستخدم كتلميح للفأرة وكتسمية دلالية لقارئ الشاشة في آنٍ واحد.
  final String tooltip;

  final VoidCallback? onPressed;
  final double iconSize;
  final Color? color;

  /// داخل صفوف القوائم المزدحمة: هدف لمس 40 نقطة بدل 48 — تنازل محسوب يبقى
  /// فوق الحد الأدنى العملي، بينما 48 كانت ستكسر ارتفاع الصف.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final target = dense ? 40.0 : 48.0;
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: tooltip,
      // الأيقونة نفسها لا تُنطَق: التسمية أعلاه تكفي، وتركها يجعل قارئ
      // الشاشة يكرّر العنصر مرّتين.
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: target,
            height: target,
            child: Icon(
              icon,
              // 16 نقطة هو الحد الذي تفقد تحته الأيقونة تمييزها لا وضوحها
              // فقط — أيقونتا «حذف» و«إزالة» تصبحان بقعتين متشابهتين.
              size: iconSize < 16 ? 16 : iconSize,
              color: color ?? Theme.of(context).iconTheme.color,
            ),
          ),
        ),
      ),
    );
  }
}
