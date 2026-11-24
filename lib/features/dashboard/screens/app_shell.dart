import 'package:flutter/material.dart';
import 'package:intellibreak/features/notifications/notification_navigator.dart';
import 'package:intellibreak/features/work_life_balance/screens/work_life_balance_screen.dart';
import 'package:provider/provider.dart';
import 'package:intellibreak/core/theme/theme_controller.dart';
import 'package:intellibreak/features/dashboard/screens/dashboard_screen.dart';
import 'package:intellibreak/features/dashboard/screens/profile_screen.dart';
import 'package:intellibreak/features/messaging/screens/messages_screen.dart';
import 'package:intellibreak/features/dashboard/screens/settings_screen.dart';
import 'package:intellibreak/features/shift_logs/screens/shift_logs_screen.dart';
import 'package:intellibreak/features/team/screens/team_view_screen.dart';
import 'package:intellibreak/features/analytics/screens/employee_analytics_screen.dart';
import 'package:intellibreak/features/analytics/screens/manager_analytics_screen.dart';
import 'package:intellibreak/features/employees/screens/employees_screen.dart';
import 'package:intellibreak/features/employees/screens/manager_team_activity_screen.dart';
import 'package:intellibreak/features/attendance/screens/attendance_screen.dart';
import 'package:intellibreak/features/team/attendance/screens/team_attendance_screen.dart';
import 'package:intellibreak/features/wellbeing/providers/wellbeing_provider.dart';
import 'package:intellibreak/features/wellbeing/widgets/team_wellbeing_overview_screen.dart';
import 'package:intellibreak/features/dashboard/widgets/work_tasks.dart';
import 'package:intellibreak/features/dashboard/widgets/dashboard_header.dart';
import 'package:intellibreak/features/dashboard/widgets/dashboard_sidebar.dart';
import 'package:intellibreak/features/notifications/widgets/notification_dropdown.dart';
import 'package:intellibreak/features/notifications/screens/notification_center_screen.dart';
import 'package:intellibreak/widgets/tab_title_ticker.dart';
import 'package:intellibreak/features/auth/services/auth_service.dart';
import 'package:intellibreak/features/auth/services/api_service.dart';
import 'package:intellibreak/providers/work_session_models.dart';
import 'package:intellibreak/providers/work_session_provider.dart';
import 'package:intellibreak/providers/team_provider.dart';
import 'package:intellibreak/providers/settings_provider.dart';
import 'package:intellibreak/providers/notification_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intellibreak/features/dashboard/tutorial/tutorial_overlay.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intellibreak/routes/auth_gate.dart';

class AppShell extends StatefulWidget {
  final bool showWelcomeBackModal;
  final WorkTask? unfinishedTask;
  final VoidCallback? onContinueTask;
  final VoidCallback? onChooseAnother;
  final VoidCallback? onTutorialDismissed;

