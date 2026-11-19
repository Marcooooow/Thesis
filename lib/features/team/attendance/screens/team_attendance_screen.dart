import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/team_attendance_provider.dart';
import 'package:intellibreak/features/attendance/models/attendance_model.dart';

class TeamAttendanceScreen extends StatefulWidget {
  const TeamAttendanceScreen({super.key});

  @override
  State<TeamAttendanceScreen> createState() => _TeamAttendanceScreenState();
}

class _TeamAttendanceScreenState extends State<TeamAttendanceScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _token;
  bool _isLoadingToken = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadTokenAndData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadTokenAndData() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (!mounted) return;
    setState(() {
      _token = token;
      _isLoadingToken = false;
    });

    if (token != null) {
      if (mounted) {
        Provider.of<TeamAttendanceProvider>(context, listen: false).loadTeamData(token);
      }
    }
  }

  void _showAcknowledgeDialog(BuildContext context, String token, AbsenceRecord absence) {
    String classification = 'EXCUSED';
    final TextEditingController notesController = TextEditingController(text: absence.notes);
    final teamProvider = Provider.of<TeamAttendanceProvider>(context, listen: false);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Acknowledge Absence'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (absence.employeeName != null) ...[
                  Text('Employee: ${absence.employeeName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                ],
                Text('Absence Date: ${absence.absenceDate.toIso8601String().split('T')[0]}'),
                const SizedBox(height: 12),
                const Text('Classification', style: TextStyle(fontWeight: FontWeight.bold)),
                DropdownButton<String>(
                  value: classification,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'EXCUSED', child: Text('Excused Absence')),
                    DropdownMenuItem(value: 'DISMISSED', child: Text('Dismissed / Administrative Override')),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => classification = val);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'Manager Acknowledgment Notes (Optional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
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
                  await teamProvider.acknowledgeAbsence(token, absence.id, classification, notesController.text.trim());
                  if (context.mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Absence successfully acknowledged.')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to acknowledge absence: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: const Text('Acknowledge'),
            ),
          ],
        ),
      ),
    );
  }

  void _showReviewLeaveDialog(BuildContext context, String token, LeaveRequest request) {
    bool approve = true;
    final TextEditingController noteController = TextEditingController();
    final teamProvider = Provider.of<TeamAttendanceProvider>(context, listen: false);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Review Leave Request'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Duration: ${request.startDate.toIso8601String().split('T')[0]} to ${request.endDate.toIso8601String().split('T')[0]}'),
                if (request.reason != null && request.reason!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Reason: ${request.reason}'),
                ],
                const SizedBox(height: 16),
                const Text('Decision:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => setDialogState(() => approve = true),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                          decoration: BoxDecoration(
                            color: approve ? Colors.green.shade700 : (isDark ? Colors.grey.shade800 : Colors.grey.shade200),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: approve ? Colors.green.shade800 : Colors.grey.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (approve) ...[
                                const Icon(Icons.check, color: Colors.white, size: 18),
                                const SizedBox(width: 6),
                              ],
                              Text(
                                'Approve',
                                style: TextStyle(
                                  color: approve ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () => setDialogState(() => approve = false),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                          decoration: BoxDecoration(
                            color: !approve ? Colors.red.shade700 : (isDark ? Colors.grey.shade800 : Colors.grey.shade200),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: !approve ? Colors.red.shade800 : Colors.grey.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (!approve) ...[
                                const Icon(Icons.close, color: Colors.white, size: 18),
                                const SizedBox(width: 6),
                              ],
                              Text(
                                'Reject',
                                style: TextStyle(
                                  color: !approve ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: noteController,
                  decoration: const InputDecoration(
                    labelText: 'Reviewer Note (Optional)',
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
              style: ElevatedButton.styleFrom(
                backgroundColor: approve ? Colors.green.shade700 : Colors.red.shade700,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                try {
                  await teamProvider.reviewLeaveRequest(token, request.id, approve, noteController.text.trim());
                  if (context.mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Leave request ${approve ? 'approved' : 'rejected'} successfully.')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to review leave request: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: Text(approve ? 'Approve Request' : 'Reject Request'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingToken) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_token == null) {
      return const Center(child: Text('Please sign in to view team attendance.'));
    }

    return ChangeNotifierProvider(
      create: (_) => TeamAttendanceProvider()..loadTeamData(_token!),
      child: Consumer<TeamAttendanceProvider>(
        builder: (context, provider, child) {
          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Team Attendance & Leave Management',
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Monitor team absences, review leave requests, and view Return-to-Work support signals',
                          style: TextStyle(color: Colors.grey, fontSize: 14),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: () => provider.loadTeamData(_token!),
                      tooltip: 'Refresh Team Data',
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    labelColor: Theme.of(context).colorScheme.primary,
                    unselectedLabelColor: Colors.grey,
                    indicatorColor: Theme.of(context).colorScheme.primary,
                    tabs: [
                      Tab(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.warning_amber_rounded, size: 18),
                            const SizedBox(width: 8),
                            Text('Absences (${provider.absences.length})'),
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.event_note, size: 18),
                            const SizedBox(width: 8),
                            Text('Leave Approvals (${provider.leaveRequests.where((r) => r.status == 'PENDING').length})'),
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.health_and_safety, size: 18),
                            const SizedBox(width: 8),
                            Text('Return-to-Work (${provider.rtwRecords.length})'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: provider.isLoading && provider.absences.isEmpty && provider.leaveRequests.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : provider.error != null
                          ? Center(child: Text('Error: ${provider.error}', style: const TextStyle(color: Colors.red)))
                          : TabBarView(
                              controller: _tabController,
                              children: [
                                _buildAbsencesTab(context, provider),
                                _buildLeaveApprovalsTab(context, provider),
                                _buildRtwTab(context, provider),
                              ],
                            ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAbsencesTab(BuildContext context, TeamAttendanceProvider provider) {
    final absences = provider.absences;
    if (absences.isEmpty) {
      return const Center(
        child: Text('No absence records found for your team.', style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView.builder(
      itemCount: absences.length,
      itemBuilder: (context, index) {
        final absence = absences[index];
        final isAcknowledged = absence.managerAcknowledgedAt != null;
        final employeeName = absence.employeeName ?? 'Team Member';
        final department = absence.department ?? 'Engineering Team';
        final shiftText = (absence.shiftStart != null && absence.shiftEnd != null)
            ? '${absence.shiftStart!.substring(0, 5)}–${absence.shiftEnd!.substring(0, 5)}'
            : '08:00–17:00';
        final dateText = absence.absenceDate.toIso8601String().split('T')[0];

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: isAcknowledged ? Colors.grey.shade200 : Colors.red.shade100,
                  child: Icon(
                    isAcknowledged ? Icons.check_circle_outline : Icons.warning,
                    color: isAcknowledged ? Colors.grey.shade700 : Colors.red,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        employeeName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        department,
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Absence Date: $dateText',
                        style: const TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Scheduled Shift: $shiftText',
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Chip(
                            label: Text(absence.classification),
                            backgroundColor: absence.classification == 'UNREPORTED' ? Colors.red.shade50 : Colors.blue.shade50,
                            labelStyle: TextStyle(
                              fontSize: 12,
                              color: absence.classification == 'UNREPORTED' ? Colors.red.shade800 : Colors.blue.shade800,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('Notification: ${absence.notificationStatus}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                      if (absence.notes != null && absence.notes!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text('Notes: ${absence.notes}', style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  icon: Icon(isAcknowledged ? Icons.edit : Icons.verified, size: 16),
                  label: Text(isAcknowledged ? 'Edit' : 'Acknowledge'),
                  onPressed: () => _showAcknowledgeDialog(context, _token!, absence),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLeaveApprovalsTab(BuildContext context, TeamAttendanceProvider provider) {
    final requests = provider.leaveRequests;
    if (requests.isEmpty) {
      return const Center(
        child: Text('No leave requests found.', style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView.builder(
      itemCount: requests.length,
      itemBuilder: (context, index) {
        final req = requests[index];
        final isPending = req.status == 'PENDING';

        Color statusColor = Colors.orange;
        if (req.status == 'APPROVED') statusColor = Colors.green;
        if (req.status == 'REJECTED') statusColor = Colors.red;
        if (req.status == 'CANCELLED') statusColor = Colors.grey;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '${req.startDate.toIso8601String().split('T')[0]} → ${req.endDate.toIso8601String().split('T')[0]}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(width: 12),
                          Chip(
                            label: Text(req.status),
                            backgroundColor: statusColor.withValues(alpha: 0.1),
                            labelStyle: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ],
                      ),
                      if (req.reason != null && req.reason!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text('Reason: ${req.reason}', style: const TextStyle(fontSize: 14)),
                      ],
                      if (req.reviewerNote != null && req.reviewerNote!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text('Reviewer Note: ${req.reviewerNote}', style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic)),
                      ],
                    ],
                  ),
                ),
                if (isPending)
                  ElevatedButton(
                    onPressed: () => _showReviewLeaveDialog(context, _token!, req),
                    child: const Text('Review'),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRtwTab(BuildContext context, TeamAttendanceProvider provider) {
    final rtwRecords = provider.rtwRecords;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Row(
            children: [
              const Icon(Icons.privacy_tip, color: Colors.blue),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Privacy Notice: In accordance with IntelliBreak well-being policy, raw health ratings '
                  '(overall wellbeing, mental fatigue, workload & stress concerns) and private comments are strictly confidential '
                  'and hidden from managers. Only absence categories (if consented) and support signals are displayed.',
                  style: TextStyle(fontSize: 13, color: Colors.blue.shade900),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: rtwRecords.isEmpty
              ? const Center(child: Text('No Return-to-Work check-ins submitted by team members.', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  itemCount: rtwRecords.length,
                  itemBuilder: (context, index) {
                    final rtw = rtwRecords[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Colors.blue,
                          child: Icon(Icons.health_and_safety, color: Colors.white),
                        ),
                        title: Text(
                          'Submitted: ${rtw.submittedAt.toLocal().toString().split('.')[0]}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text('Absence Category: ${rtw.absenceReasonCategory ?? "Not specified"}'),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(
                                  rtw.wantsManagerSupport == true ? Icons.support_agent : Icons.check_circle_outline,
                                  size: 16,
                                  color: rtw.wantsManagerSupport == true ? Colors.orange : Colors.green,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  rtw.wantsManagerSupport == true
                                      ? 'Requested Manager 1:1 Support'
                                      : 'No managerial support requested',
                                  style: TextStyle(
                                    fontWeight: rtw.wantsManagerSupport == true ? FontWeight.bold : FontWeight.normal,
                                    color: rtw.wantsManagerSupport == true ? Colors.orange.shade800 : Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
