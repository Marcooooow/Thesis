import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Represents a work session from the backend
class WorkSession {
  final String id;
  final DateTime startedAt;
  final DateTime? endedAt;

  WorkSession({
    required this.id,
    required this.startedAt,
    this.endedAt,
  });

  factory WorkSession.fromJson(Map<String, dynamic> json) {
    return WorkSession(
      id: json['id'].toString(),
      startedAt: _parseDateTime(json['started_at']),
      endedAt: json['ended_at'] != null
          ? _parseDateTime(json['ended_at'])
          : null,
    );
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value is int) {
      // Unix timestamp in milliseconds
      return DateTime.fromMillisecondsSinceEpoch(value);
    } else if (value is String) {
      // ISO 8601 string
      return DateTime.parse(value).toLocal();
    } else {
      throw FormatException('Unable to parse datetime: $value');
    }
  }
}

/// Represents a break from the backend
class WorkBreak {
  final String id;
  final String workSessionId;
  final BreakType type;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int? durationMinutes;

  WorkBreak({
    required this.id,
    required this.workSessionId,
    required this.type,
    required this.startedAt,
    this.endedAt,
    this.durationMinutes,
  });

  factory WorkBreak.fromJson(Map<String, dynamic> json) {
    return WorkBreak(
      id: json['id'].toString(),
      workSessionId: json['work_session_id'].toString(),
      type: BreakType.fromWire(json['break_type']),
      startedAt: _parseDateTime(json['started_at']),
      endedAt: json['ended_at'] != null
          ? _parseDateTime(json['ended_at'])
          : null,
      durationMinutes: json['duration_minutes'] as int?,
    );
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value is int) {
      // Unix timestamp in milliseconds
      return DateTime.fromMillisecondsSinceEpoch(value);
    } else if (value is String) {
      // ISO 8601 string
      return DateTime.parse(value).toLocal();
    } else {
      throw FormatException('Unable to parse datetime: $value');
    }
  }
}

/// Represents a task from the backend
class WorkTask {
  final String id;
  final String title;
  final String category;
  final String status;
  final String? workSessionId;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int? actualMinutes;

  WorkTask({
    required this.id,
    required this.title,
    required this.category,
    required this.status,
    this.workSessionId,
    this.startedAt,
    this.endedAt,
    this.actualMinutes,
  });

  factory WorkTask.fromJson(Map<String, dynamic> json) {
    return WorkTask(
      id: json['id'].toString(),
      title: json['title'] ?? '',
      category: json['category'] ?? 'General',
      status: json['status'] ?? 'TODO',
      workSessionId: json['work_session_id'] != null
          ? json['work_session_id'].toString()
          : null,
      startedAt: json['started_at'] != null
          ? _parseDateTime(json['started_at'])
          : null,
      endedAt: json['ended_at'] != null
          ? _parseDateTime(json['ended_at'])
          : null,
      actualMinutes: json['actual_minutes'] as int?,
    );
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value is int) {
      // Unix timestamp in milliseconds
      return DateTime.fromMillisecondsSinceEpoch(value);
    } else if (value is String) {
      // ISO 8601 string
      return DateTime.parse(value).toLocal();
    } else {
      throw FormatException('Unable to parse datetime: $value');
    }
  }
}

/// Types of breaks supported by the system
enum BreakType {
  breakGeneric('BREAK'),
  break1('BREAK_1'),
  break2('BREAK_2'),
  lunch('LUNCH'),
  meal('MEAL'),
  coachBreak('COACH_BREAK'),
  other('OTHER');

  final String wireName;

  const BreakType(this.wireName);

  static BreakType fromWire(String? wireName) {
    if (wireName == null) return BreakType.breakGeneric;
    return BreakType.values.firstWhere(
      (e) => e.wireName == wireName,
      orElse: () => BreakType.breakGeneric,
    );
  }

  String get label {
    switch (this) {
      case BreakType.breakGeneric:
        return 'Break';
      case BreakType.break1:
        return 'Break 1';
      case BreakType.break2:
        return 'Break 2';
      case BreakType.lunch:
        return 'Lunch';
      case BreakType.meal:
        return 'Meal';
      case BreakType.coachBreak:
        return 'Coach Break';
      case BreakType.other:
        return 'Away';
    }
  }

