import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intellibreak/core/theme/theme_controller.dart';
import 'package:intellibreak/features/auth/services/auth_service.dart';
import 'package:intellibreak/features/dashboard/screens/profile_screen.dart';
import 'package:intellibreak/features/dashboard/screens/app_shell.dart';
import 'package:intellibreak/features/dashboard/screens/settings_screen.dart';
import 'package:intellibreak/providers/notification_provider.dart';
import 'package:intellibreak/routes/auth_gate.dart';
import '../../../providers/presence_provider.dart';
import '../../../providers/work_session_provider.dart';
import 'package:intellibreak/widgets/user_avatar.dart';

class DashboardHeader extends StatefulWidget implements PreferredSizeWidget {
  final GlobalKey<ScaffoldState> scaffoldKey;
  final AuthService authService;
  final bool showProfileMenu;
  final VoidCallback toggleProfileMenu;
  final VoidCallback toggleNotificationDropdown;
  final String? userName;
  final String? userEmail;
  final VoidCallback? onDemoLogout;

  const DashboardHeader({
    super.key,
    required this.scaffoldKey,
    required this.authService,
    required this.showProfileMenu,
    required this.toggleProfileMenu,
    required this.toggleNotificationDropdown,
    this.userName,
    this.userEmail,
    this.onDemoLogout,
  });

  @override
  Size get preferredSize => const Size.fromHeight(70);

  @override
  State<DashboardHeader> createState() => _DashboardHeaderState();
}

class _DashboardHeaderState extends State<DashboardHeader> {
  late final AuthService authService;
  late final bool showProfileMenu;
  late final VoidCallback toggleProfileMenu;
  late final String? userName;
  late final String? userEmail;
  @override
  void initState() {
    super.initState();
    authService = widget.authService;
    showProfileMenu = widget.showProfileMenu;
    toggleProfileMenu = widget.toggleProfileMenu;
    userName = widget.userName;
    userEmail = widget.userEmail;

    // Listen to auth state changes to rebuild when user info changes
    authService.authStateChanges.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    // Clean up the listener to prevent memory leaks
    super.dispose();
  }

  bool _isDesktop(BuildContext context) {
    return MediaQuery.of(context).size.width >= 1100;
  }

