import 'package:flutter/material.dart';
import 'package:intellibreak/core/theme/theme_controller.dart';
import 'package:provider/provider.dart';

enum AdminDashboardDestination {
  adminDashboard,
  manageAccounts,
  approvals,
  auditLogs,
  teams,
  organizationAnalytics,
  systemSettings,
  settings,
  profile,
  mlModelDashboard,
  notificationCenter,
}

class AdminSidebar extends StatelessWidget {
  final AdminDashboardDestination? selectedDestination;
  final Function(AdminDashboardDestination) onDestinationSelected;

  const AdminSidebar({
    super.key,
    required this.selectedDestination,
    required this.onDestinationSelected,
  });

  List<AdminDashboardDestination> get _visibleDestinations => [
    AdminDashboardDestination.adminDashboard,
    AdminDashboardDestination.mlModelDashboard,
    AdminDashboardDestination.manageAccounts,
    AdminDashboardDestination.approvals,
    AdminDashboardDestination.auditLogs,
    AdminDashboardDestination.teams,
    AdminDashboardDestination.organizationAnalytics,
    AdminDashboardDestination.systemSettings,
    AdminDashboardDestination.settings,
    AdminDashboardDestination.profile,
  ];

  String _getDestinationLabel(AdminDashboardDestination destination) {
    return switch (destination) {
      AdminDashboardDestination.adminDashboard => 'Admin Dashboard',
      AdminDashboardDestination.manageAccounts => 'Manage Accounts',
      AdminDashboardDestination.approvals => 'Approvals',
      AdminDashboardDestination.auditLogs => 'Audit Logs',
      AdminDashboardDestination.teams => 'Teams & Organization',
      AdminDashboardDestination.organizationAnalytics =>
        'Organization Analytics',
      AdminDashboardDestination.systemSettings => 'System Settings',
      AdminDashboardDestination.settings => 'Settings',
      AdminDashboardDestination.profile => 'Profile',
      AdminDashboardDestination.mlModelDashboard => 'ML Model Dashboard',
      AdminDashboardDestination.notificationCenter => 'Notification Center',
    };
  }

  IconData _getDestinationIcon(AdminDashboardDestination destination) {
    return switch (destination) {
      AdminDashboardDestination.adminDashboard => Icons.dashboard_outlined,
      AdminDashboardDestination.manageAccounts => Icons.people_outline,
      AdminDashboardDestination.approvals => Icons.pending_actions,
      AdminDashboardDestination.auditLogs => Icons.history_outlined,
      AdminDashboardDestination.teams => Icons.groups_outlined,
      AdminDashboardDestination.organizationAnalytics =>
        Icons.analytics_outlined,
      AdminDashboardDestination.systemSettings => Icons.settings_outlined,
      AdminDashboardDestination.settings => Icons.settings_outlined,
      AdminDashboardDestination.profile => Icons.person_outlined,
      AdminDashboardDestination.mlModelDashboard => Icons.bar_chart,
      AdminDashboardDestination.notificationCenter => Icons.notifications_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    final themeController = Provider.of<ThemeController>(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = themeController.isHighContrast;

    final destinations = _visibleDestinations;

    return Container(
      width: 230,
      color: isDark
          ? (isHighContrast ? const Color(0xFF0D0D0D) : const Color(0xFF151A21))
          : Colors.white,
      child: Column(
        children: [
          const SizedBox(height: 30),
          // Removed the IntelliBreak text/logo from the sidebar
          const SizedBox(height: 35),
          // Navigation
          ...List.generate(destinations.length, (index) {
            final destination = destinations[index];
            return _buildMenuItem(destination, context, isDark, isHighContrast);
          }),
        ],
      ),
    );
  }

  Widget _buildMenuItem(
    AdminDashboardDestination destination,
    BuildContext context,
    bool isDark,
    bool isHighContrast,
  ) {
    final bool selected = selectedDestination == destination;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          onDestinationSelected(destination);
        },
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 15),
          decoration: BoxDecoration(
            color: selected
                ? (isDark
                      ? (isHighContrast
                            ? Colors.white.withValues(alpha: 0.1)
                            : Color(0xFF2A2D3A))
                      : const Color(0xFFE3F2FD))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                _getDestinationIcon(destination),
                color: selected
                    ? Theme.of(context).colorScheme.secondary
                    : isDark
                    ? (isHighContrast
                          ? Colors.white.withValues(alpha: 0.7)
                          : Color(0xFF9AA3AF))
                    : Color(0xFF5B6472),
                size: 21,
              ),
              const SizedBox(width: 14),
              Text(
                _getDestinationLabel(destination),
                style: TextStyle(
                  color: selected
                      ? Theme.of(context).colorScheme.secondary
                      : isDark
                      ? (isHighContrast ? Colors.white : Color(0xFF9AA3AF))
                      : Color(0xFF5B6472),
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
