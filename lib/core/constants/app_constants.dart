import 'package:flutter/material.dart';

class AppConstants {
  static const String appNameFallback = 'Kinetic Enterprise';
  static const Locale locale = Locale('ar');
  static const TextDirection direction = TextDirection.rtl;

  /// القيم الافتراضية فقط — تُستبدل فعلياً من إعدادات المنظمة عند الإقلاع
  /// (انظر branding_provider.dart)، حتى لا يبقى "د.ل" مثبتاً في حال
  /// بيع النظام لاحقاً لسوق خارج ليبيا.
  static const String defaultCurrencySymbol = 'د.ل';
  static const String defaultCurrencyCode = 'LYD';
}
