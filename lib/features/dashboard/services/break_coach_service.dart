import 'package:intellibreak/features/dashboard/services/work_service.dart';
import 'package:intellibreak/features/dashboard/models/break_coach_models.dart';
import 'package:intellibreak/features/dashboard/services/recommendation_service.dart';
import 'package:intellibreak/features/auth/services/api_service.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';

/// Break Coach service that implements both deterministic rules and ML-based
/// break recommendations.
///
/// ML integration can be enabled/disabled via setMlEnabled().
class BreakCoachService {
  /// Helper method to safely parse timestamp strings
  /// Returns null if the input is null, empty, or invalid
  DateTime? _safeParseTimestamp(dynamic timestamp) {
    if (timestamp == null) return null;

    final timestampStr = timestamp.toString();
    if (timestampStr.isEmpty || timestampStr == 'null') return null;

    try {
      return DateTime.parse(timestampStr);
    } catch (e) {
      debugPrint('Invalid timestamp format: $timestampStr');
      return null;
    }
  }
  final WorkService _workService;
  final RecommendationService _recommendationService = RecommendationService();
  bool _mlEnabled = false;
  double _mlConfidenceThreshold = 0.7; // Minimum confidence to show ML recommendation

  // Rule thresholds (in minutes)
  static const int continuousWorkThreshold = 90; // Default: 90 minutes
  static const int highPriorityThreshold = 120; // Higher priority at 120 minutes
  static const int lunchThreshold = 180; // Suggest lunch at 180 minutes


  /// Enable or disable ML-based recommendations
  void setMlEnabled(bool enabled) {
    _mlEnabled = enabled;
  }

  /// Set the minimum confidence threshold for ML recommendations
  void setMlConfidenceThreshold(double threshold) {
    _mlConfidenceThreshold = threshold.clamp(0.0, 1.0);
  }

  BreakCoachService({WorkService? workService})
      : _workService = workService ?? WorkService();

  /// Get current time for calculations
  DateTime _now() => DateTime.now();

  /// Get the session duration in minutes
  Future<int> getSessionDurationMinutes(String token) async {
    final session = await _workService.getActiveSession(token);
    if (session == null) return 0;

    final startedAt = _safeParseTimestamp(session['started_at']);
    if (startedAt == null) {
      debugPrint('Session start time is missing or invalid');
      return 0;
    }
    final duration = _now().difference(startedAt.toLocal());
    return duration.inMinutes;
  }

  /// Get all breaks for the current session
  Future<List<dynamic>> getSessionBreaks(String token) async {
    final session = await _workService.getActiveSession(token);
    if (session == null) return [];

    return await _workService.getActiveSessionBreaks(token);
  }

  /// Check if any lunch break exists in the session
  Future<bool> hasLunchBreak(String token) async {
    final breaks = await getSessionBreaks(token);
    for (final breakItem in breaks) {
      if (breakItem is Map<String, dynamic>) {
        final breakType = breakItem['break_type']?.toString();
        if (breakType == 'LUNCH') {
          return true;
        }
      }
    }
    return false;
  }

  /// Get time since last break in minutes
  Future<int> getTimeSinceLastBreak(String token) async {
    final breaks = await getSessionBreaks(token);
    if (breaks.isEmpty) return await getSessionDurationMinutes(token);

    // Find the most recent break that has ended
    BreakTime? lastEndedBreak;
    BreakTime? lastActiveBreak;

    for (final breakItem in breaks) {
      if (breakItem is Map<String, dynamic>) {
        final startedAt = _safeParseTimestamp(breakItem['started_at']);
        final endedAt = breakItem['ended_at'] != null
            ? _safeParseTimestamp(breakItem['ended_at'])
            : null;

        if (endedAt != null && startedAt != null) {
          if (lastEndedBreak == null ||
              endedAt.isAfter(lastEndedBreak.startedAt)) {
            lastEndedBreak = BreakTime(startedAt, endedAt);
          }
        } else if (startedAt != null) {
          // This is an active break
          lastActiveBreak = BreakTime(startedAt, null);
        }
      }
    }

    // If there's an active break, return time since it started
    if (lastActiveBreak != null) {
      return _now().difference(lastActiveBreak.startedAt.toLocal()).inMinutes;
    }

    // If there's a last ended break, return time since it ended
    if (lastEndedBreak != null && lastEndedBreak.endedAt != null) {
      return _now().difference(lastEndedBreak.endedAt!.toLocal()).inMinutes;
    }

    // No breaks at all - return session duration
    return await getSessionDurationMinutes(token);
  }

