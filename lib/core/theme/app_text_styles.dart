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
    Color color = AppColors.textPrimary,
    double letterSpacing = 0,
  }) {
    return GoogleFonts.ibmPlexSansArabic(
      fontSize: size,
      fontWeight: weight,
      height: height,
      color: color,
      letterSpacing: letterSpacing,
    );
  }

  static TextStyle displayLg({Color? color}) =>
      _base(size: 32, weight: FontWeight.w700, height: 1.25, color: color ?? AppColors.textPrimary);

  static TextStyle headlineLg({Color? color}) =>
      _base(size: 24, weight: FontWeight.w600, height: 1.3, color: color ?? AppColors.textPrimary);

  static TextStyle headlineMd({Color? color}) =>
      _base(size: 20, weight: FontWeight.w600, height: 1.3, color: color ?? AppColors.textPrimary);

  static TextStyle bodyLg({Color? color}) =>
      _base(size: 16, weight: FontWeight.w400, height: 1.5, color: color ?? AppColors.textPrimary);

  static TextStyle bodyMd({Color? color}) =>
      _base(size: 14, weight: FontWeight.w400, height: 1.45, color: color ?? AppColors.textSecondary);

  static TextStyle labelMd({Color? color}) =>
      _base(size: 13, weight: FontWeight.w500, height: 1.3, color: color ?? AppColors.textSecondary);

  /// عرض العملة (د.ل) — يستخدم أرقام جدولية لمحاذاة الجداول المالية.
  static TextStyle currency({Color? color, double size = 15}) => _base(
        size: size,
        weight: FontWeight.w700,
        color: color ?? AppColors.textPrimary,
      ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
}
