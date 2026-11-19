import 'package:flutter/material.dart';

import 'app_theme.dart';

ThemeData buildHighContrastTheme(Color accentColor) {
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppTheme.hcPrimaryBackground,

    colorScheme: ColorScheme.fromSeed(
      seedColor: accentColor,
      brightness: Brightness.dark,
    ).copyWith(surface: AppTheme.hcSecondaryBackground),

    appBarTheme: const AppBarTheme(
      backgroundColor: AppTheme.hcSecondaryBackground,
      foregroundColor: AppTheme.hcPrimaryText,
      elevation: 0,
    ),

    cardTheme: CardThemeData(
      color: AppTheme.hcSecondaryBackground,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppTheme.hcSecondaryBackground,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppTheme.hcBorders),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppTheme.hcBorders),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: accentColor, width: 2),
      ),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accentColor,
        foregroundColor: AppTheme.hcPrimaryBackground,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.hcPrimaryText,
        side: BorderSide(color: AppTheme.hcBorders, width: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppTheme.hcPrimaryText),
    ),

    dividerTheme: DividerThemeData(color: AppTheme.hcBorders, thickness: 2),
  );
}
