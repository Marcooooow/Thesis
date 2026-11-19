import 'package:flutter/foundation.dart';

/// Centralized API base URL configuration.
/// 1. Uses --dart-define=API_BASE_URL if provided.
/// 2. On Flutter Web, if hostname is localhost or 127.0.0.1, defaults to http://localhost:8000.
/// 3. Otherwise defaults to https://intellibreak.onrender.com in release mode, http://localhost:8000 in debug mode.
class ApiConfig {
  static String get baseUrl {
    const definedUrl = String.fromEnvironment('API_BASE_URL');
    if (definedUrl.isNotEmpty) {
      return definedUrl;
    }
    return kReleaseMode ? 'https://intellibreak.onrender.com' : 'http://localhost:8000';
  }
}