  bool _isBreakActive(List<dynamic> breaks) {
    for (final item in breaks) {
      if (item is Map<String, dynamic>) {
        final endedAt = item['ended_at'];
        final startedAt = item['started_at'];
        if (endedAt == null && startedAt != null) return true;
      }
    }
    return false;
  }

  Future<int> _getContinuousWorkMinutesExcludingActiveBreak(String token, List<dynamic> breaks) async {
    // Find the most recent ended break; if none, use session start
    DateTime? baseline;
    for (final item in breaks) {
      if (item is Map<String, dynamic>) {
        final startedAt = _safeParseTimestamp(item['started_at']);
        final endedAt = item['ended_at'] != null ? _safeParseTimestamp(item['ended_at']) : null;
        if (endedAt != null && startedAt != null) {
          if (baseline == null || endedAt.isAfter(baseline)) {
            baseline = endedAt;
          }
        }
      }
    }
    final session = await _workService.getActiveSession(token);
    if (session == null) return 0;
    final sessionStarted = _safeParseTimestamp(session['started_at']);
    if (sessionStarted == null) return 0;
    final start = baseline ?? sessionStarted.toLocal();
    return _now().difference(start).inMinutes;
  }

  /// Get the most recent break time (started at)
  Future<int> getMostRecentBreakStartedAt(String token) async {
    final breaks = await getSessionBreaks(token);
    if (breaks.isEmpty) return 0;

    DateTime? mostRecent;
    for (final breakItem in breaks) {
      if (breakItem is Map<String, dynamic>) {
        final startedAt = DateTime.parse(breakItem['started_at'].toString());
        if (mostRecent == null || startedAt.isAfter(mostRecent)) {
          mostRecent = startedAt;
        }
      }
    }

    if (mostRecent == null) return 0;
    return _now().difference(mostRecent.toLocal()).inMinutes;
  }

  /// Check if we should trigger a short break recommendation
  Future<BreakCoachRecommendation?> checkContinuousWorkRule(
    int continuousWorkMinutes,
    int timeSinceLastBreak,
  ) async {
    // Check for high priority first (120+ minutes)
    if (continuousWorkMinutes >= highPriorityThreshold &&
        timeSinceLastBreak >= highPriorityThreshold) {
      return BreakCoachRecommendation(
        recommendationId: '',
        type: BreakCoachRecommendationType.shortBreak,
        title: 'Time for a break?',
        reason:
            'You\'ve been working continuously for $continuousWorkMinutes minutes. Consider taking a short break to recharge.',
        suggestedBreakType: 'BREAK_1',
        generatedAt: _now(),
        trigger: BreakCoachTrigger.ruleContinuousWorkHighPriority,
      );
    }

    // Check for normal priority (90+ minutes)
    if (continuousWorkMinutes >= continuousWorkThreshold &&
        timeSinceLastBreak >= continuousWorkThreshold) {
      return BreakCoachRecommendation(
        recommendationId: '',
        type: BreakCoachRecommendationType.shortBreak,
        title: 'Consider a short break',
        reason:
            'You\'ve been working for $continuousWorkMinutes minutes without a break. A short break might help you maintain focus.',
        suggestedBreakType: 'BREAK_1',
        generatedAt: _now(),
        trigger: BreakCoachTrigger.ruleContinuousWork,
      );
    }

    return null;
  }

  /// Check if we should trigger a lunch recommendation
  Future<BreakCoachRecommendation?> checkLunchRule(
    int continuousWorkMinutes,
    bool hasLunch,
  ) async {
    // Check for lunch threshold (180+ minutes without lunch)
    if (continuousWorkMinutes >= lunchThreshold && !hasLunch) {
      return BreakCoachRecommendation(
        recommendationId: '',
        type: BreakCoachRecommendationType.lunch,
        title: 'Lunch break time?',
        reason:
            'Your work session is $continuousWorkMinutes minutes long with no lunch break recorded. Consider taking a lunch break.',
        suggestedBreakType: 'LUNCH',
        generatedAt: _now(),
        trigger: BreakCoachTrigger.ruleLunchTime,
      );
    }

    return null;
  }

