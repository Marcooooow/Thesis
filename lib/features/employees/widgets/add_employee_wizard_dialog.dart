import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intellibreak/core/design_system.dart';
import 'package:intellibreak/features/auth/services/api_service.dart';

class AddEmployeeWizardDialog extends StatefulWidget {
  final VoidCallback onEmployeeCreated;

  const AddEmployeeWizardDialog({
    super.key,
    required this.onEmployeeCreated,
  });

  @override
  State<AddEmployeeWizardDialog> createState() => _AddEmployeeWizardDialogState();
}

class _AddEmployeeWizardDialogState extends State<AddEmployeeWizardDialog> {
  int _currentStep = 0;
  bool _isLoadingTeams = true;
  bool _isSubmitting = false;
  String? _error;
  List<Map<String, dynamic>> _teams = [];

  final ApiService _apiService = ApiService();

  // Step 0: Account Information
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  String? _selectedTeamId;

  // Step 1: Personal Information
  final TextEditingController _ageController = TextEditingController();
  String? _selectedGender;
  final TextEditingController _phoneController = TextEditingController();
  String? _selectedEducation;
  String? _selectedMaritalStatus;

  // Step 2: Work Information
  final TextEditingController _jobRoleController = TextEditingController();
  final TextEditingController _departmentController = TextEditingController();
  final TextEditingController _industryController = TextEditingController();
  final TextEditingController _yearsExperienceController = TextEditingController();
  DateTime? _hireDate;

  // Step 3: Work Schedule & Breaks
  final List<String> _allDays = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
  final Map<String, bool> _workingDays = {
    'monday': true,
    'tuesday': true,
    'wednesday': true,
    'thursday': true,
    'friday': true,
    'saturday': false,
    'sunday': false,
  };

  TimeOfDay _shiftStart = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _shiftEnd = const TimeOfDay(hour: 17, minute: 0);
  int _targetDailyHours = 8;

  TimeOfDay _break1Time = const TimeOfDay(hour: 10, minute: 30);
  int _break1Duration = 15; // minutes
  TimeOfDay _lunchTime = const TimeOfDay(hour: 12, minute: 30);
  int _lunchDuration = 60; // minutes
  TimeOfDay _break2Time = const TimeOfDay(hour: 15, minute: 30);
  int _break2Duration = 15; // minutes

  @override
  void initState() {
    super.initState();
    _loadTeams();
  }

