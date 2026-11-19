import 'package:flutter/material.dart';
import 'package:intellibreak/core/design_system.dart';
import 'package:intellibreak/features/auth/services/api_service.dart';
import 'package:intellibreak/features/team/team_service.dart';
import 'package:intellibreak/features/dashboard/widgets/daily_timeline_card.dart';
import 'package:intellibreak/providers/work_session_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ManagerTeamActivityScreen extends StatefulWidget {
  const ManagerTeamActivityScreen({super.key});

  @override
  State<ManagerTeamActivityScreen> createState() => _ManagerTeamActivityScreenState();
}

class _ManagerTeamActivityScreenState extends State<ManagerTeamActivityScreen> {
  bool _loading = true;
  String? _error;
  final List<Map<String, dynamic>> _allActivitySessions = [];

  // Filters
  String _searchQuery = '';
  String _dateRangeFilter = 'All Time'; // All Time, Today, Last 7 Days, Last 30 Days
  String _statusFilter = 'All'; // All, Active, Completed

  final ApiService _api = ApiService();

  @override
  void initState() {
    super.initState();
    _loadTeamActivity();
  }

  Future<void> _loadTeamActivity() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (token == null) throw Exception('No authentication token found');

      // 1. Fetch teams managed by user
      final teamsData = await _api.getListWithAuth('/teams/my-teams', token);
      if (teamsData.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      List<Map<String, dynamic>> sessionsList = [];
      final teamService = TeamService();

      for (var team in teamsData) {
        final teamId = team['id'];
        if (teamId == null) continue;
        try {
          final summaryData = await teamService.getTeamActivitySummary(teamId.toString(), token);
          for (var member in summaryData) {
            final userId = member['id'] ?? member['employee_id'];
            final empName = member['full_name'] ?? member['name'] ?? 'Unknown Employee';
            final empEmail = member['email'] ?? '';
            final workSessions = (member['work_sessions'] as List?) ?? [];
            for (var s in workSessions) {
              sessionsList.add({
                'employee_id': userId,
                'employee_name': empName,
                'employee_email': empEmail,
                'session_id': s['id'],
                'started_at': s['started_at'],
                'ended_at': s['ended_at'],
                'duration_minutes': s['duration_minutes'] ?? 0,
                'breaks': s['breaks'] ?? [],
                'tasks': s['tasks'] ?? [],
                'is_active': s['status'] == 'active' || s['ended_at'] == null,
              });
            }
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _allActivitySessions.clear();
          _allActivitySessions.addAll(sessionsList);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> get _filteredSessions {
    return _allActivitySessions.where((session) {
      final empName = (session['employee_name'] as String).toLowerCase();
      final empEmail = (session['employee_email'] as String).toLowerCase();
      final query = _searchQuery.toLowerCase();

      if (query.isNotEmpty && !empName.contains(query) && !empEmail.contains(query)) {
        return false;
      }

      final isActive = session['is_active'] as bool;
      if (_statusFilter == 'Active' && !isActive) return false;
      if (_statusFilter == 'Completed' && isActive) return false;

      if (_dateRangeFilter != 'All Time' && session['started_at'] != null) {
        try {
          final startedAt = DateTime.parse(session['started_at']);
          final now = DateTime.now();
          if (_dateRangeFilter == 'Today') {
            if (startedAt.year != now.year || startedAt.month != now.month || startedAt.day != now.day) {
              return false;
            }
          } else if (_dateRangeFilter == 'Last 7 Days') {
            if (now.difference(startedAt).inDays > 7) return false;
          } else if (_dateRangeFilter == 'Last 30 Days') {
            if (now.difference(startedAt).inDays > 30) return false;
          }
        } catch (_) {}
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final sessions = _filteredSessions;

    // KPI Calculations
    final totalSessions = sessions.length;
    final totalMins = sessions.fold<int>(0, (sum, s) => sum + ((s['duration_minutes'] as int?) ?? 0));
    final totalWorkHours = (totalMins / 60.0).toStringAsFixed(1);
    final avgMins = totalSessions > 0 ? (totalMins / totalSessions).toStringAsFixed(0) : '0';

    int totalBreakMins = 0;
    for (var s in sessions) {
      final breaks = (s['breaks'] as List?) ?? [];
      for (var b in breaks) {
        try {
          if (b['started_at'] != null && b['ended_at'] != null) {
            final start = DateTime.parse(b['started_at']);
            final end = DateTime.parse(b['ended_at']);
            totalBreakMins += end.difference(start).inMinutes;
          }
        } catch (_) {}
      }
    }
    final totalBreakHours = (totalBreakMins / 60.0).toStringAsFixed(1);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error loading team activity: $_error', style: const TextStyle(color: Colors.red)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Team Work Activity', style: DesignSystem.titleXXL(context)),
                              const SizedBox(height: 4),
                              Text('Monitor real-time work sessions, breaks, and task execution for your team.', style: DesignSystem.caption(context)),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh),
                            tooltip: 'Refresh Activity',
                            onPressed: _loadTeamActivity,
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // 4 KPI Cards
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth > 800;
                          final cardWidth = isWide ? (constraints.maxWidth - 36) / 4 : (constraints.maxWidth - 12) / 2;
                          return Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              _buildKpiCard(context, 'Total Team Sessions', '$totalSessions', Icons.work_outline, Colors.blue, cardWidth),
                              _buildKpiCard(context, 'Total Work Hours', '$totalWorkHours hrs', Icons.schedule, Colors.green, cardWidth),
                              _buildKpiCard(context, 'Avg Session Duration', '$avgMins mins', Icons.timer, Colors.purple, cardWidth),
                              _buildKpiCard(context, 'Total Break Time', '$totalBreakHours hrs', Icons.coffee_outlined, Colors.teal, cardWidth),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 28),

                      // Search & Filters Bar
                      DesignSystem.premiumCard(
                        context: context,
                        child: Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            SizedBox(
                              width: 280,
                              child: TextField(
                                decoration: const InputDecoration(
                                  hintText: 'Search employee name or email...',
                                  prefixIcon: Icon(Icons.search, size: 20),
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (val) => setState(() => _searchQuery = val),
                              ),
                            ),
                            DropdownButton<String>(
                              value: _dateRangeFilter,
                              items: ['All Time', 'Today', 'Last 7 Days', 'Last 30 Days']
                                  .map((val) => DropdownMenuItem(value: val, child: Text(val)))
                                  .toList(),
                              onChanged: (val) => setState(() => _dateRangeFilter = val ?? 'All Time'),
                            ),
                            DropdownButton<String>(
                              value: _statusFilter,
                              items: ['All', 'Active', 'Completed']
                                  .map((val) => DropdownMenuItem(value: val, child: Text('Status: $val')))
                                  .toList(),
                              onChanged: (val) => setState(() => _statusFilter = val ?? 'All'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Activity Table / List
                      DesignSystem.premiumCard(
                        context: context,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Work Session Logs (${sessions.length})', style: DesignSystem.titleLarge(context)),
                            const SizedBox(height: 16),
                            sessions.isEmpty
                                ? Padding(
                                    padding: const EdgeInsets.all(32),
                                    child: Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.history_toggle_off, size: 48, color: Colors.grey),
                                          const SizedBox(height: 12),
                                          Text('No team activity sessions found matching current filters.', style: DesignSystem.body(context)),
                                        ],
                                      ),
                                    ),
                                  )
                                : LayoutBuilder(
                                    builder: (context, constraints) {
                                      return SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: DataTable(
                                          columns: const [
                                            DataColumn(label: Text('Employee')),
                                            DataColumn(label: Text('Status')),
                                            DataColumn(label: Text('Started At')),
                                            DataColumn(label: Text('Duration')),
                                            DataColumn(label: Text('Breaks')),
                                            DataColumn(label: Text('Tasks')),
                                            DataColumn(label: Text('Actions')),
                                          ],
                                          rows: sessions.map((s) {
                                            final isActive = s['is_active'] as bool;
                                            final breaks = (s['breaks'] as List?) ?? [];
                                            final tasks = (s['tasks'] as List?) ?? [];
                                            return DataRow(cells: [
                                              DataCell(
                                                Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Text(s['employee_name'], style: const TextStyle(fontWeight: FontWeight.w600)),
                                                    Text(s['employee_email'], style: DesignSystem.caption(context)),
                                                  ],
                                                ),
                                              ),
                                              DataCell(
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: isActive ? Colors.green.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    isActive ? 'Active' : 'Completed',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w600,
                                                      color: isActive ? Colors.green : Colors.grey.shade700,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              DataCell(Text(s['started_at']?.toString().replaceAll('T', ' ').substring(0, 19) ?? 'Unknown')),
                                              DataCell(Text('${s['duration_minutes']} mins')),
                                              DataCell(Text('${breaks.length} breaks')),
                                              DataCell(Text('${tasks.length} tasks')),
                                              DataCell(
                                                TextButton.icon(
                                                  icon: const Icon(Icons.timeline, size: 16),
                                                  label: const Text('Timeline'),
                                                  onPressed: () => _showSessionTimeline(context, s),
                                                ),
                                              ),
                                            ]);
                                          }).toList(),
                                        ),
                                      );
                                    },
                                  ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildKpiCard(BuildContext context, String title, String value, IconData icon, Color color, double width) {
    return SizedBox(
      width: width < 220 ? double.infinity : width,
      child: DesignSystem.premiumCard(
        context: context,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: DesignSystem.caption(context)),
                  const SizedBox(height: 4),
                  Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  DateTime _parseTime(dynamic val) {
    if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
    if (val is String) {
      try {
        return DateTime.parse(val).toLocal();
      } catch (_) {}
    }
    return DateTime.now();
  }

  WorkSessionState _parseSessionState(Map<String, dynamic> sessionMap) {
    WorkSession? session;
    if (sessionMap['started_at'] != null) {
      session = WorkSession(
        id: sessionMap['session_id']?.toString() ?? sessionMap['id']?.toString() ?? 'session_1',
        startedAt: _parseTime(sessionMap['started_at']),
        endedAt: sessionMap['ended_at'] != null ? _parseTime(sessionMap['ended_at']) : null,
      );
    }

    final breaksList = (sessionMap['breaks'] as List?) ?? [];
    final completedBreaks = <WorkBreak>[];
    WorkBreak? activeBreak;

    for (var b in breaksList) {
      final workBreak = WorkBreak(
        id: b['id']?.toString() ?? 'break_1',
        workSessionId: session?.id ?? 'session_1',
        type: BreakType.fromWire(b['break_type']),
        startedAt: _parseTime(b['started_at']),
        endedAt: b['ended_at'] != null ? _parseTime(b['ended_at']) : null,
        durationMinutes: b['duration_minutes'] as int?,
      );
      if (workBreak.endedAt == null) {
        activeBreak = workBreak;
      } else {
        completedBreaks.add(workBreak);
      }
    }

    final tasksList = (sessionMap['tasks'] as List?) ?? [];
    final tasks = tasksList.map((t) => WorkTask(
      id: t['id']?.toString() ?? 'task_1',
      title: t['title'] ?? 'Task',
      category: t['category'] ?? 'General',
      status: t['status'] ?? 'TODO',
      workSessionId: session?.id,
      startedAt: t['started_at'] != null ? _parseTime(t['started_at']) : null,
      endedAt: t['ended_at'] != null ? _parseTime(t['ended_at']) : null,
      actualMinutes: t['actual_minutes'] as int?,
    )).toList();

    return WorkSessionState(
      session: session,
      activeBreak: activeBreak,
      completedBreaks: completedBreaks,
      tasks: tasks,
    );
  }

  void _showSessionTimeline(BuildContext context, Map<String, dynamic> session) {
    final sessionState = _parseSessionState(session);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Session Timeline — ${session['employee_name']}'),
        content: SizedBox(
          width: 650,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                DailyTimelineCard(sessionState: sessionState),
                const SizedBox(height: 16),
                Text('Session Summary', style: DesignSystem.titleLarge(context)),
                const SizedBox(height: 8),
                Text('Started: ${session['started_at']}', style: DesignSystem.caption(context)),
                Text('Ended: ${session['ended_at'] ?? 'Ongoing (Active Shift)'}', style: DesignSystem.caption(context)),
                Text('Total Duration: ${session['duration_minutes']} minutes', style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
