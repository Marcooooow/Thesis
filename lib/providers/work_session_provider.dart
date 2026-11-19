import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/dashboard/services/work_service.dart';
import 'work_session_models.dart';

/// Provider that manages the complete work-session state as the single source of truth.
/// All session/break mutations flow through this provider, which keeps its state
/// synchronized with the backend. The provider survives theme changes and navigation
/// because it's provided via ChangeNotifierProvider.value in main.dart.
class WorkSessionProvider extends ChangeNotifier {
  WorkSessionProvider() {
    _loadToken(); // Initialize token from shared preferences
    // Timer deferred until initialize() is called after auth
  }

  /// Initialize the provider after authentication is confirmed.
  /// Called by AuthGate once the user is verified.
  /// Starts the periodic refresh timer to prevent state staleness.
  void initialize() {
    _periodicRefreshTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      if (_token != null) {
        refresh();
      }
    });
  }

  /// Stop periodic refresh timer
  void _stopPeriodicRefresh() {
    _periodicRefreshTimer?.cancel();
    _periodicRefreshTimer = null;
  }

  // Internal state - updated only via _updateState which calls notifyListeners
  WorkSessionState _state = WorkSessionState.empty;
  String? _token;
  Timer? _refreshTimer;
  Timer? _periodicRefreshTimer;
  final WorkService _workService = WorkService();

  // Getters exposing the current state
  WorkSessionState get state => _state;
  bool get isActive => _state.isActive;
  bool get isOnBreak => _state.isOnBreak;
  BreakType? get breakType => _state.breakType;
  DateTime? get startTime => _state.startTime;
  int? get elapsedTimeInSeconds => _state.elapsedTimeInSeconds;
  Set<BreakType> get breaksTaken => _state.breaksTaken;
  WorkTask? get currentTask => _state.currentTask;
  WorkTask? get unfinishedTask => _state.unfinishedTask;
  DateTime? get meetingStartedAt => _state.meetingStartedAt;
  DateTime? get meetingEndedAt => _state.meetingEndedAt;
  bool get isLoading => _state.isLoading;
  String? get lastError => _state.lastError;

  /// Returns true if we have a valid token and the last backend refresh succeeded
  /// (i.e., not loading and no error). This serves as a rough proxy for online presence.
  bool get isOnline => _token != null && !_state.isLoading && _state.lastError == null;

  /// Loads the JWT token from shared preferences.
  /// Note: Demo mode is now handled exclusively in the demo shell,
  /// this provider only handles real authenticated flows.
  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('jwt_token');

    if (_token == null) {
      // No token -> authentication required
      _updateState(_state.copyWith(
        isLoading: false,
        lastError: 'Authentication required',
      ));
    } else {
      // If we have a token, do an initial refresh to populate state
      await refresh();
    }
    notifyListeners(); // Inform listeners of initial token state
  }

  /// Refreshes the entire work-session state from the backend.
  /// This is called after every successful mutation and on initial load.
  /// Fetches session, active break, and ALL tasks (history) in parallel.
  Future<void> refresh({String? token}) async {
    if (token != null) {
      _token = token;
    }

    final prefs = await SharedPreferences.getInstance();
    final currentToken = prefs.getString('jwt_token');
    if (currentToken == null) {
      _updateState(_state.copyWith(
        isLoading: false,
        lastError: 'Not authenticated',
      ));
      return;
    }

    _updateState(_state.copyWith(isLoading: true, lastError: null));

    try {
      // Get active session first to ensure consistency
      final sessionResponse = await _workService.getActiveSession(currentToken);
      WorkSession? session;
      if (sessionResponse != null) {
        session = WorkSession.fromJson(sessionResponse);
      }

      WorkBreak? activeBreak;
      List<WorkTask?> allTasks = [];
      WorkTask? currentTask;

      // 1. Fetch persistent task history (all tasks)
      final historyResponse = await _workService.getTasksHistory(currentToken);
      for (var taskJson in historyResponse) {
        final task = WorkTask.fromJson(taskJson);
        allTasks.add(task);
      }

      // 2. Identify the active task if a session exists
      if (session != null) {
        // Get active break for this session
        final activeBreakResponse = await _workService.getActiveBreak(currentToken);
        if (activeBreakResponse != null) {
          activeBreak = WorkBreak.fromJson(activeBreakResponse);
        }

        // Find the currently active task in this session from the history we already fetched
        currentTask = allTasks.firstWhere(
          (task) =>
              task?.status == 'IN_PROGRESS' &&
              task?.workSessionId != null &&
              task?.workSessionId == session!.id,
          orElse: () => null,
        );
      }

      // Get all breaks for the session to determine completed breaks
      List<WorkBreak> completedBreaks = [];
      if (session != null) {
        final breaksResponse =
            await _workService.getSessionBreaks(currentToken, session.id);
        for (var breakJson in breaksResponse) {
          final breakItem = WorkBreak.fromJson(breakJson);
          if (breakItem.endedAt != null) {
            // Completed break
            completedBreaks.add(breakItem);
          }
        }
      }

      _updateState(WorkSessionState(
        session: session,
        activeBreak: activeBreak,
        completedBreaks: completedBreaks,
        currentTask: currentTask,
        tasks: allTasks, // All persistent tasks
        isLoading: false,
        lastError: null,
      ));
    } catch (e) {
      // If the error is due to an invalid token, clear it.
      if (e.toString().contains("401") || e.toString().contains("Unauthorized")) {
        await _clearToken();
      }
      _updateState(_state.copyWith(
        isLoading: false,
        lastError: e.toString(),
      ));
    }
  }

  /// Clears the JWT token from shared preferences.
  Future<void> _clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("jwt_token");
    _token = null;
  }

  /// Internal method to update state and notify listeners only if state actually changed.
  void _updateState(WorkSessionState newState) {
    if (newState == _state) return;
    _state = newState;
    notifyListeners();
  }

  /// Starts a new work session.
  Future<void> startShift() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null) return;

    try {
      await _workService.startWorkSession(token);
      // After successful backend call, refresh state from server
      await refresh();
    } catch (e) {
      // Re-throw to let caller handle UI feedback
      rethrow;
    }
  }

  /// Ends the current work session.
  Future<void> endShift() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null) return;

    try {
      await _workService.endWorkSession(token);
      _updateState(WorkSessionState.empty);
    } catch (e) {
      rethrow;
    }
  }

  /// Starts a break of the specified type.
  Future<void> startBreak(BreakType type, {String? recommendationId}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null) return;

    try {
      await _workService.startBreak(token, type.wireName, recommendationId: recommendationId);
      await refresh(); // Get updated state from server
    } catch (e) {
      rethrow;
    }
  }

  /// Ends the current active break.
  Future<void> endBreak() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null) return;

    try {
      // Need the active break ID to end it
      final activeBreak = _state.activeBreak;
      if (activeBreak == null) return;

      await _workService.endBreak(token, activeBreak.id);
      await refresh(); // Get updated state from server
    } catch (e) {
      rethrow;
    }
  }

  /// Extends the current active break.
  Future<void> extendBreak({int extensionMinutes = 15, String? reason}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null) return;

    try {
      final activeBreak = _state.activeBreak;
      if (activeBreak == null) return;

      await _workService.extendBreak(token, activeBreak.id, extensionMinutes: extensionMinutes, reason: reason);
      await refresh();
    } catch (e) {
      rethrow;
    }
  }

  /// Sets the current task (used by WorkTasks when a task is started).
  /// This is a local-only operation that doesn't contact the backend.
  /// The backend considers a task "current" when its status is IN_PROGRESS.
  void setCurrentTask(WorkTask? task) {
    _updateState(_state.copyWith(currentTask: task));
  }

  /// Clears all state (used on logout).
  void clear() {
    _updateState(WorkSessionState.empty);
    _token = null;
  }

  /// Determines the availability status for a specific break type.
  /// Implements the business rules: BREAK_2 requires completed BREAK_1,
  /// LUNCH requires completed BREAK_2.
  BreakAvailability availabilityFor(BreakType type) {
    // No active session
    if (!_state.isActive) {
      return BreakAvailability.disabled('Start a shift first');
    }

    // Break is currently active
    if (_state.activeBreak?.type == type) {
      return BreakAvailability.active();
    }

    // Generic break, coach break, meal, and other (away) are always available when shift is active (and repeatable)
    if (type == BreakType.breakGeneric || type == BreakType.coachBreak || type == BreakType.meal || type == BreakType.other) {
      return BreakAvailability.available();
    }

    // Break has been completed in this session
    if (_state.breaksTaken.contains(type)) {
      return BreakAvailability.completed();
    }

    // Legacy check for break2 / lunch
    if (type == BreakType.break2 || type == BreakType.lunch) {
      if (!_state.breaksTaken.contains(BreakType.break1)) {
        return BreakAvailability.disabled('Complete Break 1 first');
      }
    }

    // All conditions met - break is available
    return BreakAvailability.available();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _stopPeriodicRefresh();
    super.dispose();
  }
}