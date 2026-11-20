import 'package:flutter/material.dart';
import 'package:intellibreak/core/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:intellibreak/providers/settings_provider.dart';
import 'package:intellibreak/features/auth/services/auth_service.dart';
import 'package:intellibreak/features/auth/services/api_service.dart';
import 'package:intellibreak/core/design_system.dart';
import 'package:intellibreak/features/dashboard/tutorial/tutorial_settings.dart';
import 'package:intellibreak/features/dashboard/providers/profile_provider.dart';
import 'package:intellibreak/features/dashboard/models/profile_model.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _selectedSection = 'Appearance';
  String _userRole = 'EMPLOYEE'; // Default role
  List<String> _filteredSections = [];

  @override
  void initState() {
    super.initState();
    _loadUserRole();
  }

  Future<void> _loadUserRole() async {
    try {
      final apiService = ApiService();
      final token = await apiService.getToken();
      if (token == null) {
        // Log error and default to GUEST role to avoid showing privileged sections by mistake.
        debugPrint(
          'Failed to load user role: token is null. Defaulting to GUEST role.',
        );
        if (!mounted) return;
        setState(() {
          _userRole = 'GUEST';
          _filteredSections = _getSectionsForRole(_userRole);
          // Ensure selectedSection is in filteredSections, default to first if not
          if (!_filteredSections.contains(_selectedSection)) {
            _selectedSection = _filteredSections.isNotEmpty
                ? _filteredSections.first
                : 'Appearance';
          }
        });
        return;
      }

      try {
        final userData = await apiService.getMe(token);
        // Assuming the user data has a 'role' field
        final role = userData['role'] ?? 'EMPLOYEE';
        if (!mounted) return;
        setState(() {
          _userRole = role
              .toString()
              .toUpperCase(); // Ensure it's uppercase to match our sections
          _filteredSections = _getSectionsForRole(_userRole);
          // Ensure selectedSection is in filteredSections, default to first if not
          if (!_filteredSections.contains(_selectedSection)) {
            _selectedSection = _filteredSections.isNotEmpty
                ? _filteredSections.first
                : 'Appearance';
          }
        });
      } catch (e) {
        // Log error and default to GUEST role to avoid showing privileged sections by mistake.
        debugPrint('Failed to load user role: $e. Defaulting to GUEST role.');
        if (!mounted) return;
        setState(() {
          _userRole = 'GUEST';
          _filteredSections = _getSectionsForRole(_userRole);
          // Ensure selectedSection is in filteredSections, default to first if not
          if (!_filteredSections.contains(_selectedSection)) {
            _selectedSection = _filteredSections.isNotEmpty
                ? _filteredSections.first
                : 'Appearance';
          }
        });
      }
    } catch (e) {
      // Catch any unexpected errors
      debugPrint(
        'Unexpected error in _loadUserRole: $e. Defaulting to GUEST role.',
      );
      if (!mounted) return;
      setState(() {
        _userRole = 'GUEST';
        _filteredSections = _getSectionsForRole(_userRole);
        // Ensure selectedSection is in filteredSections, default to first if not
        if (!_filteredSections.contains(_selectedSection)) {
          _selectedSection = _filteredSections.isNotEmpty
              ? _filteredSections.first
              : 'Appearance';
        }
      });
    }
  }

  List<String> _getSectionsForRole(String role) {
    const List<String> allSections = [
      'Appearance', 'Notifications', 'Work & Productivity',
      'Breaks & Wellness', 'Shift & Attendance', 'Tasks',
      'Privacy & Data', 'Accessibility', 'Language & Region',
      'Security', 'About',
    ];
    switch (role) {
      case 'GUEST':
        return ['Appearance', 'Notifications', 'About'];
      case 'EMPLOYEE': return allSections;
      case 'MANAGER': return allSections;
      case 'ADMIN': return allSections;
      default: return allSections;
    }
  }

  void _onSectionTap(String section) {
    setState(() {
      _selectedSection = section;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final authService = AuthService();
    final displayName = authService.getUserDisplayName();
    final email = authService.getUserEmail() ?? '';
    final bool isDesktop = MediaQuery.of(context).size.width >= 1100;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      drawer: isDesktop
          ? null
          : SafeArea(
              top: true,
              bottom: true,
              child: SettingsSidebar(
                sections: _filteredSections,
                selectedSection: _selectedSection,
                onSectionTap: _onSectionTap,
              ),
            ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 1100) {
              // Desktop layout with sidebar
              return Row(
                children: [
                  DelayedAnimatedSection(
                    delay: Duration.zero,
                    slideDirection: SlideDirection.leftToRight,
                    visible: true,
                    child: SettingsSidebar(
                      sections: _filteredSections,
                      selectedSection: _selectedSection,
                      onSectionTap: _onSectionTap,
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: DelayedAnimatedSection(
                      delay: Duration(milliseconds: MotionDurations.stagger.inMilliseconds),
                      slideDirection: SlideDirection.leftToRight,
                      visible: true,
                      child: SettingsContent(
                        isGuest: false,
                        displayName: displayName,
                        email: email,
                        selectedSection: _selectedSection,
                        settingsProvider: settingsProvider,
                        onReplayTutorialPressed: _onReplayTutorialPressed,
                      ),
                    ),
                  ),
                ],
              );
            } else {
              // Mobile layout - full width content
              return DelayedAnimatedSection(
                delay: Duration.zero,
                slideDirection: SlideDirection.topToBottom,
                visible: true,
                child: SettingsContent(
                  isGuest: false,
                  displayName: displayName,
                  email: email,
                  selectedSection: _selectedSection,
                  settingsProvider: settingsProvider,
                  onReplayTutorialPressed: _onReplayTutorialPressed,
                ),
              );
            }
          },
        ),
      ),
    );
  }

  Future<void> _onReplayTutorialPressed() async {
    await TutorialSettings.resetTutorialState();
    if (!mounted) return;
    setState(() {});
  }
}

