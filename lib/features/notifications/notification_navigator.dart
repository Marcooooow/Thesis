import 'package:intellibreak/features/notifications/models/notification_model.dart';

/// Where a notification should take the user when it is pressed.
enum NotificationTarget {
  dashboard,
  tasks,
  team,
  shiftLogs,
  workLifeBalance,
  wellbeing,
  analytics,
  messages,
}

/// Routes a pressed notification to the screen it is about.
///
/// The app shell registers a handler (it owns navigation and knows the user's
/// role and account type), so notification widgets do not need to be wired to
/// the shell individually.
class NotificationNavigator {
  static void Function(NotificationTarget target)? _handler;

  static void register(void Function(NotificationTarget target) handler) {
    _handler = handler;
  }

  static void unregister(void Function(NotificationTarget target) handler) {
    if (identical(_handler, handler)) _handler = null;
  }

  /// Order matters: more specific prefixes are checked first.
  static NotificationTarget? targetFor(String rawType) {
    final type = rawType.toUpperCase();
    if (type.contains('TASK')) return NotificationTarget.tasks;
    if (type.contains('WLB') || type.contains('WORK_LIFE') || type.contains('BALANCE')) {
      return NotificationTarget.workLifeBalance;
    }
    if (type.contains('WELLBEING')) return NotificationTarget.wellbeing;
    if (type.contains('TEAM')) return NotificationTarget.team;
    if (type.contains('MESSAGE') || type.contains('CHAT')) return NotificationTarget.messages;
    if (type.contains('WORK_SESSION')) return NotificationTarget.shiftLogs;
    if (type.contains('REPORT') || type.contains('ANALYTICS') || type.contains('WEEKLY')) {
      return NotificationTarget.analytics;
    }
    if (type.contains('BREAK') || type.contains('LUNCH') || type.contains('RECOMMEND') || type.contains('COACH')) {
      return NotificationTarget.dashboard;
    }
    return null;
  }

  /// Opens the screen for [notification]. Returns false when the type has no
  /// destination (the caller then just marks it as read).
  static bool open(NotificationModel notification) {
    final target = targetFor(notification.type);
    final handler = _handler;
    if (target == null || handler == null) return false;
    handler(target);
    return true;
  }
}
