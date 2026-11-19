/// Break Coach data models for rule-based break recommendations
///
/// These models support the deterministic rule engine that suggests breaks
/// based on observable work session and break patterns.
library;
import 'package:flutter/material.dart';

enum BreakCoachTrigger {
  /// 90+ minutes continuous work without a break
  ruleContinuousWork,
  /// 120+ minutes continuous work (higher priority)
  ruleContinuousWorkHighPriority,
  /// 180+ minutes without lunch
  ruleLunchTime,
  /// Future: ML-based prediction (not implemented in Phase 1)
  mlPrediction,
  /// Break exceeded configured duration + grace
  breakDurationExceeded,
  /// Lunch exceeded configured duration + grace
  lunchDurationExceeded,
  /// Frequent short-break pattern detected
  frequentBreakPattern,
  /// Recovery reminder (optional / session-based)
  recoveryBreakReminder,
  /// Lunch reminder when window approaching / missed
  lunchReminder,
  /// Missed lunch after window passed
  missedLunch,
}

enum BreakCoachRecommendationType {
  shortBreak,
  walk,
  hydrate,
  stretch,
  lunch,
}

/// Represents a Break Coach recommendation to be shown to the user
class BreakCoachRecommendation {
  final String recommendationId;
  final BreakCoachRecommendationType type;
  final String title;
  final String reason;
  final String suggestedBreakType; // BREAK_1, BREAK_2, LUNCH
  final DateTime generatedAt;
  final BreakCoachTrigger trigger;
  /// For ML-based recommendations: probability of decline (0.0 to 1.0)
  final double? mlConfidence;
  /// Provenance of recommendation: 'heuristic', 'ml_enhanced', 'heuristic_fallback'
  final String? recommendationMethod;
  /// Whether ML scoring actually influenced this recommendation
  final bool? mlUsed;

  const BreakCoachRecommendation({
    required this.recommendationId,
    required this.type,
    required this.title,
    required this.reason,
    required this.suggestedBreakType,
    required this.generatedAt,
    required this.trigger,
    this.mlConfidence,
    this.recommendationMethod,
    this.mlUsed,
  });

  /// Generates human-readable guidance content for the break based on recommendation type
  String generateBreakGuidance() {
    final duration = _getRecommendedDuration();
    final tips = _getBreakTips();
    return '''
You're on a ${_getBreakTypeName().toLowerCase()}
Take $duration to reset before returning to work.
Try this:
$tips
'''.trim();
  }

  String _getBreakTypeName() {
    switch (type) {
      case BreakCoachRecommendationType.shortBreak:
        return 'Short Recovery Break';
      case BreakCoachRecommendationType.walk:
        return 'Walk Break';
      case BreakCoachRecommendationType.hydrate:
        return 'Hydration Break';
      case BreakCoachRecommendationType.stretch:
        return 'Stretch / Movement Break';
      case BreakCoachRecommendationType.lunch:
        return 'Lunch Break';
    }
    return 'Break';
  }

  String _getRecommendedDuration() {
    switch (type) {
      case BreakCoachRecommendationType.shortBreak:
        return '5 minutes';
      case BreakCoachRecommendationType.walk:
        return '10 minutes';
      case BreakCoachRecommendationType.hydrate:
        return '2 minutes';
      case BreakCoachRecommendationType.stretch:
        return '5 minutes';
      case BreakCoachRecommendationType.lunch:
        return '30 minutes';
    }
    return '5 minutes';
  }

  String _getBreakTips() {
    switch (type) {
      case BreakCoachRecommendationType.shortBreak:
        return '''
- Step away from your screen
- Stretch your shoulders and neck
- Take a few slow breaths
- Get some water''';
      case BreakCoachRecommendationType.walk:
        return '''
- Go for a brief walk outside or around your workspace
- Look at distant objects to rest your eyes
- Swing your arms gently to improve circulation
- Listen to calming music or podcast''';
      case BreakCoachRecommendationType.hydrate:
        return '''
- Drink a glass of water
- Consider herbal tea or infused water
- Avoid sugary drinks or excessive caffeine
- Use this time to refill your water bottle''';
      case BreakCoachRecommendationType.stretch:
        return '''
- Neck rolls: slowly rotate head clockwise and counterclockwise
- Shoulder shrugs: lift shoulders up to ears and release
- Wrist stretches: extend arms, pull fingers back gently
- Standing forward bend: let upper body hang loose''';
      case BreakCoachRecommendationType.lunch:
        return '''
- Eat a balanced meal away from your workspace
- Include protein, vegetables, and complex carbohydrates
- Take time to chew slowly and mindfully
- Consider a short walk after eating if possible''';
      default:
        return '''
- Step away from your screen
- Move your body gently
- Hydrate if needed
- Rest your eyes''';
    }
  }

  @override
  String toString() {
    return 'BreakCoachRecommendation(id: $recommendationId, type: $type, trigger: $trigger, title: $title)';
  }
}

/// Tracks snooze state for Break Coach
class BreakCoachSnoozeState {
  final DateTime? snoozedUntil;
  final DateTime? lastDismissedAt;

  const BreakCoachSnoozeState({
    this.snoozedUntil,
    this.lastDismissedAt,
  });

  bool get isSnoozed {
    if (snoozedUntil == null) return false;
    return DateTime.now().isBefore(snoozedUntil!);
  }

  bool isInCooldown(int cooldownMinutes) {
    if (lastDismissedAt == null) return false;
    final cooldownEnd = lastDismissedAt!.add(Duration(minutes: cooldownMinutes));
    return DateTime.now().isBefore(cooldownEnd);
  }

  BreakCoachSnoozeState copyWith({
    DateTime? snoozedUntil,
    DateTime? lastDismissedAt,
  }) {
    return BreakCoachSnoozeState(
      snoozedUntil: snoozedUntil ?? this.snoozedUntil,
      lastDismissedAt: lastDismissedAt ?? this.lastDismissedAt,
    );
  }

  @override
  String toString() {
    return 'BreakCoachSnoozeState(snoozedUntil: $snoozedUntil, lastDismissedAt: $lastDismissedAt)';
  }
}