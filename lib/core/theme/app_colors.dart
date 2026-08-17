import 'package:flutter/material.dart';

/// هوية ألوان "Kinetic Ink & Amber" — لوحة مصمَّمة يدوياً، وليست ناتج
/// خوارزمية Material 3 Tonal Palette (التي تعطي شكل "تصميم الذكاء الاصطناعي"
/// النمطي بنفسجي/فيروزي المتكرر في كل التصاميم الجاهزة).
///
/// هذه القيم هي اللوحة "الافتراضية" فقط. كل منظمة (زبون) يمكنها استبدال
/// [primary] و [secondary] من لوحة الإعدادات دون المساس بألوان الحالات
/// الدلالية (نجاح/تحذير/خطر) التي تبقى ثابتة دائماً لضمان وضوح المعنى.
class AppColors {
  const AppColors({
    this.primary = const Color(0xFF0B2540),
    this.primaryDark = const Color(0xFF123554),
    this.secondary = const Color(0xFFC8952B),
    this.secondaryLight = const Color(0xFFF3E3C2),
  });

  /// يبني نسخة ألوان مخصّصة لمنظمة معيّنة بناءً على القيم المخزَّنة في
  /// جدول organizations (primary_color / secondary_color) — انظر
  /// BrandingProvider. أي قيمة hex غير صالحة تسقط تلقائياً للّون الافتراضي.
  factory AppColors.fromHex({String? primaryHex, String? secondaryHex}) {
    Color? parse(String? hex) {
      if (hex == null || hex.isEmpty) return null;
      final cleaned = hex.replaceAll('#', '');
      final value = int.tryParse('FF$cleaned', radix: 16);
      return value != null ? Color(value) : null;
    }

    const defaults = AppColors();
    return AppColors(
      primary: parse(primaryHex) ?? defaults.primary,
      secondary: parse(secondaryHex) ?? defaults.secondary,
    );
  }

  final Color primary;
  final Color primaryDark;
  final Color secondary;
  final Color secondaryLight;

  // ---- محايدة (لا تتغير مع هوية الزبون) ----
  static const Color paper = Color(0xFFF6F7F9);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceAlt = Color(0xFFF0F2F5);
  static const Color border = Color(0xFFE1E4E9);
  static const Color textPrimary = Color(0xFF1A2027);
  static const Color textSecondary = Color(0xFF5B6472);
  static const Color textMuted = Color(0xFF8A93A2);

  // ---- دلالية ثابتة (لا تتأثر بالعلامة التجارية) ----
  static const Color success = Color(0xFF1E7F4F);
  static const Color successBg = Color(0xFFE3F3EA);
  static const Color warning = Color(0xFFB9791A);
  static const Color warningBg = Color(0xFFFAEEDB);
  static const Color danger = Color(0xFFB23A2E);
  static const Color dangerBg = Color(0xFFF8E4E1);
  static const Color info = Color(0xFF2A5F82);
  static const Color infoBg = Color(0xFFE2EDF3);
}
