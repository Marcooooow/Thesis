import 'package:intellibreak/providers/work_session_models.dart';

/// Utility class for calculating analytics metrics, mirroring the backend's logic.
class AnalyticsUtils {
  /// Merges overlapping or touching time intervals.
  static List<Interval> mergeIntervals(List<Interval> intervals) {
    if (intervals.isEmpty) return [];
    // Sort intervals by start time
    final List<Interval> sorted = List.from(intervals)..sort((a, b) => a.start.compareTo(b.start));
    final List<Interval> merged = [sorted.first];
    for (final Interval current in sorted.skip(1)) {
      final Interval last = merged.last;
      if (!current.start.isAfter(last.end)) {
        // Overlap or touching, merge
        merged.last = Interval(last.start, current.end.isAfter(last.end) ? current.end : last.end);
      } else {
        merged.add(current);
      }
    }
    return merged;
  }

  /// Calculates unique task active seconds within a session, excluding breaks.
  static double calculateUniqueTaskSeconds(
    List<WorkTask?> tasks,
    DateTime sessionStart,
    DateTime sessionEnd,
    List<WorkBreak> breaks,
  ) {
    // 1. Collect valid task-active intervals that overlap the WorkSession
    final List<Interval> taskIntervals = [];
    for (final WorkTask? task in tasks) {
      if (task == null) continue;
      final DateTime? taskStart = task.startedAt;
      if (taskStart == null) continue;
      final DateTime taskEnd = task.endedAt ?? DateTime.now();

      // 2. Clip each interval to the WorkSession boundaries
      final DateTime overlapStart = taskStart.isAfter(sessionStart) ? taskStart : sessionStart;
      final DateTime overlapEnd = taskEnd.isBefore(sessionEnd) ? taskEnd : sessionEnd;

      if (overlapStart.isBefore(overlapEnd)) {
        taskIntervals.add(Interval(overlapStart, overlapEnd));
      }
    }

    // 3. Merge overlapping/touching intervals
    final List<Interval> mergedTaskIntervals = mergeIntervals(taskIntervals);

    // 4. Total unique task time
    double totalTaskSeconds = 0;
    for (final Interval interval in mergedTaskIntervals) {
      totalTaskSeconds += interval.end.difference(interval.start).inSeconds.toDouble();
    }

    // 5. Subtract break time that occurred during merged task intervals
    double breakSecondsInTaskTime = 0;

    // Merge break intervals first
    final List<Interval> breakIntervals = [];
    for (final WorkBreak breakRecord in breaks) {
      final DateTime breakStart = breakRecord.startedAt;
      final DateTime breakEnd = breakRecord.endedAt ?? DateTime.now();

      // Clip to session boundaries
      final DateTime overlapStart = breakStart.isAfter(sessionStart) ? breakStart : sessionStart;
      final DateTime overlapEnd = breakEnd.isBefore(sessionEnd) ? breakEnd : sessionEnd;

      if (overlapStart.isBefore(overlapEnd)) {
        breakIntervals.add(Interval(overlapStart, overlapEnd));
      }
    }

    final List<Interval> mergedBreakIntervals = mergeIntervals(breakIntervals);

    // Calculate intersection of mergedTaskIntervals and mergedBreakIntervals
    for (final Interval taskInterval in mergedTaskIntervals) {
      for (final Interval breakInterval in mergedBreakIntervals) {
        // Intersection
        final DateTime overlapStart = taskInterval.start.isAfter(breakInterval.start)
            ? taskInterval.start
            : breakInterval.start;
        final DateTime overlapEnd = taskInterval.end.isBefore(breakInterval.end)
            ? taskInterval.end
            : breakInterval.end;

        if (overlapStart.isBefore(overlapEnd)) {
          breakSecondsInTaskTime += overlapEnd.difference(overlapStart).inSeconds.toDouble();
        }
      }
    }

    return (totalTaskSeconds - breakSecondsInTaskTime).clamp(0.0, double.infinity);
  }

  /// Calculates today's metrics from the given sessions, tasks, and breaks.
  /// Returns a map with:
  ///   - totalWorkSeconds: total work session time in seconds
  ///   - totalTaskSeconds: total time spent on tasks in seconds
  ///   - productiveBreakSeconds: total time spent on productive breaks in seconds
  ///   - focusRate: percentage of work time spent on tasks
  ///   - idlePercentage: percentage of work time spent on productive breaks
  static Map<String, double> calculateTodayMetrics(
    List<WorkSession> sessions,
    List<WorkTask?> tasks,
    List<WorkBreak> breaks,
  ) {
    double totalWorkSeconds = 0;
    double totalTaskSeconds = 0;
    double productiveBreakSeconds = 0;

    final productiveBreakTypes = {'LUNCH', 'BREAK_1', 'BREAK_2', 'SHORT_BREAK'};

    for (final session in sessions) {
      final sessionStart = session.startedAt;
      final sessionEnd = session.endedAt ?? DateTime.now();

      // Work session duration
      final workDuration = sessionEnd.difference(sessionStart).inSeconds.toDouble();
      totalWorkSeconds += workDuration.clamp(0.0, double.infinity);

      // Breaks for this session
      final sessionBreaks = breaks.where((b) => b.workSessionId != null && b.workSessionId == session.id).toList();
      for (final breakRecord in sessionBreaks) {
        final breakDuration = breakRecord.endedAt?.difference(breakRecord.startedAt).inSeconds.toDouble() ?? 0.0;
        final breakDurationClamped = breakDuration.clamp(0.0, double.infinity);
        if (productiveBreakTypes.contains(breakRecord.type.wireName)) {
          productiveBreakSeconds += breakDurationClamped;
        }
      }

      // Tasks for this session
      final sessionTasks = tasks.where((t) => t != null && t.workSessionId == session.id).toList();
      final sessionTasksWithStartedAt = sessionTasks.where((t) => t != null && t!.startedAt != null).toList();
      totalTaskSeconds += calculateUniqueTaskSeconds(
        sessionTasksWithStartedAt,
        sessionStart,
        sessionEnd,
        sessionBreaks,
      );
    }

    final focusRate = (totalWorkSeconds > 0) ? (totalTaskSeconds / totalWorkSeconds) * 100.0 : 0.0;
    final idlePercentage = (totalWorkSeconds > 0) ? (productiveBreakSeconds / totalWorkSeconds) * 100.0 : 0.0;

    return {
      'totalWorkSeconds': totalWorkSeconds.clamp(0.0, double.infinity),
      'totalTaskSeconds': totalTaskSeconds.clamp(0.0, double.infinity),
      'productiveBreakSeconds': productiveBreakSeconds.clamp(0.0, double.infinity),
      'focusRate': focusRate.clamp(0.0, 100.0),
      'idlePercentage': idlePercentage.clamp(0.0, 100.0),
    };
  }
}

/// Simple interval class for time range calculations.
class Interval {
  final DateTime start;
  final DateTime end;

  Interval(this.start, this.end);
}