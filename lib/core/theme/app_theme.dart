import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppTheme {
  const AppTheme._();


  static const CupertinoThemeData cupertinoLight = CupertinoThemeData(
    brightness: Brightness.light,
    primaryColor: AppColors.primary,
    scaffoldBackgroundColor: AppColors.lightBackground,
    barBackgroundColor: CupertinoColors.systemBackground,
    textTheme: CupertinoTextThemeData(
      primaryColor: AppColors.primary,
      textStyle: TextStyle(
        fontFamily: '.SF Pro Text',
        color: AppColors.lightTextPrimary,
        fontSize: 17,
      ),
      navTitleTextStyle: TextStyle(
        fontFamily: '.SF Pro Display',
        fontWeight: FontWeight.w600,
        fontSize: 17,
        color: AppColors.lightTextPrimary,
      ),
      navLargeTitleTextStyle: TextStyle(
        fontFamily: '.SF Pro Display',
        fontWeight: FontWeight.w700,
        fontSize: 34,
        color: AppColors.lightTextPrimary,
      ),
      tabLabelTextStyle: TextStyle(fontFamily: '.SF Pro Text', fontSize: 10),
    ),
  );

  static const CupertinoThemeData cupertinoLDark = CupertinoThemeData(
    brightness: Brightness.dark,
    primaryColor: AppColors.primary,
    scaffoldBackgroundColor: AppColors.background,
    barBackgroundColor: Color(0xFF1C1C1E),
    textTheme: CupertinoTextThemeData(
      primaryColor: AppColors.primary,
      textStyle: TextStyle(
        fontFamily: '.SF Pro Text',
        color: AppColors.textPrimary,
        fontSize: 17,
      ),
      navTitleTextStyle: TextStyle(
        fontFamily: '.SF Pro Display',
        fontWeight: FontWeight.w600,
        fontSize: 17,
        color: AppColors.textPrimary,
      ),
      navLargeTitleTextStyle: TextStyle(
        fontFamily: '.SF Pro Display',
        fontWeight: FontWeight.w700,
        fontSize: 34,
        color: AppColors.textPrimary,
      ),
      tabLabelTextStyle: TextStyle(fontFamily: '.SF Pro Text', fontSize: 10),
    ),
  );

  static ThemeData get dark => _buildMaterial(Brightness.dark);
  static ThemeData get light => _buildMaterial(Brightness.light);

  static ThemeData _buildMaterial(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: isDark
          ? AppColors.background
          : AppColors.lightBackground,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: AppColors.primary,
        onPrimary: Colors.white,
        secondary: AppColors.accent,
        onSecondary: Colors.white,
        error: AppColors.error,
        onError: Colors.white,
        surface: isDark ? AppColors.surface : AppColors.lightSurface,
        onSurface: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: isDark
            ? AppColors.textPrimary
            : AppColors.lightTextPrimary,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? AppColors.surface : AppColors.lightSurface,
        contentTextStyle: TextStyle(
          color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? AppColors.surface : AppColors.lightSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
