import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intellibreak/features/dashboard/providers/profile_provider.dart';
import 'package:intellibreak/features/dashboard/models/profile_model.dart';
import 'package:intellibreak/core/theme/theme_controller.dart';
import 'package:intellibreak/core/theme/app_theme.dart';
import 'package:intellibreak/features/dashboard/services/profile_image_service.dart';
import 'package:intellibreak/features/auth/services/api_service.dart';
import 'package:image_picker/image_picker.dart';

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1).toLowerCase()}';
  }
}

class ProfileSettingsScreen extends StatefulWidget {
  final VoidCallback? onCancel;
  final VoidCallback? onSaved;

  const ProfileSettingsScreen({
    super.key,
    this.onCancel,
    this.onSaved,
  });

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isSaving = false;

  // Profile image state
  XFile? _selectedImageFile;
  bool _isUploading = false;
  String? _uploadError;

  // Form field controllers
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _phoneNumberController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _genderController = TextEditingController();
  final TextEditingController _educationAttainmentController =
      TextEditingController();
  final TextEditingController _maritalStatusController = TextEditingController();
  final TextEditingController _jobRoleController = TextEditingController();
  final TextEditingController _industryController = TextEditingController();
  final TextEditingController _departmentController = TextEditingController();
  final TextEditingController _yearsOfExperienceController =
      TextEditingController();
  final TextEditingController _targetDailyHoursController =
      TextEditingController();
  final TextEditingController _hireDateController = TextEditingController();
  TimeOfDay? _shiftStartTime;
  TimeOfDay? _shiftEndTime;
  final Set<String> _selectedWorkDays = {};

  // Work Profile State
  bool _hasWorkProfile = false;
  String _wpScheduleType = 'flexible';
  String _wpArrangement = 'remote';
  int _wpTypicalFocus = 60;
  int _wpPreferredFocus = 45;
  int _wpTypicalBreakFrequency = 4;
  int _wpTypicalBreakDuration = 15;
  String _wpLunchStartTime = '12:30';
  int _wpLunchDuration = 45;
  String _wpLunchConsistency = 'consistent';
  List<String> _wpResponsibilities = [];
  String _wpReminderPreference = 'gentle';
  String _wpRecommendationStyle = 'structured';
  bool _wpProfileCompleted = false;

  static const List<String> _daysOfWeek = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday'
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneNumberController.dispose();
    _ageController.dispose();
    _genderController.dispose();
    _educationAttainmentController.dispose();
    _maritalStatusController.dispose();
    _jobRoleController.dispose();
    _industryController.dispose();
    _departmentController.dispose();
    _yearsOfExperienceController.dispose();
    _targetDailyHoursController.dispose();
    _hireDateController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final profileProvider =
          Provider.of<ProfileProvider>(context, listen: false);
      await profileProvider.loadProfile();
      final profile = profileProvider.profile;
      if (profile != null && mounted) {
        _populateForm(profile);
      }

