import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      // 主題色彩設計 - 深色主題為主，適合 TV 觀看
      brightness: Brightness.dark,
      primarySwatch: Colors.deepPurple,
      scaffoldBackgroundColor: const Color(AppConstants.backgroundColor),
      cardColor: const Color(AppConstants.cardBackgroundColor),

      // 自定義色彩
      colorScheme: const ColorScheme.dark(
        primary: Color(AppConstants.primaryColor),
        secondary: Color(AppConstants.secondaryColor),
        tertiary: Color(AppConstants.tertiaryColor),
        surface: Color(AppConstants.cardBackgroundColor),
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: Colors.white,
      ),

      // 卡片主題
      cardTheme: const CardThemeData(
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppConstants.cardBorderRadius)),
        ),
        color: Color(AppConstants.cardBackgroundColor),
      ),

      // 應用欄主題
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(AppConstants.backgroundColor),
        foregroundColor: Colors.white,
        elevation: 0,
      ),

      // 文字主題
      textTheme: _buildTextTheme(),

      // 按鈕主題
      elevatedButtonTheme: _buildElevatedButtonTheme(),

      // 輸入框主題
      inputDecorationTheme: _buildInputDecorationTheme(),
    );
  }

  static TextTheme _buildTextTheme() {
    return const TextTheme(
      headlineLarge: TextStyle(
        color: Colors.white,
        fontSize: 32,
        fontWeight: FontWeight.bold,
      ),
      headlineMedium: TextStyle(
        color: Colors.white,
        fontSize: 28,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: TextStyle(
        color: Colors.white,
        fontSize: AppConstants.titleFontSize,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w500,
      ),
      bodyLarge: TextStyle(
        color: Colors.white,
        fontSize: AppConstants.bodyFontSize,
      ),
      bodyMedium: TextStyle(
        color: Colors.white70,
        fontSize: AppConstants.smallFontSize,
      ),
      bodySmall: TextStyle(
        color: Colors.white60,
        fontSize: AppConstants.captionFontSize,
      ),
    );
  }

  static ElevatedButtonThemeData _buildElevatedButtonTheme() {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(AppConstants.primaryColor),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.defaultBorderRadius),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.largePadding,
          vertical: AppConstants.captionFontSize,
        ),
      ),
    );
  }

  static InputDecorationTheme _buildInputDecorationTheme() {
    return InputDecorationTheme(
      filled: true,
      fillColor: const Color(AppConstants.cardBackgroundColor),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppConstants.defaultBorderRadius),
        borderSide: const BorderSide(color: Color(AppConstants.primaryColor)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppConstants.defaultBorderRadius),
        borderSide: const BorderSide(color: Color(0xFF333333)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppConstants.defaultBorderRadius),
        borderSide: const BorderSide(color: Color(AppConstants.primaryColor), width: 2),
      ),
    );
  }
} 