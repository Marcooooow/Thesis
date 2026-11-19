import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intellibreak/core/design_system.dart';
import 'package:intellibreak/core/theme/theme_controller.dart';
import 'package:intellibreak/features/auth/widgets/auth_card.dart';
import 'package:intellibreak/features/auth/widgets/auth_layout.dart';
import 'package:intellibreak/features/auth/widgets/auth_logo.dart';
import 'package:intellibreak/features/auth/widgets/auth_form_field.dart';
import 'package:intellibreak/features/auth/widgets/auth_header.dart';
import 'package:intellibreak/features/auth/widgets/password_strength_indicator.dart';
import 'package:intellibreak/features/auth/services/api_service.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // ============================================================
  // GENERAL
  // ============================================================

  int _currentStep = 0;
  bool _isLoading = false;
  String? _generalError;

  // ============================================================
  // STEP 1 - ACCOUNT
  // ============================================================

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final TextEditingController _organizationController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void initState() {
    super.initState();
    // Listen to password changes to update strength indicator
    _passwordController.addListener(() {
      setState(() {});
    });
    _confirmPasswordController.addListener(() {
      setState(() {});
    });
  }

  // User role selection - always EMPLOYEE for security (cannot be changed via UI)
  final String _userRole = 'EMPLOYEE';

  // Account type selection
  String _accountType = 'solo'; // 'solo' or 'organization'
  String? _organizationError;

  // Work Profile Onboarding State
  String _scheduleType = 'flexible';
  String _arrangement = 'remote';
  int _typicalFocusDuration = 60;
  int _preferredFocusDuration = 45;
  int _typicalBreakFrequency = 4;
  int _typicalBreakDuration = 15;
  String _lunchStartTime = '12:30';
  int _lunchDuration = 45;
  String _lunchConsistency = 'consistent';
  final TextEditingController _scheduleTypeOtherController = TextEditingController();
  final TextEditingController _arrangementOtherController = TextEditingController();
  final TextEditingController _lunchConsistencyOtherController = TextEditingController();
  final TextEditingController _reminderPreferenceOtherController = TextEditingController();
  final TextEditingController _recommendationStyleOtherController = TextEditingController();
  final List<String> _responsibilities = [];
  String _reminderPreference = 'gentle';
  String _recommendationStyle = 'structured';

  int get _totalSteps => _accountType == 'solo' ? 6 : 5;

  // Terms of Use
  bool _termsAgreed = false;
  String? _termsError;

  // ============================================================
  // STEP 2 - PERSONAL INFORMATION
  // ============================================================

  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _jobRoleController = TextEditingController();
  final TextEditingController _industryController = TextEditingController();
  final TextEditingController _genderOtherController = TextEditingController();
  final TextEditingController _educationOtherController = TextEditingController();
  final TextEditingController _maritalOtherController = TextEditingController();
  final TextEditingController _jobRoleOtherController = TextEditingController();
  final TextEditingController _industryOtherController = TextEditingController();

  String? _selectedGender;
  String? _selectedEducation;
  String? _selectedMaritalStatus;

  final List<String> _genders = [
    'Male',
    'Female',
    'Other',
    'Prefer not to say',
  ];

  final List<String> _educationLevels = [
    'High School',
    'Vocational / Technical',
    'Associate Degree',
    "Bachelor's Degree",
    "Master's Degree",
    'Doctorate',
    'Other',
  ];

  final List<String> _maritalStatuses = [
    'Single',
    'Married',
    'Divorced',
    'Widowed',
    'Prefer not to say',
  ];

  // ============================================================
  // STEP 3 - WORK INFORMATION
  // ====================================================

  String? _selectedJobRole;
  String? _selectedIndustry;

  final TextEditingController _experienceController = TextEditingController();

  final List<String> _jobRoles = [
    'Software Developer',
    'Web Developer',
    'Mobile Developer',
    'UI/UX Designer',
    'Graphic Designer',
    'Project Manager',
    'Accountant',
    'Teacher',
    'Engineer',
    'Architect',
    'Administrative Assistant',
    'Customer Service Representative',
    'Marketing Specialist',
    'Sales Representative',
    'Human Resources',
    'Healthcare Professional',
    'Student',
    'Other',
  ];

  final List<String> _industries = [
    'Information Technology',
    'Construction',
    'Architecture',
    'Education',
    'Healthcare',
    'Finance',
    'Retail',
    'Manufacturing',
    'Hospitality',
    'Government',
    'Transportation',
    'Marketing',
    'Other',
  ];

  // ====================================================
  // STEP 4 - WORK SCHEDULE
  // ====================================================

  double _dailyHours = 8;

  TimeOfDay _shiftStart = const TimeOfDay(hour: 8, minute: 0);

  TimeOfDay _shiftEnd = const TimeOfDay(hour: 17, minute: 0);

  final Map<String, bool> _workingDays = {
    'Monday': true,
    'Tuesday': true,
    'Wednesday': true,
    'Thursday': true,
    'Friday': true,
    'Saturday': false,
    'Sunday': false,
  };

  // ====================================================
  // STEP 5 - DATA CONSENT
  // ====================================================

  bool _dataConsent = false;

  // ====================================================
  // DISPOSE
  // ====================================================

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _organizationController.dispose();
    _ageController.dispose();
    _experienceController.dispose();
    _jobRoleController.dispose();
    _industryController.dispose();
    _genderOtherController.dispose();
    _educationOtherController.dispose();
    _maritalOtherController.dispose();
    _jobRoleOtherController.dispose();
    _industryOtherController.dispose();
    _scheduleTypeOtherController.dispose();
    _arrangementOtherController.dispose();
    _lunchConsistencyOtherController.dispose();
    _reminderPreferenceOtherController.dispose();
    _recommendationStyleOtherController.dispose();
    super.dispose();
  }

  // ====================================================
  // NAVIGATION
  // ====================================================

  void _nextStep() {
    if (!_validateCurrentStep()) {
      return;
    }

    if (_currentStep < _totalSteps - 1) {
      setState(() {
        _currentStep++;
      });
    } else {
      _completeRegistration();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
      });
    } else {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              LoginScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    }
  }

  bool _validateCurrentStep() {
    if (_accountType == 'solo') {
      switch (_currentStep) {
        case 0:
          return _validateAccount();

        case 1:
          return _validatePersonal();

        case 2:
          return _validateWork();

        case 3:
          return _validateSchedule();

        case 4:
          return _validateWorkProfile();

        case 5:
          return _validateConsent();

        default:
          return false;
      }
    } else {
      switch (_currentStep) {
        case 0:
          return _validateAccount();

        case 1:
          return _validatePersonal();

        case 2:
          return _validateWork();

        case 3:
          return _validateSchedule();

        case 4:
          return _validateConsent();

        default:
          return false;
      }
    }
  }

  // ====================================================
  // VALIDATION
  // ====================================================

  bool _validateAccount() {
    // Clear previous field errors
    setState(() {
      _organizationError = null;
      _termsError = null;
      _generalError = null;
    });

    bool isValid = true;

    if (_nameController.text.trim().isEmpty) {
      _showGeneralError('Please enter your full name.');
      return false;
    }

    if (_emailController.text.trim().isEmpty) {
      _showGeneralError('Please enter your email.');
      return false;
    }

    if (!_emailController.text.contains('@')) {
      _showGeneralError('Please enter a valid email address.');
      return false;
    }

    if (_passwordController.text.length < 12) {
      _showGeneralError('Password must be at least 12 characters.');
      return false;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      _showGeneralError('Passwords do not match.');
      return false;
    }

    // Validate user role selection for Organization accounts only
    if (_accountType == 'organization' && _userRole.isEmpty) {
      // This should never happen as we have a default value, but keeping for safety
      isValid = false;
    }

    // Validate organization name for Organization accounts
    if (_accountType == 'organization') {
      if (_organizationController.text.trim().isEmpty) {
        setState(() {
          _organizationError = 'Please enter your organization name.';
        });
        isValid = false;
      }
    }

    // Validate Terms of Use (required for both account types)
    if (!_termsAgreed) {
      setState(() {
        _termsError = 'Please agree to the IntelliBreak Terms of Use.';
      });
      isValid = false;
    }

    return isValid;
  }

  bool _validatePersonal() {
    final age = int.tryParse(_ageController.text);

    if (age == null) {
      _showError('Please enter a valid age.');
      return false;
    }

    if (age < 18 || age > 100) {
      _showError('Age must be between 18 and 100.');
      return false;
    }

    if (_selectedGender == null) {
      _showError('Please select your gender.');
      return false;
    }

    // Validate gender "Other" field
    if (_selectedGender == 'Other' &&
        _genderOtherController.text.trim().isEmpty) {
      _showError('Please specify your gender.');
      return false;
    }

    if (_selectedEducation == null) {
      _showError('Please select your education attainment.');
      return false;
    }

    // Validate education "Other" field
    if (_selectedEducation == 'Other' &&
        _educationOtherController.text.trim().isEmpty) {
      _showError('Please specify your education attainment.');
      return false;
    }

    if (_selectedMaritalStatus == null) {
      _showError('Please select your marital status.');
      return false;
    }

    // Validate marital status "Other" field
    if (_selectedMaritalStatus == 'Other' &&
        _maritalOtherController.text.trim().isEmpty) {
      _showError('Please specify your marital status.');
      return false;
    }

    return true;
  }

  bool _validateWork() {
    if (_selectedJobRole == null) {
      _showError('Please select your job role.');
      return false;
    }

    // Validate job role "Other" field
    if (_selectedJobRole == 'Other' &&
        _jobRoleOtherController.text.trim().isEmpty) {
      _showError('Please specify your job role.');
      return false;
    }

    if (_selectedIndustry == null) {
      _showError('Please select your industry.');
      return false;
    }

    // Validate industry "Other" field
    if (_selectedIndustry == 'Other' &&
        _industryOtherController.text.trim().isEmpty) {
      _showError('Please specify your industry.');
      return false;
    }

    final experience = double.tryParse(_experienceController.text);

    if (experience == null || experience < 0) {
      _showError('Please enter your years of experience.');
      return false;
    }

    return true;
  }

  bool _validateSchedule() {
    final selectedDays = _workingDays.values.where((day) => day).length;

    if (selectedDays == 0) {
      _showError('Please select at least one working day.');
      return false;
    }

    return true;
  }

  bool _validateWorkProfile() {
    final otherChoices = <({String value, TextEditingController controller, String label})>[
      (value: _scheduleType, controller: _scheduleTypeOtherController, label: 'schedule type'),
      (value: _arrangement, controller: _arrangementOtherController, label: 'work arrangement'),
      (value: _lunchConsistency, controller: _lunchConsistencyOtherController, label: 'lunch consistency'),
      (value: _reminderPreference, controller: _reminderPreferenceOtherController, label: 'reminder preference'),
      (value: _recommendationStyle, controller: _recommendationStyleOtherController, label: 'recommendation style'),
    ];
    for (final choice in otherChoices) {
      if (choice.value == 'other' && choice.controller.text.trim().isEmpty) {
        _showError('Please specify your ${choice.label}.');
        return false;
      }
    }
    return true;
  }

  Widget _otherChoiceField({
    required String value,
    required TextEditingController controller,
    required String label,
  }) {
    if (value != 'other') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: TextFormField(
        controller: controller,
        maxLength: 50,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: 'Specify $label'),
      ),
    );
  }

  bool _validateConsent() {
    if (!_dataConsent) {
      _showError('Please provide consent before creating your account.');
      return false;
    }

    return true;
  }

  Future<void> _completeRegistration() async {
    setState(() {
      _isLoading = true;
    });

    final apiService = ApiService();

    try {
      // Determine approval status based on account type
      final String organizationName = _accountType == 'organization'
          ? _organizationController.text.trim()
          : '';

      // Attempt to register the user with email, password, and full name
      Map<String, dynamic>? workProfile;
      if (_accountType == 'solo') {
        workProfile = {
          'schedule_type': _scheduleType == 'other' ? _scheduleTypeOtherController.text.trim() : _scheduleType,
          'arrangement': _arrangement == 'other' ? _arrangementOtherController.text.trim() : _arrangement,
          'typical_focus_duration': _typicalFocusDuration,
          'preferred_focus_duration': _preferredFocusDuration,
          'typical_break_frequency': _typicalBreakFrequency,
          'typical_break_duration': _typicalBreakDuration,
          'lunch_start_time': _lunchStartTime,
          'lunch_duration': _lunchDuration,
          'lunch_consistency': _lunchConsistency == 'other' ? _lunchConsistencyOtherController.text.trim() : _lunchConsistency,
          'responsibilities': _responsibilities,
          'reminder_preference': _reminderPreference == 'other' ? _reminderPreferenceOtherController.text.trim() : _reminderPreference,
          'recommendation_style': _recommendationStyle == 'other' ? _recommendationStyleOtherController.text.trim() : _recommendationStyle,
          'profile_completed': true,
        };
      }

      await apiService.register(
        _emailController.text.trim(),
        _passwordController.text,
        _nameController.text.trim(),
        role: _userRole,
        accountType: _accountType,
        organizationName: organizationName,
        jobRole: _selectedJobRole == 'Other' ? _jobRoleOtherController.text.trim() : _selectedJobRole,
        industry: _selectedIndustry == 'Other' ? _industryOtherController.text.trim() : _selectedIndustry,
        yearsOfExperience: _experienceController.text.isNotEmpty
            ? int.tryParse(_experienceController.text)
            : null,
        age: _ageController.text.isNotEmpty
            ? int.tryParse(_ageController.text)
            : null,
        gender: _selectedGender == 'Other' ? _genderOtherController.text.trim() : _selectedGender,
        educationAttainment: _selectedEducation == 'Other' ? _educationOtherController.text.trim() : _selectedEducation,
        maritalStatus: _selectedMaritalStatus == 'Other' ? _maritalOtherController.text.trim() : _selectedMaritalStatus,
        targetDailyHours: _dailyHours.toInt(),
        shiftStartTime:
            '${_shiftStart.hour.toString().padLeft(2, '0')}:${_shiftStart.minute.toString().padLeft(2, '0')}',
        shiftEndTime:
            '${_shiftEnd.hour.toString().padLeft(2, '0')}:${_shiftEnd.minute.toString().padLeft(2, '0')}',
        workDays: _workingDays.entries
            .where((entry) => entry.value)
            .map((entry) => entry.key.toLowerCase())
            .toList(),
        workProfile: workProfile,
      );

      if (mounted) {
        // Show appropriate success message based on account type
        final message = _accountType == 'solo'
            ? 'Registration successful. You can now log in.'
            : 'Registration successful. Your account is waiting for manager approval.';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.green),
        );
        // Navigate back to the login screen
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Unable to create your account. Please check your information and try again.';

        // Parse error message to provide specific guidance
        final errorStr = e.toString().toLowerCase();
        if (errorStr.contains('email') || errorStr.contains('already exists')) {
          errorMessage = 'An account with this email already exists. Please use a different email.';
          // Don't reset step - let user fix email on current step
        } else if (errorStr.contains('password')) {
          errorMessage = 'Password must be at least 12 characters long.';
          // Don't reset step - let user fix password on current step
        } else if (errorStr.contains('validation') || errorStr.contains('invalid')) {
          errorMessage = 'Please check your information and try again.';
        }

        setState(() {
          _generalError = errorMessage;
          _isLoading = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showGeneralError(String message) {
    setState(() {
      _generalError = message;
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.redAccent));
  }

  // ====================================================
  // MAIN BUILD
  // ====================================================

  @override
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: AuthLayout(
        desktop: _buildDesktopRegister(context),
        tablet: _buildTabletRegister(context),
        mobile: _buildMobileRegister(context),
      ),
    );
  }

  Widget _buildMobileRegister(BuildContext context) =>
      _buildFullPageRegister(context, maxWidth: 600);

  Widget _buildTabletRegister(BuildContext context) =>
      _buildFullPageRegister(context, maxWidth: 600);

  Widget _buildDesktopRegister(BuildContext context) =>
      _buildFullPageRegister(context, maxWidth: 600);

  Widget _buildFullPageRegister(BuildContext context, {double maxWidth = 600}) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Stack(
        children: [
          // Theme toggle (top-right)
          Positioned(
            top: 24,
            right: 24,
            child: IconButton(
              onPressed: () {
                final themeController = Provider.of<ThemeController>(
                  context,
                  listen: false,
                );
                themeController.setThemeMode(
                  themeController.themeMode == ThemeMode.light
                      ? ThemeMode.dark
                      : ThemeMode.light,
                );
              },
              icon: Icon(
                Theme.of(context).brightness == Brightness.dark
                    ? Icons.sunny
                    : Icons.nightlight_round,
                color: DesignSystem.getSemanticColor(
                  context,
                  SemanticColor.onSurfaceVariant,
                ),
              ),
            ),
          ),
          // Main content centered on full screen
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: AuthCard(child: _buildRegisterForm(context)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegisterForm(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AuthLogo(),
        SizedBox(height: DesignSystem.spacingL),
        AuthHeader(
          title: 'Create an account',
          subtitle: 'Step ${_currentStep + 1} of $_totalSteps',
        ),
        SizedBox(height: DesignSystem.spacingXL),
        // Progress bar
        _buildProgressBar(context),
        SizedBox(height: DesignSystem.spacingXL),
        // Current step
        _buildCurrentStep(context),
        SizedBox(height: DesignSystem.spacingL),
        // Navigation buttons
        _buildNavigationButtons(context),
      ],
    );
  }

  // ====================================================
  // PROGRESS BAR
  // ====================================================

  Widget _buildProgressBar(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color completedColor = DesignSystem.getSemanticColor(
      context,
      SemanticColor.primary,
    );
    final Color incompleteColor = isDark
        ? DesignSystem.getSemanticColor(context, SemanticColor.background)
        : DesignSystem.getSemanticColor(context, SemanticColor.surface);

    return Row(
      children: List.generate(_totalSteps, (index) {
        final completed = index <= _currentStep;

        return Expanded(
          child: Container(
            margin: EdgeInsets.only(
              right: index == _totalSteps - 1 ? 0 : DesignSystem.spacingXS,
            ),
            height: DesignSystem.spacingXS,
            decoration: BoxDecoration(
              color: completed ? completedColor : incompleteColor,
              borderRadius: BorderRadius.circular(DesignSystem.radiusS),
            ),
          ),
        );
      }),
    );
  }

  // ====================================================
  // CURRENT STEP
  // ====================================================

  Widget _buildCurrentStep(BuildContext context) {
    switch (_currentStep) {
      case 0:
        return _buildAccountStep(context);

      case 1:
        return _buildPersonalStep(context);

      case 2:
        return _buildWorkStep(context);

      case 3:
        return _buildScheduleStep(context);

      case 4:
        return _accountType == 'solo' ? _buildWorkProfileStep(context) : _buildConsentStep(context);

      case 5:
        return _buildConsentStep(context);

      default:
        return _buildAccountStep(context);
    }
  }

  // ====================================================
  // WORK PROFILE STEP
  // ====================================================

  Widget _buildWorkProfileStep(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : const Color(0xFF171923);
    final Color secondaryTextColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Work Profile & Onboarding',
            style: TextStyle(
              color: textColor,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Customize your baseline work habits for tailored break recommendations.',
            style: TextStyle(
              color: secondaryTextColor,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 24),
          DropdownButtonFormField<String>(
            value: _scheduleType,
            decoration: const InputDecoration(labelText: 'Schedule Type'),
            items: const [
              DropdownMenuItem(value: 'fixed', child: Text('Fixed Schedule')),
              DropdownMenuItem(value: 'flexible', child: Text('Flexible Schedule')),
              DropdownMenuItem(value: 'variable', child: Text('Variable Schedule')),
              DropdownMenuItem(value: 'other', child: Text('Other')),
            ],
            onChanged: (val) {
              if (val != null) setState(() => _scheduleType = val);
            },
          ),
          _otherChoiceField(value: _scheduleType, controller: _scheduleTypeOtherController, label: 'schedule type'),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _arrangement,
            decoration: const InputDecoration(labelText: 'Work Arrangement'),
            items: const [
              DropdownMenuItem(value: 'remote', child: Text('Remote (Work from Home)')),
              DropdownMenuItem(value: 'office', child: Text('Office')),
              DropdownMenuItem(value: 'hybrid', child: Text('Hybrid')),
              DropdownMenuItem(value: 'other', child: Text('Other')),
            ],
            onChanged: (val) {
              if (val != null) setState(() => _arrangement = val);
            },
          ),
          _otherChoiceField(value: _arrangement, controller: _arrangementOtherController, label: 'work arrangement'),
          const SizedBox(height: 20),
          Text('Typical Focus Duration: $_typicalFocusDuration minutes', style: TextStyle(color: textColor, fontWeight: FontWeight.w500)),
          Slider(
            value: _typicalFocusDuration.toDouble(),
            min: 15,
            max: 180,
            divisions: 11,
            label: '$_typicalFocusDuration mins',
            onChanged: (val) => setState(() => _typicalFocusDuration = val.toInt()),
          ),
          const SizedBox(height: 16),
          Text('Preferred Focus Duration: $_preferredFocusDuration minutes', style: TextStyle(color: textColor, fontWeight: FontWeight.w500)),
          Slider(
            value: _preferredFocusDuration.toDouble(),
            min: 15,
            max: 120,
            divisions: 7,
            label: '$_preferredFocusDuration mins',
            onChanged: (val) => setState(() => _preferredFocusDuration = val.toInt()),
          ),
          const SizedBox(height: 16),
          Text('Typical Breaks Per Day: $_typicalBreakFrequency', style: TextStyle(color: textColor, fontWeight: FontWeight.w500)),
          Slider(
            value: _typicalBreakFrequency.toDouble(),
            min: 1,
            max: 12,
            divisions: 11,
            label: '$_typicalBreakFrequency breaks',
            onChanged: (val) => setState(() => _typicalBreakFrequency = val.toInt()),
          ),
          const SizedBox(height: 16),
          Text('Typical Break Duration: $_typicalBreakDuration minutes', style: TextStyle(color: textColor, fontWeight: FontWeight.w500)),
          Slider(
            value: _typicalBreakDuration.toDouble(),
            min: 5,
            max: 60,
            divisions: 11,
            label: '$_typicalBreakDuration mins',
            onChanged: (val) => setState(() => _typicalBreakDuration = val.toInt()),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: TextEditingController(text: _lunchStartTime),
            decoration: const InputDecoration(
              labelText: 'Lunch Start Time (HH:MM)',
              hintText: 'e.g. 12:30',
            ),
            onChanged: (val) => _lunchStartTime = val,
          ),
          const SizedBox(height: 16),
          Text('Lunch Duration: $_lunchDuration minutes', style: TextStyle(color: textColor, fontWeight: FontWeight.w500)),
          Slider(
            value: _lunchDuration.toDouble(),
            min: 15,
            max: 120,
            divisions: 7,
            label: '$_lunchDuration mins',
            onChanged: (val) => setState(() => _lunchDuration = val.toInt()),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _lunchConsistency,
            decoration: const InputDecoration(labelText: 'Lunch Consistency'),
            items: const [
              DropdownMenuItem(value: 'consistent', child: Text('Consistent')),
              DropdownMenuItem(value: 'variable', child: Text('Variable')),
              DropdownMenuItem(value: 'other', child: Text('Other')),
            ],
            onChanged: (val) {
              if (val != null) setState(() => _lunchConsistency = val);
            },
          ),
          _otherChoiceField(value: _lunchConsistency, controller: _lunchConsistencyOtherController, label: 'lunch consistency'),
          const SizedBox(height: 20),
          Text('Responsibilities (Optional)', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['Childcare', 'Pet Care', 'Commute', 'Exercise', 'Elder Care'].map((String item) {
              final bool selected = _responsibilities.contains(item);
              return FilterChip(
                label: Text(item),
                selected: selected,
                onSelected: (bool val) {
                  setState(() {
                    if (val) {
                      _responsibilities.add(item);
                    } else {
                      _responsibilities.remove(item);
                    }
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _reminderPreference,
            decoration: const InputDecoration(labelText: 'Reminder Preference'),
            items: const [
              DropdownMenuItem(value: 'gentle', child: Text('Gentle')),
              DropdownMenuItem(value: 'firm', child: Text('Firm')),
              DropdownMenuItem(value: 'adaptive', child: Text('Adaptive')),
              DropdownMenuItem(value: 'other', child: Text('Other')),
            ],
            onChanged: (val) {
              if (val != null) setState(() => _reminderPreference = val);
            },
          ),
          _otherChoiceField(value: _reminderPreference, controller: _reminderPreferenceOtherController, label: 'reminder preference'),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _recommendationStyle,
            decoration: const InputDecoration(labelText: 'Recommendation Style'),
            items: const [
              DropdownMenuItem(value: 'structured', child: Text('Structured (Pomodoro / Timed)')),
              DropdownMenuItem(value: 'flexible', child: Text('Flexible (Flow-based)')),
              DropdownMenuItem(value: 'other', child: Text('Other')),
            ],
            onChanged: (val) {
              if (val != null) setState(() => _recommendationStyle = val);
            },
          ),
          _otherChoiceField(value: _recommendationStyle, controller: _recommendationStyleOtherController, label: 'recommendation style'),
        ],
      ),
    );
  }

  // ====================================================
  // STEP 1 - ACCOUNT
  // ====================================================

  Widget _buildAccountStep(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Account Information',
          style: TextStyle(
            color: isDark ? Colors.white : Color(0xFF171923),
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Create your IntelliBreak account.',
          style: TextStyle(
            color: isDark ? Color(0xFF9CA3AF) : Color(0xFF6B7280),
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 24),

        // Account Type Selection
        Text('Account Type', style: DesignSystem.textM(context)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _accountType = 'solo';
                    _organizationError = null;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: _accountType == 'solo'
                        ? DesignSystem.getSemanticColor(
                            context,
                            SemanticColor.primary,
                          ).withValues(alpha: 0.1)
                        : (isDark ? Color(0xFF1B1D24) : Colors.white),
                    borderRadius: BorderRadius.circular(DesignSystem.radiusM),
                    border: Border.all(
                      color: _accountType == 'solo'
                          ? DesignSystem.getSemanticColor(
                              context,
                              SemanticColor.primary,
                            )
                          : (isDark ? Color(0xFF30323A) : Color(0xFFE0E0E0)),
                      width: _accountType == 'solo' ? 1.5 : 1,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      'Solo',
                      style: TextStyle(
                        color: _accountType == 'solo'
                            ? DesignSystem.getSemanticColor(
                                context,
                                SemanticColor.primary,
                              )
                            : (isDark ? Color(0xFF9CA3AF) : Color(0xFF6B7280)),
                        fontWeight: _accountType == 'solo'
                            ? FontWeight.w600
                            : FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _accountType = 'organization';
                    _organizationError = null;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: _accountType == 'organization'
                        ? DesignSystem.getSemanticColor(
                            context,
                            SemanticColor.primary,
                          ).withValues(alpha: 0.1)
                        : (isDark ? Color(0xFF1B1D24) : Colors.white),
                    borderRadius: BorderRadius.circular(DesignSystem.radiusM),
                    border: Border.all(
                      color: _accountType == 'organization'
                          ? DesignSystem.getSemanticColor(
                              context,
                              SemanticColor.primary,
                            )
                          : (isDark ? Color(0xFF30323A) : Color(0xFFE0E0E0)),
                      width: _accountType == 'organization' ? 1.5 : 1,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      'Organization',
                      style: TextStyle(
                        color: _accountType == 'organization'
                            ? DesignSystem.getSemanticColor(
                                context,
                                SemanticColor.primary,
                              )
                            : (isDark ? Color(0xFF9CA3AF) : Color(0xFF6B7280)),
                        fontWeight: _accountType == 'organization'
                            ? FontWeight.w600
                            : FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const SizedBox(height: 20),

        AuthFormField(
          label: 'Full Name',
          hintText: 'Enter your full name',
          controller: _nameController,
          prefixIcon: Icons.person_outline_rounded,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Please enter your full name.';
            }
            return null;
          },
        ),
        const SizedBox(height: 20),
        AuthFormField(
          label: 'Email',
          hintText: 'Enter your email',
          controller: _emailController,
          prefixIcon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Please enter your email.';
            }
            if (!value.contains('@')) {
              return 'Please enter a valid email address.';
            }
            return null;
          },
        ),
        const SizedBox(height: 20),
        AuthFormField(
          label: 'Password',
          hintText: 'Create a password',
          controller: _passwordController,
          prefixIcon: Icons.lock_outline_rounded,
          obscureText: _obscurePassword,
          suffixIcon: IconButton(
            onPressed: () {
              setState(() {
                _obscurePassword = !_obscurePassword;
              });
            },
            icon: Icon(
              _obscurePassword
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: isDark ? Color(0xFF9CA3AF) : Color(0xFF6B7280),
            ),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter your password.';
            }
            if (value.length < 12) {
              return 'Password must be at least 12 characters.';
            }
            return null;
          },
        ),
        const SizedBox(height: 12),
        // Password strength indicator
        PasswordStrengthIndicator(
          password: _passwordController.text,
          confirmPassword: _confirmPasswordController.text,
        ),
        AuthFormField(
          label: 'Confirm Password',
          hintText: 'Confirm your password',
          controller: _confirmPasswordController,
          prefixIcon: Icons.lock_outline_rounded,
          obscureText: _obscureConfirmPassword,
          suffixIcon: IconButton(
            onPressed: () {
              setState(() {
                _obscureConfirmPassword = !_obscureConfirmPassword;
              });
            },
            icon: Icon(
              _obscureConfirmPassword
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: isDark ? Color(0xFF9CA3AF) : Color(0xFF6B7280),
            ),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please confirm your password.';
            }
            if (value != _passwordController.text) {
              return 'Passwords do not match.';
            }
            return null;
          },
        ),
        const SizedBox(height: 8),
        // Confirmation feedback
        if (_confirmPasswordController.text.isNotEmpty)
          Row(
            children: [
              Icon(
                _passwordController.text == _confirmPasswordController.text
                    ? Icons.check_circle
                    : Icons.cancel,
                size: 16,
                color: _passwordController.text == _confirmPasswordController.text
                    ? Colors.green
                    : Colors.redAccent,
              ),
              const SizedBox(width: 8),
              Text(
                _passwordController.text == _confirmPasswordController.text
                    ? 'Passwords match'
                    : 'Passwords do not match',
                style: TextStyle(
                  color: _passwordController.text == _confirmPasswordController.text
                      ? Colors.green
                      : Colors.redAccent,
                  fontSize: 12,
                ),
              ),
            ],
          ),

        // Organization Name Field (only for Organization accounts)
        if (_accountType == 'organization') ...[
          const SizedBox(height: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Organization', style: DesignSystem.textM(context)),
              const SizedBox(height: DesignSystem.spacingXS),
              DesignSystem.appTextField(
                context: context,
                controller: _organizationController,
                hintText: 'Enter company or organization name',
                prefixIcon: Icons.business_outlined,
              ),
              if (_organizationError != null) ...[
                const SizedBox(height: 6),
                Text(
                  _organizationError!,
                  style: TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ],
            ],
          ),
        ],

        const SizedBox(height: 20),

        // Terms of Use Checkbox
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: _termsAgreed,
                  onChanged: (value) {
                    setState(() {
                      _termsAgreed = value ?? false;
                      if (_termsAgreed) {
                        _termsError = null;
                      }
                    });
                  },
                  activeColor: DesignSystem.getSemanticColor(
                    context,
                    SemanticColor.primary,
                  ),
                  checkColor: Colors.white,
                  side: BorderSide(
                    color: _termsError != null
                        ? Colors.redAccent
                        : DesignSystem.getSemanticColor(
                            context,
                            SemanticColor.onSurfaceVariant,
                          ).withValues(alpha: 0.5),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: GestureDetector(
                      onTap: () {
                        // TODO: Navigate to Terms of Use page when it exists
                        // For now, just toggle the checkbox
                        setState(() {
                          _termsAgreed = !_termsAgreed;
                          if (_termsAgreed) {
                            _termsError = null;
                          }
                        });
                      },
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(
                            color: isDark
                                ? Color(0xFF9CA3AF)
                                : Color(0xFF6B7280),
                            fontSize: 13,
                          ),
                          children: [
                            TextSpan(text: 'I agree to IntelliBreak '),
                            TextSpan(
                              text: 'Terms of Use',
                              style: TextStyle(
                                color: DesignSystem.getSemanticColor(
                                  context,
                                  SemanticColor.primary,
                                ),
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_termsError != null) ...[
              Padding(
                padding: const EdgeInsets.only(left: 48),
                child: Text(
                  _termsError!,
                  style: TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ),
            ],
          ],
        ),

        // General Error Message
        if (_generalError != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: EdgeInsets.all(DesignSystem.spacingM),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(DesignSystem.radiusM),
              border: Border.all(
                color: Colors.redAccent.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _generalError!,
                    style: TextStyle(color: Colors.redAccent, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ====================================================
  // STEP 2 - PERSONAL
  // ====================================================

  Widget _buildPersonalStep(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Personal Information',
          style: TextStyle(
            color: isDark ? Colors.white : Color(0xFF171923),
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Tell us a little about yourself.',
          style: TextStyle(
            color: isDark ? Color(0xFF9CA3AF) : Color(0xFF6B7280),
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 24),
        AuthFormField(
          label: 'Age',
          hintText: 'Enter your age',
          controller: _ageController,
          prefixIcon: Icons.cake_outlined,
          keyboardType: TextInputType.number,
          validator: (value) {
            if (value == null) {
              return 'Please enter a valid age.';
            }
            final age = int.tryParse(value);
            if (age == null || age < 18 || age > 100) {
              return 'Age must be between 18 and 100.';
            }
            return null;
          },
        ),
        const SizedBox(height: 20),
        // Gender
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Gender', style: DesignSystem.textM(context)),
            const SizedBox(height: DesignSystem.spacingXS),
            DesignSystem.appDropdown<String>(
              context: context,
              value: _selectedGender,
              hint: 'Select your gender',
              items: _genders
                  .map(
                    (e) => DropdownMenuItem<String>(value: e, child: Text(e)),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedGender = value;
                  // Clear other field when switching away from Other
                  if (value != 'Other') {
                    _genderOtherController.clear();
                  }
                });
              },
            ),
            // Show "Other" text field when Other is selected
            if (_selectedGender == 'Other') ...[
              const SizedBox(height: 12),
              Text(
                'Please specify your gender',
                style: TextStyle(
                  color: isDark ? Colors.white : Color(0xFF171923),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
              AuthFormField(
                label: '',
                hintText: 'Enter your gender',
                controller: _genderOtherController,
                prefixIcon: Icons.transgender,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please specify your gender.';
                  }
                  return null;
                },
              ),
            ],
          ],
        ),
        const SizedBox(height: 20),
        // Education Attainment
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Education Attainment', style: DesignSystem.textM(context)),
            const SizedBox(height: DesignSystem.spacingXS),
            DesignSystem.appDropdown<String>(
              context: context,
              value: _selectedEducation,
              hint: 'Select your highest education',
              items: _educationLevels
                  .map(
                    (e) => DropdownMenuItem<String>(value: e, child: Text(e)),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedEducation = value;
                  // Clear other field when switching away from Other
                  if (value != 'Other') {
                    _educationOtherController.clear();
                  }
                });
              },
            ),
            // Show "Other" text field when Other is selected
            if (_selectedEducation == 'Other') ...[
              const SizedBox(height: 12),
              Text(
                'Please specify your education attainment',
                style: TextStyle(
                  color: isDark ? Colors.white : Color(0xFF171923),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
              AuthFormField(
                label: '',
                hintText: 'Enter your education attainment',
                controller: _educationOtherController,
                prefixIcon: Icons.school,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please specify your education attainment.';
                  }
                  return null;
                },
              ),
            ],
          ],
        ),
        const SizedBox(height: 20),
        // Marital Status
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Marital Status', style: DesignSystem.textM(context)),
            const SizedBox(height: DesignSystem.spacingXS),
            DesignSystem.appDropdown<String>(
              context: context,
              value: _selectedMaritalStatus,
              hint: 'Select your marital status',
              items: _maritalStatuses
                  .map(
                    (e) => DropdownMenuItem<String>(value: e, child: Text(e)),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedMaritalStatus = value;
                  // Clear other field when switching away from Other
                  if (value != 'Other') {
                    _maritalOtherController.clear();
                  }
                });
              },
            ),
            // Show "Other" text field when Other is selected
            if (_selectedMaritalStatus == 'Other') ...[
              const SizedBox(height: 12),
              Text(
                'Please specify your marital status',
                style: TextStyle(
                  color: isDark ? Colors.white : Color(0xFF171923),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
              AuthFormField(
                label: '',
                hintText: 'Enter your marital status',
                controller: _maritalOtherController,
                prefixIcon: Icons.people,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please specify your marital status.';
                  }
                  return null;
                },
              ),
            ],
          ],
        ),
      ],
    );
  }

  // ====================================================
  // STEP 3 - WORK
  // ====================================================

  Widget _buildWorkStep(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Work Information',
          style: TextStyle(
            color: isDark ? Colors.white : Color(0xFF171923),
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Tell us about your professional background.',
          style: TextStyle(
            color: isDark ? Color(0xFF9CA3AF) : Color(0xFF6B7280),
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 24),
        // Job Role
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Job Role', style: DesignSystem.textM(context)),
            const SizedBox(height: DesignSystem.spacingXS),
            DesignSystem.appDropdown<String>(
              context: context,
              value: _selectedJobRole,
              hint: 'Select your job role',
              items: _jobRoles
                  .map(
                    (e) => DropdownMenuItem<String>(value: e, child: Text(e)),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedJobRole = value;
                  // Clear other field when switching away from Other
                  if (value != 'Other') {
                    _jobRoleOtherController.clear();
                  }
                });
              },
            ),
            // Show "Other" text field when Other is selected
            if (_selectedJobRole == 'Other') ...[
              const SizedBox(height: 12),
              Text(
                'Please specify your job role',
                style: TextStyle(
                  color: isDark ? Colors.white : Color(0xFF171923),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
              AuthFormField(
                label: '',
                hintText: 'Enter your job role',
                controller: _jobRoleOtherController,
                prefixIcon: Icons.work_outline_rounded,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please specify your job role.';
                  }
                  return null;
                },
              ),
            ],
          ],
        ),
        const SizedBox(height: 20),
        // Industry
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Industry', style: DesignSystem.textM(context)),
            const SizedBox(height: DesignSystem.spacingXS),
            DesignSystem.appDropdown<String>(
              context: context,
              value: _selectedIndustry,
              hint: 'Select your industry',
              items: _industries
                  .map(
                    (e) => DropdownMenuItem<String>(value: e, child: Text(e)),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedIndustry = value;
                  // Clear other field when switching away from Other
                  if (value != 'Other') {
                    _industryOtherController.clear();
                  }
                });
              },
            ),
            // Show "Other" text field when Other is selected
            if (_selectedIndustry == 'Other') ...[
              const SizedBox(height: 12),
              Text(
                'Please specify your industry',
                style: TextStyle(
                  color: isDark ? Colors.white : Color(0xFF171923),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
              AuthFormField(
                label: '',
                hintText: 'Enter your industry',
                controller: _industryOtherController,
                prefixIcon: Icons.business_outlined,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please specify your industry.';
                  }
                  return null;
                },
              ),
            ],
          ],
        ),
        const SizedBox(height: 20),
        AuthFormField(
          label: 'Years of Experience',
          hintText: 'e.g. 2.5',
          controller: _experienceController,
          prefixIcon: Icons.timeline_outlined,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter your years of experience.';
            }
            final experience = double.tryParse(value);
            if (experience == null || experience < 0) {
              return 'Please enter your years of experience.';
            }
            return null;
          },
        ),
      ],
    );
  }

  // ====================================================
  // STEP 4 - WORK SCHEDULE
  // ====================================================

  Widget _buildScheduleStep(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Work Schedule',
          style: TextStyle(
            color: isDark ? Colors.white : Color(0xFF171923),
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Set your normal working schedule.',
          style: TextStyle(
            color: isDark ? Color(0xFF9CA3AF) : Color(0xFF6B7280),
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 24),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Target Daily Work Hours', style: DesignSystem.textM(context)),
            const SizedBox(height: DesignSystem.spacingXS),
            DesignSystem.appTextField(
              context: context,
              controller: TextEditingController(
                text: '${_dailyHours.toStringAsFixed(1)} hours',
              ),
              hintText: '${_dailyHours.toStringAsFixed(1)} hours',
              readOnly: true,
              prefixIcon: Icons.access_time_rounded,
            ),
          ],
        ),
        const SizedBox(height: 20),
        // Slider for daily hours
        // We'll create a custom widget for this, but for now we'll use the original slider.
        // We'll wrap it in a container with padding.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Slider(
            value: _dailyHours,
            min: 1,
            max: 16,
            divisions: 30,
            activeColor: Color(0xFF6C63FF),
            onChanged: (value) {
              setState(() {
                _dailyHours = value;
              });
            },
          ),
        ),
        const SizedBox(height: 24),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Shift Start', style: DesignSystem.textM(context)),
            const SizedBox(height: DesignSystem.spacingXS),
            DesignSystem.appTextField(
              context: context,
              controller: TextEditingController(
                text: _shiftStart.format(context),
              ),
              hintText: _shiftStart.format(context),
              readOnly: true,
              prefixIcon: Icons.access_time_rounded,
              suffixIcon: IconButton(
                icon: Icon(Icons.access_time),
                onPressed: () => _selectStartTime(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Shift End', style: DesignSystem.textM(context)),
            const SizedBox(height: DesignSystem.spacingXS),
            DesignSystem.appTextField(
              context: context,
              controller: TextEditingController(
                text: _shiftEnd.format(context),
              ),
              hintText: _shiftEnd.format(context),
              readOnly: true,
              prefixIcon: Icons.access_time_rounded,
              suffixIcon: IconButton(
                icon: Icon(Icons.access_time),
                onPressed: () => _selectEndTime(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Working Days', style: DesignSystem.textM(context)),
            const SizedBox(height: DesignSystem.spacingXS),
            ..._workingDays.keys.map(
              (day) => CheckboxListTile(
                title: Text(day),
                value: _workingDays[day]!,
                onChanged: (value) {
                  setState(() {
                    _workingDays[day] = value!;
                  });
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ====================================================
  // STEP 5 - DATA CONSENT
  // ====================================================

  Widget _buildConsentStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Data Collection',
          style: TextStyle(
            color: DesignSystem.getSemanticColor(
              context,
              SemanticColor.onSurface,
            ),
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Review how IntelliBreak uses your information.',
          style: TextStyle(
            color: DesignSystem.getSemanticColor(
              context,
              SemanticColor.onSurfaceVariant,
            ),
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 24),
        // Data sections
        _buildDataSection(
          Icons.timer_outlined,
          'Work Sessions',
          'IntelliBreak records your work session duration '
              'and shift information.',
        ),
        const SizedBox(height: 12),
        _buildDataSection(
          Icons.bar_chart_rounded,
          'Productivity Metrics',
          'Activity data may be used to calculate '
              'productivity and focus metrics.',
        ),
        const SizedBox(height: 12),
        _buildDataSection(
          Icons.coffee_outlined,
          'Break Patterns',
          'Break duration and break patterns may be '
              'recorded to provide personalized recommendations.',
        ),
        const SizedBox(height: 12),
        _buildDataSection(
          Icons.psychology_outlined,
          'Personalized Coaching',
          'Your collected data may be analyzed by the '
              'IntelliBreak prediction system to provide '
              'personalized productivity recommendations.',
        ),
        const SizedBox(height: 24),
        // Consent checkbox
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _dataConsent,
          activeColor: DesignSystem.getSemanticColor(
            context,
            SemanticColor.primary,
          ),
          title: Text(
            'I understand and agree to the collection and '
            'processing of my data for IntelliBreak.',
            style: TextStyle(
              color: DesignSystem.getSemanticColor(
                context,
                SemanticColor.onSurface,
              ),
              fontSize: 14,
            ),
          ),
          onChanged: (value) {
            setState(() {
              _dataConsent = value ?? false;
            });
          },
        ),
      ],
    );
  }

  // ====================================================
  // DATA SECTION
  // ====================================================

  Widget _buildDataSection(IconData icon, String title, String description) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = Provider.of<ThemeController>(
      context,
      listen: false,
    ).isHighContrast;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? (isHighContrast
                  ? DesignSystem.getSemanticColor(
                      context,
                      SemanticColor.background,
                    )
                  : DesignSystem.getSemanticColor(
                      context,
                      SemanticColor.background,
                    ))
            : DesignSystem.getSemanticColor(context, SemanticColor.surface),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? (isHighContrast
                    ? DesignSystem.getSemanticColor(
                        context,
                        SemanticColor.onSurface,
                      ).withValues(alpha: 0.3)
                    : DesignSystem.getSemanticColor(
                        context,
                        SemanticColor.onSurfaceVariant,
                      ))
              : DesignSystem.getSemanticColor(
                  context,
                  SemanticColor.onSurfaceVariant,
                ).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: DesignSystem.getSemanticColor(
              context,
              SemanticColor.primary,
            ),
            size: 24,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: DesignSystem.getSemanticColor(
                      context,
                      SemanticColor.onSurface,
                    ),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    color: DesignSystem.getSemanticColor(
                      context,
                      SemanticColor.onSurfaceVariant,
                    ),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ====================================================
  // TIME PICKER
  // ====================================================

  Future<void> _selectStartTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _shiftStart,
    );

    if (selected != null) {
      setState(() {
        _shiftStart = selected;
      });
    }
  }

  Future<void> _selectEndTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _shiftEnd,
    );

    if (selected != null) {
      setState(() {
        _shiftEnd = selected;
      });
    }
  }

  // ====================================================
  // NAVIGATION BUTTONS
  // ====================================================

  Widget _buildNavigationButtons(BuildContext context) {
    return Row(
      children: [
        // Back button (left side, only show if not on first step)
        if (_currentStep > 0)
          Expanded(
            child: SizedBox(
              height: 48,
              child: OutlinedButton(
                onPressed: _previousStep,
                child: const Text('Back'),
              ),
            ),
          ),
        // Spacer between buttons
        if (_currentStep > 0) const SizedBox(width: 12),
        // Continue button (right side, takes remaining space or full width if no back button)
        Expanded(
          child: SizedBox(
            height: 48,
            child: DesignSystem.primaryButton(
              context: context,
              label: _currentStep == 4 ? 'Create Account' : 'Continue',
              onPressed: _nextStep,
              isLoading: _isLoading,
            ),
          ),
        ),
      ],
    );
  }
}
