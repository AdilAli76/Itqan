
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// عرض مبلغ مالي مع رمز العملة (افتراضياً د.ل، لكنه قابل للتمرير من إعدادات
/// المنظمة حتى لا يُثبَّت "د.ل" داخل الكود في مكان لا يمكن تغييره لاحقاً
/// لو بيع النظام لسوق آخر بعملة مختلفة).
class CurrencyBadge extends StatelessWidget {
  const CurrencyBadge({
    super.key,
    required this.amount,
    this.currencySymbol = 'د.ل',
    this.showSign = false,
  });

  final double amount;
  final String currencySymbol;
  final bool showSign;

  /// كيف يُنطق رمز العملة. «د.ل» يقرأها قارئ الشاشة حرفاً حرفاً («دال نقطة
  /// لام») فتصبح المبالغ المالية غير مفهومة تماماً سمعياً — وهي أهم رقم في
  /// النظام كله. الخريطة هنا لأشهر العملات، وأي رمز غير معروف يُنطق كما هو.
  static const _spoken = <String, String>{
    'د.ل': 'دينار ليبي',
    'ر.س': 'ريال سعودي',
    'د.إ': 'درهم إماراتي',
    'ج.م': 'جنيه مصري',
    'د.ت': 'دينار تونسي',
  };

  @override
  Widget build(BuildContext context) {
    final isNegative = amount < 0;
    final formatted = NumberFormat('#,##0.00', 'en').format(amount.abs());
    final color = showSign ? (isNegative ? AppColors.danger : AppColors.success) : AppColors.textPrimary;

    final sign = showSign ? (isNegative ? '- ' : '+ ') : '';
    final spokenSign = showSign ? (isNegative ? 'سالب ' : 'موجب ') : '';
    final spokenUnit = _spoken[currencySymbol] ?? currencySymbol;

    return Directionality(
      textDirection: ui.TextDirection.ltr,
      child: Text(
        '$sign$formatted $currencySymbol',
        style: AppTextStyles.currency(color: color),
        semanticsLabel: '$spokenSign$formatted $spokenUnit',
      ),
    );
  }
}