  const AppShell({
    super.key,
    this.showWelcomeBackModal = false,
    this.unfinishedTask,
    this.onContinueTask,
    this.onChooseAnother,
    this.onTutorialDismissed,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isLoadingToken = true;
  bool _hasBackendToken = false;
  DashboardDestination _selectedDestination = DashboardDestination.dashboard;
  bool _isSolo = false;
  DashboardDestination _previousDestination = DashboardDestination.dashboard;
  String _userRole = 'GUEST';
  final AuthService _authService = AuthService();
  final ApiService _apiService = ApiService();
  bool _showProfileMenu = false;
  bool _showNotificationDropdown = false;
  String? _backendUserName;
  String? _backendUserEmail;

  @override
  void initState() {
    super.initState();
    NotificationNavigator.register(_handleNotificationTarget);
    _loadToken();
  }

  @override
  void dispose() {
    NotificationNavigator.unregister(_handleNotificationTarget);
    super.dispose();
  }

  /// Opens the screen a pressed notification refers to.
  void _handleNotificationTarget(NotificationTarget target) {
    final isManager = _userRole == 'MANAGER' || _userRole == 'ADMIN';
    final DashboardDestination? destination = switch (target) {
      NotificationTarget.dashboard => DashboardDestination.dashboard,
      NotificationTarget.tasks => DashboardDestination.tasks,
      NotificationTarget.team => _isSolo ? null : DashboardDestination.teamView,
      NotificationTarget.shiftLogs => DashboardDestination.shiftLogs,
      NotificationTarget.workLifeBalance => DashboardDestination.workLifeBalance,
      NotificationTarget.wellbeing =>
        isManager && !_isSolo ? DashboardDestination.wellbeing : DashboardDestination.workLifeBalance,
      NotificationTarget.analytics => DashboardDestination.analytics,
      NotificationTarget.messages => _isSolo ? null : DashboardDestination.messages,
    };
    if (destination == null || !mounted) return;
    setState(() => _showNotificationDropdown = false);
    _onDestinationSelected(destination);
  }

  void _toggleProfileMenu() {
    setState(() {
      _showProfileMenu = !_showProfileMenu;
      if (_showProfileMenu) _showNotificationDropdown = false; // Close notification dropdown
    });
  }

  void _toggleNotificationDropdown() {
    setState(() {
      _showNotificationDropdown = !_showNotificationDropdown;
      if (_showNotificationDropdown) _showProfileMenu = false; // Close profile menu
    });
  }

  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (!mounted) return;
    setState(() {
      _isLoadingToken = false;
    });

    // If we have a token, fetch user info to get role and user details
    if (token != null) {
      try {
        final userData = await _apiService.getMe(token);
        final role = userData['role'];
        if (!mounted) return;
        setState(() {
          _userRole = role;
          _isSolo = userData['account_type'] == 'solo';
          _backendUserName = userData['full_name'] as String?;
          _backendUserEmail = userData['email'] as String?;
          print('[NAME-TRACE-4] AppShell._backendUserName = "$_backendUserName"');
          // Update initial destination based on role
          _selectedDestination = _getInitialDestinationForRole(role);
        });
        // Load settings now that token is confirmed available
        if (!mounted) return;
        final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
        await settingsProvider.loadSettings();
        if (!mounted) return;
        final notificationProvider = Provider.of<NotificationProvider>(context, listen: false);
        notificationProvider.setSettingsProvider(settingsProvider);
        notificationProvider.setWorkSessionProvider(
          Provider.of<WorkSessionProvider>(context, listen: false),
        );
        notificationProvider.startPolling();
      } catch (e) {
        // If we cannot fetch user info, still use backend token but mark as error
        // Don't fall back to Firebase identity as it may be stale
        if (!mounted) return;
        setState(() {
          _userRole = 'GUEST'; // Still show as guest in sidebar but don't use Firebase identity
          _selectedDestination = DashboardDestination.dashboard;
          _backendUserName = null; // Keep as null to show loading state or handle appropriately
          _backendUserEmail = null;
        });
        // Re-token fetch might be needed here, but for now don't fallback to Firebase
      }
    } else {
      // No token, default to GUEST
      if (!mounted) return;
      setState(() {
        _userRole = 'GUEST';
        _selectedDestination = DashboardDestination.dashboard;
        _backendUserName = null;
        _backendUserEmail = null;
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

  DashboardDestination _getInitialDestinationForRole(String role) {
    switch (role) {
      case 'MANAGER':
        return DashboardDestination.teamView;
      default:
        return DashboardDestination.dashboard;
    }
  }

  Widget _buildScreenContent() {
    switch (_selectedDestination) {
      case DashboardDestination.dashboard:
        return TutorialOverlay(
          child: DashboardScreenContent(
            userName: _backendUserName,
            userEmail: _backendUserEmail,
            onOpenWorkLifeBalance: () =>
                _onDestinationSelected(DashboardDestination.workLifeBalance),
          ),
          onDismissed: widget.onTutorialDismissed,
        );
      case DashboardDestination.workLifeBalance:
        return const WorkLifeBalanceScreen();
      case DashboardDestination.teamView:
        return const TeamViewScreenContent();
      case DashboardDestination.attendance:
        return const AttendanceScreen();
      case DashboardDestination.teamAttendance:
        return const TeamAttendanceScreen();
      case DashboardDestination.teamActivity:
        return (_userRole == 'MANAGER' || _userRole == 'ADMIN')
            ? const ManagerTeamActivityScreen()
            : const Center(child: Text('Unauthorized'));
      case DashboardDestination.tasks:
        return const SingleChildScrollView(
          child: Padding(padding: EdgeInsets.all(24), child: WorkTasks()),
        );
      case DashboardDestination.shiftLogs:
        return const ShiftLogsScreenContent();
      case DashboardDestination.analytics:
        return (_userRole == 'MANAGER' || _userRole == 'ADMIN')
            ? const ManagerAnalyticsScreenContent()
            : const EmployeeAnalyticsScreenContent();
      case DashboardDestination.settings:
        return const SettingsScreen();
      case DashboardDestination.messages:
        return const MessagesScreenContent();
      case DashboardDestination.notificationCenter:
        return NotificationCenterScreen(
          onBack: () => _onDestinationSelected(_previousDestination),
        );
      case DashboardDestination.profile:
        return const ProfileScreen();
      case DashboardDestination.employees:
        // For production, only managers should see this
        // But we'll show it for any authenticated user and let the screen handle auth
        return const EmployeesScreenContent();
      case DashboardDestination.wellbeing:
        return ChangeNotifierProvider(
          create: (_) => WellbeingProvider(),
          child: const TeamWellbeingOverviewScreen(),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeController = Provider.of<ThemeController>(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = themeController.isHighContrast;
    final bool isDesktop = MediaQuery.of(context).size.width >= 1100;

    final String? userName = _authService.getUserDisplayName();

    return Stack(
      children: [
        // Tab title ticker for updating browser tab title
        TabTitleTicker(),
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
              userName: _backendUserName,
              userEmail: _backendUserEmail,
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
                    isSolo: _isSolo,
                  ),
                ),
          body: Row(
            children: [
              if (isDesktop)
                DashboardSidebar(
                  selectedDestination: _selectedDestination,
                  onDestinationSelected: _onDestinationSelected,
                  userRole: _userRole,
                  isSolo: _isSolo,
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
                            : const Color(0xFF182029))
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
                                          : Color(0xFF9AA3AF))
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
                                    _backendUserName ?? userName ?? 'Guest User',
                                    style: TextStyle(
                                      color: isDark
                                          ? (isHighContrast
                                                ? Colors.white
                                                : Color(0xFFE8EBEF))
                                          : Colors.black,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _backendUserEmail ?? _authService.getUserEmail() ??
                                        'guest@demo.intellibreak.local',
                                    style: TextStyle(
                                      color: isDark
                                          ? (isHighContrast
                                                ? Colors.white.withValues(
                                                    alpha: 0.7,
                                                  )
                                                : Color(0xFF9AA3AF))
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
                                  : Color(0xFF2D3643))
                            : Color(0xFFD3D9E1),
                      ),
                      // Menu Items
                      ListTile(
                        leading: Icon(
                          Icons.person,
                          color: isDark
                              ? (isHighContrast
                                    ? Colors.white
                                    : Color(0xFF9AA3AF))
                              : Colors.black,
                          size: 22,
                        ),
                        title: Text(
                          'Profile',
                          style: TextStyle(
                            color: isDark
                                ? (isHighContrast
                                      ? Colors.white
                                      : Color(0xFFE8EBEF))
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
                                    : Color(0xFF9AA3AF))
                              : Colors.black,
                          size: 22,
                        ),
                        title: Text(
                          'Settings',
                          style: TextStyle(
                            color: isDark
                                ? (isHighContrast
                                      ? Colors.white
                                      : Color(0xFFE8EBEF))
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
                                    : Color(0xFF9AA3AF))
                              : Colors.black,
                          size: 22,
                        ),
                        title: Text(
                          'Logout',
                          style: TextStyle(
                            color: isDark
                                ? (isHighContrast
                                      ? Colors.white
                                      : Color(0xFFE8EBEF))
                                : Colors.black,
                            fontSize: 16,
                          ),
                        ),
                        onTap: () async {
                          debugPrint('AppShell logout: logout initiated');
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
                          debugPrint('AppShell logout: user confirmed logout: $shouldLogout');
                          if (shouldLogout == true) {
                            debugPrint('AppShell logout: calling signOut');
                            final firebaseUserBefore = FirebaseAuth.instance.currentUser;
                            debugPrint('AppShell logout: Firebase user before signOut: $firebaseUserBefore');
                            final prefsBefore = await SharedPreferences.getInstance();
                            final tokenBefore = prefsBefore.getString('jwt_token');
                            debugPrint('AppShell logout: JWT present before signOut: ${tokenBefore != null && tokenBefore.isNotEmpty}');
                            await _authService.signOut();
                            debugPrint('AppShell logout: signOut completed');
                            final firebaseUserAfter = FirebaseAuth.instance.currentUser;
                            debugPrint('AppShell logout: Firebase user after signOut: $firebaseUserAfter');
                            final prefsAfter = await SharedPreferences.getInstance();
                            final tokenAfter = prefsAfter.getString('jwt_token');
                            debugPrint('AppShell logout: JWT present after signOut: ${tokenAfter != null && tokenAfter.isNotEmpty}');
                            // Clear state providers
                            if (mounted) {
                              debugPrint('AppShell logout: clearing WorkSessionProvider');
                              final sessionProvider = Provider.of<WorkSessionProvider>(context, listen: false);
                              sessionProvider.clear();
                              debugPrint('AppShell logout: WorkSessionProvider cleared');
                              final teamProvider = Provider.of<TeamProvider>(context, listen: false);
                              teamProvider.clear();
                              debugPrint('AppShell logout: TeamProvider cleared');
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
        if (_showNotificationDropdown)
          Positioned(
            top: isDesktop ? 70 : (56 + MediaQuery.of(context).padding.top),
            right: isDesktop ? 16 : 8,
            child: GestureDetector(
              onTap: () {
                debugPrint('=== NOTIFICATION DROPDOWN CLICKED ===');
              },
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
        ],
      );
    }
  }