class SettingsSidebar extends StatelessWidget {
  final List<String> sections;
  final String selectedSection;
  final ValueChanged<String> onSectionTap;

  const SettingsSidebar({
    super.key,
    required this.sections,
    required this.selectedSection,
    required this.onSectionTap,
  });

  @override
  Widget build(BuildContext context) {
    final themeController = Provider.of<ThemeController>(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = themeController.isHighContrast;

    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: isDark
            ? (isHighContrast
                  ? const Color(0xFF0D0D0D)
                  : const Color(0xFF151A21))
            : Colors.grey.shade50,
        border: Border(
          right: BorderSide(
            color: isDark
                ? (isHighContrast
                      ? Colors.white.withValues(alpha: 0.1)
                      : const Color(0xFF262D37))
                : Colors.grey.shade300,
            width: 1,
          ),
        ),
      ),
      child: ListView(
        children: [
          const SettingsHeader(),
          const SettingsDivider(),
          for (final section in sections)
            SettingsMenuItem(
              icon: _getIconForSection(section),
              title: section,
              isSelected: selectedSection == section,
              onTap: () => onSectionTap(section),
            ),
        ],
      ),
    );
  }

  IconData _getIconForSection(String section) {
    switch (section) {
      case 'Appearance':
        return Icons.palette;
      case 'Notifications':
        return Icons.notifications;
      case 'Work & Productivity':
        return Icons.work;
      case 'Breaks & Wellness':
        return Icons.timer;
      case 'Shift & Attendance':
        return Icons.access_time;
      case 'Tasks':
        return Icons.task;
      case 'Privacy & Data':
        return Icons.privacy_tip;
      case 'Accessibility':
        return Icons.accessibility;
      case 'Language & Region':
        return Icons.language;
      case 'Security':
        return Icons.security;
      case 'About':
        return Icons.info;
      default:
        return Icons.settings;
    }
  }
}

class SettingsHeader extends StatelessWidget {
  const SettingsHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = Provider.of<ThemeController>(
      context,
      listen: false,
    ).isHighContrast;

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Settings',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: isDark
                  ? (isHighContrast ? Colors.white : Color(0xFFE8EBEF))
                  : Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Manage your IntelliBreak preferences',
            style: TextStyle(
              fontSize: 14,
              color: isDark
                  ? (isHighContrast
                        ? Colors.white.withValues(alpha: 0.7)
                        : Color(0xFF9AA3AF))
                  : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsDivider extends StatelessWidget {
  const SettingsDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = Provider.of<ThemeController>(
      context,
      listen: false,
    ).isHighContrast;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Divider(
        color: isDark
            ? (isHighContrast
                  ? Colors.white.withValues(alpha: 0.1)
                  : Color(0xFF262D37))
            : Colors.grey.shade300,
        height: 1,
      ),
    );
  }
}

class SettingsMenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  const SettingsMenuItem({
    super.key,
    required this.icon,
    required this.title,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = Provider.of<ThemeController>(
      context,
      listen: false,
    ).isHighContrast;

    return Material(
      color: Colors.transparent,
      child: ListTile(
        leading: Icon(
          icon,
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : isDark
                  ? (isHighContrast ? Colors.white : Color(0xFF9AA3AF))
                  : Colors.black,
          size: 22,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : isDark
                    ? (isHighContrast ? Colors.white : Color(0xFF9AA3AF))
                    : Colors.black,
          ),
        ),
        selected: isSelected,
        selectedTileColor: isDark
            ? (isHighContrast
                  ? Colors.white.withValues(alpha: 0.05)
                  : Theme.of(context).colorScheme.primary
                        .withValues(alpha: 0.1))
            : Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
        onTap: onTap,
      ),
    );
  }
}

class SettingsSectionTitle extends StatelessWidget {
  final String title;

  const SettingsSectionTitle({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = Provider.of<ThemeController>(
      context,
      listen: false,
    ).isHighContrast;

    return Padding(
      padding: const EdgeInsets.only(top: 24.0, bottom: 12.0),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: isDark
              ? (isHighContrast ? Colors.white : Color(0xFFE8EBEF))
              : Colors.black,
        ),
      ),
    );
  }
}

class SettingsListTile extends StatelessWidget {
  final IconData leadingIcon;
  final String title;
  final String? subtitle;
  final bool isSelected;
  final bool isEnabled;
  final VoidCallback? onTap;

  const SettingsListTile({
    super.key,
    required this.leadingIcon,
    required this.title,
    this.subtitle,
    this.isSelected = false,
    this.isEnabled = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = Provider.of<ThemeController>(
      context,
      listen: false,
    ).isHighContrast;

    return ListTile(
      leading: Icon(
        leadingIcon,
        color: isDark
            ? (isHighContrast ? Colors.white : Color(0xFF9AA3AF))
            : Colors.black,
        size: 22,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          color: isDark
              ? (isHighContrast ? Colors.white : Color(0xFF9AA3AF))
              : Colors.black,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? (isHighContrast
                          ? Colors.white.withValues(alpha: 0.7)
                          : Color(0xFF9AA3AF))
                    : Colors.grey.shade600,
              ),
            )
          : null,
      trailing: isSelected
          ? Icon(
              Icons.check_circle,
              color: Theme.of(context).colorScheme.primary,
              size: 20,
            )
          : null,
      enabled: isEnabled,
      onTap: onTap,
    );
  }
}

class SettingsContent extends StatefulWidget {
  final bool isGuest;
  final String displayName;
  final String email;
  final String selectedSection;
  final SettingsProvider settingsProvider;
  final VoidCallback onReplayTutorialPressed;

  const SettingsContent({
    super.key,
    required this.isGuest,
    required this.displayName,
    required this.email,
    required this.selectedSection,
    required this.settingsProvider,
    required this.onReplayTutorialPressed,
  });

  @override
  State<SettingsContent> createState() => _SettingsContentState();
}

