import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_text_styles.dart';

/// يبني ThemeData كاملة من [AppColors] الممرَّرة، بحيث يمكن استدعاء
/// AppTheme.build(colors) بلوحة ألوان مختلفة لكل منظمة/زبون فور تحميل
/// إعدادات العلامة التجارية من Supabase.
class AppTheme {
  static ThemeData build(AppColors colors) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: colors.primary,
      primary: colors.primary,
      secondary: colors.secondary,
      brightness: Brightness.light,
      surface: AppColors.surface,
      error: AppColors.danger,
    );

    return ThemeData(
      useMaterial3: true,
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
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: AppTextStyles.labelMd(color: Colors.white),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.primary,
          side: BorderSide(color: colors.primary, width: 1),
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
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.primary, width: 1.5),
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStateProperty.all(AppColors.surfaceAlt),
        dataRowMinHeight: 48,
        dataRowMaxHeight: 52,
      ),
    );
  }
}
