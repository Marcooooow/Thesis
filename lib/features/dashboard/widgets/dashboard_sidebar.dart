import 'package:flutter/material.dart';

enum DashboardDestination {
  dashboard,
  workLifeBalance,
  teamView,
  attendance,
  teamAttendance,
  teamActivity,
  wellbeing,
  tasks,
  shiftLogs,
  analytics,
  settings,
  profile,
  employees,
  messages,
  notificationCenter,
}

class DashboardSidebar extends StatelessWidget {
  final DashboardDestination? selectedDestination;
  final Function(DashboardDestination) onDestinationSelected;
  final String userRole;

  /// Solo accounts work on their own: team, employee, team-attendance and
  /// team-messaging modules do not apply to them and are hidden.
  final bool isSolo;

  const DashboardSidebar({
    super.key,
    required this.selectedDestination,
    required this.onDestinationSelected,
    required this.userRole,
    this.isSolo = false,
  });

  bool get _isManagerOrAdmin => userRole == 'MANAGER' || userRole == 'ADMIN';

  String _label(DashboardDestination d) => switch (d) {
        DashboardDestination.dashboard => 'Dashboard',
        DashboardDestination.workLifeBalance => 'Work-Life Balance',
        DashboardDestination.attendance => 'Attendance & Leave',
        DashboardDestination.teamAttendance => 'Team Attendance',
        DashboardDestination.teamActivity => 'Team Activity',
        DashboardDestination.teamView => 'Team View',
        DashboardDestination.wellbeing => 'Team Well-being',
        DashboardDestination.tasks => 'Tasks',
        DashboardDestination.shiftLogs => 'Shift Logs',
        DashboardDestination.analytics => 'Analytics',
        DashboardDestination.settings => 'Settings',
        DashboardDestination.profile => 'Profile',
        DashboardDestination.employees => 'Employees',
        DashboardDestination.messages => 'Messages',
        DashboardDestination.notificationCenter => 'Notification Center',
      };

  IconData _icon(DashboardDestination d) => switch (d) {
        DashboardDestination.dashboard => Icons.dashboard_outlined,
        DashboardDestination.workLifeBalance => Icons.balance_rounded,
        DashboardDestination.attendance => Icons.event_available_outlined,
        DashboardDestination.teamAttendance => Icons.event_note_outlined,
        DashboardDestination.teamActivity => Icons.assignment_outlined,
        DashboardDestination.teamView => Icons.groups_outlined,
        DashboardDestination.wellbeing => Icons.health_and_safety_outlined,
        DashboardDestination.tasks => Icons.task_alt_outlined,
        DashboardDestination.shiftLogs => Icons.history_outlined,
        DashboardDestination.analytics => Icons.analytics_outlined,
        DashboardDestination.settings => Icons.settings_outlined,
        DashboardDestination.profile => Icons.person_outline,
        DashboardDestination.employees => Icons.people_outline,
        DashboardDestination.messages => Icons.chat_bubble_outline,
        DashboardDestination.notificationCenter => Icons.notifications_outlined,
      };

  bool _allowed(DashboardDestination d) {
    switch (d) {
      case DashboardDestination.dashboard:
      case DashboardDestination.workLifeBalance:
      case DashboardDestination.tasks:
      case DashboardDestination.shiftLogs:
      case DashboardDestination.analytics:
      case DashboardDestination.settings:
      case DashboardDestination.profile:
        return true;
      // Team-only modules: not shown to solo accounts.
      case DashboardDestination.teamView:
      case DashboardDestination.messages:
        return !isSolo;
      case DashboardDestination.attendance:
        return !isSolo && userRole == 'EMPLOYEE';
      case DashboardDestination.employees:
      case DashboardDestination.wellbeing:
      case DashboardDestination.teamAttendance:
      case DashboardDestination.teamActivity:
        return !isSolo && _isManagerOrAdmin;
      case DashboardDestination.notificationCenter:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = theme.dividerTheme.color ?? theme.colorScheme.outline;

    final sections = <(String?, List<DashboardDestination>)>[
      (null, [DashboardDestination.dashboard, DashboardDestination.workLifeBalance]),
      ('Team', [DashboardDestination.teamView, DashboardDestination.employees]),
      ('Work', [
        DashboardDestination.attendance,
        DashboardDestination.teamActivity,
        DashboardDestination.teamAttendance,
        DashboardDestination.shiftLogs,
        DashboardDestination.tasks,
      ]),
      ('Insights', [
        DashboardDestination.analytics,
        DashboardDestination.wellbeing,
      ]),
      ('Communication', [DashboardDestination.messages]),
    ];

    return Container(
      width: 248,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(right: BorderSide(color: border)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.self_improvement_rounded, size: 18, color: theme.colorScheme.onPrimary),
                ),
                const SizedBox(width: 10),
                Text('IntelliBreak',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    )),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              children: [
                for (final section in sections)
                  ..._buildSection(context, section.$1, section.$2),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: border))),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _item(context, DashboardDestination.settings),
                _item(context, DashboardDestination.profile),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSection(BuildContext context, String? title, List<DashboardDestination> items) {
    final visible = items.where(_allowed).toList();
    if (visible.isEmpty) return const [];
    final theme = Theme.of(context);
    return [
      if (title != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 18, 10, 6),
          child: Text(
            title.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 0.9,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        )
      else
        const SizedBox(height: 4),
      for (final d in visible) _item(context, d),
    ];
  }

  Widget _item(BuildContext context, DashboardDestination d) {
    final theme = Theme.of(context);
    final selected = selectedDestination == d;
    final primary = theme.colorScheme.primary;
    final fg = selected ? primary : theme.colorScheme.onSurface.withValues(alpha: 0.72);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: selected ? primary.withValues(alpha: 0.10) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onDestinationSelected(d),
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Icon(_icon(d), size: 19, color: fg),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _label(d),
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: fg,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