  /// Fetch recommendation from backend for active session, or user-level if no session
  Future<BreakCoachRecommendation?> getBackendRecommendation(String token) async {
    try {
      final session = await _workService.getActiveSession(token);
      if (session != null && session['id'] != null) {
        final sessionId = session['id'].toString();
        var result = await _workService.getSessionRecommendations(token, sessionId);
        var recommendations = List<dynamic>.from(result['items'] ?? []);

        // Only generate a new recommendation if one doesn't exist AND conditions warrant it
        if (recommendations.isEmpty) {
          final shouldGenerate = await shouldGenerateRecommendation(token);
          if (shouldGenerate) {
            try {
              await _recommendationService.generateRecommendation();
              result = await _workService.getSessionRecommendations(token, sessionId);
              recommendations = List<dynamic>.from(result['items'] ?? []);
            } catch (e) {
              debugPrint('Error generating recommendation for session: $e');
            }
          }
        }

        if (recommendations.isNotEmpty) {
          final rec = recommendations.first;
          final type = rec['recommendation_type']?.toString() ?? 'SHORT_BREAK';
          final title = type == 'SHORT_BREAK' ? 'Take a short recovery break.' : (type == 'LUNCH' ? 'Lunch break time?' : 'Wellness Recommendation');
          final reason = rec['reason']?.toString() ?? 'Based on current session patterns.';
          final recId = rec['recommendation_id']?.toString() ?? rec['id']?.toString() ?? '';
          return BreakCoachRecommendation(
            recommendationId: recId,
            type: type == 'SHORT_BREAK' ? BreakCoachRecommendationType.shortBreak : BreakCoachRecommendationType.lunch,
            title: title,
            reason: reason,
            suggestedBreakType: type == 'LUNCH' ? 'LUNCH' : 'BREAK_1',
            generatedAt: rec['timestamp'] != null ? DateTime.parse(rec['timestamp'].toString()) : DateTime.now(),
            trigger: BreakCoachTrigger.ruleContinuousWork,
          );
        }
      }
    } catch (e) {
      debugPrint('Backend recommendation fetch error: $e');
    }
    return null;
  }

  /// Check if active break exceeds configured duration + grace
  Future<BreakCoachRecommendation?> checkBreakDurationExceeded(
    List<dynamic> breaks,
    int shortBreakDurationMinutes,
    int graceMinutes,
  ) async {
    for (final item in breaks) {
      if (item is! Map<String, dynamic>) continue;
      final endedAt = item['ended_at'];
      final startedAt = _safeParseTimestamp(item['started_at']);
      final breakType = item['break_type']?.toString();
      if (endedAt != null || startedAt == null) {
        continue; // only active breaks
      }
      if (breakType == 'BREAK_1' || breakType == 'SHORT_BREAK' || breakType == 'COACH_BREAK') {
        final elapsed = _now().difference(startedAt.toLocal()).inMinutes;
        if (elapsed >= shortBreakDurationMinutes + graceMinutes) {
          return BreakCoachRecommendation(
            recommendationId: '',
            type: BreakCoachRecommendationType.shortBreak,
            title: 'Break duration exceeded',
            reason: 'Your break has exceeded its planned duration. Consider returning to work when ready.',
            suggestedBreakType: 'BREAK_1',
            generatedAt: _now(),
            trigger: BreakCoachTrigger.breakDurationExceeded,
          );
        }
      }
    }
    return null;
  }

