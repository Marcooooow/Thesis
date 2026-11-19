import 'package:flutter/material.dart';

import 'app_theme.dart';

ThemeData buildLightTheme(Color accentColor) {
  return ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppTheme.lightPrimaryBackground,

    colorScheme: ColorScheme.fromSeed(
      seedColor: accentColor,
      brightness: Brightness.light,
    ).copyWith(surface: AppTheme.lightSecondaryBackground),
    visualDensity: VisualDensity.standard,
    useMaterial3: true,

    appBarTheme: const AppBarTheme(
      backgroundColor: AppTheme.lightSecondaryBackground,
      foregroundColor: AppTheme.lightPrimaryText,
      elevation: 0,
    ),

    cardTheme: CardThemeData(
      color: AppTheme.lightSecondaryBackground,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),

    inputDecorationTheme: InputDecorationTheme(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      filled: true,
      fillColor: AppTheme.lightSecondaryBackground,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppTheme.lightBorders),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppTheme.lightBorders),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: accentColor, width: 2),
      ),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accentColor,
        foregroundColor: Colors.white,
        elevation: 0,
        minimumSize: const Size(44, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.lightPrimaryText,
        side: BorderSide(color: AppTheme.lightBorders),
        minimumSize: const Size(44, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppTheme.lightSecondaryText),
    ),

    dividerTheme: DividerThemeData(color: AppTheme.lightBorders, thickness: 1),
  );
}
