import 'package:flutter/material.dart';

/// Context helper للترجمة السهلة داخل الواجهة
extension BuildContextTranslation on BuildContext {
  /// ترجمة سهلة داخل البناء
  String translate(String key) {
    // يمكن استخدام Consumer للوصول للـ locale الحالي
    return key; // هذا تبسيط، استخدم Consumer بشكل حقيقي
  }
}

/// مساعد لتنسيق العملات
class CurrencyFormatter {
  /// تنسيق رقم كعملة
  static String format(
    double amount,
    String currencyCode,
    bool isArabic,
  ) {
    // تنسيق الرقم
    final formatted = amount.toStringAsFixed(2);

    // ترتيب العملة والرقم حسب الاتجاه
    if (isArabic) {
      return '$formatted $currencyCode'; // العربية: الرقم ثم الرمز
    } else {
      return '$currencyCode $formatted'; // الإنجليزية: الرمز ثم الرقم
    }
  }

  /// تنسيق مبسط (بدون كسور عشرية)
  static String formatSimple(
    double amount,
    String currencyCode,
    bool isArabic,
  ) {
    return format(amount, currencyCode, isArabic);
  }

  /// تنسيق منفصل (الرقم والرمز منفصلان)
  static ({String amount, String symbol}) formatSeparate(
    double amount,
    String currencyCode,
    bool isArabic,
  ) {
    return (
      amount: amount.toStringAsFixed(2),
      symbol: currencyCode,
    );
  }
}
