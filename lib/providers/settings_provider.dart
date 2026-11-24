import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:intellibreak/features/auth/services/api_service.dart';

/// Provider that manages the user's application settings.
/// Fetches and maintains the settings for the authenticated user from the backend.
/// Handles loading state, error state, and updating settings via the backend.
class SettingsProvider extends ChangeNotifier {
  SettingsProvider() {
    // Do NOT call loadSettings() here.
    // Settings should only load after auth is confirmed (token available).
    // AuthGate or AppShell will call loadSettings() when authenticated.
  }

  // Internal state
  Map<String, dynamic> _settings = {};
  bool _isLoading = false;
  String? _error;
  final ApiService _apiService = ApiService();

  // Getters
  Map<String, dynamic> get settings => _settings;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Loads settings from the backend
  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');

    if (token == null) {
      _updateState(
        settings: {},
        isLoading: false,
        error: 'Not authenticated',
      );
      return;
    }

    debugPrint('[SETTINGS_PROVIDER] Loading settings with token');
    _updateState(
      settings: _settings,
      isLoading: true,
      error: null,
    );

    try {
      debugPrint('[SETTINGS_PROVIDER] Calling GET /settings');
      final settingsData = await _apiService.getMapWithAuth(
        '/settings',
        token,
      );
      debugPrint('[SETTINGS_PROVIDER] Got settings: $settingsData');

      _updateState(
        settings: settingsData ?? {},
        isLoading: false,
        error: null,
      );
    } catch (e) {
      debugPrint('[SETTINGS_PROVIDER] Error loading settings: $e');
      _updateState(
        settings: _settings,
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Refreshes the settings (same as loadSettings)
  Future<void> refresh() async {
    await loadSettings();
  }

  /// Updates settings via PATCH /settings
  /// Only sends the provided fields to the backend.
  Future<void> updateSettings(Map<String, dynamic> updateData) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');

    if (token == null) {
      _updateState(
        settings: _settings,
        isLoading: false,
        error: 'Not authenticated',
      );
      return;
    }

    debugPrint('[SETTINGS_PROVIDER] Updating settings with: $updateData');
    _updateState(
      settings: _settings,
      isLoading: true,
      error: null,
    );

    try {
      final updatedSettings = await _apiService.patchWithAuth(
        '/settings',
        token,
        updateData,
      );

      debugPrint('[SETTINGS_PROVIDER] Updated settings: $updatedSettings');
      _updateState(
        settings: updatedSettings,
        isLoading: false,
        error: null,
      );
    } catch (e) {
      debugPrint('[SETTINGS_PROVIDER] Error updating settings: $e');
      _updateState(
        settings: _settings,
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Internal method to update state and notify listeners
  void _updateState({
    required Map<String, dynamic> settings,
    required bool isLoading,
    required String? error,
  }) {
    _settings = settings;
    _isLoading = isLoading;
    _error = error;
    notifyListeners();
  }

  /// Clears the settings state (used on logout)
  void clear() {
    _updateState(
      settings: {},
      isLoading: false,
      error: null,
    );
  }

  // Convenience getters for specific settings (optional, but useful for UI)
  bool get notificationsEnabled => _settings['notifications_enabled'] ?? true;
  bool get breakReminders => _settings['break_reminders'] ?? true;
  int get breakIntervalMinutes => _settings['break_interval_minutes'] ?? 30;
  int get breakDurationMinutes => _settings['break_duration_minutes'] ?? 10;
  bool get breakCoachEnabled => _settings['break_coach_enabled'] ?? true;
  int get breakCoachCooldownMinutes => _settings['break_coach_cooldown_minutes'] ?? 30;
  bool get reduceMotion => _settings['reduce_motion'] ?? false;
  String? get interfaceDensity => _settings['interface_density'];
  String? get timezone => _settings['timezone'];
  String get timeFormat => _settings['time_format'] ?? '12h';
  int? get workTargetDailyHours => _settings['work_target_daily_hours'];
  int? get focusTargetPercentage => _settings['focus_target_percentage'];
  String? get idleDetectionSensitivity => _settings['idle_detection_sensitivity'];
  bool get shiftReminders => _settings['shift_reminders'] ?? true;
  bool get taskReminders => _settings['task_reminders'] ?? true;
  bool get workDaysTracking => _settings['work_days'] != null && (_settings['work_days'] as List<dynamic>?)?.isNotEmpty == true;
  String? get defaultWorkSchedule => _settings['default_work_schedule'];
  String? get shiftStartTime => _settings['shift_start_time'];
  String? get shiftEndTime => _settings['shift_end_time'];
  int? get targetDailyHours => _settings['work_target_daily_hours'];
  int? get focusTarget => _settings['focus_target_percentage'];
  bool get productivityTracking => _settings['task_reminders'] ?? true;
  bool get focusReminders => _settings['focus_reminders'] ?? true;
  bool get wellnessReminders => _settings['wellness_reminders'] ?? true;
  bool get dailySummary => _settings['daily_summary'] ?? false;
  bool get weeklySummary => _settings['weekly_summary'] ?? false;
  String get managerDefaultLanding => _settings['manager_default_landing'] ?? 'dashboard';
  bool? get manualDndOverride => _settings['manual_dnd_override'];
  bool get browserNotificationsEnabled => _settings['browser_notifications_enabled'] ?? true;
  bool get notificationSoundsEnabled => _settings['notification_sounds_enabled'] ?? true;
  bool get tabAttentionEnabled => _settings['tab_attention_enabled'] ?? true;
}
