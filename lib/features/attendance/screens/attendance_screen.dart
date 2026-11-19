import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/attendance_provider.dart';
import '../services/attendance_service.dart';
import '../widgets/attendance_calendar_widget.dart';
import '../models/attendance_model.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  String? _token;
  bool _isLoadingToken = true;
  final AttendanceService _attendanceService = AttendanceService();

  @override
  void initState() {
    super.initState();
    _loadTokenAndCheckRtw();
  }

  Future<void> _loadTokenAndCheckRtw() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (!mounted) return;
    setState(() {
      _token = token;
      _isLoadingToken = false;
    });

    if (token != null) {
      // Check pending Return-to-Work check-in
      final pendingRtw = await _attendanceService.checkPendingRtw(token);
      if (pendingRtw.hasPending && mounted) {
        _showRtwCheckinDialog(token, pendingRtw);
      }
    }
  }

  void _showRtwCheckinDialog(String token, PendingRtwInfo pendingRtw) {
    String? category = 'Personal';
    int overallFeeling = 3;
    int workloadConcern = 3;
    int stressConcern = 3;
    bool workContributed = false;
    bool wantsManagerSupport = false;
    final TextEditingController commentsController = TextEditingController();
    final BuildContext parentContext = context;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.health_and_safety, color: Colors.blue),
              SizedBox(width: 8),
              Text('Return-to-Work Check-in'),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 450,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Welcome back! Please complete this voluntary wellbeing check-in. '
                    'Health ratings and private notes remain strictly confidential.',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  const Text('Absence Category', style: TextStyle(fontWeight: FontWeight.bold)),
                  DropdownButton<String>(
                    value: category,
                    isExpanded: true,
                    items: ['Personal', 'Medical', 'Family', 'Other'].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => category = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  Text('Overall Feeling (1-5): $overallFeeling'),
                  Slider(
                    value: overallFeeling.toDouble(),
                    min: 1,
                    max: 5,
                    divisions: 4,
                    label: overallFeeling.toString(),
                    onChanged: (val) => setDialogState(() => overallFeeling = val.toInt()),
                  ),
                  const SizedBox(height: 12),
                  Text('Workload Manageability Concern (1-5): $workloadConcern'),
                  Slider(
                    value: workloadConcern.toDouble(),
                    min: 1,
                    max: 5,
                    divisions: 4,
                    label: workloadConcern.toString(),
                    onChanged: (val) => setDialogState(() => workloadConcern = val.toInt()),
                  ),
                  const SizedBox(height: 12),
                  Text('Stress Level (1-5): $stressConcern'),
                  Slider(
                    value: stressConcern.toDouble(),
                    min: 1,
                    max: 5,
                    divisions: 4,
                    label: stressConcern.toString(),
                    onChanged: (val) => setDialogState(() => stressConcern = val.toInt()),
                  ),
                  CheckboxListTile(
                    title: const Text('Did work factors contribute to absence?'),
                    value: workContributed,
                    onChanged: (val) => setDialogState(() => workContributed = val ?? false),
                    contentPadding: EdgeInsets.zero,
                  ),
                  CheckboxListTile(
                    title: const Text('Would you like a supportive manager 1:1 check-in?'),
                    value: wantsManagerSupport,
                    onChanged: (val) => setDialogState(() => wantsManagerSupport = val ?? false),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: commentsController,
                    decoration: const InputDecoration(
                      labelText: 'Additional Comments (Private)',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () async {
                try {
                  final data = {
                    'work_session_id': pendingRtw.workSessionId,
                    if (pendingRtw.absenceRecordId != null) 'absence_record_id': pendingRtw.absenceRecordId,
                    'absence_reason_category': category,
                    'overall_feeling': overallFeeling,
                    'workload_concern': workloadConcern,
                    'stress_concern': stressConcern,
                    'work_contributed_to_absence': workContributed,
                    'wants_manager_support': wantsManagerSupport,
                    'additional_comments': commentsController.text.trim(),
                    'is_manager_visible': wantsManagerSupport, // only visible categories/support signals exposed to manager if consented
                  };
                  await _attendanceService.submitRtwCheckin(token, data);
                  if (parentContext.mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(parentContext).showSnackBar(
                      const SnackBar(content: Text('Return-to-work check-in submitted successfully.')),
                    );
                    Provider.of<AttendanceProvider>(parentContext, listen: false).loadAttendance(token);
                  }
                } catch (e) {
                  if (parentContext.mounted) {
                    ScaffoldMessenger.of(parentContext).showSnackBar(
                      SnackBar(content: Text('Failed to submit RTW check-in: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: const Text('Submit Check-in'),
            ),
          ],
        ),
      ),
    );
  }

  void _showLeaveRequestDialog(String token) async {
    List<LeaveType> leaveTypes = [];
    try {
      leaveTypes = await _attendanceService.fetchLeaveTypes(token);
    } catch (_) {}

    if (leaveTypes.isEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active leave types available.'), backgroundColor: Colors.orange),
      );
      return;
    }

    String? selectedLeaveTypeId = leaveTypes.first.id;
    DateTime startDate = DateTime.now();
    DateTime endDate = DateTime.now().add(const Duration(days: 1));
    final TextEditingController reasonController = TextEditingController();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Request Leave'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Leave Type', style: TextStyle(fontWeight: FontWeight.bold)),
                DropdownButton<String>(
                  value: selectedLeaveTypeId,
                  isExpanded: true,
                  items: leaveTypes.map((lt) => DropdownMenuItem(value: lt.id, child: Text(lt.name))).toList(),
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedLeaveTypeId = val);
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text('Start: ${startDate.toIso8601String().split('T')[0]}'),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: startDate,
                            firstDate: DateTime.now().subtract(const Duration(days: 30)),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) setDialogState(() => startDate = picked);
                        },
                      ),
                    ),
                    Expanded(
                      child: TextButton.icon(
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text('End: ${endDate.toIso8601String().split('T')[0]}'),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: endDate,
                            firstDate: startDate,
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) setDialogState(() => endDate = picked);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: reasonController,
                  decoration: const InputDecoration(
                    labelText: 'Reason (Optional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
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
              onPressed: () async {
                try {
                  await _attendanceService.submitLeaveRequest(
                    token,
                    selectedLeaveTypeId!,
                    startDate.toIso8601String().split('T')[0],
                    endDate.toIso8601String().split('T')[0],
                    reasonController.text.trim(),
                  );
                  if (context.mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Leave request submitted successfully.')),
                    );
                    Provider.of<AttendanceProvider>(context, listen: false).loadAttendance(token);
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to submit leave request: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: const Text('Submit Request'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingToken) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_token == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in to view attendance.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance & Leave Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Request Leave',
            onPressed: () => _showLeaveRequestDialog(_token!),
          ),
        ],
      ),
      body: AttendanceCalendarWidget(token: _token!),
    );
  }
}