  /// Check if lunch exceeds duration + grace (only if active lunch)
  Future<BreakCoachRecommendation?> checkLunchDurationExceeded(
    List<dynamic> breaks,
    int lunchDurationMinutes,
    int graceMinutes,
  ) async {
    for (final item in breaks) {
      if (item is! Map<String, dynamic>) continue;
      final endedAt = item['ended_at'];
      final startedAt = _safeParseTimestamp(item['started_at']);
      final breakType = item['break_type']?.toString();
      if (endedAt != null || startedAt == null) continue;
      if (breakType == 'LUNCH') {
        final elapsed = _now().difference(startedAt.toLocal()).inMinutes;
        if (elapsed >= lunchDurationMinutes + graceMinutes) {
          return BreakCoachRecommendation(
            recommendationId: '',
            type: BreakCoachRecommendationType.lunch,
            title: 'Lunch duration exceeded',
            reason: 'Your lunch break has exceeded its planned duration. Resume when you are ready.',
            suggestedBreakType: 'LUNCH',
            generatedAt: _now(),
            trigger: BreakCoachTrigger.lunchDurationExceeded,
          );
        }
      }
    }
    return null;
  }

  /// Check for frequent completed short breaks in rolling window
  Future<BreakCoachRecommendation?> checkFrequentBreaks(
    List<dynamic> breaks,
    int countThreshold,
    int windowMinutes,
  ) async {
    final now = _now();
    int count = 0;
    for (final item in breaks) {
      if (item is! Map<String, dynamic>) continue;
      final endedAt = item['ended_at'];
      final startedAt = _safeParseTimestamp(item['started_at']);
      final breakType = item['break_type']?.toString();
      if (endedAt == null || startedAt == null) continue; // completed only
      if (breakType != 'BREAK_1' && breakType != 'SHORT_BREAK' && breakType != 'COACH_BREAK') continue;
      if (now.difference(endedAt.toLocal()).inMinutes <= windowMinutes) {
        count++;
      }
    }
    if (count >= countThreshold) {
      return BreakCoachRecommendation(
        recommendationId: '',
        type: BreakCoachRecommendationType.shortBreak,
        title: 'Frequent break check-in',
        reason: 'You\'ve taken several short breaks recently. Would a longer break help you reset?',
        suggestedBreakType: 'BREAK_1',
        generatedAt: now,
        trigger: BreakCoachTrigger.frequentBreakPattern,
      );
    }
    return null;
  }

  /// Check missed lunch using profile shift/schedule
  Future<BreakCoachRecommendation?> checkMissedLunch(
    List<dynamic> breaks,
    DateTime? sessionStartedAt,
    DateTime? sessionEndedAt,
    DateTime? shiftStartTime,
  ) async {
    if (sessionEndedAt != null) return null; // session ended
    if (shiftStartTime == null) return null; // no schedule configured
    final now = _now();
    // Lunch window: assume 4h after shift start to 6h after (configurable via settings if desired)
    final lunchWindowStart = shiftStartTime.add(const Duration(hours: 4));
    final lunchWindowEnd = shiftStartTime.add(const Duration(hours: 6));
    if (now.isBefore(lunchWindowEnd)) return null; // window hasn't passed
    bool hasLunch = false;
    for (final item in breaks) {
      if (item is! Map<String, dynamic>) continue;
      final breakType = item['break_type']?.toString();
      if (breakType == 'LUNCH') {
        final startedAt = _safeParseTimestamp(item['started_at']);
        if (startedAt != null && startedAt.isAfter(lunchWindowStart) && startedAt.isBefore(lunchWindowEnd)) {
          hasLunch = true;
          break;
        }
      }
    }
    if (!hasLunch) {
      return BreakCoachRecommendation(
        recommendationId: '',
        type: BreakCoachRecommendationType.lunch,
        title: 'Missed lunch',
        reason: 'Your lunch window has passed and no lunch break was recorded. Consider taking a break.',
        suggestedBreakType: 'LUNCH',
        generatedAt: now,
        trigger: BreakCoachTrigger.missedLunch,
      );
    }
    return null;
  }

  /// Check recovery reminder when session is long but break may help
  Future<BreakCoachRecommendation?> checkRecoveryReminder(
    int continuousWorkMinutes,
  ) async {
    if (continuousWorkMinutes >= 60 && continuousWorkMinutes < continuousWorkThreshold) {
      return BreakCoachRecommendation(
        recommendationId: '',
        type: BreakCoachRecommendationType.shortBreak,
        title: 'Recovery break reminder',
        reason: 'You\'ve been working for a while. A short break can help maintain focus.',
        suggestedBreakType: 'BREAK_1',
        generatedAt: _now(),
        trigger: BreakCoachTrigger.recoveryBreakReminder,
      );
    }
    return null;
  }

