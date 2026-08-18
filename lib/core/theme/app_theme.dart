import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_text_styles.dart';

/// يبني ThemeData كاملة من [AppColors] الممرَّرة، بحيث يمكن استدعاء
/// AppTheme.build(colors) بلوحة ألوان مختلفة لكل منظمة/زبون فور تحميل
/// إعدادات العلامة التجارية.
class AppTheme {
  /// [brightness] يحدّد اللوحة المحايدة المستعملة أثناء البناء.
  ///
  /// applyBrightness تُستدعى هنا لا في مكان آخر: قيم الثيم نفسها (لون
  /// الحدود، خلفية الصفحة، ألوان النصوص) تُقرأ من AppColors أثناء بناء
  /// ThemeData، فيجب أن تكون اللوحة النشطة صحيحة قبل أول قراءة منها.
  static ThemeData build(AppColors colors, {Brightness brightness = Brightness.light}) {
    AppColors.applyBrightness(brightness);

    final colorScheme = ColorScheme.fromSeed(
      seedColor: colors.primary,
      // في الوضع الليلي لا يصلح اللون الأساسي كما هو: هوية العميل غالباً
      // داكنة (كحلي، عنابي) فتذوب في خلفية داكنة ويختفي زر الإجراء الأساسي.
      // harmonizeWith يُبقي الطابع اللوني ويرفع السطوع للحد المقروء.
      primary: brightness == Brightness.dark ? _lighten(colors.primary) : colors.primary,
      secondary: colors.secondary,
      brightness: brightness,
      surface: AppColors.surface,
      error: AppColors.danger,
    );

    return ThemeData(
      useMaterial3: true,
      // أهداف اللمس على مستوى النظام كله بدل إصلاحها ودجت ودجت.
      //
      // materialTapTargetSize.padded يفرض 48 نقطة كمنطقة نقر لعناصر Material
      // (المفاتيح، مربعات الاختيار، أزرار الأيقونات) حتى لو بدا العنصر أصغر —
      // المساحة القابلة للنقر تتوسّع دون تغيير الشكل المرسوم.
      //
      // VisualDensity.standard بدل الافتراضي الذي يتكيّف مع المنصّة: على سطح
      // المكتب يختار Flutter كثافة مضغوطة تُنقص الارتفاعات أربع نقاط، وهي
      // مناسبة لفأرة لا لشاشة كاشير تعمل باللمس. والنظام يعمل على الاثنتين.
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.paper,
      fontFamily: 'IBMPlexSansArabic',
      textTheme: TextTheme(
        displayLarge: AppTextStyles.displayLg(),
        headlineLarge: AppTextStyles.headlineLg(),
        headlineMedium: AppTextStyles.headlineMd(),
        bodyLarge: AppTextStyles.bodyLg(),
        bodyMedium: AppTextStyles.bodyMd(),
        labelMedium: AppTextStyles.labelMd(),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: AppTextStyles.headlineMd(),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.border),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: AppTextStyles.labelMd(color: Colors.white),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          side: BorderSide(color: colorScheme.primary, width: 1),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
      ),
      dividerTheme: DividerThemeData(color: AppColors.border, thickness: 1),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStateProperty.all(AppColors.surfaceAlt),
        dataRowMinHeight: 48,
        dataRowMaxHeight: 52,
      ),
    );
  }

  /// يرفع سطوع لون العلامة ليبقى مقروءاً على خلفية داكنة، مع الحفاظ على
  /// درجته اللونية (Hue) فلا تتبدّل هوية العميل — تصبح أفتح لا مختلفة.
  static Color _lighten(Color color) {
    final hsl = HSLColor.fromColor(color);
    return hsl.withLightness((hsl.lightness + 0.32).clamp(0.0, 0.78)).toColor();
  }
}