  @override
  Widget build(BuildContext context) {
    final bool desktop = _isDesktop(context);
    final themeController = Provider.of<ThemeController>(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = themeController.isHighContrast;
    final AuthService authService = widget.authService;
    final displayName = (userName ?? authService.getUserDisplayName());
    final email = (userEmail ?? authService.getUserEmail() ?? '');

    // Mobile header with proper SafeArea and responsive layout
    if (!desktop) {
      return SafeArea(
        bottom: false,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: isDark
                ? (isHighContrast
                      ? const Color(0xFF0D0D0D)
                      : const Color(0xFF1B1D24))
                : Colors.white,
            border: Border(
              bottom: BorderSide(
                color: isDark
                    ? (isHighContrast
                          ? Colors.white.withValues(alpha: 0.2)
                          : const Color(0xFF30323A))
                    : const Color(0xFFE0E0E0),
                width: 1,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              children: [
                // Hamburger menu
                IconButton(
                  onPressed: () {
                    widget.scaffoldKey.currentState?.openDrawer();
                  },
                  icon: Icon(
                    Icons.menu,
                    color: isDark
                        ? (isHighContrast
                              ? Colors.white
                              : const Color(0xFFA5A7AE))
                        : Colors.black,
                    size: 24,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                ),

                // IntelliBreak title
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      final currentRoute = ModalRoute.of(context)?.settings.name;
                      if (currentRoute == '/' || currentRoute == '/dashboard') {
                        return;
                      }
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const AppShell()),
                      );
                    },
                    child: Text(
                      'IntelliBreak',
                  style: TextStyle(
                    color: isDark
                        ? (isHighContrast
                              ? Colors.white
                              : const Color(0xFFF2F2F2))
                        : const Color(0xFF171923),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                // Flexible search field with constrained width
                SizedBox(
                  width: 250,
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search...',
                      hintStyle: TextStyle(
                        color: isDark
                            ? (isHighContrast
                                  ? Colors.white.withValues(alpha: 0.5)
                                  : const Color(0xFFA5A7AE))
                            : Colors.grey,
                      ),
                      filled: true,
                      fillColor: isDark
                          ? (isHighContrast
                                ? const Color(0xFF0D0D0D)
                                : const Color(0xFF1B1D24))
                          : Colors.grey.shade200,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        color: isDark
                            ? (isHighContrast
                                  ? Colors.white.withValues(alpha: 0.5)
                                  : const Color(0xFFA5A7AE))
                            : Colors.grey,
                        size: 20,
                      ),
                      isDense: true,
                    ),
                    style: TextStyle(
                      color: isDark
                          ? (isHighContrast
                                ? Colors.white
                                : const Color(0xFFF2F2F2))
                          : Colors.black,
                      fontSize: 14,
                    ),
                  ),
                ),

                const SizedBox(width: 4),

                // Notification button (dropdown in AppShell overlay)
                Consumer<NotificationProvider>(
                  builder: (context, notificationProvider, _) {
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        IconButton(
                          onPressed: widget.toggleNotificationDropdown,
                          icon: Icon(
                            Icons.notifications_none_rounded,
                            color: isDark
                                ? (isHighContrast
                                    ? Colors.white
                                    : const Color(0xFFA5A7AE))
                                : Colors.black,
                            size: 22,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 40,
                            minHeight: 40,
                          ),
                        ),
                        if (notificationProvider.unreadCount > 0)
                          Positioned(
                            right: 8,
                            top: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: const BoxDecoration(
                                color: Color(0xFF6C63FF),
                                borderRadius:
                                    BorderRadius.all(Radius.circular(10)),
                              ),
                              child: Text(
                                notificationProvider.unreadCount > 9
                                    ? '9+'
                                    : '${notificationProvider.unreadCount}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),

                // Profile button with online status indicator
                GestureDetector(
                  onTap: () {
                    debugPrint('=== PROFILE ICON CLICKED ===');
                    widget.toggleProfileMenu();
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: UserAvatar(
                      name: displayName,
                      size: 36,
                      presenceStatus: Provider.of<PresenceProvider>(context).isOnline ? 'online' : 'offline',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Desktop header (unchanged)
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          height: 70,
          decoration: BoxDecoration(
            color: isDark
                ? (isHighContrast
                      ? const Color(0xFF0D0D0D)
                      : const Color(0xFF1B1D24))
                : Colors.white,
            border: Border(
              bottom: BorderSide(
                color: isDark
                    ? (isHighContrast
                          ? Colors.white.withValues(alpha: 0.2)
                          : const Color(0xFF30323A))
                    : const Color(0xFFE0E0E0),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: 12),

              // TITLE
              Text(
                'IntelliBreak',
                style: TextStyle(
                  color: isDark
                      ? (isHighContrast
                            ? Colors.white
                            : const Color(0xFFF2F2F2))
                      : const Color(0xFF171923),
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Spacer(),

              // RIGHT-SIDE CONTROLS GROUP
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // SEARCH BAR - responsive constrained width
                  SizedBox(
                    width: 360,
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Search...',
                        hintStyle: TextStyle(
                          color: isDark
                              ? (isHighContrast
                                    ? Colors.white.withValues(alpha: 0.5)
                                    : const Color(0xFFA5A7AE))
                              : Colors.grey,
                        ),
                        filled: true,
                        fillColor: isDark
                            ? (isHighContrast
                                  ? const Color(0xFF0D0D0D)
                                  : const Color(0xFF1B1D24))
                            : Colors.grey.shade200,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        prefixIcon: Icon(
                          Icons.search,
                          color: isDark
                              ? (isHighContrast
                                    ? Colors.white.withValues(alpha: 0.5)
                                    : const Color(0xFFA5A7AE))
                              : Colors.grey,
                        ),
                      ),
                      style: TextStyle(
                        color: isDark
                            ? (isHighContrast
                                  ? Colors.white
                                  : const Color(0xFFF2F2F2))
                            : Colors.black,
                        fontSize: 14,
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  // THEME TOGGLE
                  IconButton(
                    onPressed: () async {
                      final ThemeMode nextMode =
                          themeController.themeMode == ThemeMode.dark
                          ? ThemeMode.light
                          : ThemeMode.dark;
                      await themeController.setThemeMode(nextMode);
                    },
                    icon: Icon(
                      isDark
                          ? Icons.wb_sunny_outlined
                          : Icons.nights_stay_outlined,
                      color: isDark
                          ? (isHighContrast
                                ? Colors.white
                                : const Color(0xFFA5A7AE))
                          : Colors.black,
                      size: 25,
                    ),
                  ),

                  const SizedBox(width: 12),

                  // NOTIFICATION BELL (button only, dropdown in AppShell overlay)
                  Consumer<NotificationProvider>(
                    builder: (context, notificationProvider, _) {
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          IconButton(
                            onPressed: widget.toggleNotificationDropdown,
                            icon: Icon(
                              Icons.notifications_none_rounded,
                              color: isDark
                                  ? (isHighContrast
                                      ? Colors.white
                                      : const Color(0xFFA5A7AE))
                                  : Colors.black,
                              size: 25,
                            ),
                          ),
                          if (notificationProvider.unreadCount > 0)
                            Positioned(
                              right: 8,
                              top: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF6C63FF),
                                  borderRadius:
                                      BorderRadius.all(Radius.circular(10)),
                                ),
                                child: Text(
                                  notificationProvider.unreadCount > 9
                                      ? '9+'
                                      : '${notificationProvider.unreadCount}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(width: 8),

                  // PROFILE BUTTON
                  GestureDetector(
                    onTap: () {
                      debugPrint('=== PROFILE ICON CLICKED ===');
                      widget.toggleProfileMenu();
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: UserAvatar(
                        name: displayName,
                        size: 38,
                        presenceStatus: Provider.of<PresenceProvider>(context).isOnline ? 'online' : 'offline',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
              ),
            ],
          ),
        ),
        if (widget.showProfileMenu)
          Positioned(
            top: 70,
            right: 0,
            child: GestureDetector(
              onTap: () {
                debugPrint('=== DROPDOWN AREA CLICKED ===');
              },
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
                            UserAvatar(
                              name: displayName,
                              size: 40,
                              showPresence: false,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    displayName,
                                    style: TextStyle(
                                      color: isDark
                                          ? (isHighContrast
                                                ? Colors.white
                                                : const Color(0xFFF2F2F2))
                                          : Colors.black,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    email,
                                    style: TextStyle(
                                      color: isDark
                                          ? (isHighContrast
                                                ? Colors.white.withValues(
                                                    alpha: 0.7,
                                                  )
                                                : const Color(0xFFA5A7AE))
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
                                  : const Color(0xFF30323A))
                            : const Color(0xFFE0E0E0),
                      ),
                      // Menu Items
                      ListTile(
                        leading: Icon(
                          Icons.person,
                          color: isDark
                              ? (isHighContrast
                                    ? Colors.white
                                    : const Color(0xFFA5A7AE))
                              : Colors.black,
                          size: 22,
                        ),
                        title: Text(
                          'Profile',
                          style: TextStyle(
                            color: isDark
                                ? (isHighContrast
                                      ? Colors.white
                                      : const Color(0xFFF2F2F2))
                                : Colors.black,
                            fontSize: 16,
                          ),
                        ),
                        onTap: () {
                          debugPrint('PROFILE MENU ITEM TAPPED');
                          widget.toggleProfileMenu();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ProfileScreen(),
                            ),
                          );
                        },
                      ),
                      ListTile(
                        leading: Icon(
                          Icons.settings,
                          color: isDark
                              ? (isHighContrast
                                    ? Colors.white
                                    : const Color(0xFFA5A7AE))
                              : Colors.black,
                          size: 22,
                        ),
                        title: Text(
                          'Settings',
                          style: TextStyle(
                            color: isDark
                                ? (isHighContrast
                                      ? Colors.white
                                      : const Color(0xFFF2F2F2))
                                : Colors.black,
                            fontSize: 16,
                          ),
                        ),
                        onTap: () {
                          debugPrint('SETTINGS MENU ITEM TAPPED');
                          widget.toggleProfileMenu();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SettingsScreen(),
                            ),
                          );
                        },
                      ),
                      ListTile(
                        leading: Icon(
                          Icons.logout,
                          color: isDark
                              ? (isHighContrast
                                    ? Colors.white
                                    : const Color(0xFFA5A7AE))
                              : Colors.black,
                          size: 22,
                        ),
                        title: Text(
                          'Logout',
                          style: TextStyle(
                            color: isDark
                                ? (isHighContrast
                                      ? Colors.white
                                      : const Color(0xFFF2F2F2))
                                : Colors.black,
                            fontSize: 16,
                          ),
                        ),
                        onTap: () async {
                          widget.toggleProfileMenu();
                          // Show confirmation dialog
                          showDialog(
                            context: context,
                            builder: (BuildContext context) {
                              return AlertDialog(
                                title: const Text('Logout'),
                                content: const Text(
                                  'Are you sure you want to log out?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () async {
                                      Navigator.pop(context);
                                      debugPrint('[DEMO_LOGOUT] BUTTON PRESSED in DashboardHeader');
                                      debugPrint('[DEMO_LOGOUT] CALLBACK STARTED');
                                      // Perform logout
                                      debugPrint('[DEMO_LOGOUT] calling AuthService.signOut');
                                      await widget.authService.signOut();
                                      debugPrint('[DEMO_LOGOUT] signOut completed');
                                      // Clear session state
                                      if (context.mounted) {
                                        if (widget.authService.runtimeType.toString() == 'DemoAuthService') {
                                          // Handle demo logout via callback if provided
                                          if (widget.onDemoLogout != null) {
                                            debugPrint('[DEMO_LOGOUT] calling onDemoLogout');
                                            widget.onDemoLogout!();
                                            debugPrint('[DEMO_LOGOUT] onDemoLogout completed');
                                          }
                                        } else {
                                          // Clear real WorkSessionProvider
                                          final sessionProvider = Provider.of<WorkSessionProvider>(context, listen: false);
                                          sessionProvider.clear();
                                          // Also clear presence provider on logout
                                          final presenceProvider = Provider.of<PresenceProvider>(context, listen: false);
                                          presenceProvider.logout();
                                        }
                                      }
                                      // Navigate to login screen
                                      if (context.mounted) {
                                        Navigator.of(context)
                                            .pushAndRemoveUntil(
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    const AuthGate(),
                                              ),
                                              (route) => false,
                                            );
                                      }
                                    },
                                    child: const Text('Log Out'),
                                  ),
                                ],
                              );
                            },
                          );
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