  /// Main method: Check all rules and return highest priority recommendation
  ///
  /// The rule priority is:
  /// 1. High priority continuous work (120+ min) - highest
  /// 2. ML-based recommendation (if enabled and confidence above threshold)
  /// 3. Lunch rule (180+ min without lunch)
  /// 4. Normal continuous work (90+ min)
  ///
  /// Returns null if no rule triggers.
  Future<BreakCoachRecommendation?> getRecommendation(String token) async {
    try {
      // Try backend first for active session recommendations
      final backendRec = await getBackendRecommendation(token);
      if (backendRec != null) {
        return backendRec;
      }
    } catch (e) {
      // Backend call failed, fall through to rule-based fallback
      debugPrint('Backend recommendation fetch failed: $e, falling back to rule-based');
    }

    // No backend recommendation available or backend call failed - try rule-based
    try {
      // Check if there's an active session
      final session = await _workService.getActiveSession(token);
      if (session == null) return null;

      // Get session duration and work patterns
      final breaks = await getSessionBreaks(token);
      final continuousWorkMinutes = _isBreakActive(breaks)
          ? await _getContinuousWorkMinutesExcludingActiveBreak(token, breaks)
          : await getSessionDurationMinutes(token);
      final timeSinceLastBreak = await getTimeSinceLastBreak(token);
      final hasLunch = await hasLunchBreak(token);

      // Existing continuous-work rules preserved (90 / 120)
      if (continuousWorkMinutes >= highPriorityThreshold && timeSinceLastBreak >= highPriorityThreshold) {
        return BreakCoachRecommendation(
          recommendationId: '',
          type: BreakCoachRecommendationType.shortBreak,
          title: 'Time for a break?',
          reason: 'You\'ve been working continuously for $continuousWorkMinutes minutes. Consider taking a short break to recharge.',
          suggestedBreakType: 'BREAK_1',
          generatedAt: _now(),
          trigger: BreakCoachTrigger.ruleContinuousWorkHighPriority,
        );
      }
      if (continuousWorkMinutes >= continuousWorkThreshold && timeSinceLastBreak >= continuousWorkThreshold) {
        return BreakCoachRecommendation(
          recommendationId: '',
          type: BreakCoachRecommendationType.shortBreak,
          title: 'Consider a short break',
          reason: 'You\'ve been working for $continuousWorkMinutes minutes without a break. A short break might help you maintain focus.',
          suggestedBreakType: 'BREAK_1',
          generatedAt: _now(),
          trigger: BreakCoachTrigger.ruleContinuousWork,
        );
      }

      // New notification rules (check active break independently)
      final breakExceeded = await checkBreakDurationExceeded(breaks, 10, 2); // 10m short + 2m grace
      if (breakExceeded != null) return breakExceeded;
      final lunchExceeded = await checkLunchDurationExceeded(breaks, 30, 5); // 30m lunch + 5m grace
      if (lunchExceeded != null) return lunchExceeded;
      final frequent = await checkFrequentBreaks(breaks, 3, 60);
      if (frequent != null) return frequent;
      final sessionStartedAt = _safeParseTimestamp(session['started_at']);
      final missed = await checkMissedLunch(breaks, sessionStartedAt, session['ended_at'], sessionStartedAt); // shift start derived from session start for demo
      if (missed != null) return missed;
      final recovery = await checkRecoveryReminder(continuousWorkMinutes);
      if (recovery != null) return recovery;

      // No rule-based recommendation applies — check if we should generate a new one
      final shouldGenerate = await shouldGenerateRecommendation(token);
      if (!shouldGenerate) {
        return null;
      }

      // Attempt backend persistence via generate
      try {
        final generated = await generateNewRecommendation(token);
        if (generated != null) {
          return generated;
        }
      } catch (e) {
        debugPrint('Backend persistence after rules failed: $e');
      }
      return null;
    } catch (e) {
      debugPrint('Rule-based recommendation failed: $e');
      return null;
    }
  }