  Future<void> _loadTeams() async {
    setState(() {
      _isLoadingTeams = true;
      _error = null;
    });
    try {
      final token = await _apiService.getToken();
      if (token == null) throw Exception('No authentication token available');
      final response = await _apiService.getListWithAuth('/teams/my-teams', token);
      if (!mounted) return;
      setState(() {
        _teams = response.cast<Map<String, dynamic>>();
        _isLoadingTeams = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingTeams = false;
        _error = 'Failed to load teams: $e';
      });
    }
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  bool _validateStep() {
    setState(() { _error = null; });
    if (_currentStep == 0) {
      if (_fullNameController.text.trim().isEmpty) {
        setState(() { _error = 'Full name is required.'; });
        return false;
      }
      if (_emailController.text.trim().isEmpty || !_emailController.text.contains('@')) {
        setState(() { _error = 'Please enter a valid email address.'; });
        return false;
      }
    } else if (_currentStep == 1) {
      if (_ageController.text.trim().isNotEmpty) {
        final age = int.tryParse(_ageController.text.trim());
        if (age == null || age < 18 || age > 100) {
          setState(() { _error = 'Please enter a valid age between 18 and 100.'; });
          return false;
        }
      }
    } else if (_currentStep == 2) {
      if (_yearsExperienceController.text.trim().isNotEmpty) {
        final exp = int.tryParse(_yearsExperienceController.text.trim());
        if (exp == null || exp < 0) {
          setState(() { _error = 'Years of experience must be a non-negative number.'; });
          return false;
        }
      }
    } else if (_currentStep == 3) {
      if (!_workingDays.values.contains(true)) {
        setState(() { _error = 'Please select at least one working day.'; });
        return false;
      }
      final startMinutes = _shiftStart.hour * 60 + _shiftStart.minute;
      final endMinutes = _shiftEnd.hour * 60 + _shiftEnd.minute;
      if (startMinutes >= endMinutes) {
        setState(() { _error = 'Shift end time must be after start time.'; });
        return false;
      }

      final b1Minutes = _break1Time.hour * 60 + _break1Time.minute;
      final lunchMinutes = _lunchTime.hour * 60 + _lunchTime.minute;
      final b2Minutes = _break2Time.hour * 60 + _break2Time.minute;

      if (b1Minutes < startMinutes || b1Minutes > endMinutes ||
          lunchMinutes < startMinutes || lunchMinutes > endMinutes ||
          b2Minutes < startMinutes || b2Minutes > endMinutes) {
        setState(() { _error = 'All breaks must fall within shift working hours.'; });
        return false;
      }

      if (b1Minutes >= lunchMinutes || lunchMinutes >= b2Minutes) {
        setState(() { _error = 'Breaks must be in chronological order: Break 1 -> Lunch -> Break 2 without overlap.'; });
        return false;
      }
    }
    return true;
  }

  Future<void> _submitEmployee() async {
    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final token = await _apiService.getToken();
      if (token == null) throw Exception('No authentication token available');

      final activeDays = _workingDays.entries
          .where((e) => e.value)
          .map((e) => e.key)
          .toList();

      final body = {
        'email': _emailController.text.trim(),
        'full_name': _fullNameController.text.trim(),
        'team_id': _selectedTeamId,
        'target_daily_hours': _targetDailyHours,
        'shift_start_time': _formatTime(_shiftStart),
        'shift_end_time': _formatTime(_shiftEnd),
        'working_days': activeDays,
        if (_ageController.text.trim().isNotEmpty)
          'age': int.tryParse(_ageController.text.trim()),
        if (_selectedGender != null) 'gender': _selectedGender,
        if (_phoneController.text.trim().isNotEmpty)
          'phone_number': _phoneController.text.trim(),
        if (_selectedEducation != null) 'education_attainment': _selectedEducation,
        if (_selectedMaritalStatus != null) 'marital_status': _selectedMaritalStatus,
        if (_jobRoleController.text.trim().isNotEmpty)
          'job_role': _jobRoleController.text.trim(),
        if (_departmentController.text.trim().isNotEmpty)
          'department': _departmentController.text.trim(),
        if (_industryController.text.trim().isNotEmpty)
          'industry': _industryController.text.trim(),
        if (_yearsExperienceController.text.trim().isNotEmpty)
          'years_of_experience': int.tryParse(_yearsExperienceController.text.trim()),
        if (_hireDate != null)
          'hire_date': "${_hireDate!.year.toString().padLeft(4, '0')}-${_hireDate!.month.toString().padLeft(2, '0')}-${_hireDate!.day.toString().padLeft(2, '0')}",
      };

      final response = await _apiService.postWithAuth('/employees', token, body);

      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onEmployeeCreated();

      final tempPassword = response['temporary_password'] ?? 'GeneratedPassword';
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Employee Created Successfully'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Employee account created for ${_fullNameController.text.trim()}.'),
              const SizedBox(height: 12),
              const Text(
                'Please save this temporary password. It will not be shown again:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                ),
                child: SelectableText(
                  tempPassword,
                  style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: tempPassword));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Temporary password copied to clipboard')),
                  );
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy Password'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.secondary;

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF151A21) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 650,
        constraints: const BoxConstraints(maxHeight: 750),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Add Employee Registration',
                      style: DesignSystem.titleLarge(context).copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Step ${_currentStep + 1} of 5: ${_getStepTitle()}',
                      style: DesignSystem.caption(context).copyWith(color: primaryColor, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: (_currentStep + 1) / 5.0,
              backgroundColor: isDark ? Colors.white12 : Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
            ),
            const SizedBox(height: 20),

            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13))),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            Expanded(
              child: SingleChildScrollView(
                child: _buildStepContent(),
              ),
            ),

            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (_currentStep > 0)
                  OutlinedButton.icon(
                    onPressed: _isSubmitting ? null : () => setState(() => _currentStep--),
                    icon: const Icon(Icons.arrow_back, size: 16),
                    label: const Text('Back'),
                  )
                else
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),

                if (_currentStep < 4)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: primaryColor, foregroundColor: Colors.white),
                    onPressed: () {
                      if (_validateStep()) {
                        setState(() => _currentStep++);
                      }
                    },
                    child: const Text('Continue'),
                  )
                else
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: primaryColor, foregroundColor: Colors.white),
                    onPressed: _isSubmitting ? null : _submitEmployee,
                    child: _isSubmitting
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Create Employee'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _getStepTitle() {
    switch (_currentStep) {
      case 0: return 'Account Information';
      case 1: return 'Personal Information';
      case 2: return 'Work Information';
      case 3: return 'Work Schedule';
      case 4: return 'Review and Create';
      default: return '';
    }
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildStep1Account();
      case 1:
        return _buildStep2Personal();
      case 2:
        return _buildStep3Work();
      case 3:
        return _buildStep4Schedule();
      case 4:
        return _buildStep5Review();
      default:
        return Container();
    }
  }

  Widget _buildStep1Account() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Provide basic employee account details and team assignment.', style: DesignSystem.body(context)),
        const SizedBox(height: 20),
        const Text('Full Name *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 6),
        TextField(
          controller: _fullNameController,
          decoration: const InputDecoration(
            hintText: 'e.g. Jane Doe',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Email Address *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 6),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            hintText: 'e.g. jane.doe@intellibreak.local',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Team Assignment', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 6),
        _isLoadingTeams
            ? const Center(child: CircularProgressIndicator())
            : DropdownButtonFormField<String?>(
                initialValue: _selectedTeamId,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                hint: const Text('Select a team (optional)'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('No team assigned')),
                  ..._teams.map((t) => DropdownMenuItem<String?>(
                        value: t['id']?.toString(),
                        child: Text(t['name']?.toString() ?? 'Unnamed Team'),
                      )),
                ],
                onChanged: (val) => setState(() => _selectedTeamId = val),
              ),
      ],
    );
  }

  Widget _buildStep2Personal() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Provide optional personal details and background information.', style: DesignSystem.body(context)),
        const SizedBox(height: 20),
        const Text('Age', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 6),
        TextField(
          controller: _ageController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: 'e.g. 30',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Gender', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: _selectedGender,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          hint: const Text('Select gender (optional)'),
          items: ['Male', 'Female', 'Non-Binary', 'Prefer not to say', 'Other']
              .map((g) => DropdownMenuItem(value: g, child: Text(g)))
              .toList(),
          onChanged: (val) => setState(() => _selectedGender = val),
        ),
        const SizedBox(height: 16),
        const Text('Phone Number', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 6),
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            hintText: 'e.g. +1 (555) 019-2834',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Education', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: _selectedEducation,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          hint: const Text('Select education level (optional)'),
          items: ["High School", "Bachelor's", "Master's", "Doctorate", "Other"]
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: (val) => setState(() => _selectedEducation = val),
        ),
        const SizedBox(height: 16),
        const Text('Marital Status', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: _selectedMaritalStatus,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          hint: const Text('Select marital status (optional)'),
          items: ["Single", "Married", "Divorced", "Widowed", "Other"]
              .map((m) => DropdownMenuItem(value: m, child: Text(m)))
              .toList(),
          onChanged: (val) => setState(() => _selectedMaritalStatus = val),
        ),
      ],
    );
  }

  Widget _buildStep3Work() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Provide professional and organizational background information.', style: DesignSystem.body(context)),
        const SizedBox(height: 20),
        const Text('Job Role', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 6),
        TextField(
          controller: _jobRoleController,
          decoration: const InputDecoration(
            hintText: 'e.g. Software Engineer',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Department', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 6),
        TextField(
          controller: _departmentController,
          decoration: const InputDecoration(
            hintText: 'e.g. Engineering',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Industry', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 6),
        TextField(
          controller: _industryController,
          decoration: const InputDecoration(
            hintText: 'e.g. Technology',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Years of Experience', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 6),
        TextField(
          controller: _yearsExperienceController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: 'e.g. 5',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Hire Date', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 6),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _hireDate ?? DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (picked != null) {
              setState(() => _hireDate = picked);
            }
          },
          child: InputDecorator(
            decoration: const InputDecoration(border: OutlineInputBorder()),
            child: Text(
              _hireDate == null
                  ? 'Select hire date (optional)'
                  : '${_hireDate!.year}-${_hireDate!.month.toString().padLeft(2, '0')}-${_hireDate!.day.toString().padLeft(2, '0')}',
              style: TextStyle(
                fontSize: 15,
                color: _hireDate == null ? Colors.grey : (Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep4Schedule() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Configure working days, standard shift hours, and scheduled breaks.', style: DesignSystem.body(context)),
        const SizedBox(height: 20),
        const Text('Working Days', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _allDays.map((day) {
            final isSelected = _workingDays[day] ?? false;
            return FilterChip(
              label: Text(day[0].toUpperCase() + day.substring(1)),
              selected: isSelected,
              onSelected: (val) => setState(() => _workingDays[day] = val),
              selectedColor: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.2),
              checkmarkColor: Theme.of(context).colorScheme.secondary,
            );
          }).toList(),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Shift Start Time', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () async {
                      final picked = await showTimePicker(context: context, initialTime: _shiftStart);
                      if (picked != null) setState(() => _shiftStart = picked);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                      child: Text(_shiftStart.format(context), style: const TextStyle(fontSize: 15)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Shift End Time', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () async {
                      final picked = await showTimePicker(context: context, initialTime: _shiftEnd);
                      if (picked != null) setState(() => _shiftEnd = picked);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                      child: Text(_shiftEnd.format(context), style: const TextStyle(fontSize: 15)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text('Target Daily Hours', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 6),
        Slider(
          value: _targetDailyHours.toDouble(),
          min: 4,
          max: 12,
          divisions: 8,
          label: '$_targetDailyHours hours',
          onChanged: (val) => setState(() => _targetDailyHours = val.round()),
        ),
        Text('Target: $_targetDailyHours hours per day', style: DesignSystem.caption(context)),
        const SizedBox(height: 24),
        const Text('Scheduled Breaks & Lunch', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 12),
        _buildBreakConfigRow('Break 1 (Morning)', _break1Time, _break1Duration, (t, d) {
          setState(() {
            if (t != null) _break1Time = t;
            if (d != null) _break1Duration = d;
          });
        }),
        const SizedBox(height: 16),
        _buildBreakConfigRow('Lunch Break', _lunchTime, _lunchDuration, (t, d) {
          setState(() {
            if (t != null) _lunchTime = t;
            if (d != null) _lunchDuration = d;
          });
        }),
        const SizedBox(height: 16),
        _buildBreakConfigRow('Break 2 (Afternoon)', _break2Time, _break2Duration, (t, d) {
          setState(() {
            if (t != null) _break2Time = t;
            if (d != null) _break2Duration = d;
          });
        }),
      ],
    );
  }

  Widget _buildBreakConfigRow(String label, TimeOfDay time, int duration, Function(TimeOfDay?, int?) onChanged) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: InkWell(
                  onTap: () async {
                    final picked = await showTimePicker(context: context, initialTime: time);
                    if (picked != null) onChanged(picked, null);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Start Time', border: OutlineInputBorder(), isDense: true),
                    child: Text(time.format(context)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<int>(
                  initialValue: duration,
                  decoration: const InputDecoration(labelText: 'Duration', border: OutlineInputBorder(), isDense: true),
                  items: [5, 10, 15, 20, 30, 45, 60, 90].map((m) => DropdownMenuItem(value: m, child: Text('$m mins'))).toList(),
                  onChanged: (val) => onChanged(null, val),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStep5Review() {
    final activeDaysList = _workingDays.entries.where((e) => e.value).map((e) => e.key[0].toUpperCase() + e.key.substring(1)).toList();
    final teamName = _selectedTeamId == null
        ? 'No team assigned'
        : _teams.firstWhere((t) => t['id']?.toString() == _selectedTeamId, orElse: () => {'name': 'Assigned Team'})['name'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Review the employee configuration before finalizing account creation.', style: DesignSystem.body(context)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Account Information', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 14)),
              const SizedBox(height: 8),
              _buildReviewRow('Full Name', _fullNameController.text.trim()),
              const Divider(height: 12),
              _buildReviewRow('Email Address', _emailController.text.trim()),
              const Divider(height: 12),
              _buildReviewRow('Assigned Team', teamName?.toString() ?? 'None'),
              const SizedBox(height: 16),
              const Text('Personal Information', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 14)),
              const SizedBox(height: 8),
              _buildReviewRow('Age', _ageController.text.trim().isEmpty ? 'N/A' : _ageController.text.trim()),
              const Divider(height: 12),
              _buildReviewRow('Gender', _selectedGender ?? 'N/A'),
              const Divider(height: 12),
              _buildReviewRow('Phone Number', _phoneController.text.trim().isEmpty ? 'N/A' : _phoneController.text.trim()),
              const Divider(height: 12),
              _buildReviewRow('Education', _selectedEducation ?? 'N/A'),
              const Divider(height: 12),
              _buildReviewRow('Marital Status', _selectedMaritalStatus ?? 'N/A'),
              const SizedBox(height: 16),
              const Text('Work Information', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 14)),
              const SizedBox(height: 8),
              _buildReviewRow('Job Role', _jobRoleController.text.trim().isEmpty ? 'N/A' : _jobRoleController.text.trim()),
              const Divider(height: 12),
              _buildReviewRow('Department', _departmentController.text.trim().isEmpty ? 'N/A' : _departmentController.text.trim()),
              const Divider(height: 12),
              _buildReviewRow('Industry', _industryController.text.trim().isEmpty ? 'N/A' : _industryController.text.trim()),
              const Divider(height: 12),
              _buildReviewRow('Experience', _yearsExperienceController.text.trim().isEmpty ? 'N/A' : '${_yearsExperienceController.text.trim()} years'),
              const Divider(height: 12),
              _buildReviewRow('Hire Date', _hireDate == null ? 'N/A' : '${_hireDate!.year}-${_hireDate!.month.toString().padLeft(2, '0')}-${_hireDate!.day.toString().padLeft(2, '0')}'),
              const SizedBox(height: 16),
              const Text('Work Schedule', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 14)),
              const SizedBox(height: 8),
              _buildReviewRow('Working Days', activeDaysList.join(', ')),
              const Divider(height: 12),
              _buildReviewRow('Shift Hours', '${_shiftStart.format(context)} - ${_shiftEnd.format(context)} (${_targetDailyHours}h target)'),
              const Divider(height: 12),
              _buildReviewRow('Break Schedule', 'Break 1: ${_break1Time.format(context)} (${_break1Duration}m) | Lunch: ${_lunchTime.format(context)} (${_lunchDuration}m) | Break 2: ${_break2Time.format(context)} (${_break2Duration}m)'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReviewRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 130, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.grey))),
        Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500))),
      ],
    );
  }
}
