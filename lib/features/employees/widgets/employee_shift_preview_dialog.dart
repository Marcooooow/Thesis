import 'package:flutter/material.dart';
import 'package:intellibreak/features/auth/services/api_service.dart';
import 'package:intellibreak/features/dashboard/widgets/shift_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EmployeeShiftPreviewDialog extends StatefulWidget {
  final String employeeId;
  final String name;
  final String email;
  final String role;

  const EmployeeShiftPreviewDialog({
    super.key,
    required this.employeeId,
    required this.name,
    required this.email,
    required this.role,
  });

  @override
  State<EmployeeShiftPreviewDialog> createState() =>
      _EmployeeShiftPreviewDialogState();
}

class _EmployeeShiftPreviewDialogState
    extends State<EmployeeShiftPreviewDialog> {
  final ApiService _api = ApiService();
  bool _loading = true;
  String? _errorMessage;
  Map<String, dynamic>? _liveStatus;
  List<dynamic> _shiftLogs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null) {
      setState(() {
        _loading = false;
        _errorMessage = 'Not Authenticated';
      });
      return;
    }
    try {
      _liveStatus = await _api.getMapWithAuth(
        '/employees/${widget.employeeId}/live-status',
        token,
      );
      _shiftLogs = await _api.getListWithAuth(
        '/employees/${widget.employeeId}/work-sessions',
        token,
      );
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('404') || msg.contains('Not Found')) {
        _errorMessage = 'Employee Not Found';
      } else if (msg.contains('403') || msg.contains('Access denied')) {
        _errorMessage = 'Access Denied';
      } else {
        _errorMessage = 'Unable to Load Status';
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String _formatDate(String? isoStr) {
    if (isoStr == null) return 'N/A';
    try {
      final dt = DateTime.parse(isoStr).toLocal();
      return '${dt.month}/${dt.day}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.visibility, color: Colors.blue, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Live Shift & Logs: ${widget.name}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 680),
        child: SizedBox(
          width: 700,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 48,
                        color: Colors.orange,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _errorMessage == 'Employee Not Found'
                            ? 'The selected employee record could not be found.'
                            : _errorMessage == 'Access Denied'
                            ? 'You do not have permission to view this employee.'
                            : 'Failed to retrieve live status. Please check your connection and try again.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Summary Card
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.blue.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.monitor_heart,
                                      color: Colors.blue,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Status: ${_liveStatus?['status_category'] ?? 'Not Started'}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'Read-Only Preview',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Employee: ${widget.name}\nEmail: ${widget.email}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    'Role: ${widget.role}\nID: ${widget.employeeId.substring(0, 8)}...',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Shift Controller Preview',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ShiftController(
                        readOnly: true,
                        employeeName: widget.name,
                        liveStatus: _liveStatus,
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Recent Shift Logs',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_shiftLogs.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'No recent shift logs found.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      else
                        ..._shiftLogs.take(5).map((log) {
                          final durationMins = log['duration_minutes'] ?? 0;
                          final startTime = _formatDate(log['started_at']);
                          final status = log['ended_at'] != null
                              ? 'Completed'
                              : 'Active';
                          return Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E222A),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey[800]!),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Started: $startTime',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Duration: $durationMins mins',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: status == 'Completed'
                                        ? Colors.green.withValues(alpha: 0.15)
                                        : Colors.blue.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    status,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: status == 'Completed'
                                          ? Colors.green
                                          : Colors.blue,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
