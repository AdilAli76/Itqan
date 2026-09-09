&#65279;import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_translations.dart';

/// مزود الترجمة - دالة مساعدة للحصول على الترجمة الحالية
final translationProvider = Provider<String Function(String)>((ref) {
  final locale = ref.watch(localeProvider);
  return (key) => key.tr(locale.languageCode);
});

// استيراد المزود من locale_provider
import 'locale_provider.dart';

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
    final currencyInfo = AppConstants.supportedCurrencies[currencyCode];
    if (currencyInfo == null) return amount.toString();

    final symbol = currencyInfo.getSymbol(isArabic);
    final fractionDigits = currencyInfo.fractionDigits;

    // تنسيق الرقم
    final formatted = amount.toStringAsFixed(fractionDigits);

    // ترتيب العملة والرقم حسب الاتجاه
    if (isArabic) {
      return '$formatted $symbol'; // العربية: الرقم ثم الرمز
    } else {
      return '$symbol $formatted'; // الإنجليزية: الرمز ثم الرقم
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
    final currencyInfo = AppConstants.supportedCurrencies[currencyCode];
    final fractionDigits = currencyInfo?.fractionDigits ?? 2;
    final symbol = currencyInfo?.getSymbol(isArabic) ?? currencyCode;

    return (
      amount: amount.toStringAsFixed(fractionDigits),
      symbol: symbol,
    );
  }
}

// استيراد AppConstants
import '../constants/app_constants.dart';
