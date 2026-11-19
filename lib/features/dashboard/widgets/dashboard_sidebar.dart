import 'package:flutter/material.dart';
import 'package:intellibreak/core/theme/theme_controller.dart';
import 'package:provider/provider.dart';

enum DashboardDestination {
  dashboard,
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

class DashboardSidebar extends StatefulWidget {
  final DashboardDestination? selectedDestination;
  final Function(DashboardDestination) onDestinationSelected;
  final String userRole;
  final String accountType;

  const DashboardSidebar({
    super.key,
    required this.selectedDestination,
    required this.onDestinationSelected,
    required this.userRole,
    this.accountType = 'organization',
  });

  @override
  State<DashboardSidebar> createState() => _DashboardSidebarState();
}

class _DashboardSidebarState extends State<DashboardSidebar> {
  final Map<String, bool> _expandedGroups = {
    'Team Management': true,
    'Work Monitoring': true,
    'Team Insights': true,
    'Communication & Tasks': true,
  };

  @override
  void didUpdateWidget(DashboardSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedDestination != oldWidget.selectedDestination) {
      _autoExpandForDestination(widget.selectedDestination);
    }
  }

  void _autoExpandForDestination(DashboardDestination? destination) {
    if (destination == null) return;
    if (destination == DashboardDestination.teamView || destination == DashboardDestination.employees) {
      _expandedGroups['Team Management'] = true;
    } else if (destination == DashboardDestination.teamActivity || destination == DashboardDestination.teamAttendance || destination == DashboardDestination.shiftLogs || destination == DashboardDestination.attendance) {
      _expandedGroups[widget.accountType == 'organization' ? 'Work Monitoring' : 'My Work'] = true;
    } else if (destination == DashboardDestination.analytics || destination == DashboardDestination.wellbeing) {
      _expandedGroups[widget.accountType == 'organization' ? 'Team Insights' : 'My Insights'] = true;
    } else if (destination == DashboardDestination.messages || destination == DashboardDestination.tasks) {
      _expandedGroups['Communication & Tasks'] = true;
    }
    if (mounted) setState(() {});
  }

  String _getDestinationLabel(DashboardDestination destination) {
    return switch (destination) {
      DashboardDestination.dashboard => 'Dashboard',
      DashboardDestination.attendance => 'Attendance & Leave',
      DashboardDestination.teamAttendance => 'Team Attendance',
      DashboardDestination.teamActivity => 'Team Activity',
      DashboardDestination.teamView => 'Team View',
      DashboardDestination.wellbeing => 'Well-being',
      DashboardDestination.tasks => 'Tasks',
      DashboardDestination.shiftLogs => 'Shift Logs',
      DashboardDestination.analytics => widget.accountType == 'solo'
          ? 'Work–Life Balance'
          : 'Analytics',
      DashboardDestination.settings => 'Settings',
      DashboardDestination.profile => 'Profile',
      DashboardDestination.employees => 'Employees',
      DashboardDestination.messages => 'Messages',
      DashboardDestination.notificationCenter => 'Notification Center',
    };
  }

  IconData _getDestinationIcon(DashboardDestination destination) {
    return switch (destination) {
      DashboardDestination.dashboard => Icons.dashboard_outlined,
      DashboardDestination.attendance => Icons.event_available_outlined,
      DashboardDestination.teamAttendance => Icons.event_note_outlined,
      DashboardDestination.teamActivity => Icons.assignment_outlined,
      DashboardDestination.teamView => Icons.groups_outlined,
      DashboardDestination.wellbeing => Icons.health_and_safety_outlined,
      DashboardDestination.tasks => Icons.task_alt_outlined,
      DashboardDestination.shiftLogs => Icons.history_outlined,
      DashboardDestination.analytics => Icons.analytics_outlined,
      DashboardDestination.settings => Icons.settings_outlined,
      DashboardDestination.profile => Icons.person_outlined,
      DashboardDestination.employees => Icons.people_outlined,
      DashboardDestination.messages => Icons.chat_bubble_outline,
      DashboardDestination.notificationCenter => Icons.notifications_outlined,
    };
  }

