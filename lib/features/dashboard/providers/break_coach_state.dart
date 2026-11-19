import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intellibreak/features/dashboard/models/break_coach_models.dart';
import 'package:intellibreak/features/dashboard/services/break_coach_service.dart';
import 'package:intellibreak/features/dashboard/services/recommendation_service.dart';
import 'package:intellibreak/providers/work_session_provider.dart';
import 'package:intellibreak/providers/work_session_models.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Break Coach state provider that manages notification visibility and user actions
///
/// Uses Provider pattern for state management. Integrates with the existing
/// WorkService for session/break data and SharedPreferences for preferences.
class BreakCoachState extends ChangeNotifier {
  final BreakCoachService _service;
  final RecommendationService _recommendationService = RecommendationService();

  // State
  BreakCoachRecommendation? _currentRecommendation;
  bool _isVisible = false;
  bool _isLoading = false;
  String? _error;
  int _cooldownMinutes = 30;

  // Break-in-progress state
  bool _isBreakInProgress = false;
  BreakCoachRecommendation? _acceptedRecommendation;

  // Snooze and preferences
  static const String _prefBreakCoachEnabled = 'break_coach_enabled';
  static const String _prefSnoozeUntil = 'break_coach_snooze_until';
  static const String _prefLastDismissedAt = 'break_coach_last_dismissed_at';
  static const String _prefCooldownMinutes = 'break_coach_cooldown_minutes';
  static const String _prefDismissedRecommendationId = 'break_coach_dismissed_rec_id';
  static const String _prefDismissedAt = 'break_coach_dismissed_at';

  // Default values
  static const bool _defaultEnabled = true;
  static const int _defaultCooldownMinutes = 30;

  bool _isEnabled = _defaultEnabled;
  DateTime? _snoozeUntil;
  DateTime? _lastDismissedAt;
  String? _dismissedRecommendationId;
  DateTime? _dismissedAt;

  Timer? _timer;
  String? _elapsedText;

  // Session provider listener for reactive updates
  WorkSessionProvider? _sessionProvider;
  VoidCallback? _sessionListener;

  BreakCoachState({BreakCoachService? service})
      : _service = service ?? BreakCoachService();

  // Getters
  bool get isVisible => _isVisible;
  bool get isEnabled => _isEnabled;
  BreakCoachRecommendation? get currentRecommendation => _currentRecommendation;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get cooldownMinutes => _cooldownMinutes;
  bool get isBreakInProgress => _isBreakInProgress;
  BreakCoachRecommendation? get acceptedRecommendation => _acceptedRecommendation;

  /// Load preferences from SharedPreferences
  Future<void> loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool(_prefBreakCoachEnabled) ?? _defaultEnabled;
    _cooldownMinutes =
        prefs.getInt(_prefCooldownMinutes) ?? _defaultCooldownMinutes;

    // Parse snooze until
    final snoozeUntilStr = prefs.getString(_prefSnoozeUntil);
    if (snoozeUntilStr != null) {
      try {
        _snoozeUntil = DateTime.parse(snoozeUntilStr);
      } catch (e) {
        _snoozeUntil = null;
      }
    }

    // Parse last dismissed at
    final lastDismissedStr = prefs.getString(_prefLastDismissedAt);
    if (lastDismissedStr != null) {
      try {
        _lastDismissedAt = DateTime.parse(lastDismissedStr);
      } catch (e) {
        _lastDismissedAt = null;
      }
    }

    // Parse dismissed recommendation ID
    final dismissedRecIdStr = prefs.getString(_prefDismissedRecommendationId);
    if (dismissedRecIdStr != null && dismissedRecIdStr.isNotEmpty) {
      _dismissedRecommendationId = dismissedRecIdStr;
    }

    // Parse dismissed at timestamp
    final dismissedAtStr = prefs.getString(_prefDismissedAt);
    if (dismissedAtStr != null) {
      try {
        _dismissedAt = DateTime.parse(dismissedAtStr);
      } catch (e) {
        _dismissedAt = null;
      }
    }

