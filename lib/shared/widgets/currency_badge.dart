
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

  @override
  Widget build(BuildContext context) {
    final isNegative = amount < 0;
    final formatted = NumberFormat('#,##0.00', 'en').format(amount.abs());
    final color = showSign ? (isNegative ? AppColors.danger : AppColors.success) : AppColors.textPrimary;

    return Directionality(
textDirection: ui.TextDirection.ltr,
      child: Text(
        '${showSign ? (isNegative ? '- ' : '+ ') : ''}$formatted $currencySymbol',
        style: AppTextStyles.currency(color: color),
      ),
    );
  }
}
