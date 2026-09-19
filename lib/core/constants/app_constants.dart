import 'package:flutter/material.dart';

class AppConstants {
  /// الاسم التجاري للمنتج.
  ///
  /// «احتياطي» لأن كل منظمة تعرض اسمها هي (White-Labeling، راجع
  /// branding_provider). وهذا ما يظهر قبل تحميل هويّتها وفي شاشة الدخول.
  static const String appNameFallback = 'إتقان ERP';
  static const String appVersion = '2.0.9';
  static const Locale locale = Locale('ar');
  static const TextDirection direction = TextDirection.rtl;

  /// القيم الافتراضية فقط — تُستبدل فعلياً من إعدادات المنظمة عند الإقلاع
  /// (انظر branding_provider.dart)، حتى لا يبقى "د.ل" مثبتاً في حال
  /// بيع النظام لاحقاً لسوق خارج ليبيا.
  static const String defaultCurrencySymbol = 'د.ل';
  static const String defaultCurrencyCode = 'LYD';
}
