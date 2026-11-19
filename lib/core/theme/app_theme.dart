import 'package:flutter/material.dart';

class AppTheme {
  // ============================
  // COLOR PALETTE DEFINITIONS
  // ============================

  // Dark Charcoal Base Colors
  static const Color darkPrimaryBackground = Color(0xFF121318);
  static const Color darkSecondaryBackground = Color(0xFF1B1D24);
  static const Color darkPrimaryText = Color(0xFFF2F2F2);
  static const Color darkSecondaryText = Color(0xFFA5A7AE);
  static const Color darkBorders = Color(0xFF30323A);
  static const Color darkAccent = Color(0xFF67B9A8);

  // Light Theme Colors
  static const Color lightPrimaryBackground = Color(0xFFF4F6F8);
  static const Color lightSecondaryBackground = Colors.white;
  static const Color lightPrimaryText = Color(0xFF171923);
  static const Color lightSecondaryText = Color(0xFF6B7280);
  static const Color lightBorders = Color(0xFFDCE3E8);
  static const Color lightAccent = Color(0xFF176B5B);

  // High Contrast Theme Colors
  static const Color hcPrimaryBackground = Color(0xFF000000);
  static const Color hcSecondaryBackground = Color(0xFF0D0D0D);
  static const Color hcPrimaryText = Color(0xFFFFFFFF);
  static const Color hcSecondaryText = Color(0xFFE0E0E0);
  static const Color hcBorders = Color(0xFF404040);
  static const Color hcAccent = Color(0xFFFFD700); // Gold for high visibility

  // ============================
  // LIGHT THEME
  // ============================

  static ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: lightPrimaryBackground,

    colorScheme: ColorScheme.fromSeed(
      seedColor: lightAccent,
      brightness: Brightness.light,
    ).copyWith(surface: lightSecondaryBackground),

    appBarTheme: const AppBarTheme(
      backgroundColor: lightSecondaryBackground,
      foregroundColor: lightPrimaryText,
      elevation: 0,
    ),

    cardTheme: CardThemeData(
      color: lightSecondaryBackground,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: lightSecondaryBackground,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: lightBorders),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: lightBorders),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: lightAccent, width: 2),
      ),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: lightAccent,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: lightPrimaryText,
        side: BorderSide(color: lightBorders),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: lightSecondaryText),
    ),

    dividerTheme: DividerThemeData(color: lightBorders, thickness: 1),
  );

  // ============================
  // DARK THEME
  // ============================

  static ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: darkPrimaryBackground,

    colorScheme: ColorScheme.fromSeed(
      seedColor: darkAccent,
      brightness: Brightness.dark,
    ).copyWith(surface: darkSecondaryBackground),

    appBarTheme: const AppBarTheme(
      backgroundColor: darkSecondaryBackground,
      foregroundColor: darkPrimaryText,
      elevation: 0,
    ),

    cardTheme: CardThemeData(
      color: darkSecondaryBackground,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: darkSecondaryBackground,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: darkBorders),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: darkBorders),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: darkAccent, width: 2),
      ),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: darkAccent,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: darkPrimaryText,
        side: BorderSide(color: darkBorders),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: darkSecondaryText),
    ),

    dividerTheme: DividerThemeData(color: darkBorders, thickness: 1),
  );

  // ============================
  // HIGH CONTRAST THEME
  // ============================

  static ThemeData highContrastTheme = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: hcPrimaryBackground,

    colorScheme: ColorScheme.fromSeed(
      seedColor: hcAccent,
      brightness: Brightness.dark,
    ).copyWith(surface: hcSecondaryBackground),

    appBarTheme: const AppBarTheme(
      backgroundColor: hcSecondaryBackground,
      foregroundColor: hcPrimaryText,
      elevation: 0,
    ),

    cardTheme: CardThemeData(
      color: hcSecondaryBackground,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: hcSecondaryBackground,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: hcBorders),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: hcBorders),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: hcAccent, width: 2),
      ),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: hcAccent,
        foregroundColor: hcPrimaryBackground,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: hcPrimaryText,
        side: BorderSide(color: hcBorders, width: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: hcPrimaryText),
    ),

    dividerTheme: DividerThemeData(color: hcBorders, thickness: 2),
  );
}
