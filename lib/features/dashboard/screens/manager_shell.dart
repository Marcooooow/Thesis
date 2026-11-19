import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intellibreak/core/theme/theme_controller.dart';
import 'package:intellibreak/features/auth/services/auth_service.dart';
import 'package:intellibreak/features/auth/services/api_service.dart';
import 'package:intellibreak/features/dashboard/screens/dashboard_screen.dart';
import 'package:intellibreak/features/dashboard/screens/manager_dashboard_screen.dart';
import 'package:intellibreak/features/dashboard/screens/profile_screen.dart';
import 'package:intellibreak/features/dashboard/screens/settings_screen.dart';
import 'package:intellibreak/features/shift_logs/screens/shift_logs_screen.dart';
import 'package:intellibreak/features/team/screens/team_view_screen.dart';
import 'package:intellibreak/features/employees/screens/employees_screen.dart';
import 'package:intellibreak/features/analytics/screens/manager_analytics_screen.dart';
import 'package:intellibreak/features/employees/screens/manager_team_activity_screen.dart';
import 'package:intellibreak/features/dashboard/widgets/work_tasks.dart';
import 'package:intellibreak/features/dashboard/widgets/dashboard_header.dart';
import 'package:intellibreak/features/dashboard/widgets/dashboard_sidebar.dart';
import 'package:intellibreak/features/wellbeing/providers/wellbeing_provider.dart';
import 'package:intellibreak/features/wellbeing/widgets/team_wellbeing_overview_screen.dart';
import 'package:intellibreak/features/team/attendance/screens/team_attendance_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../providers/work_session_provider.dart';
import '../../../providers/team_provider.dart';
import '../../../providers/settings_provider.dart';
import 'package:intellibreak/features/messaging/screens/messages_screen.dart';
import 'package:intellibreak/features/notifications/widgets/notification_dropdown.dart';
import 'package:intellibreak/features/notifications/screens/notification_center_screen.dart';
import '../../../routes/auth_gate.dart';

class ManagerShell extends StatefulWidget {
  const ManagerShell({super.key});

  @override
  State<ManagerShell> createState() => _ManagerShellState();
}

