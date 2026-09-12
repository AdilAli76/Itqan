import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// بطاقة إحصائية احترافية - قابلة لإعادة الاستخدام
/// Professional stats card widget for KPI display
class StatsCard extends StatelessWidget {
  /// عنوان الإحصائية (مثل: "إجمالي المبيعات")
  final String title;

  /// القيمة الرئيسية (مثل: 150000)
  final dynamic value;

  /// الوحدة (مثل: "د.ع" أو "فاتورة")
  final String unit;

  /// الأيقونة المعروضة
  final IconData icon;

  /// نسبة التغيير (مثل: 25 للـ +25%)
  final double changePercent;

  /// هل التغيير موجب أم سالب
  final bool isPositive;

  /// لون الخلفية الأساسي (اختياري)
  final Color? backgroundColor;

  /// دالة عند النقر على البطاقة
  final VoidCallback? onTap;

  /// هل تظهر نسبة التغيير
  final bool showChangePercent;

  /// نص إضافي أسفل الوحدة
  final String? subtitle;

  const StatsCard({
    Key? key,
    required this.title,
    required this.value,
    this.unit = '',
    required this.icon,
    this.changePercent = 0,
    this.isPositive = true,
    this.backgroundColor,
    this.onTap,
    this.showChangePercent = true,
    this.subtitle,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final Color baseColor = backgroundColor ?? AppColors.primary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              baseColor.withValues(alpha:0.8),
              baseColor,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: baseColor.withValues(alpha:0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Background decoration
            Positioned(
              right: -20,
              top: -20,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha:0.1),
                  shape: BoxShape.circle,
                ),
              ),
            ),

            // Main content
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header: Title + Icon
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha:0.85),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha:0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          icon,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Value section
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        _formatValue(value),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (unit.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          unit,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha:0.75),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),

                  // Subtitle (optional)
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha:0.65),
                        fontSize: 12,
                      ),
                    ),
                  ],

                  // Change percentage (optional)
                  if (showChangePercent && changePercent != 0) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isPositive
                            ? AppColors.success.withValues(alpha:0.2)
                            : AppColors.error.withValues(alpha:0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isPositive
                                ? Icons.trending_up
                                : Icons.trending_down,
                            size: 14,
                            color: isPositive
                                ? AppColors.success
                                : AppColors.error,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${changePercent > 0 ? '+' : ''}${changePercent.toStringAsFixed(1)}%',
                            style: TextStyle(
                              color: isPositive
                                  ? AppColors.success
                                  : AppColors.error,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'من الشهر',
                            style: TextStyle(
                              color: isPositive
                                  ? AppColors.success.withValues(alpha:0.8)
                                  : AppColors.error.withValues(alpha:0.8),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// صيغة القيمة بشكل احترافي
  String _formatValue(dynamic value) {
    if (value is int) {
      if (value >= 1000000) {
        return '${(value / 1000000).toStringAsFixed(1)}M';
      } else if (value >= 1000) {
        return '${(value / 1000).toStringAsFixed(1)}K';
      }
      return value.toString();
    } else if (value is double) {
      return value.toStringAsFixed(1);
    }
    return value.toString();
  }
}

/// متغيرات مسبقة للحالات الشائعة
class StatsCardPresets {
  /// بطاقة للمبيعات
  static Widget sales({
    required dynamic value,
    required double changePercent,
    bool isPositive = true,
  }) {
    return StatsCard(
      title: 'إجمالي المبيعات',
      value: value,
      unit: 'د.ع',
      icon: Icons.trending_up,
      changePercent: changePercent,
      isPositive: isPositive,
      backgroundColor: AppColors.success,
    );
  }

  /// بطاقة للطلبات المعلقة
  static Widget pendingOrders({
    required dynamic value,
    required double changePercent,
  }) {
    return StatsCard(
      title: 'الطلبات المعلقة',
      value: value,
      unit: 'طلب',
      icon: Icons.schedule,
      changePercent: changePercent,
      isPositive: false,
      backgroundColor: AppColors.warning,
    );
  }

  /// بطاقة للعملاء النشطين
  static Widget activeCustomers({
    required dynamic value,
    required double changePercent,
  }) {
    return StatsCard(
      title: 'العملاء النشطين',
      value: value,
      icon: Icons.people,
      changePercent: changePercent,
      isPositive: true,
      backgroundColor: AppColors.info,
    );
  }

  /// بطاقة للمنتجات
  static Widget products({
    required dynamic value,
    required double changePercent,
  }) {
    return StatsCard(
      title: 'المنتجات',
      value: value,
      icon: Icons.shopping_bag,
      changePercent: changePercent,
      isPositive: true,
      backgroundColor: AppColors.primary,
    );
  }

  /// بطاقة للمتأخرات
  static Widget overdue({
    required dynamic value,
    required double changePercent,
  }) {
    return StatsCard(
      title: 'الفواتير المتأخرة',
      value: value,
      unit: 'فاتورة',
      icon: Icons.warning,
      changePercent: changePercent,
      isPositive: false,
      backgroundColor: AppColors.error,
    );
  }
}
