import 'package:flutter/material.dart';
import 'app_colors.dart';

/// نظام الثيم الموحد لـ Kinetic ERP
/// Unified theme system for consistent design across the app
class AppTheme {
  /// الثيم الفاتح
  /// Light theme
  static ThemeData lightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,

      // ═══════════════════════════════════════════════════════════════
      // Color Scheme
      // ═══════════════════════════════════════════════════════════════

      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: Colors.white,
        primaryContainer: AppColors.lightPrimary,
        onPrimaryContainer: AppColors.darkPrimary,
        secondary: AppColors.primary,
        onSecondary: Colors.white,
        tertiary: AppColors.info,
        onTertiary: Colors.white,
        surface: AppColors.cardBackground,
        onSurface: AppColors.primaryText,
        error: AppColors.error,
        onError: Colors.white,
      ),

      // ═══════════════════════════════════════════════════════════════
      // App Bar Theme
      // ═══════════════════════════════════════════════════════════════

      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),

      // ═══════════════════════════════════════════════════════════════
      // Button Themes
      // ═══════════════════════════════════════════════════════════════

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 2,
          padding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 14,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 2),
          padding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 14,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // ═══════════════════════════════════════════════════════════════
      // Floating Action Button Theme
      // ═══════════════════════════════════════════════════════════════

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      // ═══════════════════════════════════════════════════════════════
      // Input Decoration Theme
      // ═══════════════════════════════════════════════════════════════

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.lightBackground,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
            color: AppColors.lightBorder,
            width: 1,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
            color: AppColors.lightBorder,
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
            color: AppColors.primary,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
            color: AppColors.error,
            width: 1,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
            color: AppColors.error,
            width: 2,
          ),
        ),
        labelStyle: const TextStyle(
          color: AppColors.primaryText,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        hintStyle: const TextStyle(
          color: AppColors.secondaryText,
          fontSize: 14,
        ),
        errorStyle: const TextStyle(
          color: AppColors.error,
          fontSize: 12,
        ),
        prefixIconColor: AppColors.secondaryText,
        suffixIconColor: AppColors.secondaryText,
      ),

      // ═══════════════════════════════════════════════════════════════
      // Card Theme
      // ═══════════════════════════════════════════════════════════════

      cardTheme: CardThemeData(
        color: AppColors.cardBackground,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: EdgeInsets.zero,
      ),

      // ═══════════════════════════════════════════════════════════════
      // List Tile Theme
      // ═══════════════════════════════════════════════════════════════

      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        textColor: AppColors.primaryText,
        iconColor: AppColors.primary,
      ),

      // ═══════════════════════════════════════════════════════════════
      // Dialog Theme
      // ═══════════════════════════════════════════════════════════════

      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.cardBackground,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      // ═══════════════════════════════════════════════════════════════
      // Bottom Sheet Theme
      // ═══════════════════════════════════════════════════════════════

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.cardBackground,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(20),
          ),
        ),
      ),

      // ═══════════════════════════════════════════════════════════════
      // Chip Theme
      // ═══════════════════════════════════════════════════════════════

      chipTheme: ChipThemeData(
        backgroundColor: AppColors.lightBackground,
        selectedColor: AppColors.primary,
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),

      // ═══════════════════════════════════════════════════════════════
      // Data Table Theme
      // ═══════════════════════════════════════════════════════════════

      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStateProperty.all(
          AppColors.lightBackground,
        ),
        dataRowMinHeight: 56,
        dataRowMaxHeight: 56,
        headingTextStyle: const TextStyle(
          color: AppColors.primaryText,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        dataTextStyle: const TextStyle(
          color: AppColors.primaryText,
          fontSize: 14,
        ),
        dividerThickness: 1,
      ),

      // ═══════════════════════════════════════════════════════════════
      // Progress Indicator Theme
      // ═══════════════════════════════════════════════════════════════

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
      ),

      // ═══════════════════════════════════════════════════════════════
      // Divider Theme
      // ═══════════════════════════════════════════════════════════════

      dividerTheme: const DividerThemeData(
        color: AppColors.lightBorder,
        thickness: 1,
        space: 1,
      ),

      // ═══════════════════════════════════════════════════════════════
      // Scaffold Background
      // ═══════════════════════════════════════════════════════════════

      scaffoldBackgroundColor: AppColors.lightBackground,

      // ═══════════════════════════════════════════════════════════════
      // Icon Theme
      // ═══════════════════════════════════════════════════════════════

      iconTheme: const IconThemeData(
        color: AppColors.primary,
        size: 24,
      ),
    );
  }

  /// الثيم الداكن
  /// Dark theme
  static ThemeData darkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,

      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        onPrimary: Colors.white,
        primaryContainer: AppColors.darkPrimary,
        onPrimaryContainer: AppColors.lightPrimary,
        secondary: AppColors.primary,
        onSecondary: Colors.white,
        tertiary: AppColors.info,
        onTertiary: Colors.white,
        surface: Color(0xFF2C2C2C),
        onSurface: Color(0xFFEEEEEE),
        error: AppColors.error,
        onError: Colors.white,
      ),

      scaffoldBackgroundColor: const Color(0xFF1E1E1E),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF2C2C2C),
        foregroundColor: Color(0xFFEEEEEE),
        elevation: 0,
      ),
    );
  }
}