class _ManagerShellState extends State<ManagerShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isLoadingToken = true;
  DashboardDestination _selectedDestination = DashboardDestination.teamView;
  DashboardDestination _previousDestination = DashboardDestination.teamView;
  String? _token;
  String _userRole = 'MANAGER';
  final AuthService _authService = AuthService();
  final ApiService _apiService = ApiService();
  bool _showProfileMenu = false;
  bool _showNotificationDropdown = false;
  String? _userName;
  String? _userEmail;

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  void _toggleProfileMenu() {
    setState(() {
      _showProfileMenu = !_showProfileMenu;
      if (_showProfileMenu) _showNotificationDropdown = false;
    });
  }

  void _toggleNotificationDropdown() {
    setState(() {
      _showNotificationDropdown = !_showNotificationDropdown;
      if (_showNotificationDropdown) _showProfileMenu = false;
    });
  }

  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (!mounted) return;
    setState(() {
      _token = token;
      _isLoadingToken = false;
    });

    // If we have a token, fetch user info to get role and identity
    if (token != null) {
      try {
        final userData = await _apiService.getMe(token);
        // Set the current user ID in TeamProvider
        if (mounted) {
          final teamProvider = Provider.of<TeamProvider>(context, listen: false);
          teamProvider.setCurrentUserId(userData['id'].toString());
        }
        final role = userData['role'];
        final fullName = userData['full_name'] as String?;
        final email = userData['email'] as String?;

        if (!mounted) return;
        setState(() {
          _userRole = role;
          _userName = fullName;
          _userEmail = email;
          // For manager, use saved preference or default to teamView
          final settings = Provider.of<SettingsProvider>(context, listen: false);
          final landingPreference = settings.managerDefaultLanding;
          _selectedDestination = landingPreference == 'dashboard'
              ? DashboardDestination.dashboard
              : DashboardDestination.teamView;
        });
      } catch (e) {
        // If we cannot fetch user info, treat as error state - don't change role/destination
        // The existing values will be used, and error will be handled elsewhere
        if (!mounted) return;
        // Keep current state - don't default to GUEST on error
      }
    } else {
      // No token, user is not authenticated
      if (!mounted) return;
      setState(() {
        _userRole = 'MANAGER'; // Clear role when no token (default to manager)
        _userName = null;
        _userEmail = null;
        _selectedDestination = DashboardDestination.dashboard; // Default to dashboard for unauthenticated
      });
    }
  }

  void _onDestinationSelected(DashboardDestination destination) {
    setState(() {
      _selectedDestination = destination;
    });
    // Close drawer on mobile when an item is selected
    if (MediaQuery.of(context).size.width < 1100) {
      _scaffoldKey.currentState?.closeDrawer();
    }
  }

  Widget _buildScreenContent() {
    switch (_selectedDestination) {
      case DashboardDestination.dashboard:
        return const ManagerDashboardContent();
      case DashboardDestination.teamView:
        return const TeamViewScreenContent();
      case DashboardDestination.attendance:
      case DashboardDestination.teamAttendance:
        return const TeamAttendanceScreen();
      case DashboardDestination.teamActivity:
        return const ManagerTeamActivityScreen();
      case DashboardDestination.wellbeing:
        return ChangeNotifierProvider(
          create: (_) => WellbeingProvider(),
          child: const TeamWellbeingOverviewScreen(),
        );
      case DashboardDestination.tasks:
        return const SingleChildScrollView(
          child: Padding(padding: EdgeInsets.all(24), child: WorkTasks()),
        );
      case DashboardDestination.shiftLogs:
        return const ShiftLogsScreenContent();
      case DashboardDestination.analytics:
        return const ManagerAnalyticsScreenContent();
      case DashboardDestination.settings:
        return const SettingsScreen();
      case DashboardDestination.profile:
        return const ProfileScreen();
      case DashboardDestination.employees:
        return const EmployeesScreenContent();
      case DashboardDestination.messages:
        return const MessagesScreenContent();
      case DashboardDestination.notificationCenter:
        return NotificationCenterScreen(
          onBack: () => _onDestinationSelected(_previousDestination),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeController = Provider.of<ThemeController>(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = themeController.isHighContrast;
    final bool isDesktop = MediaQuery.of(context).size.width >= 1100;

    return Stack(
      children: [
        Scaffold(
          key: _scaffoldKey,
          backgroundColor: isDark
              ? (isHighContrast
                    ? const Color(0xFF0D0D0D)
                    : const Color(0xFF1A1A1A))
              : Colors.white,
          appBar: PreferredSize(
            preferredSize: Size.fromHeight(
              isDesktop ? 70 : (56 + MediaQuery.of(context).padding.top),
            ),
            child: DashboardHeader(
              scaffoldKey: _scaffoldKey,
              authService: _authService,
              showProfileMenu: _showProfileMenu,
              toggleProfileMenu: _toggleProfileMenu,
              toggleNotificationDropdown: _toggleNotificationDropdown,
              userName: _userName,
              userEmail: _userEmail,
            ),
          ),
          drawer: isDesktop
              ? null
              : SafeArea(
                  top: true,
                  bottom: true,
                  child: DashboardSidebar(
                    selectedDestination: _selectedDestination,
                    onDestinationSelected: _onDestinationSelected,
                    userRole: _userRole,
                  ),
                ),
          body: Row(
            children: [
              if (isDesktop)
                DashboardSidebar(
                  selectedDestination: _selectedDestination,
                  onDestinationSelected: _onDestinationSelected,
                  userRole: _userRole,
                ),
              Expanded(
                child: _isLoadingToken
                    ? const Center(child: CircularProgressIndicator())
                    : _selectedDestination == DashboardDestination.notificationCenter
                        ? _buildScreenContent()
                        : RefreshIndicator(
                            onRefresh: _loadToken,
                            child: _buildScreenContent(),
                          ),
              ),
            ],
          ),
        ),
        if (_showNotificationDropdown)
          Positioned(
            top: isDesktop ? 70 : (56 + MediaQuery.of(context).padding.top),
            right: isDesktop ? 16 : 8,
            child: GestureDetector(
              onTap: () {},
              child: NotificationDropdown(
                isDark: isDark,
                isHighContrast: isHighContrast,
                onOpenNotificationCenter: () {
                  setState(() {
                    _showNotificationDropdown = false;
                    if (_selectedDestination != DashboardDestination.notificationCenter) {
                      _previousDestination = _selectedDestination;
                    }
                    _selectedDestination = DashboardDestination.notificationCenter;
                  });
                },
              ),
            ),
          ),
        if (_showProfileMenu)
          Positioned(
            top: isDesktop ? 70 : (56 + MediaQuery.of(context).padding.top),
            right: 0,
            child: GestureDetector(
              onTap: () {},
              child: Container(
                width: 220,
                decoration: BoxDecoration(
                  color: isDark
                      ? (isHighContrast
                            ? const Color(0xFF0D0D0D)
                            : const Color(0xFF1B1D24))
                      : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // User Info
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? (isHighContrast
                                          ? Colors.white
                                          : Color(0xFFA5A7AE))
                                    : Colors.grey.shade300,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.person,
                                color: isDark
                                    ? (isHighContrast
                                          ? Colors.black
                                          : Colors.white)
                                    : Colors.grey.shade800,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _userName ?? 'Manager',
                                    style: TextStyle(
                                      color: isDark
                                          ? (isHighContrast
                                                ? Colors.white
                                                : Color(0xFFF2F2F2))
                                          : Colors.black,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _userEmail ?? 'manager@intellibreak.local',
                                    style: TextStyle(
                                      color: isDark
                                          ? (isHighContrast
                                                ? Colors.white.withValues(
                                                    alpha: 0.7,
                                                  )
                                                : Color(0xFFA5A7AE))
                                          : Colors.grey.shade600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Divider(
                        height: 1,
                        color: isDark
                            ? (isHighContrast
                                  ? Colors.white.withValues(alpha: 0.1)
                                  : Color(0xFF30323A))
                            : Color(0xFFE0E0E0),
                      ),
                      // Menu Items
                      ListTile(
                        leading: Icon(
                          Icons.person,
                          color: isDark
                              ? (isHighContrast
                                    ? Colors.white
                                    : Color(0xFFA5A7AE))
                              : Colors.black,
                          size: 22,
                        ),
                        title: Text(
                          'Profile',
                          style: TextStyle(
                            color: isDark
                                ? (isHighContrast
                                      ? Colors.white
                                      : Color(0xFFF2F2F2))
                                : Colors.black,
                            fontSize: 16,
                          ),
                        ),
                        onTap: () {
                          _toggleProfileMenu();
                          _onDestinationSelected(DashboardDestination.profile);
                        },
                      ),
                      ListTile(
                        leading: Icon(
                          Icons.settings,
                          color: isDark
                              ? (isHighContrast
                                    ? Colors.white
                                    : Color(0xFFA5A7AE))
                              : Colors.black,
                          size: 22,
                        ),
                        title: Text(
                          'Settings',
                          style: TextStyle(
                            color: isDark
                                ? (isHighContrast
                                      ? Colors.white
                                      : Color(0xFFA5A7AE))
                                : Colors.black,
                            fontSize: 16,
                          ),
                        ),
                        onTap: () {
                          _toggleProfileMenu();
                          _onDestinationSelected(DashboardDestination.settings);
                        },
                      ),
                      ListTile(
                        leading: Icon(
                          Icons.logout,
                          color: isDark
                              ? (isHighContrast
                                    ? Colors.white
                                    : Color(0xFFA5A7AE))
                              : Colors.black,
                          size: 22,
                        ),
                        title: Text(
                          'Logout',
                          style: TextStyle(
                            color: isDark
                                ? (isHighContrast
                                      ? Colors.white
                                      : Color(0xFFF2F2F2))
                                : Colors.black,
                            fontSize: 16,
                          ),
                        ),
                        onTap: () async {
                          _toggleProfileMenu();
                          // Show confirmation dialog
                          final shouldLogout = await showDialog<bool>(
                            context: context,
                            builder: (BuildContext context) {
                              return AlertDialog(
                                title: const Text('Logout'),
                                content: const Text('Are you sure you want to log out?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    child: const Text('Log Out'),
                                  ),
                                ],
                              );
                            },
                          );
                          if (shouldLogout == true) {
                            await _authService.signOut();
                            // Clear state providers
                            if (mounted) {
                              final sessionProvider = Provider.of<WorkSessionProvider>(context, listen: false);
                              sessionProvider.clear();
                              final teamProvider = Provider.of<TeamProvider>(context, listen: false);
                              teamProvider.clear();
                            }
                            // Navigate to login screen to ensure proper route replacement
                            if (mounted) {
                              Navigator.of(context).pushAndRemoveUntil(
                                MaterialPageRoute(builder: (_) => const AuthGate()),
                                (route) => false,
                              );
                            }
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
