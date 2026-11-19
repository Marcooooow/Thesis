import 'package:flutter/material.dart';

import 'app_theme.dart';

ThemeData buildDarkTheme(Color accentColor) {
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppTheme.darkPrimaryBackground,

    colorScheme: ColorScheme.fromSeed(
      seedColor: accentColor,
      brightness: Brightness.dark,
    ).copyWith(surface: AppTheme.darkSecondaryBackground),
    visualDensity: VisualDensity.standard,
    useMaterial3: true,

    appBarTheme: const AppBarTheme(
      backgroundColor: AppTheme.darkSecondaryBackground,
      foregroundColor: AppTheme.darkPrimaryText,
      elevation: 0,
    ),

    cardTheme: CardThemeData(
      color: AppTheme.darkSecondaryBackground,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),

    inputDecorationTheme: InputDecorationTheme(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      filled: true,
      fillColor: AppTheme.darkSecondaryBackground,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppTheme.darkBorders),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppTheme.darkBorders),
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
        foregroundColor: AppTheme.darkPrimaryText,
        side: BorderSide(color: AppTheme.darkBorders),
        minimumSize: const Size(44, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppTheme.darkSecondaryText),
    ),

    dividerTheme: DividerThemeData(color: AppTheme.darkBorders, thickness: 1),
  );
}