class _SettingsContentState extends State<SettingsContent> {
  Profile? _profile;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadProfile();
      }
    });
  }

  Future<void> _loadProfile() async {
    if (!mounted) return;
    try {
      final profileProvider = Provider.of<ProfileProvider>(context, listen: false);
      await profileProvider.loadProfile();
      if (!mounted) return;
      setState(() {
        _profile = profileProvider.profile;
      });
    } catch (e) {
      // ignore
    }
  }

  @override
  Widget build(BuildContext context) {
    // Handle loading and error states from SettingsProvider
    if (widget.settingsProvider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.settingsProvider.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              'Error loading settings',
              style: TextStyle(fontSize: 18, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 8),
            Text(
              widget.settingsProvider.error!,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => widget.settingsProvider.refresh(),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.selectedSection,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          _buildSectionContent(context),
        ],
      ),
    );
  }

  Widget _buildSectionContent(BuildContext context) {
    switch (widget.selectedSection) {
      case 'Appearance':
        return _buildAppearanceSection(context);
      case 'Notifications':
        return _buildNotificationsSection(context);
      case 'Work & Productivity':
        return _buildWorkProductivitySection(context);
      case 'Breaks & Wellness':
        return _buildBreaksWellnessSection(context);
      case 'Shift & Attendance':
        return _buildShiftAttendanceSection(context);
      case 'Tasks':
        return _buildTasksSection(context);
      case 'Privacy & Data':
        return _buildPrivacyDataSection(context);
      case 'Accessibility':
        return _buildAccessibilitySection(context);
      case 'Language & Region':
        return _buildLanguageRegionSection(context);
      case 'Security':
        return _buildSecuritySection(context);
      case 'About':
        return _buildAboutSection(context);
      default:
        return const Text('Section not implemented');
    }
  }

  Widget _buildAppearanceSection(BuildContext context) {
    final themeController = Provider.of<ThemeController>(context);
    final bool isHighContrast = themeController.isHighContrast;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionTitle(title: 'Theme'),
        SettingsListTile(
          leadingIcon: Icons.wb_sunny_outlined,
          title: 'System',
          isSelected: themeController.themeMode == ThemeMode.system,
          onTap: () => themeController.setThemeMode(ThemeMode.system),
        ),
        SettingsListTile(
          leadingIcon: Icons.wb_sunny_outlined,
          title: 'Light',
          isSelected: themeController.themeMode == ThemeMode.light,
          onTap: () => themeController.setThemeMode(ThemeMode.light),
        ),
        SettingsListTile(
          leadingIcon: Icons.nights_stay_outlined,
          title: 'Dark',
          isSelected: themeController.themeMode == ThemeMode.dark,
          onTap: () => themeController.setThemeMode(ThemeMode.dark),
        ),
        const SizedBox(height: 24),
        const SettingsSectionTitle(title: 'Accent color'),
        SettingsListTile(
          leadingIcon: Icons.color_lens,
          title: 'Teal (default)',
          isSelected: themeController.accentColor == const Color(0xFF0F766E),
          onTap: () => themeController.setAccentColor(const Color(0xFF0F766E)),
        ),
        SettingsListTile(
          leadingIcon: Icons.color_lens,
          title: 'Navy',
          isSelected: themeController.accentColor == const Color(0xFF1E4E8C),
          onTap: () => themeController.setAccentColor(const Color(0xFF1E4E8C)),
        ),
        SettingsListTile(
          leadingIcon: Icons.color_lens,
          title: 'Forest',
          isSelected: themeController.accentColor == const Color(0xFF2E6B4F),
          onTap: () => themeController.setAccentColor(const Color(0xFF2E6B4F)),
        ),
        const SizedBox(height: 24),
        const SettingsSectionTitle(title: 'Interface'),
        SettingsListTile(
          leadingIcon: Icons.view_compact,
          title: 'Compact',
          isSelected: widget.settingsProvider.interfaceDensity == 'COMPACT',
          onTap: () => widget.settingsProvider
              .updateSettings({'interface_density': 'COMPACT'}),
        ),
        SettingsListTile(
          leadingIcon: Icons.view_comfy,
          title: 'Comfortable',
          isSelected: widget.settingsProvider.interfaceDensity == 'COMFORTABLE',
          onTap: () => widget.settingsProvider
              .updateSettings({'interface_density': 'COMFORTABLE'}),
        ),
        SettingsListTile(
          leadingIcon: Icons.view_comfortable,
          title: 'Spacious',
          isSelected: widget.settingsProvider.interfaceDensity == 'SPACIOUS',
          onTap: () => widget.settingsProvider
              .updateSettings({'interface_density': 'SPACIOUS'}),
        ),
        const SizedBox(height: 24),
        const SettingsSectionTitle(title: 'Motion'),
        SettingsListTile(
          leadingIcon: Icons.animation,
          title: 'Reduce animations',
          isSelected: widget.settingsProvider.reduceMotion,
          onTap: () => widget.settingsProvider
              .updateSettings({'reduce_motion': !widget.settingsProvider.reduceMotion}),
        ),
        SettingsListTile(
          leadingIcon: Icons.accessibility,
          title: 'High contrast mode',
          isSelected: isHighContrast,
          onTap: () => themeController.setHighContrast(!isHighContrast),
        ),
      ],
    );
  }

  Widget _buildNotificationsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionTitle(title: 'Notifications'),
        SettingsListTile(
          leadingIcon: Icons.notifications,
          title: 'Enable notifications',
          isSelected: widget.settingsProvider.notificationsEnabled,
          onTap: () => widget.settingsProvider
              .updateSettings({'notifications_enabled': !widget.settingsProvider.notificationsEnabled}),
        ),
        const SizedBox(height: 16),
        const SettingsSectionTitle(title: 'Break reminders'),
        SettingsListTile(
          leadingIcon: Icons.timer,
          title: 'Break reminders',
          isSelected: widget.settingsProvider.breakReminders,
          onTap: () => widget.settingsProvider
              .updateSettings({'break_reminders': !widget.settingsProvider.breakReminders}),
        ),
        const SizedBox(height: 16),
        const SettingsSectionTitle(title: 'Shift reminders'),
        SettingsListTile(
          leadingIcon: Icons.access_time,
          title: 'Shift reminders',
          isSelected: widget.settingsProvider.shiftReminders,
          onTap: () => widget.settingsProvider
              .updateSettings({'shift_reminders': !widget.settingsProvider.shiftReminders}),
        ),
        const SizedBox(height: 16),
        const SettingsSectionTitle(title: 'Task reminders'),
        SettingsListTile(
          leadingIcon: Icons.task,
          title: 'Task reminders',
          isSelected: widget.settingsProvider.taskReminders,
          onTap: () => widget.settingsProvider
              .updateSettings({'task_reminders': !widget.settingsProvider.taskReminders}),
        ),
        const SizedBox(height: 16),
        const SettingsSectionTitle(title: 'Focus reminders'),
        SettingsListTile(
          leadingIcon: Icons.timer,
          title: 'Focus reminders',
          isSelected: widget.settingsProvider.focusReminders,
          onTap: () => widget.settingsProvider
              .updateSettings({'focus_reminders': !widget.settingsProvider.focusReminders}),
        ),
        const SizedBox(height: 16),
        const SettingsSectionTitle(title: 'Wellness reminders'),
        SettingsListTile(
          leadingIcon: Icons.health_and_safety,
          title: 'Wellness reminders',
          isSelected: widget.settingsProvider.wellnessReminders,
          onTap: () => widget.settingsProvider
              .updateSettings({'wellness_reminders': !widget.settingsProvider.wellnessReminders}),
        ),
        const SizedBox(height: 16),
        const SettingsSectionTitle(title: 'Summaries'),
        SettingsListTile(
          leadingIcon: Icons.insert_chart_outlined,
          title: 'Daily productivity summary',
          isSelected: widget.settingsProvider.dailySummary,
          onTap: () => widget.settingsProvider
              .updateSettings({'daily_summary': !widget.settingsProvider.dailySummary}),
        ),
        SettingsListTile(
          leadingIcon: Icons.insert_chart_outlined,
          title: 'Weekly productivity summary',
          isSelected: widget.settingsProvider.weeklySummary,
          onTap: () => widget.settingsProvider
              .updateSettings({'weekly_summary': !widget.settingsProvider.weeklySummary}),
        ),
        const SizedBox(height: 24),
        const SettingsSectionTitle(title: 'Break interval'),
        SettingsListTile(
          leadingIcon: Icons.timer,
          title: 'Reminder interval: ${widget.settingsProvider.breakIntervalMinutes} minutes',
          isSelected: false,
          onTap: () => _showIntervalSelector(context),
        ),
        const SizedBox(height: 16),
        const SettingsSectionTitle(title: 'Break duration'),
        SettingsListTile(
          leadingIcon: Icons.timer,
          title: 'Break duration: ${widget.settingsProvider.breakDurationMinutes} minutes',
          isSelected: false,
          onTap: () => _showDurationSelector(context),
        ),
        const SizedBox(height: 24),
        const SettingsSectionTitle(title: 'Do Not Disturb (DND)'),
        SettingsListTile(
          leadingIcon: Icons.notifications_off_outlined,
          title: 'Follow Automatic',
          subtitle: 'DND automatically follows your shift status (on off-shift, off while working)',
          isSelected: widget.settingsProvider.manualDndOverride == null,
          onTap: () => widget.settingsProvider.updateSettings({'manual_dnd_override': null}),
        ),
        SettingsListTile(
          leadingIcon: Icons.do_not_disturb_on_outlined,
          title: 'Force ON',
          subtitle: 'Suppress non-critical notifications regardless of shift status',
          isSelected: widget.settingsProvider.manualDndOverride == true,
          onTap: () => widget.settingsProvider.updateSettings({'manual_dnd_override': true}),
        ),
        SettingsListTile(
          leadingIcon: Icons.notifications_active_outlined,
          title: 'Force OFF',
          subtitle: 'Allow notifications regardless of shift status',
          isSelected: widget.settingsProvider.manualDndOverride == false,
          onTap: () => widget.settingsProvider.updateSettings({'manual_dnd_override': false}),
        ),
      ],
    );
  }

  void _showIntervalSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Break Interval',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                'Select how often you want to be reminded to take a break:',
              ),
              const SizedBox(height: 24),
              _buildIntervalOption(context, '15 minutes', 15),
              const SizedBox(height: 12),
              _buildIntervalOption(context, '30 minutes', 30),
              const SizedBox(height: 12),
              _buildIntervalOption(context, '45 minutes', 45),
              const SizedBox(height: 12),
              _buildIntervalOption(context, '60 minutes', 60),
              const SizedBox(height: 12),
              _buildIntervalOption(context, '90 minutes', 90),
              const SizedBox(height: 12),
              _buildIntervalOption(context, '120 minutes', 120),
            ],
          ),
        );
      },
    );
  }

  Widget _buildIntervalOption(BuildContext context, String label, int minutes) {
    final bool isSelected = widget.settingsProvider.breakIntervalMinutes == minutes;
    return ListTile(
      leading: AnimatedContainer(
        width: 20,
        height: 20,
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.shade400,
            width: 2,
          ),
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
              : Colors.transparent,
        ),
        child: isSelected
            ? Icon(
                Icons.check_circle,
                color: Theme.of(context).colorScheme.primary,
                size: 16,
              )
            : null,
      ),
      title: Text(label),
      selected: isSelected,
      selectedTileColor: Theme.of(context).colorScheme.primary
          .withValues(alpha: 0.05),
      onTap: () {
        Navigator.of(context).pop();
        widget.settingsProvider.updateSettings({'break_interval_minutes': minutes});
      },
    );
  }

  void _showDurationSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Break Duration',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text('Select how long your breaks should last:'),
              const SizedBox(height: 24),
              _buildDurationOption(context, '5 minutes', 5),
              const SizedBox(height: 12),
              _buildDurationOption(context, '10 minutes', 10),
              const SizedBox(height: 12),
              _buildDurationOption(context, '15 minutes', 15),
              const SizedBox(height: 12),
              _buildDurationOption(context, '20 minutes', 20),
              const SizedBox(height: 12),
              _buildDurationOption(context, '30 minutes', 30),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDurationOption(BuildContext context, String label, int minutes) {
    final bool isSelected = widget.settingsProvider.breakDurationMinutes == minutes;
    return ListTile(
      leading: AnimatedContainer(
        width: 20,
        height: 20,
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.shade400,
            width: 2,
          ),
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
              : Colors.transparent,
        ),
        child: isSelected
            ? Icon(
                Icons.check_circle,
                color: Theme.of(context).colorScheme.primary,
                size: 16,
              )
            : null,
      ),
      title: Text(label),
      selected: isSelected,
      selectedTileColor: Theme.of(context).colorScheme.primary
          .withValues(alpha: 0.05),
      onTap: () {
        Navigator.of(context).pop();
        widget.settingsProvider.updateSettings({'break_duration_minutes': minutes});
      },
    );
  }

  Widget _buildWorkProductivitySection(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final timeFormat = settingsProvider.timeFormat;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionTitle(title: 'Work hours'),
        SettingsListTile(
          leadingIcon: Icons.timelapse,
          title: 'Daily target hours',
          subtitle: '${widget.settingsProvider.workTargetDailyHours ?? 'Not set'} hours',
          onTap: () => _editDailyTargetHours(context),
        ),
        SettingsListTile(
          leadingIcon: Icons.work_outline,
          title: 'Work Schedule',
          subtitle: _profile != null
              ? '${_formatTimeOfDay(_profile?.shiftStartTime, timeFormat)} - ${_formatTimeOfDay(_profile?.shiftEndTime, timeFormat)}'
              : 'Not set',
          onTap: () => _editWorkSchedule(context),
        ),
        const SizedBox(height: 24),
        const SizedBox(height: 24),
        const SettingsSectionTitle(title: 'Focus'),
        SettingsListTile(
          leadingIcon: Icons.timeline,
          title: 'Focus target',
          subtitle: '${widget.settingsProvider.focusTargetPercentage ?? 'Not set'}%',
          onTap: () => _editFocusTargetPercentage(context),
        ),
        SettingsListTile(
          leadingIcon: Icons.track_changes,
          title: 'Productivity tracking',
          subtitle: widget.settingsProvider.taskReminders ? 'ON' : 'OFF',
          onTap: () => _toggleProductivityTracking(context),
        ),
        SettingsListTile(
          leadingIcon: Icons.accessibility,
          title: 'Idle detection sensitivity',
          subtitle: widget.settingsProvider.idleDetectionSensitivity ?? 'Not set',
          onTap: () => _editIdleDetectionSensitivity(context),
        ),
        const SizedBox(height: 24),
        const SettingsSectionTitle(title: 'Focus reminders'),
        SettingsListTile(
          leadingIcon: Icons.task_alt,
          title: 'Focus reminders',
          subtitle: widget.settingsProvider.focusReminders ? 'ON' : 'OFF',
          onTap: () => _toggleFocusReminders(context),
        ),
      ],
    );
  }

  Widget _buildBreaksWellnessSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionTitle(title: 'Break Coach'),
        SettingsListTile(
          leadingIcon: Icons.psychology,
          title: 'Enable Break Coach',
          isSelected: widget.settingsProvider.breakCoachEnabled,
          onTap: () => widget.settingsProvider
              .updateSettings({'break_coach_enabled': !widget.settingsProvider.breakCoachEnabled}),
        ),
        const SizedBox(height: 16),
        const SettingsSectionTitle(title: 'Cooldown'),
        SettingsListTile(
          leadingIcon: Icons.timer,
          title: 'Cooldown: ${widget.settingsProvider.breakCoachCooldownMinutes} minutes',
          isSelected: false,
          onTap: () => _showCooldownSelector(context),
        ),
      ],
    );
  }

  void _showCooldownSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Break Coach Cooldown',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text('Select how long to wait before showing another recommendation:'),
              const SizedBox(height: 24),
              _buildCooldownOption(context, '5 minutes', 5),
              const SizedBox(height: 12),
              _buildCooldownOption(context, '10 minutes', 10),
              const SizedBox(height: 12),
              _buildCooldownOption(context, '15 minutes', 15),
              const SizedBox(height: 12),
              _buildCooldownOption(context, '20 minutes', 20),
              const SizedBox(height: 12),
              _buildCooldownOption(context, '30 minutes', 30),
              _buildCooldownOption(context, '45 minutes', 45),
              _buildCooldownOption(context, '60 minutes', 60),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCooldownOption(BuildContext context, String label, int minutes) {
    final bool isSelected =
        widget.settingsProvider.breakCoachCooldownMinutes == minutes;
    return ListTile(
      leading: AnimatedContainer(
        width: 20,
        height: 20,
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.shade400,
            width: 2,
          ),
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
              : Colors.transparent,
        ),
        child: isSelected
            ? Icon(
                Icons.check_circle,
                color: Theme.of(context).colorScheme.primary,
                size: 16,
              )
            : null,
      ),
      title: Text(label),
      selected: isSelected,
      selectedTileColor: Theme.of(context).colorScheme.primary
          .withValues(alpha: 0.05),
      onTap: () {
        Navigator.of(context).pop();
        widget.settingsProvider.updateSettings(
            {'break_coach_cooldown_minutes': minutes});
      },
    );
  }

  Widget _buildShiftAttendanceSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionTitle(title: 'Shift'),
        SettingsListTile(
          leadingIcon: Icons.access_time,
          title: 'Default shift',
          onTap: null,
        ),
        SettingsListTile(
          leadingIcon: Icons.access_time,
          title: 'Shift reminders',
          onTap: null,
        ),
        SettingsListTile(
          leadingIcon: Icons.accessibility,
          title: 'Auto-start shift',
          onTap: null,
        ),
        SettingsListTile(
          leadingIcon: Icons.accessibility,
          title: 'Auto-end shift',
          onTap: null,
        ),
        const SizedBox(height: 24),
        const SettingsSectionTitle(title: 'Tracking'),
        SettingsListTile(
          leadingIcon: Icons.timer,
          title: 'Break tracking',
          onTap: null,
        ),
        SettingsListTile(
          leadingIcon: Icons.lunch_dining,
          title: 'Lunch tracking',
          onTap: null,
        ),
        SettingsListTile(
          leadingIcon: Icons.check_circle,
          title: 'End Shift confirmation',
          onTap: null,
        ),
        const SizedBox(height: 24),
        const SettingsSectionTitle(title: 'Notifications'),
        SettingsListTile(
          leadingIcon: Icons.notifications,
          title: 'Shift notifications',
          onTap: null,
        ),
      ],
    );
  }

  Widget _buildTasksSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionTitle(title: 'Tasks'),
        SettingsListTile(
          leadingIcon: Icons.category,
          title: 'Default task category',
          onTap: null,
        ),
        SettingsListTile(
          leadingIcon: Icons.task,
          title: 'Task reminders',
          onTap: null,
        ),
        SettingsListTile(
          leadingIcon: Icons.check_circle,
          title: 'Show completed tasks',
          onTap: null,
        ),
        SettingsListTile(
          leadingIcon: Icons.timelapse,
          title: 'Automatically track active task',
          onTap: null,
        ),
        SettingsListTile(
          leadingIcon: Icons.timer,
          title: 'Task timer behavior',
          onTap: null,
        ),
        SettingsListTile(
          leadingIcon: Icons.delete,
          title: 'Confirm task deletion',
          onTap: null,
        ),
      ],
    );
  }

  Widget _buildPrivacyDataSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionTitle(title: 'Data collection'),
        SettingsListTile(
          leadingIcon: Icons.analytics,
          title: 'Activity tracking',
          onTap: null,
        ),
        SettingsListTile(
          leadingIcon: Icons.track_changes,
          title: 'Productivity tracking',
          onTap: null,
        ),
        SettingsListTile(
          leadingIcon: Icons.timeline,
          title: 'Focus data collection',
          onTap: null,
        ),
        SettingsListTile(
          leadingIcon: Icons.health_and_safety,
          title: 'Wellness data collection',
          onTap: null,
        ),
        const SizedBox(height: 24),
        const SettingsSectionTitle(title: 'Sharing'),
        SettingsListTile(
          leadingIcon: Icons.share,
          title: 'Data sharing preferences',
          onTap: null,
        ),
        const SizedBox(height: 24),
        const SettingsSectionTitle(title: 'Data actions'),
        SettingsListTile(
          leadingIcon: Icons.download,
          title: 'Export data',
          onTap: null,
        ),
        SettingsListTile(
          leadingIcon: Icons.delete,
          title: 'Delete account/data',
          onTap: null,
        ),
      ],
    );
  }

  Widget _buildAccessibilitySection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionTitle(title: 'Vision'),
        SettingsListTile(
          leadingIcon: Icons.high_quality,
          title: 'High contrast',
          onTap: null,
        ),
        SettingsListTile(
          leadingIcon: Icons.text_increase,
          title: 'Larger text',
          onTap: null,
        ),
        const SizedBox(height: 24),
        const SettingsSectionTitle(title: 'Motion'),
        SettingsListTile(
          leadingIcon: Icons.animation,
          title: 'Reduce motion',
          onTap: null,
        ),
        const SizedBox(height: 24),
        const SettingsSectionTitle(title: 'Interaction'),
        SettingsListTile(
          leadingIcon: Icons.keyboard,
          title: 'Keyboard navigation support',
          onTap: null,
        ),
        SettingsListTile(
          leadingIcon: Icons.accessibility,
          title: 'Screen reader-friendly interface',
          onTap: null,
        ),
      ],
    );
  }

  Widget _buildLanguageRegionSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionTitle(title: 'Language'),
        SettingsListTile(
          leadingIcon: Icons.language,
          title: 'Language',
          onTap: null,
        ),
        const SizedBox(height: 24),
        const SettingsSectionTitle(title: 'Region'),
        SettingsListTile(
          leadingIcon: Icons.access_time,
          title: 'Time zone',
          onTap: null,
        ),
        SettingsListTile(
          leadingIcon: Icons.calendar_today,
          title: 'Date format',
          onTap: null,
        ),
        SettingsListTile(
          leadingIcon: Icons.access_time,
          title: 'Time format',
          subtitle: '${widget.settingsProvider.timeFormat} (${_getTimeFormatExample(widget.settingsProvider.timeFormat)})',
          onTap: () => _editTimeFormat(context),
        ),
        SettingsListTile(
          leadingIcon: Icons.calendar_today,
          title: 'First day of week',
          onTap: null,
        ),
      ],
    );
  }

  Widget _buildSecuritySection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionTitle(title: 'Account security'),
        SettingsListTile(
          leadingIcon: Icons.lock,
          title: 'Change password',
          onTap: null,
        ),
        SettingsListTile(
          leadingIcon: Icons.logout,
          title: 'Sign out',
          onTap: () => _logout(context),
        ),
        SettingsListTile(
          leadingIcon: Icons.logout,
          title: 'Sign out of all sessions',
          isEnabled: false,
          onTap: null,
        ),
        const SizedBox(height: 24),
        const SettingsSectionTitle(title: 'Session'),
        SettingsListTile(
          leadingIcon: Icons.timer,
          title: 'Session/security information',
          onTap: null,
        ),
      ],
    );
  }

  Future<void> _logout(BuildContext context) async {
    final authService = AuthService();
    await authService.signOut();
    // Clear SettingsProvider on logout
    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    settingsProvider.clear(); // Assuming clear method exists; if not, we'll add it
    // Navigate to AuthGate (handled by auth service or app logic)
    if (!mounted) return;
    // We'll rely on the auth service to notify listeners and the app to handle navigation
  }

  Widget _buildAboutSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionTitle(title: 'IntelliBreak'),
        SettingsListTile(
          leadingIcon: Icons.info,
          title: 'Version',
          onTap: null,
        ),
        SettingsListTile(
          leadingIcon: Icons.build,
          title: 'Build information',
          onTap: null,
        ),
        const SizedBox(height: 24),
        const SettingsSectionTitle(title: 'Legal'),
        SettingsListTile(
          leadingIcon: Icons.description,
          title: 'Terms of Service',
          onTap: null,
        ),
        SettingsListTile(
          leadingIcon: Icons.privacy_tip,
          title: 'Privacy Policy',
          onTap: null,
        ),
        const SizedBox(height: 24),
        const SettingsSectionTitle(title: 'Support'),
        SettingsListTile(
          leadingIcon: Icons.help,
          title: 'Help / Support',
          onTap: null,
        ),
        SettingsListTile(
          leadingIcon: Icons.feedback,
          title: 'Feedback',
          onTap: null,
        ),
        const SizedBox(height: 24),
        const SettingsSectionTitle(title: 'Advanced'),
        SettingsListTile(
          leadingIcon: Icons.restore,
          title: 'Replay Tutorial',
          onTap: widget.onReplayTutorialPressed,
        ),
      ],
    );
  }

  Future<void> _editDailyTargetHours(BuildContext context) async {
    final currentValue = widget.settingsProvider.workTargetDailyHours ?? 8;
    final result = await showDialog<int>(
      context: context,
      builder: (BuildContext dialogCtx) {
        String? errorText;
        int? tempValue = currentValue;
        return StatefulBuilder(
          builder: (BuildContext ctx, StateSetter setState) {
            return AlertDialog(
              title: const Text('Daily target hours'),
              content: SingleChildScrollView(
                child: ListBody(
                  children: [
                    TextField(
                      keyboardType: TextInputType.number,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'Hours per day',
                        hintText: 'Enter value between 1 and 24',
                        errorText: errorText,
                      ),
                      onChanged: (value) {
                        final hours = int.tryParse(value);
                        if (hours != null && hours >= 1 && hours <= 24) {
                          setState(() {
                            errorText = null;
                            tempValue = hours;
                          });
                        } else {
                          setState(() {
                            errorText = 'Please enter a value between 1 and 24';
                          });
                        }
                      },
                      onSubmitted: (value) {
                        final hours = int.tryParse(value);
                        if (hours == null) {
                          // Do nothing
                        } else if (hours >= 1 && hours <= 24) {
                          Navigator.of(ctx).pop(hours);
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final value = tempValue;
                    if (value == null) {
                      // Invalid: keep dialog open
                    } else if (value >= 1 && value <= 24) {
                      Navigator.of(ctx).pop(value);
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null && result >= 1 && result <= 24) {
      await widget.settingsProvider.updateSettings({
        'work_target_daily_hours': result,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Daily target hours updated')),
        );
      }
    }
  }

  TimeOfDay _parseTimeOfDay(String timeStr) {
    final parts = timeStr.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    return TimeOfDay(hour: hour, minute: minute);
  }

  String _formatTimeOfDay(String? timeStr, String format) {
    if (timeStr == null || timeStr.isEmpty) return 'Not set';
    final parts = timeStr.split(':');
    if (parts.length != 2) return timeStr;
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;
    final tod = TimeOfDay(hour: hour, minute: minute);
    return DesignSystem.formatTimeOfDay(tod, format);
  }

  Future<void> _editWorkSchedule(BuildContext context) async {
    final profileProvider = Provider.of<ProfileProvider>(context, listen: false);
    final timeFormat = widget.settingsProvider.timeFormat;
    final currentStart = profileProvider.profile?.shiftStartTime ?? '09:00';
    final currentEnd = profileProvider.profile?.shiftEndTime ?? '17:00';
    final currentWorkDays = profileProvider.profile?.workDays ?? ['monday', 'tuesday', 'wednesday', 'thursday', 'friday'];

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (BuildContext dialogContext) {
        TimeOfDay startTime = _parseTimeOfDay(currentStart);
        TimeOfDay endTime = _parseTimeOfDay(currentEnd);
        Set<String> selectedDays = Set<String>.from(currentWorkDays.map((e) => e.toString()));
        String? validationError;

        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: const Text('Work Schedule'),
              content: SingleChildScrollView(
                child: ListBody(
                  children: [
                    ListTile(
                      title: const Text('Start time'),
                      subtitle: Text(_formatTimeOfDay('${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}', timeFormat)),
                      trailing: const Icon(Icons.access_time),
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: dialogContext,
                          initialTime: startTime,
                        );
                        if (picked != null) {
                          setState(() {
                            startTime = picked;
                            validationError = null;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      title: const Text('End time'),
                      subtitle: Text(_formatTimeOfDay('${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}', timeFormat)),
                      trailing: const Icon(Icons.access_time),
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: dialogContext,
                          initialTime: endTime,
                        );
                        if (picked != null) {
                          setState(() {
                            endTime = picked;
                            validationError = null;
                          });
                        }
                      },
                    ),
                    if (validationError != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          border: Border.all(color: Colors.red, width: 1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          validationError!,
                          style: const TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    const Text('Select your working days:'),
                    const SizedBox(height: 16),
                    ...['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
                        .map((day) => CheckboxListTile(
                              title: Text(day),
                              value: selectedDays.contains(day.toLowerCase()),
                              onChanged: (bool? value) {
                                setState(() {
                                  if (value == true) {
                                    selectedDays.add(day.toLowerCase());
                                  } else {
                                    selectedDays.remove(day.toLowerCase());
                                  }
                                });
                              },
                            ))
                        .toList(),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final startMinutes = startTime.hour * 60 + startTime.minute;
                    final endMinutes = endTime.hour * 60 + endTime.minute;

                    if (startMinutes == endMinutes) {
                      setState(() {
                        validationError = 'Start time cannot equal end time.';
                      });
                      return;
                    }

                    final canonicalStart = '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}';
                    final canonicalEnd = '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}';
                    final scheduleStartDays = selectedDays.toList();

                    Navigator.of(context).pop({
                      'start': canonicalStart,
                      'end': canonicalEnd,
                      'work_days': scheduleStartDays,
                    });
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      try {
        await profileProvider.updateProfile({
          'shift_start_time': result['start'],
          'shift_end_time': result['end'],
          'work_days': result['work_days'],
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Work schedule updated')),
          );
          // Refresh the profile so the Settings UI immediately shows the updated schedule
          await profileProvider.loadProfile();
          // Also refresh the SettingsContentState profile so the UI rebuilds
          // from the updated state without requiring a section change
          _profile = profileProvider.profile;
          if (mounted) {
            setState(() {});
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to update work schedule: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _editFocusTargetPercentage(BuildContext context) async {
    final currentValue = widget.settingsProvider.focusTargetPercentage ?? 80;
    final result = await showDialog<int>(
      context: context,
      builder: (BuildContext context) {
        final controller = TextEditingController(text: currentValue.toString());
        return AlertDialog(
          title: const Text('Focus target'),
          content: SingleChildScrollView(
            child: ListBody(
              children: [
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: 'Percentage (%)',
                    hintText: 'Enter value between 0 and 100',
                  ),
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  onSubmitted: (value) {
                    final percent = int.tryParse(value);
                    if (percent != null && percent >= 0 && percent <= 100) {
                      Navigator.of(context).pop(percent);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final percent = int.tryParse(controller.text);
                if (percent != null && percent >= 0 && percent <= 100) {
                  Navigator.of(context).pop(percent);
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (result != null && result >= 0 && result <= 100) {
      await widget.settingsProvider.updateSettings({
        'focus_target_percentage': result,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Focus target updated')),
        );
      }
    }
  }

  Future<void> _toggleProductivityTracking(BuildContext context) async {
    final currentValue = widget.settingsProvider.taskReminders;
    await widget.settingsProvider.updateSettings({
      'task_reminders': !currentValue,
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Productivity tracking ${!currentValue ? 'enabled' : 'disabled'}',
          ),
        ),
      );
    }
  }

  Future<void> _toggleFocusReminders(BuildContext context) async {
    final currentValue = widget.settingsProvider.focusReminders;
    await widget.settingsProvider.updateSettings({
      'focus_reminders': !currentValue,
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Focus reminders ${!currentValue ? 'enabled' : 'disabled'}',
          ),
        ),
      );
    }
  }

  Future<void> _editIdleDetectionSensitivity(BuildContext context) async {
    final currentValue = widget.settingsProvider.idleDetectionSensitivity ?? 'MEDIUM';
    final result = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Idle detection sensitivity'),
          content: SingleChildScrollView(
            child: ListBody(
              children: [
                ListTile(
                  title: const Text('Low'),
                  leading: Radio<String>(
                    value: 'LOW',
                    groupValue: currentValue,
                    onChanged: (String? value) {
                      if (value != null) {
                        Navigator.of(context).pop(value);
                      }
                    },
                  ),
                ),
                ListTile(
                  title: const Text('Medium'),
                  leading: Radio<String>(
                    value: 'MEDIUM',
                    groupValue: currentValue,
                    onChanged: (String? value) {
                      if (value != null) {
                        Navigator.of(context).pop(value);
                      }
                    },
                  ),
                ),
                ListTile(
                  title: const Text('High'),
                  leading: Radio<String>(
                    value: 'HIGH',
                    groupValue: currentValue,
                    onChanged: (String? value) {
                      if (value != null) {
                        Navigator.of(context).pop(value);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );

    if (result != null) {
      await widget.settingsProvider.updateSettings({
        'idle_detection_sensitivity': result,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Idle detection sensitivity updated')),
        );
      }
    }
  }

  String _getTimeFormatExample(String format) {
    if (format == '12h') {
      return '1:00 PM';
    } else {
      return '13:00';
    }
  }

  Future<void> _editTimeFormat(BuildContext context) async {
    final currentValue = widget.settingsProvider.timeFormat;
    final result = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Time format'),
          content: SingleChildScrollView(
            child: ListBody(
              children: [
                RadioListTile<String>(
                  title: const Text('12-hour'),
                  subtitle: const Text('Example: 1:00 PM'),
                  value: '12h',
                  groupValue: currentValue,
                  onChanged: (String? value) {
                    if (value != null) {
                      Navigator.of(context).pop(value);
                    }
                  },
                ),
                RadioListTile<String>(
                  title: const Text('24-hour'),
                  subtitle: const Text('Example: 13:00'),
                  value: '24h',
                  groupValue: currentValue,
                  onChanged: (String? value) {
                    if (value != null) {
                      Navigator.of(context).pop(value);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );

    if (result != null) {
      try {
        await widget.settingsProvider.updateSettings({
          'time_format': result,
        });
        if (mounted && widget.settingsProvider.error == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Time format updated')),
          );
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to save time format: ${widget.settingsProvider.error ?? 'Unknown error'}')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to save time format: $e')),
          );
        }
      }
    }
  }
}

class DelayedAnimatedSection extends StatelessWidget {
  final Duration delay;
  final SlideDirection slideDirection;
  final bool visible;
  final Widget child;

  const DelayedAnimatedSection({
    super.key,
    required this.delay,
    required this.slideDirection,
    required this.visible,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: visible ? 1.0 : 0.0,
      child: IgnorePointer(
        ignoring: !visible,
        child: child,
      ),
    );
  }
}

enum SlideDirection {
  leftToRight,
  rightToLeft,
  topToBottom,
  bottomToTop,
}

class MotionDurations {
  static const Duration slideIn = Duration(milliseconds: 300);
  static const Duration stagger = Duration(milliseconds: 100);
}
