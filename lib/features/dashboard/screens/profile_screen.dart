import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intellibreak/features/dashboard/providers/profile_provider.dart';
import 'package:intellibreak/features/dashboard/models/profile_model.dart';
import 'package:intellibreak/core/theme/theme_controller.dart';
import 'package:intellibreak/core/theme/app_theme.dart';
import 'package:intellibreak/features/dashboard/screens/profile_settings_screen.dart';
import 'package:intellibreak/core/motion.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    if (!mounted) return;
    final profileProvider =
        Provider.of<ProfileProvider>(context, listen: false);
    await profileProvider.loadProfile();
  }

  @override
  Widget build(BuildContext context) {
    final themeController = Provider.of<ThemeController>(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = themeController.isHighContrast;

    // Helper to get text colors and surface colors
    final Color primaryText = isHighContrast
        ? AppTheme.hcPrimaryText
        : isDark
            ? AppTheme.darkPrimaryText
            : AppTheme.lightPrimaryText;
    final Color secondaryText = isHighContrast
        ? AppTheme.hcSecondaryText
        : isDark
            ? AppTheme.darkSecondaryText
            : AppTheme.lightSecondaryText;
    final Color borderColor = isHighContrast
        ? AppTheme.hcBorders
        : isDark
            ? AppTheme.darkBorders
            : AppTheme.lightBorders;
    final Color surfaceColor = isHighContrast
        ? (isDark ? AppTheme.hcPrimaryBackground : Colors.white)
        : isDark
            ? const Color(0xFF182029)
            : Colors.white;
    final Color accentColor = themeController.accentColor;

    // Get current user email from Firebase Auth
    final String? userEmail = FirebaseAuth.instance.currentUser?.email;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Profile' : 'Profile'),
        elevation: 0,
        backgroundColor: isHighContrast
            ? AppTheme.hcPrimaryBackground
            : isDark
                ? AppTheme.darkPrimaryBackground
                : AppTheme.lightPrimaryBackground,
        foregroundColor: primaryText,
        leading: _isEditing
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _isEditing = false),
              )
            : null,
      ),
      body: _isEditing
          ? ProfileSettingsScreen(
              onCancel: () => setState(() => _isEditing = false),
              onSaved: () {
                setState(() => _isEditing = false);
                _loadProfile();
              },
            )
          : Consumer<ProfileProvider>(
              builder: (context, profileProvider, child) {
                if (profileProvider.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (profileProvider.error != null) {
                  return Center(
                    child: Text(
                      'Error loading profile: ${profileProvider.error}',
                      style: TextStyle(color: secondaryText),
                    ),
                  );
                }

                final profile = profileProvider.profile;
                if (profile == null) {
                  return Center(
                    child: Text(
                      'Profile data not available',
                      style: TextStyle(fontSize: 16, color: secondaryText),
                    ),
                  );
                }

                final double screenWidth = MediaQuery.of(context).size.width;
                final bool isWide = screenWidth >= 900;
                final bool isTablet = screenWidth >= 600 && screenWidth < 900;

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: DelayedAnimatedSection(
                    delay: Duration.zero,
                    slideDirection: SlideDirection.topToBottom,
                    visible: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 1. Identity Header Card
                        DelayedAnimatedSection(
                          delay: Duration.zero,
                          slideDirection: SlideDirection.topToBottom,
                          visible: true,
                          child: Card(
                            elevation: 2,
                            color: surfaceColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: borderColor),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: _buildProfileHero(
                                context,
                                profile,
                                userEmail,
                                primaryText,
                                secondaryText,
                                borderColor,
                                accentColor,
                                isHighContrast,
                                isDark,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        // 2. Personal Information Section
                        DelayedAnimatedSection(
                          delay: Duration(milliseconds: MotionDurations.stagger.inMilliseconds),
                          slideDirection: SlideDirection.topToBottom,
                          visible: true,
                          child: Card(
                            elevation: 2,
                            color: surfaceColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: borderColor),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: _buildSectionContent(
                                context,
                                'Personal Information',
                                _buildPersonalInfoFields(profile, primaryText, secondaryText),
                                isWide,
                                isTablet,
                                primaryText,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        // 3. Work Information Section
                        DelayedAnimatedSection(
                          delay: Duration(milliseconds: MotionDurations.stagger.inMilliseconds * 2),
                          slideDirection: SlideDirection.topToBottom,
                          visible: true,
                          child: Card(
                            elevation: 2,
                            color: surfaceColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: borderColor),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: _buildSectionContent(
                                context,
                                'Work Information',
                                _buildWorkInfoFields(profile, primaryText, secondaryText),
                                isWide,
                                isTablet,
                                primaryText,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        // 4. Work Schedule Section
                        DelayedAnimatedSection(
                          delay: Duration(milliseconds: MotionDurations.stagger.inMilliseconds * 3),
                          slideDirection: SlideDirection.topToBottom,
                          visible: true,
                          child: Card(
                            elevation: 2,
                            color: surfaceColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: borderColor),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: _buildSectionContent(
                                context,
                                'Work Schedule',
                                _buildWorkScheduleFields(profile, primaryText, secondaryText, accentColor, borderColor, isDark),
                                isWide,
                                isTablet,
                                primaryText,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildProfileHero(
    BuildContext context,
    Profile profile,
    String? userEmail,
    Color primaryText,
    Color secondaryText,
    Color borderColor,
    Color accentColor,
    bool isHighContrast,
    bool isDark,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isCompact = constraints.maxWidth < 600;
        final avatarAndInfo = Row(
          children: [
            // Avatar
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: borderColor,
                      width: 2,
                    ),
                    image: profile.profileImageUrl != null && profile.profileImageUrl!.isNotEmpty
                        ? DecorationImage(
                            image: NetworkImage(profile.profileImageUrl!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: profile.profileImageUrl == null || profile.profileImageUrl!.isEmpty
                      ? Icon(
                          Icons.person,
                          size: 40,
                          color: secondaryText,
                        )
                      : null,
                ),
                // Subtle edit icon overlay on avatar
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: accentColor,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.edit, size: 14),
                      color: Colors.white,
                      onPressed: () {
                        setState(() {
                          _isEditing = true;
                        });
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 26,
                        minHeight: 26,
                      ),
                      tooltip: 'Edit Profile',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 20),
            // Text info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.fullName,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: primaryText,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${profile.jobRole ?? 'Not provided'} • ${profile.industry ?? 'Not provided'}',
                    style: TextStyle(
                      fontSize: 14,
                      color: secondaryText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (userEmail != null && userEmail.isNotEmpty)
                    Text(
                      userEmail,
                      style: TextStyle(
                        fontSize: 14,
                        color: secondaryText,
                      ),
                    ),
                ],
              ),
            ),
          ],
        );

        final editButton = ElevatedButton.icon(
          onPressed: () {
            setState(() {
              _isEditing = true;
            });
          },
          icon: const Icon(Icons.edit, size: 16),
          label: const Text('Edit Profile'),
          style: ElevatedButton.styleFrom(
            backgroundColor: accentColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );

        if (isCompact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              avatarAndInfo,
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: editButton,
              ),
            ],
          );
        } else {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: avatarAndInfo),
              const SizedBox(width: 16),
              editButton,
            ],
          );
        }
      },
    );
  }

  Widget _buildSectionContent(
    BuildContext context,
    String title,
    List<Widget> fields,
    bool isWide,
    bool isTablet,
    Color primaryText,
  ) {
    int crossAxisCount = isWide ? 3 : (isTablet ? 2 : 1);

    final fieldsGrid = LayoutBuilder(
      builder: (context, constraints) {
        double itemWidth = (constraints.maxWidth - (crossAxisCount - 1) * 24) / crossAxisCount;
        if (itemWidth < 180) itemWidth = constraints.maxWidth;
        return Wrap(
          spacing: 24,
          runSpacing: 20,
          children: fields
              .map(
                (field) => SizedBox(
                  width: itemWidth,
                  child: field,
                ),
              )
              .toList(),
        );
      },
    );

    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 220,
            child: Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: primaryText,
              ),
            ),
          ),
          Expanded(child: fieldsGrid),
        ],
      );
    } else {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: primaryText,
            ),
          ),
          const SizedBox(height: 16),
          fieldsGrid,
        ],
      );
    }
  }

  Widget _buildInfoField(String label, String value, Color primaryText, Color secondaryText) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
            color: secondaryText,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: primaryText,
          ),
        ),
      ],
    );
  }

  List<Widget> _buildPersonalInfoFields(Profile profile, Color primaryText, Color secondaryText) {
    return [
      _buildInfoField('Age', profile.age != null ? '${profile.age}' : 'Not provided', primaryText, secondaryText),
      _buildInfoField('Gender', profile.gender ?? 'Not provided', primaryText, secondaryText),
      _buildInfoField('Marital Status', profile.maritalStatus ?? 'Not provided', primaryText, secondaryText),
      _buildInfoField('Education', profile.educationAttainment ?? 'Not provided', primaryText, secondaryText),
      _buildInfoField('Phone Number', profile.phoneNumber ?? 'Not provided', primaryText, secondaryText),
    ];
  }

  List<Widget> _buildWorkInfoFields(Profile profile, Color primaryText, Color secondaryText) {
    return [
      _buildInfoField('Job Role', profile.jobRole ?? 'Not provided', primaryText, secondaryText),
      _buildInfoField('Industry', profile.industry ?? 'Not provided', primaryText, secondaryText),
      _buildInfoField('Department', profile.department ?? 'Not provided', primaryText, secondaryText),
      _buildInfoField(
        'Years of Experience',
        profile.yearsOfExperience != null ? '${profile.yearsOfExperience} years' : 'Not provided',
        primaryText,
        secondaryText,
      ),
    ];
  }

  List<Widget> _buildWorkScheduleFields(
    Profile profile,
    Color primaryText,
    Color secondaryText,
    Color accentColor,
    Color borderColor,
    bool isDark,
  ) {
    final shiftValue = (profile.shiftStartTime != null && profile.shiftEndTime != null)
        ? '${profile.shiftStartTime} — ${profile.shiftEndTime}'
        : 'Not provided';
    final targetHoursValue = profile.targetDailyHours != null
        ? '${profile.targetDailyHours} hours'
        : 'Not provided';
    final hireDateValue = profile.hireDate ?? 'Not provided';

    return [
      _buildInfoField('Shift', shiftValue, primaryText, secondaryText),
      _buildInfoField('Target Daily Hours', targetHoursValue, primaryText, secondaryText),
      _buildInfoField('Hire Date', hireDateValue, primaryText, secondaryText),
      // Work Days Chips field occupying full width or standard slot
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WORK DAYS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: secondaryText,
            ),
          ),
          const SizedBox(height: 8),
          _buildWorkDaysChips(profile.workDays, accentColor, primaryText, secondaryText, borderColor, isDark),
        ],
      ),
    ];
  }

  Widget _buildWorkDaysChips(
    List<String>? workDays,
    Color accentColor,
    Color primaryText,
    Color secondaryText,
    Color borderColor,
    bool isDark,
  ) {
    final allDays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final normalizedSelected = (workDays ?? []).map((d) => d.toLowerCase().trim()).toSet();

    if (allDays.every((day) => !normalizedSelected.contains(day.toLowerCase())) && (workDays == null || workDays.isEmpty)) {
      return Text(
        'Not provided',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: primaryText,
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: allDays.map((day) {
        final isSelected = normalizedSelected.contains(day.toLowerCase());
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? accentColor.withValues(alpha: 0.2)
                : (isDark ? const Color(0xFF2A2D3A) : Colors.grey.shade100),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? accentColor : borderColor,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Text(
            day,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              color: isSelected ? accentColor : secondaryText,
            ),
          ),
        );
      }).toList(),
    );
  }
}
