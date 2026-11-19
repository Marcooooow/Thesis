import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/attendance_provider.dart';
import 'package:intellibreak/widgets/state_display.dart';

class AttendanceCalendarWidget extends StatefulWidget {
  final String token;

  const AttendanceCalendarWidget({super.key, required this.token});

  @override
  State<AttendanceCalendarWidget> createState() => _AttendanceCalendarWidgetState();
}

class _AttendanceCalendarWidgetState extends State<AttendanceCalendarWidget> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AttendanceProvider>(context, listen: false).loadAttendance(widget.token);
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AttendanceProvider>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return StateDisplay(
      isLoading: provider.isLoading,
      errorMessage: provider.errorMessage,
      isEmpty: provider.attendanceOverview == null,
      onRetry: () => provider.loadAttendance(widget.token),
      content: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Attendance & Leave Overview',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                ElevatedButton.icon(
                  onPressed: () => provider.loadAttendance(widget.token),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Refresh'),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Schedule Banner
            if (provider.attendanceOverview?.schedule != null) ...[
              Card(
                elevation: 0,
                color: isDark ? const Color(0xFF252836) : Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.schedule, color: Colors.blue),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Active Schedule',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Work Days: ${provider.attendanceOverview!.schedule!.workDays.join(", ").toUpperCase()} | '
                              'Shift: ${provider.attendanceOverview!.schedule!.shiftStart} - ${provider.attendanceOverview!.schedule!.shiftEnd} '
                              '(${provider.attendanceOverview!.schedule!.timezone})',
                              style: TextStyle(fontSize: 13, color: isDark ? Colors.grey.shade300 : Colors.grey.shade700),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Legend
            Row(
              children: [
                _buildLegendItem(Colors.green, 'Work Session / Attended'),
                const SizedBox(width: 16),
                _buildLegendItem(Colors.blue, 'Approved Leave'),
                const SizedBox(width: 16),
                _buildLegendItem(Colors.orange, 'Unreported / Potential Absence'),
              ],
            ),
            const SizedBox(height: 24),

            // Absences Section
            const Text(
              'Absence Records',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (provider.attendanceOverview?.absences.isEmpty ?? true)
              const Text('No absence records found.', style: TextStyle(color: Colors.grey))
            else
              ...provider.attendanceOverview!.absences.map((absence) => Card(
                elevation: 0,
                color: isDark ? const Color(0xFF1E212B) : Colors.grey.shade100,
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(
                    absence.classification == 'LEAVE_APPROVED' ? Icons.event_available : Icons.warning_amber_rounded,
                    color: absence.classification == 'LEAVE_APPROVED' ? Colors.blue : Colors.orange,
                  ),
                  title: Text('Absence Date: ${absence.absenceDate.toIso8601String().split('T')[0]}'),
                  subtitle: Text('Classification: ${absence.classification} | Notification: ${absence.notificationStatus}'),
                  trailing: Chip(
                    label: Text(absence.classification),
                    backgroundColor: absence.classification == 'LEAVE_APPROVED'
                        ? Colors.blue.withValues(alpha: 0.2)
                        : Colors.orange.withValues(alpha: 0.2),
                  ),
                ),
              )),
            const SizedBox(height: 24),

            // Leave Requests Section
            const Text(
              'Leave Requests',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (provider.attendanceOverview?.leaveRequests.isEmpty ?? true)
              const Text('No leave requests found.', style: TextStyle(color: Colors.grey))
            else
              ...provider.attendanceOverview!.leaveRequests.map((leave) => Card(
                elevation: 0,
                color: isDark ? const Color(0xFF1E212B) : Colors.grey.shade100,
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.date_range, color: Colors.indigo),
                  title: Text('${leave.startDate.toIso8601String().split('T')[0]} to ${leave.endDate.toIso8601String().split('T')[0]}'),
                  subtitle: Text('Reason: ${leave.reason ?? "N/A"}'),
                  trailing: Chip(
                    label: Text(leave.status),
                    backgroundColor: leave.status == 'APPROVED'
                        ? Colors.green.withValues(alpha: 0.2)
                        : (leave.status == 'PENDING' ? Colors.orange.withValues(alpha: 0.2) : Colors.red.withValues(alpha: 0.2)),
                  ),
                ),
              )),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
