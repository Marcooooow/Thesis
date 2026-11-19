import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'light_theme.dart';
import 'dark_theme.dart';
import 'high_contrast_theme.dart';

class ThemeController extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.dark;
  Color _accentColor = const Color(0xFF176B5B);
  bool _isHighContrast = false;

  ThemeMode get themeMode => _themeMode;
  Color get accentColor => _accentColor;
  bool get isHighContrast => _isHighContrast;

  ThemeController() {
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final themeModeIndex = prefs.getInt('theme_mode');
    final accentColorValue = prefs.getInt('accent_color');
    final isHighContrastValue = prefs.getBool('high_contrast');

    if (themeModeIndex != null) {
      _themeMode = ThemeMode.values[themeModeIndex];
    }
    if (accentColorValue != null) {
      _accentColor = Color(accentColorValue);
    }
    if (isHighContrastValue != null) {
      _isHighContrast = isHighContrastValue;
    }
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_mode', mode.index);
    notifyListeners();
  }

  Future<void> setAccentColor(Color color) async {
    if (_accentColor == color) return;
    _accentColor = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('accent_color', color.toARGB32());
    notifyListeners();
  }

  Future<void> setHighContrast(bool enabled) async {
    if (_isHighContrast == enabled) return;
    _isHighContrast = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('high_contrast', enabled);
    notifyListeners();
  }

  ThemeData getThemeData(BuildContext context) {
    if (_isHighContrast) {
      return buildHighContrastTheme(_accentColor);
    }
    switch (_themeMode) {
      case ThemeMode.light:
        return buildLightTheme(_accentColor);
      case ThemeMode.dark:
        return buildDarkTheme(_accentColor);
      case ThemeMode.system:
        final brightness = MediaQuery.of(context).platformBrightness;
        return brightness == Brightness.dark
            ? buildDarkTheme(_accentColor)
            : buildLightTheme(_accentColor);
    }
  }
}