  IconData get icon {
    switch (this) {
      case BreakType.breakGeneric:
        return Icons.coffee_outlined;
      case BreakType.break1:
        return Icons.coffee_outlined;
      case BreakType.break2:
        return Icons.nightlight_round_outlined;
      case BreakType.lunch:
        return Icons.local_dining_outlined;
      case BreakType.meal:
        return Icons.restaurant_outlined;
      case BreakType.coachBreak:
        return Icons.self_improvement_outlined;
      case BreakType.other:
        return Icons.access_time_outlined;
    }
  }
}

/// Represents the availability status of a break
class BreakAvailability {
  final BreakStatus status;
  final String? reason;

  const BreakAvailability({
    required this.status,
    this.reason,
  });

  factory BreakAvailability.available() =>
      const BreakAvailability(status: BreakStatus.available);

  factory BreakAvailability.active() =>
      const BreakAvailability(status: BreakStatus.active);

  factory BreakAvailability.completed() =>
      const BreakAvailability(status: BreakStatus.completed);

  factory BreakAvailability.disabled(String reason) =>
      BreakAvailability(status: BreakStatus.disabled, reason: reason);
}

/// Status of break availability
enum BreakStatus {
  available,
  active,
  completed,
  disabled;
}

/// State held by WorkSessionProvider
@immutable
class WorkSessionState {
  final WorkSession? session;
  final WorkBreak? activeBreak;
  final List<WorkBreak> completedBreaks;
  final WorkTask? currentTask;
  final List<WorkTask?> tasks;
  final bool isLoading;
  final String? lastError;

  const WorkSessionState({
    this.session,
    this.activeBreak,
    this.completedBreaks = const [],
    this.currentTask,
    this.tasks = const [],
    this.isLoading = false,
    this.lastError,
  });

  bool get isActive => session != null;
  bool get isOnBreak => activeBreak != null;
  BreakType? get breakType => activeBreak?.type;
  DateTime? get startTime {
    final st = session?.startedAt;
    debugPrint('[WorkSessionState] startTime getter: session?.startedAt = $st');
    return st;
  }
  int? get elapsedTimeInSeconds {
    if (!isActive || startTime == null) return null;
    return DateTime.now().difference(startTime!).inSeconds;
  }

  /// Derive active meeting from task list (category='Meeting', active/un-ended)
  WorkTask? get meetingTask {
    final sid = session?.id;
    if (tasks.isEmpty) return null;
    for (final t in tasks) {
      if (t == null) continue;
      if (t.category == 'Meeting' && t.endedAt == null) {
        if (sid == null || t.workSessionId == null || t.workSessionId == sid) {
          return t; // active meeting
        }
      }
    }
    return null;
  }

  DateTime? get meetingStartedAt => meetingTask?.startedAt;
  DateTime? get meetingEndedAt => meetingTask?.endedAt;

  /// Set of break types that have been completed in this session
  Set<BreakType> get breaksTaken =>
      completedBreaks.map((b) => b.type).toSet();

  /// Returns an unfinished task (either current task or a TODO task from history)
  // Note: This would typically require access to task history,
  // so this is a simplified version - full implementation would need task list
  WorkTask? get unfinishedTask => currentTask;

  WorkSessionState copyWith({
    WorkSession? session,
    WorkBreak? activeBreak,
    List<WorkBreak>? completedBreaks,
    WorkTask? currentTask,
    List<WorkTask>? tasks,
    bool? isLoading,
    String? lastError,
  }) {
    return WorkSessionState(
      session: session ?? this.session,
      activeBreak: activeBreak ?? this.activeBreak,
      completedBreaks: completedBreaks ?? this.completedBreaks,
      currentTask: currentTask ?? this.currentTask,
      tasks: tasks ?? this.tasks,
      isLoading: isLoading ?? this.isLoading,
      lastError: lastError ?? this.lastError,
    );
  }

  /// Empty state representing no active session
  static const WorkSessionState empty = WorkSessionState();

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WorkSessionState &&
        other.session == session &&
        other.activeBreak == activeBreak &&
        listEquals(other.completedBreaks, completedBreaks) &&
        other.currentTask == currentTask &&
        other.isLoading == isLoading &&
        other.lastError == lastError;
  }

  @override
  int get hashCode =>
      Object.hash(session, activeBreak, Object.hashAll(completedBreaks),
          currentTask, isLoading, lastError);
}