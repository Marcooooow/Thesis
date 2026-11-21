import 'package:flutter/material.dart';

/// Central design tokens and theme construction for IntelliBreak.
///
/// Palette: cool slate neutrals with a single deep-teal accent. Surfaces are
/// separated by 1px borders rather than heavy shadows, type is set in a
/// consistent scale, and every component theme is defined once here so
/// individual screens do not need to restyle controls.
class AppTheme {
  // ============================
  // COLOR TOKENS
  // ============================

  /// Default brand accent (deep teal).
  static const Color defaultAccent = Color(0xFF0F766E);

  // Dark
  static const Color darkPrimaryBackground = Color(0xFF0E1217);
  static const Color darkSecondaryBackground = Color(0xFF182029);
  static const Color darkPrimaryText = Color(0xFFE8EBEF);
  static const Color darkSecondaryText = Color(0xFF9AA3AF);
  static const Color darkBorders = Color(0xFF2D3643);
  static const Color darkAccent = defaultAccent;

  // Light
  static const Color lightPrimaryBackground = Color(0xFFECEFF3);
  static const Color lightSecondaryBackground = Colors.white;
  static const Color lightPrimaryText = Color(0xFF111827);
  static const Color lightSecondaryText = Color(0xFF5B6472);
  static const Color lightBorders = Color(0xFFD3D9E1);
  static const Color lightAccent = defaultAccent;

  // High contrast
  static const Color hcPrimaryBackground = Color(0xFF000000);
  static const Color hcSecondaryBackground = Color(0xFF0D0D0D);
  static const Color hcPrimaryText = Color(0xFFFFFFFF);
  static const Color hcSecondaryText = Color(0xFFE0E0E0);
  static const Color hcBorders = Color(0xFF6B6B6B);
  static const Color hcAccent = Color(0xFFFFD700);

  // Radii
  static const double radiusControl = 8;
  static const double radiusCard = 12;

  // ============================
  // SHARED BUILDER
  // ============================

  /// On dark surfaces a deep accent loses contrast; lift its lightness so
  /// links, rings and selected states stay legible.
  static Color accentOnDark(Color accent) {
    final hsl = HSLColor.fromColor(accent);
    if (hsl.lightness >= 0.55) return accent;
    return hsl.withLightness(0.55).withSaturation((hsl.saturation * 0.9).clamp(0.0, 1.0)).toColor();
  }

  static ThemeData build({
    required Brightness brightness,
    required Color accent,
    required Color background,
    required Color surface,
    required Color text,
    required Color secondaryText,
    required Color border,
    bool highContrast = false,
    Color? onAccentOverride,
  }) {
    final isDark = brightness == Brightness.dark;
    final primary = (isDark && !highContrast) ? accentOnDark(accent) : accent;
    final onPrimary = onAccentOverride ??
        (ThemeData.estimateBrightnessForColor(primary) == Brightness.dark ? Colors.white : const Color(0xFF0B1115));
    final borderWidth = highContrast ? 2.0 : 1.0;

    final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: brightness).copyWith(
      primary: primary,
      onPrimary: onPrimary,
      secondary: primary,
      onSecondary: onPrimary,
      surface: surface,
      onSurface: text,
      onSurfaceVariant: secondaryText,
      outline: border,
      outlineVariant: border,
      surfaceTint: Colors.transparent,
      error: isDark ? const Color(0xFFE5806C) : const Color(0xFFB3412C),
    );

