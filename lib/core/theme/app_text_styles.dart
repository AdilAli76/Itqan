import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// درجات الطباعة — IBM Plex Sans Arabic، مطابقة لمواصفات DESIGN.md
/// الفرق بين الأصل والنسخة الحالية: أرقام العملة تستخدم أرقام جدولية
/// (Tabular Figures) دائماً لضمان محاذاة الأعمدة في الجداول المالية.
class AppTextStyles {
  static TextStyle _base({
    required double size,
    required FontWeight weight,
    double? height,
    // لم تعد قيمة افتراضية ثابتة: AppColors.textPrimary صار getter يتبع
    // سطوع السمة، وقيم المعاملات الافتراضية في Dart يجب أن تكون ثوابت.
    // null هنا تعني «اللون الأساسي أياً كان في السمة الحالية».
    Color? color,
    double letterSpacing = 0,
  }) {
    return GoogleFonts.ibmPlexSansArabic(
      fontSize: size,
      fontWeight: weight,
      height: height,
      color: color ?? AppColors.textPrimary,
      letterSpacing: letterSpacing,
    );
  }

  static TextStyle displayLg({Color? color}) =>
      _base(size: 32, weight: FontWeight.w700, height: 1.25, color: color ?? AppColors.textPrimary);

  static TextStyle headlineLg({Color? color}) =>
      _base(size: 24, weight: FontWeight.w600, height: 1.3, color: color ?? AppColors.textPrimary);

  static TextStyle headlineMd({Color? color}) =>
      _base(size: 20, weight: FontWeight.w600, height: 1.3, color: color ?? AppColors.textPrimary);

  static TextStyle headlineSm({Color? color}) =>
      _base(size: 18, weight: FontWeight.w600, height: 1.3, color: color ?? AppColors.textPrimary);

  static TextStyle bodyLg({Color? color}) =>
      _base(size: 16, weight: FontWeight.w400, height: 1.5, color: color ?? AppColors.textPrimary);

  static TextStyle bodyMd({Color? color}) =>
      _base(size: 14, weight: FontWeight.w400, height: 1.45, color: color ?? AppColors.textSecondary);

  static TextStyle bodySm({Color? color}) =>
      _base(size: 13, weight: FontWeight.w400, height: 1.4, color: color ?? AppColors.textSecondary);

  static TextStyle labelMd({Color? color}) =>
      _base(size: 13, weight: FontWeight.w500, height: 1.3, color: color ?? AppColors.textSecondary);

  /// أصغر درجة في السلّم — للنصوص المساعدة: تسميات التبويبات، التواريخ
  /// الثانوية، النصوص التوضيحية تحت الحقول، وتلميحات الرسوم البيانية.
  ///
  /// أُضيفت لأن غيابها كان يُنتج النمط نفسه في سبعة مواضع مختلفة:
  /// `AppTextStyles.bodyMd(...).copyWith(fontSize: 12)`. حين يلتفّ سبعة
  /// مواضع حول السلّم بالطريقة نفسها فالنقص في السلّم لا في المواضع —
  /// وتركها كما هي يعني أن الثامن سيخترع 11 أو 13 بدل 12.
  ///
  /// 12 نقطة هو الحدّ الأدنى المقروء المعتمد في هذا النظام؛ لا تُضاف درجة
  /// أصغر منه (راجع قاعدة AC-02 في مدقّق الوصولية).
  static TextStyle caption({Color? color}) =>
      _base(size: 12, weight: FontWeight.w400, height: 1.35, color: color ?? AppColors.textSecondary);

  /// عرض العملة (د.ل) — يستخدم أرقام جدولية لمحاذاة الجداول المالية.
  static TextStyle currency({Color? color, double size = 15}) => _base(
        size: size,
        weight: FontWeight.w700,
        color: color ?? AppColors.textPrimary,
      ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
}