    notifyListeners();
  }

  /// Attach to WorkSessionProvider for reactive updates.
  /// Listens to session/break/task state changes and re-evaluates the
  /// recommendation when thresholds may have been crossed.
  void attachSessionProvider(WorkSessionProvider sessionProvider) {
    if (_sessionProvider == sessionProvider) return;
    _sessionProvider = sessionProvider;
    _sessionListener ??= () => _onSessionProviderChanged();
    sessionProvider.addListener(_sessionListener!);
    debugPrint('[BREAK-COACH] Attached to WorkSessionProvider');
    // Evaluate current session immediately on attach (handles reload / initialization)
    if (sessionProvider.isActive || sessionProvider.isOnBreak) {
      _onSessionProviderChanged();
    }
  }

  /// Detach from WorkSessionProvider to prevent leaks.
  void detachSessionProvider() {
    if (_sessionProvider != null && _sessionListener != null) {
      _sessionProvider!.removeListener(_sessionListener!);
      _sessionProvider = null;
      _evaluationTimer?.cancel();
      _evaluationTimer = null;
      debugPrint('[BREAK-COACH] Detached from WorkSessionProvider');
    }
  }

  /// Called when WorkSessionProvider notifies its listeners.
  /// Re-evaluates the recommendation if the session state has changed in a
  /// way that could affect break eligibility.
  void _onSessionProviderChanged() {
    final sp = _sessionProvider;
    if (sp == null) return;
    debugPrint('[BREAK-COACH] WorkSessionProvider changed: isActive=${sp.isActive}, isOnBreak=${sp.isOnBreak}');

    // If session ended, clear recommendation state AND dismissed state for new session
    if (!sp.isActive) {
      clearState();
      _clearDismissedState();
      return;
    }

    // If break started, show break guidance (preserve any exceeded-break notification)
    if (sp.isOnBreak) {
      _isBreakInProgress = true;
      // Don't automatically set _isVisible = true - let evaluation determine visibility
      // if (_acceptedRecommendation == null && _currentRecommendation != null) {
      //   _acceptedRecommendation = _currentRecommendation;
      // }
      notifyListeners();
      // Still evaluate duration rules during active break so exceeded-break can appear
      _scheduleEvaluation();
      return;
    }

    // If break ended, re-evaluate recommendation
    if (_isBreakInProgress) {
      _isBreakInProgress = false;
      _acceptedRecommendation = null;
      _currentRecommendation = null;
      _isVisible = false;
      notifyListeners();
    }

    // Re-evaluate recommendation on session state change (debounced)
    _scheduleEvaluation();
  }

  /// Debounced evaluation to avoid excessive backend requests.
  void _scheduleEvaluation() {
    _evaluationTimer?.cancel();
    _evaluationTimer = Timer(const Duration(milliseconds: 500), () {
      // Invalidate any pending request when scheduling a new evaluation
      _requestToken++;
      _evaluateActiveSession();
    });
  }

  Timer? _evaluationTimer;

  int _requestToken = 0;

  /// Evaluate recommendation for the currently active session.
  /// Uses the existing service with the current token.
  Future<void> _evaluateActiveSession() async {
    final sp = _sessionProvider;
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    // Allow evaluation during active break for exceeded-break detection
    if (token == null || sp == null || !sp.isActive) {
      return;
    }

    // Avoid duplicate evaluation if already loading
    if (_isLoading) return;

    // Do not treat temporary loading absence as no-recommendation (wait for data)
    if (sp.isLoading && _currentRecommendation == null) {
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Respect notification settings (same as checkRecommendation)
      if (!_isEnabled || isSnoozed || isInCooldown) {
        _isLoading = false;
        notifyListeners();
        return;
      }

      final currentToken = ++_requestToken;

      final recommendation = await _service.getRecommendation(token);

      // Check if evaluation is still valid after async call
      // Allow evaluation to complete even if we're now on break (for break duration exceeded detection)
      if (_requestToken != currentToken ||
          _sessionProvider != sp ||
          !sp.isActive ||
          !_isLoading) {
        _isLoading = false;
        notifyListeners();
        return;
      }

      if (recommendation == null) {
        // Service found no reason for a new recommendation
        // Clear the current recommendation and hide the notification
        _currentRecommendation = null;
        _isVisible = false;
        debugPrint('[BREAK-COACH] Evaluation produced no recommendation');
      } else {
        // Check if this recommendation was already dismissed in this session
        if (recommendation.recommendationId.isNotEmpty &&
            _dismissedRecommendationId != null &&
            recommendation.recommendationId == _dismissedRecommendationId) {
          debugPrint('[BREAK-COACH] Skipping already dismissed recommendation: ${recommendation.recommendationId}');
          await _clearDismissedState();
          _currentRecommendation = null;
          _isVisible = false;
        } else {
          final isColdStartBaseline = recommendation.reason.toLowerCase().contains('cold-start baseline');
          final currentType = _currentRecommendation?.type;

          if (!isColdStartBaseline &&
              recommendation.type != currentType) {
            _currentRecommendation = recommendation;
            _isVisible = true;
            debugPrint('[BREAK-COACH] Evaluation produced recommendation: ${recommendation.title}');
          } else {
            if (isColdStartBaseline) {
              _currentRecommendation = null;
              _isVisible = false;
              debugPrint('[BREAK-COACH] Cold-start baseline cleared');
            } else if (sp.isOnBreak && recommendation.trigger == BreakCoachTrigger.breakDurationExceeded) {
              _currentRecommendation = recommendation;
              _isVisible = true;
              debugPrint('[BREAK-COACH] Break exceeded preserved on active break');
            } else {
              _currentRecommendation = _currentRecommendation; // keep existing
              _isVisible = true;
              debugPrint('[BREAK-COACH] Recommendation same type retained');
            }
          }
        }
      }
    } catch (e) {
      _error = e.toString();
      debugPrint('[BREAK-COACH] Evaluation error: $_error');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Check if snooze is active
  bool get isSnoozed {
    if (_snoozeUntil == null) return false;
    return DateTime.now().isBefore(_snoozeUntil!);
  }

  /// Check if in cooldown period
  bool get isInCooldown {
    if (_lastDismissedAt == null) return false;
    final cooldownEnd = _lastDismissedAt!.add(Duration(minutes: _cooldownMinutes));
    return DateTime.now().isBefore(cooldownEnd);
  }

  /// Enable or disable Break Coach
  Future<void> setEnabled(bool value) async {
    _isEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefBreakCoachEnabled, value);
    notifyListeners();
  }

  /// Set cooldown duration in minutes
  Future<void> setCooldownMinutes(int minutes) async {
    _cooldownMinutes = minutes;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefCooldownMinutes, minutes);
    notifyListeners();
  }

  /// Snooze the current recommendation
  Future<void> snooze() async {
    final rec = _currentRecommendation;

    // Send feedback to backend (treated as ignored with snooze intent)
    if (rec != null && rec.recommendationId.isNotEmpty) {
      try {
        await _recommendationService.submitFeedback(rec.recommendationId, 'ignored');
        debugPrint('[RECOMMEND-STATE] Feedback sent: ignored (snoozed)');
      } catch (e) {
        debugPrint('[RECOMMEND-STATE] Failed to send snooze feedback: $e');
      }
    }

    final snoozeDuration = const Duration(minutes: 5);
    _snoozeUntil = DateTime.now().add(snoozeDuration);
    _isVisible = false;
    _currentRecommendation = null;

    // Persist snooze state
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefSnoozeUntil, _snoozeUntil!.toIso8601String());

    notifyListeners();
  }

  /// Ignore the current recommendation without snoozing
  Future<void> ignore() async {
    final rec = _currentRecommendation;

    // Send feedback to backend as ignored
    if (rec != null && rec.recommendationId.isNotEmpty) {
      try {
        await _recommendationService.submitFeedback(rec.recommendationId, 'ignored');
        debugPrint('[RECOMMEND-STATE] Feedback sent: ignored');
      } catch (e) {
        debugPrint('[RECOMMEND-STATE] Failed to send ignore feedback: $e');
      }
    }

    _isVisible = false;
    _currentRecommendation = null;
    // Do not set snooze or dismissed state
    notifyListeners();
  }

  /// Dismiss the recommendation (Continue button)
  Future<void> dismiss() async {
    final rec = _currentRecommendation;

    // Send feedback to backend before dismissing
    if (rec != null && rec.recommendationId.isNotEmpty) {
      try {
        await _recommendationService.submitFeedback(rec.recommendationId, 'dismissed');
        debugPrint('[RECOMMEND-STATE] Feedback sent: dismissed');
      } catch (e) {
        debugPrint('[RECOMMEND-STATE] Failed to send dismissal feedback: $e');
      }
    }

    _isVisible = false;
    _currentRecommendation = null;
    _lastDismissedAt = DateTime.now();
    _dismissedRecommendationId = rec?.recommendationId;
    _dismissedAt = DateTime.now();

    // Persist dismissal state
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefLastDismissedAt, _lastDismissedAt!.toIso8601String());
    if (_dismissedRecommendationId != null && _dismissedRecommendationId!.isNotEmpty) {
      await prefs.setString(_prefDismissedRecommendationId, _dismissedRecommendationId!);
    }
    await prefs.setString(_prefDismissedAt, _dismissedAt!.toIso8601String());

    notifyListeners();
  }

  /// Hide notification without recording action
  void hide() {
    _isVisible = false;
    notifyListeners();
  }

  /// Clear snooze state
  Future<void> clearSnooze() async {
    _snoozeUntil = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefSnoozeUntil);
    notifyListeners();
  }

  /// Clear dismissed recommendation state
  Future<void> _clearDismissedState() async {
    _dismissedRecommendationId = null;
    _dismissedAt = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefDismissedRecommendationId);
    await prefs.remove(_prefDismissedAt);
  }

  /// Clear all state (call when session ends)
  void clearState() {
    _evaluationTimer?.cancel();
    _evaluationTimer = null;
    _isVisible = false;
    _currentRecommendation = null;
    _error = null;
    // Note: We keep dismissed state to prevent re-showing after refresh
    notifyListeners();
  }

  /// Set break-in-progress from existing active session break (no new start)
  void setBreakInProgressFromActiveBreak() {
    _isBreakInProgress = true;
    _isVisible = true;
    notifyListeners();
  }

  /// Check if a break recommendation should be shown
  Future<void> checkRecommendation(String token, {WorkSessionProvider? sessionProvider}) async {
    final sp = sessionProvider;
    if (sp != null && sp.isOnBreak) {
      // When an active break exists, show break guidance instead of recommendation
      _isBreakInProgress = true;
      _isVisible = true;
      if (_acceptedRecommendation == null && _currentRecommendation != null) {
        _acceptedRecommendation = _currentRecommendation; // preserve guidance from accepted rec
      }
      notifyListeners();
      // Still evaluate duration rules during active break so exceeded-break can appear
      _scheduleEvaluation();
      return;
    }

    // Existing recommendation-check logic continues...
    debugPrint('[RECOMMEND-STATE] checkRecommendation() called on instance $hashCode');

    // Don't check if disabled, snoozed, or in cooldown
    if (!_isEnabled || isSnoozed || isInCooldown) {
      debugPrint('[RECOMMEND-STATE] Skipped: enabled=$_isEnabled, snoozed=$isSnoozed, cooldown=$isInCooldown');
      return;
    }

    if (_isLoading) {
      debugPrint('[RECOMMEND-STATE] Already loading, returning early');
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();
    debugPrint('[RECOMMEND-STATE] Set loading to true');

    try {
      // First, try to retrieve existing backend recommendation
      debugPrint('[RECOMMEND-STATE] Calling _service.getRecommendation');
      final existingRecommendation = await _service.getRecommendation(token);

      debugPrint('[RECOMMEND-STATE] Existing recommendation: ${existingRecommendation != null}');

      // Check if this recommendation was already dismissed in this session
      if (existingRecommendation != null &&
          existingRecommendation.recommendationId.isNotEmpty &&
          _dismissedRecommendationId != null &&
          existingRecommendation.recommendationId == _dismissedRecommendationId) {
        debugPrint('[RECOMMEND-STATE] Skipping already dismissed recommendation: ${existingRecommendation.recommendationId}');
        // Clear the dismissed state since we're checking a new evaluation cycle
        await _clearDismissedState();
        // Don't show this recommendation
        _currentRecommendation = null;
        _isVisible = false;
        _isLoading = false;
        notifyListeners();
        return;
      }

      if (existingRecommendation != null) {
        // Use existing recommendation
        _currentRecommendation = existingRecommendation;
        _isVisible = true;
        debugPrint('[RECOMMEND-STATE] Set existing recommendation: ${existingRecommendation.title}');
        debugPrint('[RECOMMEND-STATE] _isVisible=$_isVisible, _currentRecommendation=${_currentRecommendation?.title}');
      } else {
        // No existing recommendation found - generate a new one if we should
        debugPrint('[RECOMMEND-STATE] Calling _service.shouldGenerateRecommendation');
        final shouldGenerate = await _service.shouldGenerateRecommendation(token);

        debugPrint('[RECOMMEND-STATE] shouldGenerateRecommendation: $shouldGenerate');

        if (shouldGenerate) {
          debugPrint('[RECOMMEND-STATE] Calling _service.generateNewRecommendation');

          // Generate new recommendation via backend
          final generatedRecommendation = await _service.generateNewRecommendation(token);

          debugPrint('[RECOMMEND-STATE] Generation result: ${generatedRecommendation != null}');
          if (generatedRecommendation != null) {
            debugPrint('[RECOMMEND-STATE] Recommendation generated: ${generatedRecommendation.title}');
          }

          if (generatedRecommendation != null) {
            _currentRecommendation = generatedRecommendation;
            _isVisible = true;
            debugPrint('[RECOMMEND-STATE] _currentRecommendation assigned: ${_currentRecommendation?.title}');
            debugPrint('[RECOMMEND-STATE] Set generated recommendation: ${generatedRecommendation.title}');
            debugPrint('[RECOMMEND-STATE] _isVisible=$_isVisible, _currentRecommendation=${_currentRecommendation?.title}');
          } else {
            debugPrint('[RECOMMEND-STATE] No recommendation generated');
          }
        } else {
          debugPrint('[RECOMMEND-STATE] Should not generate recommendation');
        }
      }
    } catch (e) {
      // Log error but don't show notification
      _error = e.toString();
      debugPrint('[RECOMMEND-STATE] Error: $_error');
    } finally {
      _isLoading = false;
      debugPrint('[RECOMMEND-STATE] Calling notifyListeners() - _isVisible=$_isVisible, rec=${_currentRecommendation?.title}');
      notifyListeners();
    }
  }

  /// Called when user takes a break - clears snooze and resets state
  void onBreakTaken() {
    _snoozeUntil = null;
    _lastDismissedAt = null;
    _dismissedRecommendationId = null;
    _dismissedAt = null;
    _currentRecommendation = null;
    _isVisible = false;
    _acceptedRecommendation = null;
    notifyListeners();
  }

  /// Accept the current recommendation and start the appropriate break.
  /// Returns true if break started successfully, false otherwise.
  Future<bool> acceptRecommendation(BuildContext context) async {
    // Get session provider from context (single source of truth)
    final sessionProvider = Provider.of<WorkSessionProvider>(context, listen: false);

    debugPrint('[RECOMMEND-ACTION] active session ID: ${sessionProvider.state.session?.id}');
    debugPrint('[RECOMMEND-ACTION] session provider found');

    final rec = _currentRecommendation;
    if (rec == null) {
      debugPrint('[RECOMMEND-ACTION] No recommendation to accept');
      return false;
    }

    debugPrint('[RECOMMEND-ACTION] Accepting recommendation: ${rec.recommendationId}');
    debugPrint('[RECOMMEND-ACTION] Suggested break type: ${rec.suggestedBreakType}');

    // 1. Resolve suggested break type
    final suggestedBreak = _parseBreakType(rec.suggestedBreakType);
    debugPrint('[RECOMMEND-ACTION] Parsed suggested break: $suggestedBreak');

    // 2. Determine which break to actually start
    BreakType? breakToStart;

    if (suggestedBreak != null) {
      final availability = sessionProvider.availabilityFor(suggestedBreak);
      debugPrint('[RECOMMEND-ACTION] Suggested break availability: ${availability.status}');

      if (availability.status == BreakStatus.available) {
        breakToStart = suggestedBreak;
        debugPrint('[RECOMMEND-ACTION] Using suggested break: $breakToStart');
      }
    }

    // 3. Fallback to next available break if suggested unavailable
    if (breakToStart == null) {
      breakToStart = _findNextAvailableBreak(sessionProvider);
      if (breakToStart != null) {
        debugPrint('[RECOMMEND-ACTION] Suggested break unavailable, falling back to: $breakToStart');
      }
    }

    // 4. If no breaks available at all, fail gracefully without dismissing
    if (breakToStart == null) {
      debugPrint('[RECOMMEND-ACTION] No breaks available, cannot accept recommendation');
      return false; // Do NOT dismiss recommendation
    }

    // 5. Start the break via WorkSessionProvider (single source of truth)
    try {
      debugPrint('[RECOMMEND-ACTION] Starting break: $breakToStart');
      await sessionProvider.startBreak(breakToStart, recommendationId: rec.recommendationId);
      debugPrint('[RECOMMEND-ACTION] startBreak SUCCESS');
      debugPrint('[RECOMMEND-ACTION] break API result: success');
    } catch (e) {
      debugPrint('[RECOMMEND-ACTION] Failed to start break: $e');
      debugPrint('[RECOMMEND-ACTION] break API result: failed - $e');
      return false; // Do NOT dismiss on error
    }

    // 6. Send feedback to backend (only after successful break start)
    if (rec.recommendationId.isNotEmpty) {
      try {
        await _recommendationService.submitFeedback(rec.recommendationId, 'accepted');
        debugPrint('[RECOMMEND-ACTION] Feedback sent: accepted');
        debugPrint('[RECOMMEND-ACTION]   suggested=${rec.suggestedBreakType}, actual=${breakToStart.wireName}');
        debugPrint('[RECOMMEND-ACTION] recommendation accepted');
      } catch (e) {
        debugPrint('[RECOMMEND-ACTION] Failed to send acceptance feedback: $e');
        // Don't fail the whole action if feedback fails
      }
    }

    // 7. Transition to break-in-progress state (keep recommendation visible for guidance)
    _isBreakInProgress = true;
    _acceptedRecommendation = rec;
    // Keep _currentRecommendation as the accepted recommendation for UI display
    _isVisible = true; // Keep visible to show break guidance
    debugPrint('[RECOMMEND-ACTION] startBreak SUCCESS');
    debugPrint('[RECOMMEND-ACTION] acceptedRecommendation = ${_acceptedRecommendation?.recommendationId}/${_acceptedRecommendation?.title}');
    debugPrint('[RECOMMEND-ACTION] isBreakInProgress = $_isBreakInProgress');
    notifyListeners();
    debugPrint('[BREAK-COACH] notifyListeners()');
    debugPrint('[RECOMMEND-ACTION] Recommendation accepted, transitioning to break-in-progress');
    debugPrint('[RECOMMEND-ACTION] break state entered');

    return true;
  }

  /// Accept a recommendation map from AIWellnessCard and start the appropriate break.
  Future<bool> acceptRecommendationMap(BuildContext context, Map<String, dynamic> recMap) async {
    final sessionProvider = Provider.of<WorkSessionProvider>(context, listen: false);
    if (!sessionProvider.state.isActive || sessionProvider.state.session == null) {
      debugPrint('[RECOMMEND-ACTION] No active work session found to start break.');
      return false;
    }

    final category = recMap['category']?.toString().toUpperCase() ?? '';
    final actionType = recMap['action_type']?.toString().toLowerCase() ?? '';
    final title = recMap['title']?.toString().toLowerCase() ?? '';

    BreakType breakType = BreakType.break1;
    if (category.contains('LUNCH') || actionType.contains('lunch') || title.contains('lunch')) {
      breakType = BreakType.lunch;
    } else if (actionType.contains('walk') || title.contains('walk')) {
      breakType = BreakType.break1;
    } else if (actionType.contains('stretch') || title.contains('stretch')) {
      breakType = BreakType.break1;
    } else if (actionType.contains('hydrate') || title.contains('hydrate')) {
      breakType = BreakType.break1;
    } else {
      breakType = _findNextAvailableBreak(sessionProvider) ?? BreakType.break1;
    }

    try {
      final recId = recMap['id']?.toString();
      await sessionProvider.startBreak(breakType, recommendationId: recId);

      if (recId != null && recId.isNotEmpty) {
        await _recommendationService.submitFeedback(recId, 'accepted');
      }

      _isBreakInProgress = true;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[RECOMMEND-ACTION] Failed to start break from map: $e');
      return false;
    }
  }

  /// Call when the break ends (user resumes work) to complete the recommendation lifecycle.
  Future<void> endBreak() async {
    _isBreakInProgress = false;
    _acceptedRecommendation = null;
    _currentRecommendation = null;
    _isVisible = false;
    _snoozeUntil = null;
    _lastDismissedAt = null;
    notifyListeners();
    debugPrint('[RECOMMEND-STATE] Break ended, recommendation completed');
  }

  /// Parse break type wire name to enum, returning null for unknown types
  BreakType? _parseBreakType(String wireName) {
    switch (wireName) {
      case 'BREAK_1':
        return BreakType.break1;
      case 'BREAK_2':
        return BreakType.break2;
      case 'LUNCH':
        return BreakType.lunch;
      case 'COACH_BREAK':
        return BreakType.coachBreak;
      case 'SHORT_BREAK':
        return BreakType.break1; // Map SHORT_BREAK to Break 1
      default:
        debugPrint('[RECOMMEND-ACTION] Unknown break type: $wireName');
        return null;
    }
  }

  /// Find the next available break according to business rules
  BreakType? _findNextAvailableBreak(WorkSessionProvider sessionProvider) {
    // Break precedence: Break1 → Break2 → Lunch → CoachBreak
    final precedence = [
      BreakType.break1,
      BreakType.break2,
      BreakType.lunch,
      BreakType.coachBreak,
    ];

    for (final type in precedence) {
      final availability = sessionProvider.availabilityFor(type);
      if (availability.status == BreakStatus.available) {
        return type;
      }
    }

    return null; // No breaks available
  }

  /// Real-time elapsed-time text for the recommendation (e.g. "Just now", "10 seconds ago")
  String? get elapsedText => _elapsedText;

  /// Start lightweight timer to update elapsed display without recreating card
  void startElapsedTimer() {
    _timer?.cancel();
    _updateElapsed();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _updateElapsed());
  }

  void _updateElapsed() {
    final rec = _currentRecommendation;
    if (rec == null) {
      _elapsedText = null;
      return;
    }
    final diff = DateTime.now().difference(rec.generatedAt);
    if (diff.inSeconds < 10) {
      _elapsedText = 'Just now';
    } else if (diff.inSeconds < 60) {
      _elapsedText = '${diff.inSeconds} seconds ago';
    } else if (diff.inMinutes < 2) {
      _elapsedText = '${diff.inMinutes} minute ago';
    } else {
      _elapsedText = '${diff.inMinutes} minutes ago';
    }
    notifyListeners();
  }

  void stopElapsedTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// Get human-readable status for debugging
  String getStatus() {
    return 'BreakCoachState(enabled: $_isEnabled, visible: $_isVisible, '
        'snoozed: $isSnoozed, cooldown: $isInCooldown, '
        'recommendation: ${_currentRecommendation?.type})';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    detachSessionProvider();
    super.dispose();
  }
}

/// Provider for Break Coach state
class BreakCoachProvider extends StatelessWidget {
  final Widget child;
  final BreakCoachState? mockState;

  const BreakCoachProvider({
    super.key,
    required this.child,
    this.mockState,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => mockState ?? BreakCoachState(),
      child: child,
    );
  }
}