    // Type scale: tight, neutral, with clear step sizes.
    final base = ThemeData(brightness: brightness).textTheme;
    final textTheme = base
        .apply(bodyColor: text, displayColor: text)
        .copyWith(
          displaySmall: base.displaySmall?.copyWith(fontSize: 36, fontWeight: FontWeight.w600, letterSpacing: -0.8, color: text),
          headlineMedium: base.headlineMedium?.copyWith(fontSize: 26, fontWeight: FontWeight.w600, letterSpacing: -0.5, color: text),
          headlineSmall: base.headlineSmall?.copyWith(fontSize: 21, fontWeight: FontWeight.w600, letterSpacing: -0.3, color: text),
          titleLarge: base.titleLarge?.copyWith(fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: text),
          titleMedium: base.titleMedium?.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: text),
          titleSmall: base.titleSmall?.copyWith(fontSize: 14, fontWeight: FontWeight.w600, color: text),
          bodyLarge: base.bodyLarge?.copyWith(fontSize: 15, height: 1.45, color: text),
          bodyMedium: base.bodyMedium?.copyWith(fontSize: 14, height: 1.45, color: text),
          bodySmall: base.bodySmall?.copyWith(fontSize: 12.5, height: 1.4, color: secondaryText),
          labelLarge: base.labelLarge?.copyWith(fontSize: 14, fontWeight: FontWeight.w600, color: text),
          labelMedium: base.labelMedium?.copyWith(fontSize: 12.5, fontWeight: FontWeight.w500, color: secondaryText),
          labelSmall: base.labelSmall?.copyWith(fontSize: 11.5, fontWeight: FontWeight.w500, color: secondaryText),
        );

    OutlineInputBorder inputBorder(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          borderSide: BorderSide(color: c, width: w),
        );

    final fieldFill = isDark ? Color.alphaBlend(Colors.white.withValues(alpha: 0.03), surface) : surface;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: surface,
      dividerColor: border,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      visualDensity: VisualDensity.standard,
      splashFactory: InkRipple.splashFactory,

      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge,
      ),

      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: BorderSide(color: border, width: borderWidth),
        ),
      ),

      dividerTheme: DividerThemeData(color: border, thickness: borderWidth, space: 1),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fieldFill,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        labelStyle: TextStyle(color: secondaryText, fontSize: 14),
        floatingLabelStyle: TextStyle(color: primary, fontSize: 13, fontWeight: FontWeight.w500),
        hintStyle: TextStyle(color: secondaryText.withValues(alpha: 0.75), fontSize: 14),
        helperStyle: TextStyle(color: secondaryText, fontSize: 12),
        errorStyle: TextStyle(color: scheme.error, fontSize: 12),
        border: inputBorder(border, borderWidth),
        enabledBorder: inputBorder(border, borderWidth),
        focusedBorder: inputBorder(primary, 1.6),
        errorBorder: inputBorder(scheme.error, borderWidth),
        focusedErrorBorder: inputBorder(scheme.error, 1.6),
        disabledBorder: inputBorder(border.withValues(alpha: 0.5), borderWidth),
      ),

      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: textTheme.bodyMedium,
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(4),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusControl + 2),
            side: BorderSide(color: border),
          )),
        ),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusControl + 2),
          side: BorderSide(color: border),
        ),
        textStyle: textTheme.bodyMedium,
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          disabledBackgroundColor: text.withValues(alpha: 0.10),
          disabledForegroundColor: text.withValues(alpha: 0.38),
          elevation: 0,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusControl)),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          minimumSize: const Size(0, 44),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusControl)),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          side: BorderSide(color: border, width: borderWidth),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusControl)),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: highContrast ? text : primary,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusControl)),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: secondaryText),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: Colors.transparent,
        selectedColor: primary.withValues(alpha: 0.14),
        disabledColor: border,
        side: BorderSide(color: border, width: borderWidth),
        labelStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w500),
        secondaryLabelStyle: textTheme.labelLarge?.copyWith(color: primary),
        checkmarkColor: primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusControl)),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard + 4),
          side: BorderSide(color: border),
        ),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? const Color(0xFFE8EBEF) : const Color(0xFF1F2933),
        contentTextStyle: TextStyle(
          color: isDark ? const Color(0xFF111827) : Colors.white,
          fontSize: 14,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusControl)),
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFFE8EBEF) : const Color(0xFF1F2933),
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: TextStyle(
          color: isDark ? const Color(0xFF111827) : Colors.white,
          fontSize: 12,
        ),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? onPrimary : (isDark ? secondaryText : Colors.white)),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? primary : border),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? primary : Colors.transparent),
        checkColor: WidgetStatePropertyAll(onPrimary),
        side: BorderSide(color: secondaryText, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),

      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? primary : secondaryText),
      ),

      sliderTheme: SliderThemeData(
        activeTrackColor: primary,
        inactiveTrackColor: border,
        thumbColor: primary,
        overlayColor: primary.withValues(alpha: 0.12),
        trackHeight: 4,
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: border,
        circularTrackColor: border,
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: primary,
        unselectedLabelColor: secondaryText,
        indicatorColor: primary,
        dividerColor: border,
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),

      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(secondaryText.withValues(alpha: 0.35)),
        radius: const Radius.circular(8),
        thickness: const WidgetStatePropertyAll(6),
      ),
    );
  }

  // ============================
  // PRESETS (kept for existing call sites)
  // ============================

  static ThemeData lightThemeFor(Color accent) => build(
        brightness: Brightness.light,
        accent: accent,
        background: lightPrimaryBackground,
        surface: lightSecondaryBackground,
        text: lightPrimaryText,
        secondaryText: lightSecondaryText,
        border: lightBorders,
      );

  static ThemeData darkThemeFor(Color accent) => build(
        brightness: Brightness.dark,
        accent: accent,
        background: darkPrimaryBackground,
        surface: darkSecondaryBackground,
        text: darkPrimaryText,
        secondaryText: darkSecondaryText,
        border: darkBorders,
      );

  static ThemeData highContrastThemeFor(Color accent) => build(
        brightness: Brightness.dark,
        accent: hcAccent,
        background: hcPrimaryBackground,
        surface: hcSecondaryBackground,
        text: hcPrimaryText,
        secondaryText: hcSecondaryText,
        border: hcBorders,
        highContrast: true,
        onAccentOverride: hcPrimaryBackground,
      );

  static ThemeData lightTheme = lightThemeFor(defaultAccent);
  static ThemeData darkTheme = darkThemeFor(defaultAccent);
  static ThemeData highContrastTheme = highContrastThemeFor(hcAccent);
}