  /// Check if we should generate a new recommendation
  /// Returns true if conditions are met for recommendation generation
  Future<bool> shouldGenerateRecommendation(String token) async {
    // Check if there's an active session
    final session = await _workService.getActiveSession(token);
    if (session == null) return false;

    // Check session duration and work patterns to determine if generation is warranted
    final continuousWorkMinutes = await getSessionDurationMinutes(token);
    final timeSinceLastBreak = await getTimeSinceLastBreak(token);

    // Generate if continuous work exceeds threshold OR significant time since last break
    return continuousWorkMinutes >= continuousWorkThreshold ||
           timeSinceLastBreak >= continuousWorkThreshold;
  }

  /// Generate a new recommendation via backend API
  Future<BreakCoachRecommendation?> generateNewRecommendation(String token) async {
    try {
      // Use RecommendationService to generate recommendation via backend API
      final recommendationService = RecommendationService();
      final result = await recommendationService.generateRecommendation();

      // Parse the generated recommendation
      final type = result['candidate_type']?.toString() ?? 'SHORT_BREAK';
      final title = type == 'SHORT_BREAK' ? 'Take a short recovery break' : (type == 'LUNCH' ? 'Lunch break time?' : 'Wellness Recommendation');
      final reason = result['reason']?.toString() ?? 'Based on current session patterns.';
      final timestamp = result['timestamp'] != null ? DateTime.parse(result['timestamp'].toString()) : DateTime.now();
      final recId = result['recommendation_id']?.toString() ?? '';
      final recommendationMethod = result['recommendation_method']?.toString();
      final mlUsedRaw = result['ml_used'];
      final bool? mlUsed = mlUsedRaw is bool ? mlUsedRaw : (mlUsedRaw is String ? mlUsedRaw.toLowerCase() == 'true' : null);

      return BreakCoachRecommendation(
        recommendationId: recId,
        type: type == 'SHORT_BREAK' ? BreakCoachRecommendationType.shortBreak : BreakCoachRecommendationType.lunch,
        title: title,
        reason: reason,
        recommendationMethod: recommendationMethod,
        mlUsed: mlUsed,
        suggestedBreakType: type == 'LUNCH' ? 'LUNCH' : 'BREAK_1',
        generatedAt: timestamp,
        trigger: BreakCoachTrigger.ruleContinuousWork,
      );
    } catch (e) {
      debugPrint('Generate new recommendation error: $e');
      return null;
    }
  }

  /// Get ML-based recommendation for work pattern decline
  Future<BreakCoachRecommendation?> _getMlRecommendation(String token) async {
    try {
      // Call the ML prediction service via ApiService
      final result = await ApiService().postWithAuth(
        '/ml/predict-decline',
        token,
        {'token': token},
      );

      // postWithAuth returns parsed JSON; reconstruct simple response shape
      final responseData = result;
      final int statusCode = 200; // postWithAuth throws on non-2xx
      final String body = jsonEncode(responseData);

      if (statusCode == 200) {
        final data = jsonDecode(body);
        final double confidence = data['decline_probability']?.toDouble() ?? 0.0;

        // Only return recommendation if confidence meets threshold
        if (confidence >= _mlConfidenceThreshold) {
          return BreakCoachRecommendation(
            recommendationId: '',
            type: BreakCoachRecommendationType.shortBreak,
            title: 'ML suggests a break',
            reason:
                'Our ML model predicts a ${(confidence * 100).toStringAsFixed(0)}% chance of work pattern decline in the next 40 minutes. Consider taking a break.',
            suggestedBreakType: 'BREAK_1',
            generatedAt: _now(),
            trigger: BreakCoachTrigger.mlPrediction,
            mlConfidence: confidence,
          );
        }
      }
    } catch (e) {
      // Log error but don't break the service
      debugPrint('ML recommendation error: $e');
    }
    return null;
  }
}

/// Helper class to track break timing
class BreakTime {
  final DateTime startedAt;
  final DateTime? endedAt;

  const BreakTime(this.startedAt, this.endedAt);
}