  bool _isDestinationAllowed(DashboardDestination destination) {
    final isOrganizationAccount = widget.accountType == 'organization';
    if (!isOrganizationAccount && (destination == DashboardDestination.teamView ||
        destination == DashboardDestination.employees ||
        destination == DashboardDestination.teamActivity ||
        destination == DashboardDestination.teamAttendance ||
        destination == DashboardDestination.wellbeing)) {
      return false;
    }
    if (destination == DashboardDestination.dashboard ||
        destination == DashboardDestination.teamView ||
        destination == DashboardDestination.messages ||
        destination == DashboardDestination.tasks ||
        destination == DashboardDestination.shiftLogs ||
        destination == DashboardDestination.analytics ||
        destination == DashboardDestination.settings ||
        destination == DashboardDestination.profile) {
      return true;
    }
    if (destination == DashboardDestination.attendance) {
      return widget.userRole == 'EMPLOYEE';
    }
    if (destination == DashboardDestination.employees ||
        destination == DashboardDestination.wellbeing ||
        destination == DashboardDestination.teamAttendance ||
        destination == DashboardDestination.teamActivity) {
      return widget.userRole == 'MANAGER' || widget.userRole == 'ADMIN';
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final themeController = Provider.of<ThemeController>(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = themeController.isHighContrast;

    return Container(
      width: 230,
      color: isDark
          ? (isHighContrast ? const Color(0xFF0D0D0D) : const Color(0xFF1B1D24))
          : Colors.white,
      child: Column(
        children: [
          const SizedBox(height: 12),
          // Scrollable middle navigation area
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.balance_outlined, size: 19, color: Theme.of(context).colorScheme.primary),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('IntelliBreak', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface)),
                            Text('Work with balance', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (_isDestinationAllowed(DashboardDestination.dashboard))
                    _buildMenuItem(DashboardDestination.dashboard, context, isDark, isHighContrast),
                  const SizedBox(height: 6),
                  if (widget.accountType == 'organization') _buildMenuGroup(
                    title: 'Team Management',
                    icon: Icons.groups_outlined,
                    destinations: [
                      DashboardDestination.teamView,
                      DashboardDestination.employees,
                    ],
                    context: context,
                    isDark: isDark,
                    isHighContrast: isHighContrast,
                  ),
                  _buildMenuGroup(
                    title: widget.accountType == 'organization' ? 'Work Monitoring' : 'My Work',
                    icon: Icons.assignment_outlined,
                    destinations: [
                      if (widget.userRole == 'EMPLOYEE') DashboardDestination.attendance,
                      if (widget.accountType == 'organization' && (widget.userRole == 'MANAGER' || widget.userRole == 'ADMIN')) ...[
                        DashboardDestination.teamActivity,
                        DashboardDestination.teamAttendance,
                      ],
                      DashboardDestination.shiftLogs,
                    ],
                    context: context,
                    isDark: isDark,
                    isHighContrast: isHighContrast,
                  ),
                  _buildMenuGroup(
                    title: widget.accountType == 'organization' ? 'Team Insights' : 'My Insights',
                    icon: Icons.analytics_outlined,
                    destinations: [
                      DashboardDestination.analytics,
                      if (widget.userRole == 'MANAGER' || widget.userRole == 'ADMIN')
                        DashboardDestination.wellbeing,
                    ],
                    context: context,
                    isDark: isDark,
                    isHighContrast: isHighContrast,
                  ),
                  _buildMenuGroup(
                    title: 'Communication & Tasks',
                    icon: Icons.chat_bubble_outline,
                    destinations: [
                      DashboardDestination.messages,
                      DashboardDestination.tasks,
                    ],
                    context: context,
                    isDark: isDark,
                    isHighContrast: isHighContrast,
                  ),
                ],
              ),
            ),
          ),

          // Pinned bottom items (Settings, Profile)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: isDark ? Colors.white24 : Colors.grey.shade200,
                  width: 1,
                ),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isDestinationAllowed(DashboardDestination.settings))
                  _buildMenuItem(DashboardDestination.settings, context, isDark, isHighContrast),
                if (_isDestinationAllowed(DashboardDestination.profile))
                  _buildMenuItem(DashboardDestination.profile, context, isDark, isHighContrast),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuGroup({
    required String title,
    required IconData icon,
    required List<DashboardDestination> destinations,
    required BuildContext context,
    required bool isDark,
    required bool isHighContrast,
  }) {
    final validDestinations = destinations.where((d) => _isDestinationAllowed(d)).toList();
    if (validDestinations.isEmpty) return const SizedBox.shrink();

    final isExpanded = _expandedGroups[title] ?? true;
    final hasSelectedChild = validDestinations.contains(widget.selectedDestination);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            setState(() {
              _expandedGroups[title] = !isExpanded;
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: hasSelectedChild
                      ? Theme.of(context).colorScheme.secondary
                      : (isDark ? const Color(0xFFA5A7AE) : const Color(0xFF6B7280)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: hasSelectedChild
                          ? Theme.of(context).colorScheme.secondary
                          : (isDark ? const Color(0xFFA5A7AE) : const Color(0xFF6B7280)),
                    ),
                  ),
                ),
                Icon(
                  isExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: isDark ? const Color(0xFFA5A7AE) : const Color(0xFF6B7280),
                ),
              ],
            ),
          ),
        ),
        if (isExpanded)
          ...validDestinations.map((destination) => Padding(
                padding: const EdgeInsets.only(left: 12),
                child: _buildMenuItem(destination, context, isDark, isHighContrast),
              )),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildMenuItem(
    DashboardDestination destination,
    BuildContext context,
    bool isDark,
    bool isHighContrast,
  ) {
    final bool selected = widget.selectedDestination == destination;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          widget.onDestinationSelected(destination);
        },
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected
                ? (isDark
                      ? (isHighContrast
                            ? Colors.white.withValues(alpha: 0.1)
                            : destination == DashboardDestination.messages
                                ? const Color(0xFF222530)
                                : const Color(0xFF2A2D3A))
                      : destination == DashboardDestination.messages
                          ? const Color(0xFFE8EEF5)
                          : const Color(0xFFE3F2FD))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                _getDestinationIcon(destination),
                color: selected
                    ? (destination == DashboardDestination.messages
                        ? (isDark ? Colors.white : const Color(0xFF171923))
                        : Theme.of(context).colorScheme.secondary)
                    : isDark
                    ? (isHighContrast
                          ? Colors.white.withValues(alpha: 0.7)
                          : const Color(0xFFA5A7AE))
                    : const Color(0xFF6B7280),
                size: 19,
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Text(
                  _getDestinationLabel(destination),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? (destination == DashboardDestination.messages
                            ? (isDark ? Colors.white : const Color(0xFF171923))
                            : Theme.of(context).colorScheme.secondary)
                        : isDark
                        ? (isHighContrast ? Colors.white : const Color(0xFFA5A7AE))
                        : const Color(0xFF6B7280),
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
