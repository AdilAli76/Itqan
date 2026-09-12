import 'package:flutter/material.dart';

/// نظام الألوان الموحد لـ Kinetic ERP
/// Color system for professional and consistent design
class AppColors {
  // ═══════════════════════════════════════════════════════════════
  // Primary Colors - الألوان الأساسية
  // ═══════════════════════════════════════════════════════════════

  /// اللون الأساسي - أخضر تيروكيز
  /// Main brand color - used for primary actions and branding
  static const Color primary = Color(0xFF2D9B92);

  /// اللون الأساسي الداكن - للعناوين والنصوص المهمة
  /// Dark primary - used for text and headers
  static const Color darkPrimary = Color(0xFF1B5D56);

  /// اللون الأساسي الفاتح - للخلفيات والأيقونات
  /// Light primary - used for backgrounds and light elements
  static const Color lightPrimary = Color(0xFF4DB8AD);

  // ═══════════════════════════════════════════════════════════════
  // Status Colors - ألوان الحالات
  // ═══════════════════════════════════════════════════════════════

  /// النجاح / المدفوع / المعتمد - أخضر
  /// Success state - approved, paid, completed
  static const Color success = Color(0xFF4CAF50);

  /// التحذير / المعلق / في الانتظار - برتقالي
  /// Warning state - pending, waiting, in progress
  static const Color warning = Color(0xFFFF9800);

  /// الخطأ / المتأخر / المرفوض - أحمر
  /// Error state - failed, overdue, rejected
  static const Color error = Color(0xFFF44336);

  /// المعلومة / الإشارة - أزرق
  /// Info state - notification, alert
  static const Color info = Color(0xFF2196F3);

  // ═══════════════════════════════════════════════════════════════
  // Background Colors - ألوان الخلفيات
  // ═══════════════════════════════════════════════════════════════

  /// خلفية الصفحة الفاتحة
  /// Light page background
  static const Color lightBackground = Color(0xFFF5F5F5);

  /// خلفية البطاقات والسطوح
  /// Card and surface background
  static const Color cardBackground = Color(0xFFFFFFFF);

  /// خلفية الصفحة الداكنة
  /// Dark page background
  static const Color darkBackground = Color(0xFF212121);

  /// خلفية فاتحة جداً (للفاصلات)
  /// Very light background (for dividers)
  static const Color veryLightBackground = Color(0xFFFAFAFA);

  // ═══════════════════════════════════════════════════════════════
  // Text Colors - ألوان النصوص
  // ═══════════════════════════════════════════════════════════════

  /// النص الأساسي الداكن
  /// Primary text color
  static const Color primaryText = Color(0xFF212121);

  /// النص الثانوي / الضعيف
  /// Secondary text color
  static const Color secondaryText = Color(0xFF757575);

  /// النص المعطل / المخفي
  /// Disabled text color
  static const Color disabledText = Color(0xFFBDBDBD);

  /// النص الأبيض (للخلفيات الداكنة)
  /// White text (for dark backgrounds)
  static const Color whiteText = Color(0xFFFFFFFF);

  // ═══════════════════════════════════════════════════════════════
  // Border Colors - ألوان الحدود
  // ═══════════════════════════════════════════════════════════════

  /// حدود خفيفة
  /// Light border color
  static const Color lightBorder = Color(0xFFE0E0E0);

  /// حدود متوسطة
  /// Medium border color
  static const Color mediumBorder = Color(0xFFBDBDBD);

  /// حدود داكنة
  /// Dark border color
  static const Color darkBorder = Color(0xFF757575);

  // ═══════════════════════════════════════════════════════════════
  // Overlay Colors - ألوان الطبقات الشفافة
  // ═══════════════════════════════════════════════════════════════

  /// طبقة شفافة داكنة (للـ modals والـ overlays)
  /// Dark overlay for modals and overlays
  static const Color darkOverlay = Color(0x80000000);

  /// طبقة شفافة فاتحة
  /// Light overlay
  static const Color lightOverlay = Color(0x80FFFFFF);

  // ═══════════════════════════════════════════════════════════════
  // Gradient Colors - ألوان الـ Gradients
  // ═══════════════════════════════════════════════════════════════

  /// gradient من الأساسي الفاتح إلى الأساسي الداكن
  static List<Color> get primaryGradient => [lightPrimary, primary];

  /// gradient للنجاح
  static List<Color> get successGradient => [
    const Color(0xFF66BB6A),
    success,
  ];

  /// gradient للتحذير
  static List<Color> get warningGradient => [
    const Color(0xFFFFB74D),
    warning,
  ];

  /// gradient للخطأ
  static List<Color> get errorGradient => [
    const Color(0xFFEF5350),
    error,
  ];

  // ═══════════════════════════════════════════════════════════════
  // Shadow Colors - ألوان الظلال
  // ═══════════════════════════════════════════════════════════════

  /// لون الظل الخفيف
  static const Color lightShadow = Color(0x1F000000);

  /// لون الظل المتوسط
  static const Color mediumShadow = Color(0x3F000000);

  /// لون الظل الداكن
  static const Color darkShadow = Color(0x5F000000);

  // ═══════════════════════════════════════════════════════════════
  // Utility Methods - دوال مساعدة
  // ═══════════════════════════════════════════════════════════════

  /// احصل على لون الحالة بناءً على نوع الحالة
  /// Get status color based on status type
  static Color getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'مدفوع':
      case 'معتمد':
      case 'نشط':
      case 'paid':
      case 'approved':
      case 'active':
        return success;

      case 'معلق':
      case 'في الانتظار':
      case 'قيد المعالجة':
      case 'pending':
      case 'waiting':
      case 'processing':
        return warning;

      case 'متأخر':
      case 'مرفوض':
      case 'ملغى':
      case 'overdue':
      case 'rejected':
      case 'cancelled':
        return error;

      default:
        return secondaryText;
    }
  }

  /// احصل على لون الأيقونة المناسب للحالة
  /// Get icon color based on status
  static Color getStatusIconColor(String status) {
    return getStatusColor(status);
  }

  /// احصل على لون الخلفية المناسب للحالة
  /// Get background color for status badge
  static Color getStatusBackgroundColor(String status) {
    final Color statusColor = getStatusColor(status);

    if (statusColor == success) {
      return const Color(0xFFC8E6C9);
    } else if (statusColor == warning) {
      return const Color(0xFFFFE0B2);
    } else if (statusColor == error) {
      return const Color(0xFFFFCDD2);
    } else {
      return lightBackground;
    }
  }

  /// احصل على gradient بناءً على نوع الحالة
  /// Get gradient based on status type
  static List<Color> getStatusGradient(String status) {
    switch (status.toLowerCase()) {
      case 'مدفوع':
      case 'معتمد':
      case 'paid':
      case 'approved':
        return successGradient;

      case 'معلق':
      case 'في الانتظار':
      case 'pending':
      case 'waiting':
        return warningGradient;

      case 'متأخر':
      case 'مرفوض':
      case 'overdue':
      case 'rejected':
        return errorGradient;

      default:
        return primaryGradient;
    }
  }
}