      final token = await ApiService().getToken();
      if (token != null) {
        final wp = await ApiService().getWorkProfile(token);
        if (wp != null && mounted) {
          setState(() {
            _hasWorkProfile = true;
            _wpScheduleType = wp['schedule_type'] ?? 'flexible';
            _wpArrangement = wp['arrangement'] ?? 'remote';
            _wpTypicalFocus = wp['typical_focus_duration'] ?? 60;
            _wpPreferredFocus = wp['preferred_focus_duration'] ?? 45;
            _wpTypicalBreakFrequency = wp['typical_break_frequency'] ?? 4;
            _wpTypicalBreakDuration = wp['typical_break_duration'] ?? 15;
            _wpLunchStartTime = wp['lunch_start_time'] ?? '12:30';
            _wpLunchDuration = wp['lunch_duration'] ?? 45;
            _wpLunchConsistency = wp['lunch_consistency'] ?? 'consistent';
            _wpResponsibilities = List<String>.from(wp['responsibilities'] ?? []);
            _wpReminderPreference = wp['reminder_preference'] ?? 'gentle';
            _wpRecommendationStyle = wp['recommendation_style'] ?? 'structured';
            _wpProfileCompleted = wp['profile_completed'] ?? false;
          });
        }
      }
    } catch (e) {
      // Handled by loading/error state
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _populateForm(Profile profile) {
    _fullNameController.text = profile.fullName;
    _phoneNumberController.text = profile.phoneNumber ?? '';
    _ageController.text = profile.age?.toString() ?? '';
    _genderController.text = profile.gender ?? '';
    _educationAttainmentController.text = profile.educationAttainment ?? '';
    _maritalStatusController.text = profile.maritalStatus ?? '';
    _jobRoleController.text = profile.jobRole ?? '';
    _industryController.text = profile.industry ?? '';
    _departmentController.text = profile.department ?? '';
    _yearsOfExperienceController.text =
        profile.yearsOfExperience?.toString() ?? '';
    _targetDailyHoursController.text =
        profile.targetDailyHours?.toString() ?? '';
    _hireDateController.text = profile.hireDate ?? '';
    if (profile.shiftStartTime != null) {
      final parts = profile.shiftStartTime!.split(':');
      if (parts.length >= 2) {
        _shiftStartTime = TimeOfDay(
          hour: int.tryParse(parts[0]) ?? 8,
          minute: int.tryParse(parts[1]) ?? 0,
        );
      }
    }
    if (profile.shiftEndTime != null) {
      final parts = profile.shiftEndTime!.split(':');
      if (parts.length >= 2) {
        _shiftEndTime = TimeOfDay(
          hour: int.tryParse(parts[0]) ?? 17,
          minute: int.tryParse(parts[1]) ?? 0,
        );
      }
    }
    _selectedWorkDays.clear();
    if (profile.workDays != null && profile.workDays!.isNotEmpty) {
      _selectedWorkDays
          .addAll(profile.workDays!.map((day) => day.toLowerCase().trim()));
    } else {
      // Default to Monday-Friday if none specified
      _selectedWorkDays.addAll(['monday', 'tuesday', 'wednesday', 'thursday', 'friday']);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    if (!mounted) return;
    setState(() {
      _uploadError = null;
    });

    final profileImageService = ProfileImageService();
    try {
      final pickedFile = await profileImageService.pickImage(source: source);
      if (pickedFile == null) return;
      setState(() {
        _selectedImageFile = pickedFile;
        _isUploading = true;
      });

      final downloadUrl = await profileImageService.uploadProfileImage(pickedFile);
      if (!mounted) return;

      final profileProvider =
          Provider.of<ProfileProvider>(context, listen: false);
      await profileProvider.updateProfile({'profile_image_url': downloadUrl});

      setState(() {
        _isUploading = false;
        _selectedImageFile = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile image updated'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _uploadError = e.toString();
      });
    }
  }

  Future<void> _removeImage() async {
    if (!mounted) return;
    try {
      final profileImageService = ProfileImageService();
      await profileImageService.deleteProfileImage();

      if (!mounted) return;
      final profileProvider =
          Provider.of<ProfileProvider>(context, listen: false);
      await profileProvider.updateProfile({'profile_image_url': null});

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile image removed'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploadError = e.toString();
      });
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final updateData = <String, dynamic>{};

      void addIfNotEmpty(String key, String value) {
        if (value.isNotEmpty) {
          updateData[key] = value;
        } else {
          updateData[key] = null;
        }
      }

      void addIfNotEmptyInt(String key, int? value) {
        if (value != null) {
          updateData[key] = value;
        } else {
          updateData[key] = null;
        }
      }

      addIfNotEmpty('full_name', _fullNameController.text.trim());
      addIfNotEmpty('phone_number', _phoneNumberController.text.trim());
      addIfNotEmptyInt('age', int.tryParse(_ageController.text.trim()));
      addIfNotEmpty('gender', _genderController.text.trim());
      addIfNotEmpty('education_attainment', _educationAttainmentController.text.trim());
      addIfNotEmpty('marital_status', _maritalStatusController.text.trim());
      addIfNotEmpty('job_role', _jobRoleController.text.trim());
      addIfNotEmpty('industry', _industryController.text.trim());
      addIfNotEmpty('department', _departmentController.text.trim());
      addIfNotEmptyInt('years_of_experience', int.tryParse(_yearsOfExperienceController.text.trim()));
      addIfNotEmptyInt('target_daily_hours', int.tryParse(_targetDailyHoursController.text.trim()));
      addIfNotEmpty('hire_date', _hireDateController.text.trim());

      if (_shiftStartTime != null) {
        updateData['shift_start_time'] =
            '${_shiftStartTime!.hour.toString().padLeft(2, '0')}:${_shiftStartTime!.minute.toString().padLeft(2, '0')}';
      }
      if (_shiftEndTime != null) {
        updateData['shift_end_time'] =
            '${_shiftEndTime!.hour.toString().padLeft(2, '0')}:${_shiftEndTime!.minute.toString().padLeft(2, '0')}';
      }

      updateData['work_days'] = _selectedWorkDays.toList();

      final profileProvider =
          Provider.of<ProfileProvider>(context, listen: false);
      await profileProvider.updateProfile(updateData);

      try {
        final token = await ApiService().getToken();
        if (token != null) {
          final wpData = {
            'schedule_type': _wpScheduleType,
            'arrangement': _wpArrangement,
            'typical_focus_duration': _wpTypicalFocus,
            'preferred_focus_duration': _wpPreferredFocus,
            'typical_break_frequency': _wpTypicalBreakFrequency,
            'typical_break_duration': _wpTypicalBreakDuration,
            'lunch_start_time': _wpLunchStartTime,
            'lunch_duration': _wpLunchDuration,
            'lunch_consistency': _wpLunchConsistency,
            'responsibilities': _wpResponsibilities,
            'reminder_preference': _wpReminderPreference,
            'recommendation_style': _wpRecommendationStyle,
            'profile_completed': true,
          };
          if (_hasWorkProfile) {
            await ApiService().updateWorkProfile(token, wpData);
          } else {
            await ApiService().saveWorkProfile(token, wpData);
            _hasWorkProfile = true;
          }
        }
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
        if (widget.onSaved != null) {
          widget.onSaved!();
        } else {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  List<String> _getUniqueItems(List<String> items) {
    return items.toSet().toList();
  }

  List<String> _getDropdownItems(List<String> items, String currentValue) {
    final uniqueItems = _getUniqueItems(items);
    if (currentValue.isNotEmpty && !uniqueItems.contains(currentValue)) {
      return [...uniqueItems, currentValue];
    }
    return uniqueItems;
  }

  @override
  Widget build(BuildContext context) {
    final themeController = Provider.of<ThemeController>(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = themeController.isHighContrast;

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
            ? const Color(0xFF1B1D24)
            : Colors.white;
    final Color accentColor = themeController.accentColor;

    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isWide = screenWidth >= 900;
    final bool isTablet = screenWidth >= 600 && screenWidth < 900;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Page Header
            Text(
              'Edit profile',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: primaryText,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Update personal details, work information and the regular work schedule.',
              style: TextStyle(
                fontSize: 14,
                color: secondaryText,
              ),
            ),
            const SizedBox(height: 24),

            // 2. Identity Header Card
            Card(
              elevation: 2,
              color: surfaceColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: borderColor),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: _buildIdentityHeader(
                  context,
                  primaryText,
                  secondaryText,
                  borderColor,
                  accentColor,
                  isDark,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 3. Personal Information Section
            Card(
              elevation: 2,
              color: surfaceColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: borderColor),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: _buildSectionLayout(
                  context,
                  title: 'Personal Information',
                  description: 'Demographic details and personal contact information.',
                  fields: _buildPersonalInfoFields(isDark, isHighContrast, borderColor, primaryText, secondaryText),
                  isWide: isWide,
                  isTablet: isTablet,
                  primaryText: primaryText,
                  secondaryText: secondaryText,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 4. Work Information Section
            Card(
              elevation: 2,
              color: surfaceColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: borderColor),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: _buildSectionLayout(
                  context,
                  title: 'Work Information',
                  description: 'Employment role, department, experience, and hire date.',
                  fields: _buildWorkInfoFields(isDark, isHighContrast, borderColor, primaryText, secondaryText),
                  isWide: isWide,
                  isTablet: isTablet,
                  primaryText: primaryText,
                  secondaryText: secondaryText,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 5. Work Schedule Section
            Card(
              elevation: 2,
              color: surfaceColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: borderColor),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: _buildSectionLayout(
                  context,
                  title: 'Work Schedule',
                  description: 'Target daily hours, shift timings, and working days.',
                  fields: _buildWorkScheduleFields(isDark, isHighContrast, borderColor, primaryText, secondaryText, accentColor),
                  isWide: isWide,
                  isTablet: isTablet,
                  primaryText: primaryText,
                  secondaryText: secondaryText,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 6. Work Profile & Onboarding Questionnaire Section
            Card(
              elevation: 2,
              color: surfaceColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: borderColor),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: _buildSectionLayout(
                  context,
                  title: 'Work Profile & Onboarding Questionnaire',
                  description: 'Self-reported work habits, focus durations, and break preferences for personalized recommendations.',
                  fields: [
                    DropdownButtonFormField<String>(
                      value: _wpScheduleType,
                      decoration: const InputDecoration(labelText: 'Schedule Type'),
                      items: const [
                        DropdownMenuItem(value: 'fixed', child: Text('Fixed Schedule')),
                        DropdownMenuItem(value: 'flexible', child: Text('Flexible Schedule')),
                        DropdownMenuItem(value: 'variable', child: Text('Variable Schedule')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _wpScheduleType = val);
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _wpArrangement,
                      decoration: const InputDecoration(labelText: 'Work Arrangement'),
                      items: const [
                        DropdownMenuItem(value: 'remote', child: Text('Remote (Work from Home)')),
                        DropdownMenuItem(value: 'office', child: Text('Office')),
                        DropdownMenuItem(value: 'hybrid', child: Text('Hybrid')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _wpArrangement = val);
                      },
                    ),
                    const SizedBox(height: 20),
                    Text('Typical Focus Duration: $_wpTypicalFocus minutes', style: TextStyle(color: primaryText, fontWeight: FontWeight.w500)),
                    Slider(
                      value: _wpTypicalFocus.toDouble(),
                      min: 15,
                      max: 180,
                      divisions: 11,
                      label: '$_wpTypicalFocus mins',
                      onChanged: (val) => setState(() => _wpTypicalFocus = val.toInt()),
                    ),
                    const SizedBox(height: 16),
                    Text('Preferred Focus Duration: $_wpPreferredFocus minutes', style: TextStyle(color: primaryText, fontWeight: FontWeight.w500)),
                    Slider(
                      value: _wpPreferredFocus.toDouble(),
                      min: 15,
                      max: 120,
                      divisions: 7,
                      label: '$_wpPreferredFocus mins',
                      onChanged: (val) => setState(() => _wpPreferredFocus = val.toInt()),
                    ),
                    const SizedBox(height: 16),
                    Text('Typical Breaks Per Day: $_wpTypicalBreakFrequency', style: TextStyle(color: primaryText, fontWeight: FontWeight.w500)),
                    Slider(
                      value: _wpTypicalBreakFrequency.toDouble(),
                      min: 1,
                      max: 12,
                      divisions: 11,
                      label: '$_wpTypicalBreakFrequency breaks',
                      onChanged: (val) => setState(() => _wpTypicalBreakFrequency = val.toInt()),
                    ),
                    const SizedBox(height: 16),
                    Text('Typical Break Duration: $_wpTypicalBreakDuration minutes', style: TextStyle(color: primaryText, fontWeight: FontWeight.w500)),
                    Slider(
                      value: _wpTypicalBreakDuration.toDouble(),
                      min: 5,
                      max: 60,
                      divisions: 11,
                      label: '$_wpTypicalBreakDuration mins',
                      onChanged: (val) => setState(() => _wpTypicalBreakDuration = val.toInt()),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      initialValue: _wpLunchStartTime,
                      decoration: const InputDecoration(labelText: 'Lunch Start Time (HH:MM)', hintText: '12:30'),
                      onChanged: (val) => _wpLunchStartTime = val,
                    ),
                    const SizedBox(height: 16),
                    Text('Lunch Duration: $_wpLunchDuration minutes', style: TextStyle(color: primaryText, fontWeight: FontWeight.w500)),
                    Slider(
                      value: _wpLunchDuration.toDouble(),
                      min: 15,
                      max: 120,
                      divisions: 7,
                      label: '$_wpLunchDuration mins',
                      onChanged: (val) => setState(() => _wpLunchDuration = val.toInt()),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _wpLunchConsistency,
                      decoration: const InputDecoration(labelText: 'Lunch Consistency'),
                      items: const [
                        DropdownMenuItem(value: 'consistent', child: Text('Consistent')),
                        DropdownMenuItem(value: 'variable', child: Text('Variable')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _wpLunchConsistency = val);
                      },
                    ),
                    const SizedBox(height: 20),
                    Text('Responsibilities (Optional)', style: TextStyle(color: primaryText, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ['Childcare', 'Pet Care', 'Commute', 'Exercise', 'Elder Care'].map((String item) {
                        final bool selected = _wpResponsibilities.contains(item);
                        return FilterChip(
                          label: Text(item),
                          selected: selected,
                          onSelected: (bool val) {
                            setState(() {
                              if (val) {
                                _wpResponsibilities.add(item);
                              } else {
                                _wpResponsibilities.remove(item);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _wpReminderPreference,
                      decoration: const InputDecoration(labelText: 'Reminder Preference'),
                      items: const [
                        DropdownMenuItem(value: 'gentle', child: Text('Gentle')),
                        DropdownMenuItem(value: 'firm', child: Text('Firm')),
                        DropdownMenuItem(value: 'adaptive', child: Text('Adaptive')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _wpReminderPreference = val);
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _wpRecommendationStyle,
                      decoration: const InputDecoration(labelText: 'Recommendation Style'),
                      items: const [
                        DropdownMenuItem(value: 'structured', child: Text('Structured (Pomodoro / Timed)')),
                        DropdownMenuItem(value: 'flexible', child: Text('Flexible (Flow-based)')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _wpRecommendationStyle = val);
                      },
                    ),
                  ],
                  isWide: isWide,
                  isTablet: isTablet,
                  primaryText: primaryText,
                  secondaryText: secondaryText,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 6. Form Actions
            Divider(color: borderColor, height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: _isSaving
                      ? null
                      : (widget.onCancel ?? () => Navigator.of(context).pop()),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: primaryText,
                    side: BorderSide(color: borderColor),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: _isSaving ? null : _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save changes'),
                ),
              ],
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildIdentityHeader(
    BuildContext context,
    Color primaryText,
    Color secondaryText,
    Color borderColor,
    Color accentColor,
    bool isDark,
  ) {
    final profileProvider = Provider.of<ProfileProvider>(context);
    final profile = profileProvider.profile;
    final fullName = profile?.fullName ?? _fullNameController.text;
    final roleAndIndustry =
        '${profile?.jobRole ?? _jobRoleController.text.ifEmpty('Not provided')} • ${profile?.industry ?? _industryController.text.ifEmpty('Not provided')}';

    return Row(
      children: [
        // Avatar
        Container(
          width: 70,
          height: 70,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: borderColor, width: 2),
            image: _selectedImageFile != null
                ? DecorationImage(
                    image: FileImage(File(_selectedImageFile!.path)),
                    fit: BoxFit.cover,
                  )
                : (profile?.profileImageUrl != null &&
                        profile!.profileImageUrl!.isNotEmpty)
                    ? DecorationImage(
                        image: NetworkImage(profile.profileImageUrl!),
                        fit: BoxFit.cover,
                      )
                    : null,
          ),
          child: (_selectedImageFile == null &&
                  (profile?.profileImageUrl == null ||
                      profile!.profileImageUrl!.isEmpty))
              ? Icon(Icons.person, size: 35, color: secondaryText)
              : null,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                fullName.isEmpty ? 'Your Name' : fullName,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: primaryText,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                roleAndIndustry,
                style: TextStyle(
                  fontSize: 13,
                  color: secondaryText,
                ),
              ),
            ],
          ),
        ),
        // Change photo button
        OutlinedButton.icon(
          onPressed: _isUploading
              ? null
              : () {
                  showModalBottomSheet(
                    context: context,
                    builder: (BuildContext context) {
                      return SafeArea(
                        child: Wrap(
                          children: [
                            ListTile(
                              leading: const Icon(Icons.photo_library),
                              title: const Text('Choose from Gallery'),
                              onTap: () {
                                Navigator.of(context).pop();
                                _pickImage(ImageSource.gallery);
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.camera_alt),
                              title: const Text('Take Photo'),
                              onTap: () {
                                Navigator.of(context).pop();
                                _pickImage(ImageSource.camera);
                              },
                            ),
                            if (profile?.profileImageUrl != null &&
                                profile!.profileImageUrl!.isNotEmpty)
                              ListTile(
                                leading: const Icon(Icons.delete),
                                title: const Text('Remove Photo'),
                                onTap: () {
                                  Navigator.of(context).pop();
                                  _removeImage();
                                },
                              ),
                          ],
                        ),
                      );
                    },
                  );
                },
          icon: const Icon(Icons.camera_alt_outlined, size: 16),
          label: const Text('Change photo'),
          style: OutlinedButton.styleFrom(
            foregroundColor: primaryText,
            side: BorderSide(color: borderColor),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionLayout(
    BuildContext context, {
    required String title,
    required String description,
    required List<Widget> fields,
    required bool isWide,
    required bool isTablet,
    required Color primaryText,
    required Color secondaryText,
  }) {
    int crossAxisCount = isWide ? 2 : 1;

    final fieldsGrid = LayoutBuilder(
      builder: (context, constraints) {
        double itemWidth = (constraints.maxWidth - (crossAxisCount - 1) * 24) / crossAxisCount;
        if (itemWidth < 200) itemWidth = constraints.maxWidth;
        return Wrap(
          spacing: 24,
          runSpacing: 20,
          children: fields
              .map(
                (field) => SizedBox(
                  width: field is FullWidthField ? constraints.maxWidth : itemWidth,
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
            width: 240,
            child: Column(
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
                const SizedBox(height: 6),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    color: secondaryText,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 32),
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
          const SizedBox(height: 4),
          Text(
            description,
            style: TextStyle(
              fontSize: 13,
              color: secondaryText,
            ),
          ),
          const SizedBox(height: 20),
          fieldsGrid,
        ],
      );
    }
  }

  List<Widget> _buildPersonalInfoFields(
    bool isDark,
    bool isHighContrast,
    Color borderColor,
    Color primaryText,
    Color secondaryText,
  ) {
    return [
      _buildTextField(
        label: 'Full Name',
        controller: _fullNameController,
        validator: (v) => (v == null || v.isEmpty) ? 'Please enter your full name' : null,
        isDark: isDark,
        isHighContrast: isHighContrast,
        borderColor: borderColor,
        primaryText: primaryText,
        secondaryText: secondaryText,
      ),
      _buildTextField(
        label: 'Phone Number',
        controller: _phoneNumberController,
        isDark: isDark,
        isHighContrast: isHighContrast,
        borderColor: borderColor,
        primaryText: primaryText,
        secondaryText: secondaryText,
      ),
      _buildDropdownField(
        label: 'Gender',
        controller: _genderController,
        items: ['Male', 'Female', 'Other'],
        isDark: isDark,
        isHighContrast: isHighContrast,
        borderColor: borderColor,
        primaryText: primaryText,
        secondaryText: secondaryText,
      ),
      _buildDropdownField(
        label: 'Education Attainment',
        controller: _educationAttainmentController,
        items: [
          'High School',
          'Bachelor\'s Degree',
          'Master\'s Degree',
          'Doctorate',
          'Trade School',
          'Some College'
        ],
        isDark: isDark,
        isHighContrast: isHighContrast,
        borderColor: borderColor,
        primaryText: primaryText,
        secondaryText: secondaryText,
      ),
      _buildDropdownField(
        label: 'Marital Status',
        controller: _maritalStatusController,
        items: ['Single', 'Married', 'Divorced', 'Widowed', 'In a relationship'],
        isDark: isDark,
        isHighContrast: isHighContrast,
        borderColor: borderColor,
        primaryText: primaryText,
        secondaryText: secondaryText,
      ),
    ];
  }

  List<Widget> _buildWorkInfoFields(
    bool isDark,
    bool isHighContrast,
    Color borderColor,
    Color primaryText,
    Color secondaryText,
  ) {
    return [
      _buildDropdownField(
        label: 'Job Role',
        controller: _jobRoleController,
        items: [
          'Engineering',
          'Marketing',
          'Sales',
          'Human Resources',
          'Finance',
          'Operations',
          'Customer Support',
          'Research & Development'
        ],
        isDark: isDark,
        isHighContrast: isHighContrast,
        borderColor: borderColor,
        primaryText: primaryText,
        secondaryText: secondaryText,
      ),
      _buildDropdownField(
        label: 'Industry',
        controller: _industryController,
        items: ['Technology', 'Healthcare', 'Finance', 'Education', 'Retail', 'Manufacturing'],
        isDark: isDark,
        isHighContrast: isHighContrast,
        borderColor: borderColor,
        primaryText: primaryText,
        secondaryText: secondaryText,
      ),
      _buildDropdownField(
        label: 'Department',
        controller: _departmentController,
        items: [
          'Engineering',
          'Marketing',
          'Sales',
          'Human Resources',
          'Finance',
          'Operations',
          'Customer Support',
          'Research & Development'
        ],
        isDark: isDark,
        isHighContrast: isHighContrast,
        borderColor: borderColor,
        primaryText: primaryText,
        secondaryText: secondaryText,
      ),
      _buildTextField(
        label: 'Years of Experience',
        controller: _yearsOfExperienceController,
        keyboardType: TextInputType.number,
        validator: (value) {
          if (value == null || value.isEmpty) return null;
          final int? years = int.tryParse(value);
          if (years == null || years < 0) return 'Enter a valid number';
          return null;
        },
        isDark: isDark,
        isHighContrast: isHighContrast,
        borderColor: borderColor,
        primaryText: primaryText,
        secondaryText: secondaryText,
      ),
      _buildDateField(
        label: 'Hire Date',
        controller: _hireDateController,
        isDark: isDark,
        isHighContrast: isHighContrast,
        borderColor: borderColor,
        primaryText: primaryText,
        secondaryText: secondaryText,
      ),
    ];
  }

  List<Widget> _buildWorkScheduleFields(
    bool isDark,
    bool isHighContrast,
    Color borderColor,
    Color primaryText,
    Color secondaryText,
    Color accentColor,
  ) {
    return [
      _buildTextField(
        label: 'Target Daily Hours',
        controller: _targetDailyHoursController,
        keyboardType: TextInputType.number,
        validator: (value) {
          if (value == null || value.isEmpty) return null;
          final int? hours = int.tryParse(value);
          if (hours == null || hours < 1 || hours > 24) return 'Enter 1 - 24 hours';
          return null;
        },
        isDark: isDark,
        isHighContrast: isHighContrast,
        borderColor: borderColor,
        primaryText: primaryText,
        secondaryText: secondaryText,
      ),
      _buildTimeField(
        label: 'Shift Start Time',
        isDark: isDark,
        isHighContrast: isHighContrast,
        borderColor: borderColor,
        primaryText: primaryText,
        secondaryText: secondaryText,
        onTimeSelected: (t) => setState(() => _shiftStartTime = t),
        initialTime: _shiftStartTime,
        timeOfDay: _shiftStartTime,
      ),
      _buildTimeField(
        label: 'Shift End Time',
        isDark: isDark,
        isHighContrast: isHighContrast,
        borderColor: borderColor,
        primaryText: primaryText,
        secondaryText: secondaryText,
        onTimeSelected: (t) => setState(() => _shiftEndTime = t),
        initialTime: _shiftEndTime,
        timeOfDay: _shiftEndTime,
      ),
      FullWidthField(
        child: _buildWorkDaysSelector(isDark, borderColor, primaryText, secondaryText, accentColor),
      ),
    ];
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
    required bool isDark,
    required bool isHighContrast,
    required Color borderColor,
    required Color primaryText,
    required Color secondaryText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: secondaryText,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          style: TextStyle(color: primaryText, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Enter $label',
            hintStyle: TextStyle(color: secondaryText.withValues(alpha: 0.5)),
            filled: true,
            fillColor: isDark ? const Color(0xFF252833) : Colors.grey.shade50,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Theme.of(context).colorScheme.secondary, width: 1.5),
            ),
          ),
          validator: validator,
        ),
      ],
    );
  }

  Widget _buildDropdownField({
    required String label,
    required TextEditingController controller,
    required List<String> items,
    required bool isDark,
    required bool isHighContrast,
    required Color borderColor,
    required Color primaryText,
    required Color secondaryText,
  }) {
    final currentValue = controller.text;
    final dropdownItems = _getDropdownItems(items, currentValue);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: secondaryText,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: currentValue.isNotEmpty && dropdownItems.contains(currentValue)
              ? currentValue
              : null,
          dropdownColor: isDark ? const Color(0xFF1B1D24) : Colors.white,
          style: TextStyle(color: primaryText, fontSize: 14),
          items: dropdownItems
              .map((item) => DropdownMenuItem(
                    value: item,
                    child: Text(item.capitalize(), style: TextStyle(color: primaryText)),
                  ))
              .toList(),
          onChanged: (value) {
            if (value != null) {
              controller.text = value;
            }
          },
          decoration: InputDecoration(
            hintText: 'Select $label',
            hintStyle: TextStyle(color: secondaryText.withValues(alpha: 0.5)),
            filled: true,
            fillColor: isDark ? const Color(0xFF252833) : Colors.grey.shade50,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Theme.of(context).colorScheme.secondary, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDateField({
    required String label,
    required TextEditingController controller,
    required bool isDark,
    required bool isHighContrast,
    required Color borderColor,
    required Color primaryText,
    required Color secondaryText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: secondaryText,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          style: TextStyle(color: primaryText, fontSize: 14),
          readOnly: true,
          decoration: InputDecoration(
            hintText: 'YYYY-MM-DD',
            hintStyle: TextStyle(color: secondaryText.withValues(alpha: 0.5)),
            suffixIcon: Icon(Icons.calendar_today_outlined, size: 18, color: secondaryText),
            filled: true,
            fillColor: isDark ? const Color(0xFF252833) : Colors.grey.shade50,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Theme.of(context).colorScheme.secondary, width: 1.5),
            ),
          ),
          onTap: () async {
            final DateTime? picked = await showDatePicker(
              context: context,
              initialDate: DateTime.tryParse(controller.text) ?? DateTime.now(),
              firstDate: DateTime(1950),
              lastDate: DateTime.now(),
            );
            if (picked != null && mounted) {
              setState(() {
                controller.text =
                    '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
              });
            }
          },
        ),
      ],
    );
  }

  Widget _buildTimeField({
    required String label,
    required bool isDark,
    required bool isHighContrast,
    required Color borderColor,
    required Color primaryText,
    required Color secondaryText,
    required void Function(TimeOfDay) onTimeSelected,
    TimeOfDay? initialTime,
    TimeOfDay? timeOfDay,
  }) {
    final timeStr = timeOfDay != null
        ? '${timeOfDay.hour.toString().padLeft(2, '0')}:${timeOfDay.minute.toString().padLeft(2, '0')}'
        : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: secondaryText,
          ),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: () async {
            final TimeOfDay? picked = await showTimePicker(
              context: context,
              initialTime: timeOfDay ?? initialTime ?? const TimeOfDay(hour: 9, minute: 0),
            );
            if (picked != null && mounted) {
              onTimeSelected(picked);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF252833) : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  timeStr.isNotEmpty ? timeStr : 'Select time',
                  style: TextStyle(
                    color: timeStr.isNotEmpty ? primaryText : secondaryText.withValues(alpha: 0.5),
                    fontSize: 14,
                  ),
                ),
                Icon(Icons.access_time_outlined, size: 18, color: secondaryText),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWorkDaysSelector(
    bool isDark,
    Color borderColor,
    Color primaryText,
    Color secondaryText,
    Color accentColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Work Days',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: secondaryText,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _daysOfWeek.map((day) {
            final isSelected = _selectedWorkDays.contains(day);
            return FilterChip(
              label: Text(day.capitalize()),
              selected: isSelected,
              onSelected: (bool selected) {
                setState(() {
                  if (selected) {
                    _selectedWorkDays.add(day);
                  } else {
                    _selectedWorkDays.remove(day);
                  }
                });
              },
              backgroundColor: isDark ? const Color(0xFF252833) : Colors.grey.shade100,
              selectedColor: accentColor.withValues(alpha: 0.25),
              checkmarkColor: accentColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color: isSelected ? accentColor : borderColor,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              labelStyle: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? accentColor : primaryText,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class FullWidthField extends StatelessWidget {
  final Widget child;
  const FullWidthField({super.key, required this.child});

  @override
  Widget build(BuildContext context) => child;
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
