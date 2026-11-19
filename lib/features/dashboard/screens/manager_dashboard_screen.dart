import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intellibreak/core/design_system.dart';
import 'package:intellibreak/features/auth/services/api_service.dart';
import 'package:intellibreak/features/wellbeing/screens/employee_wellbeing_detail_screen.dart';
import 'package:intellibreak/providers/team_provider.dart';
import 'package:intellibreak/models/team_models.dart';
import 'package:intellibreak/providers/work_session_models.dart';
import 'package:intellibreak/features/wellbeing/models/wellbeing_models.dart';
import 'package:intellibreak/features/wellbeing/services/wellbeing_service.dart';
import 'package:intellibreak/features/wellbeing/widgets/team_wellbeing_dashboard_widget.dart';

class ManagerDashboardContent extends StatefulWidget {
  const ManagerDashboardContent({super.key});

  @override
  State<ManagerDashboardContent> createState() => _ManagerDashboardContentState();
}

class _ManagerDashboardContentState extends State<ManagerDashboardContent> {
  bool _isLoading = true;
  Map<String, dynamic> _summaryData = {};
  Map<String, dynamic> _wellbeingWeeklyData = {};
  WeeklyOverviewResponse? _weeklyOverview;
  bool _isLoadingWellbeing = false;
  Map<String, dynamic> _advisorReport = {};
  bool _isLoadingAdvisor = false;
  DateTime? _selectedWeekStart;
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    _selectedWeekStart = _getMonday(DateTime.now());
    _loadData();
    _fetchWeeklyOverview(weekStart: _selectedWeekStart);
    _fetchAdvisorReport();
  }

  Future<void> _fetchAdvisorReport() async {
    setState(() => _isLoadingAdvisor = true);
    try {
      final wellbeingService = WellbeingService();
      final report = await wellbeingService.getTeamWellnessAdvisor();
      if (mounted) {
        setState(() {
          _advisorReport = report;
          _isLoadingAdvisor = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingAdvisor = false);
      }
    }
  }


  Future<void> _loadData() async {
    final teamProvider = context.read<TeamProvider>();
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');

    if (token != null) {
      await teamProvider.loadMyTeam(token);
      if (!mounted) return;
      if (teamProvider.hasTeam) {
        await teamProvider.loadTeamMembers(teamProvider.currentTeam!.id, token);
      }
      if (!mounted) return;
      await Future.wait([
        _fetchTeamSummary(token),
        _fetchWeeklyOverview(weekStart: _selectedWeekStart),
      ]);
      if (mounted) setState(() => _isLoading = false);
    } else {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchTeamSummary(String token) async {
    try {
      final res = await _apiService.getMapWithAuth('/manager/analytics/team-summary', token);
      if (res != null && mounted) {
        setState(() {
          _summaryData = res;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchWellbeingWeekly(String token) async {
    try {
      final res = await _apiService.getMapWithAuth('/manager/wellbeing/weekly', token);
      if (res != null && mounted) {
        setState(() {
          _wellbeingWeeklyData = res;
        });
      }
    } catch (_) {} finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchWeeklyOverview({DateTime? weekStart}) async {
    if (!mounted) return;

    setState(() {
      _isLoadingWellbeing = true;
    });

    try {
      final wellbeingService = WellbeingService();
      final overview = await wellbeingService.getWeeklyOverview(
        weekStart: weekStart ?? _selectedWeekStart,
      );

      if (mounted) {
        setState(() {
          _weeklyOverview = overview;
          _selectedWeekStart = weekStart ?? _selectedWeekStart;
          _isLoadingWellbeing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingWellbeing = false;
        });
      }
    }
  }

  void _onWeekChange(DateTime newWeekStart) {
    _fetchWeeklyOverview(weekStart: newWeekStart);
  }

  void _onRefreshWellbeing() {
    _fetchWeeklyOverview(weekStart: _selectedWeekStart);
  }

  DateTime _getMonday(DateTime date) {
    return date.subtract(Duration(days: date.weekday - 1));
  }

  void _navigateToEmployee(String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EmployeeWellbeingDetailScreen(
          employeeId: userId,
          employeeName: '',  // Will be fetched from API
          initialWeekStart: _selectedWeekStart,
        ),
      ),
    );
  }

  void _onEmployeeSelected(String employeeId, String employeeName, String? teamName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EmployeeWellbeingDetailScreen(
          employeeId: employeeId,
          employeeName: employeeName,
          teamName: teamName,
          initialWeekStart: _selectedWeekStart,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isDesktop = screenWidth >= 1100;
    final teamProvider = context.watch<TeamProvider>();

    if (_isLoading && _summaryData.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: DesignSystem.skeletonMetricCard(context: context)),
                const SizedBox(width: 16),
                Expanded(child: DesignSystem.skeletonMetricCard(context: context)),
                const SizedBox(width: 16),
                Expanded(child: DesignSystem.skeletonMetricCard(context: context)),
                const SizedBox(width: 16),
                Expanded(child: DesignSystem.skeletonMetricCard(context: context)),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(child: DesignSystem.skeletonTable(context: context, rows: 5, columns: 4)),
          ],
        ),
      );
    }

    final teamName = teamProvider.currentTeam?.name ?? 'Assigned Team';
    final totalEmployees = (_summaryData['total_employees'] as num?)?.toInt() ?? teamProvider.teamMembers.length;
    final int currentlyWorking = teamProvider.teamMembers.where((m) => m.status == 'Working').length;
    final teamFocusRate = (_summaryData['team_focus_rate'] as num?)?.toDouble() ?? 85.0;
    final aggregateWellbeing = _summaryData['aggregate_wellbeing'] as Map<String, dynamic>?;
    final avgWellbeing = aggregateWellbeing != null
        ? ((aggregateWellbeing['low'] ?? 0) * 5.0 + (aggregateWellbeing['moderate'] ?? 0) * 3.5) / math.max(1, totalEmployees)
        : 4.2;

    final workloadSummary = (_summaryData['workload_summary'] is Map) ? (_summaryData['workload_summary'] as Map) : {};
    final totalWorkHours = (workloadSummary['total_work_hours'] as num?)?.toDouble() ?? (totalEmployees * 32.5);
    final avgWorkHoursPerEmp = (workloadSummary['avg_work_hours_per_employee'] as num?)?.toDouble() ?? 32.5;
    final breakCompliance = (_summaryData['break_compliance_percentage'] as num?)?.toDouble() ?? 88.5;
    final extendedSessionsCount = (_summaryData['extended_sessions_count'] as num?)?.toInt() ?? 2;

    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(isDesktop ? 24.0 : 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Manager Dashboard',
                      style: DesignSystem.titleXXL(context),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Team oversight and wellness monitoring for $teamName',
                      style: DesignSystem.caption(context),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: DesignSystem.getSemanticColor(context, SemanticColor.primary).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(DesignSystem.radiusM),
                    border: Border.all(
                      color: DesignSystem.getSemanticColor(context, SemanticColor.primary).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.group,
                        size: 16,
                        color: DesignSystem.getSemanticColor(context, SemanticColor.primary),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        teamName,
                        style: TextStyle(
                          color: DesignSystem.getSemanticColor(context, SemanticColor.primary),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Overview Cards (4 KPI Cards)
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 900) {
                  return Row(
                    children: [
                      Expanded(
                        child: DesignSystem.statCard(
                          context: context,
                          label: 'Total Members',
                          value: '$totalEmployees',
                          icon: Icons.people_outline,
                          color: Colors.blueAccent,
                          description: 'Assigned team count',
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: DesignSystem.statCard(
                          context: context,
                          label: 'Currently Working',
                          value: '$currentlyWorking',
                          icon: Icons.work_outline,
                          color: Colors.greenAccent,
                          description: 'Active shifts right now',
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: DesignSystem.statCard(
                          context: context,
                          label: 'Team Focus Rate',
                          value: '${teamFocusRate.toStringAsFixed(1)}%',
                          icon: Icons.track_changes,
                          color: Colors.purpleAccent,
                          description: 'Productivity ratio',
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: DesignSystem.statCard(
                          context: context,
                          label: 'Average Wellbeing',
                          value: '${avgWellbeing.toStringAsFixed(1)} / 5.0',
                          icon: Icons.spa_outlined,
                          color: Colors.tealAccent,
                          description: 'Wellness index',
                        ),
                      ),
                    ],
                  );
                } else {
                  return Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: DesignSystem.statCard(
                              context: context,
                              label: 'Total Members',
                              value: '$totalEmployees',
                              icon: Icons.people_outline,
                              color: Colors.blueAccent,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: DesignSystem.statCard(
                              context: context,
                              label: 'Currently Working',
                              value: '$currentlyWorking',
                              icon: Icons.work_outline,
                              color: Colors.greenAccent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: DesignSystem.statCard(
                              context: context,
                              label: 'Team Focus Rate',
                              value: '${teamFocusRate.toStringAsFixed(1)}%',
                              icon: Icons.track_changes,
                              color: Colors.purpleAccent,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: DesignSystem.statCard(
                              context: context,
                              label: 'Average Wellbeing',
                              value: '${avgWellbeing.toStringAsFixed(1)} / 5.0',
                              icon: Icons.spa_outlined,
                              color: Colors.tealAccent,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                }
              },
            ),
            const SizedBox(height: 24),

            // Main Sections Layout (70/30 split)
            if (isDesktop)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 7,
                    child: Column(
                      children: [
                        _buildLiveTeamStatusCard(context, teamProvider),
                        const SizedBox(height: 24),
                        _buildTeamActivityTimelineCard(context, teamProvider),
                        const SizedBox(height: 24),
                        _buildWorkPatternsCard(context, totalWorkHours, avgWorkHoursPerEmp, breakCompliance, extendedSessionsCount),
                        const SizedBox(height: 24),
                        TeamWellbeingDashboardWidget(
                          weeklyData: _weeklyOverview,
                          isLoading: _isLoadingWellbeing,
                          onRefresh: _onRefreshWellbeing,
                          onWeekChange: _onWeekChange,
                          selectedWeekStart: _selectedWeekStart,
                          onEmployeeSelected: _onEmployeeSelected,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 3,
                    child: Column(
                      children: [
                        _buildRecoverySummaryCard(context),
                        const SizedBox(height: 24),
                        _buildAttentionRequiredCard(context),
                      ],
                    ),
                  ),
                ],
              )
            else
              Column(
                children: [
                  _buildLiveTeamStatusCard(context, teamProvider),
                  const SizedBox(height: 24),
                  _buildTeamActivityTimelineCard(context, teamProvider),
                  const SizedBox(height: 24),
                  _buildWorkPatternsCard(context, totalWorkHours, avgWorkHoursPerEmp, breakCompliance, extendedSessionsCount),
                  const SizedBox(height: 24),
                  _buildRecoverySummaryCard(context),
                  const SizedBox(height: 24),
                  _buildAttentionRequiredCard(context),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveTeamStatusCard(BuildContext context, TeamProvider teamProvider) {
    final members = teamProvider.teamMembers;

    return DesignSystem.premiumCard(
      context: context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Live Team Status', style: DesignSystem.titleLarge(context)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${members.length} Active Members • Live Sync',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.green),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (members.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: Center(
                child: Text('No team members assigned to this team yet.', style: DesignSystem.body(context)),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: members.length,
              separatorBuilder: (context, index) => Divider(
                height: 1,
                color: Theme.of(context).dividerTheme.color ?? Colors.grey.withValues(alpha: 0.2),
              ),
              itemBuilder: (context, index) {
                final member = members[index];
                return InkWell(
                  onTap: () => _navigateToEmployee(member.userId),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 4.0),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: Colors.blueAccent.withValues(alpha: 0.1),
                          child: Text(
                            member.userName.isNotEmpty ? member.userName[0].toUpperCase() : 'U',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent, fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(member.userName, style: DesignSystem.title(context)),
                              const SizedBox(height: 2),
                              Text(member.userEmail, style: DesignSystem.caption(context)),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: member.status == 'Working'
                                      ? Colors.green.withValues(alpha: 0.1)
                                      : member.status == 'On Break'
                                          ? Colors.orange.withValues(alpha: 0.1)
                                          : Colors.grey.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  member.status,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: member.status == 'Working'
                                        ? Colors.green
                                        : member.status == 'On Break'
                                            ? Colors.orange.shade800
                                            : Colors.grey.shade700,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text('Role: ${member.role}', style: DesignSystem.caption(context)),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(member.hoursTodayText, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              const SizedBox(height: 2),
                              Text(member.focusText, style: DesignSystem.caption(context)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  WorkSessionState _buildMemberState(TeamMember member) {
    WorkSession? session;
    if (member.activeWorkSession != null) {
      session = WorkSession(
        id: member.activeWorkSession!['id']?.toString() ?? 'session_1',
        startedAt: DateTime.parse(member.activeWorkSession!['started_at'] as String).toLocal(),
        endedAt: member.activeWorkSession!['ended_at'] != null
            ? DateTime.parse(member.activeWorkSession!['ended_at'] as String).toLocal()
            : null,
      );
    }

    WorkBreak? activeBreak;
    if (member.activeBreak != null) {
      activeBreak = WorkBreak(
        id: member.activeBreak!['id']?.toString() ?? 'break_1',
        workSessionId: session?.id ?? 'session_1',
        type: BreakType.fromWire(member.activeBreak!['break_type']),
        startedAt: DateTime.parse(member.activeBreak!['started_at'] as String).toLocal(),
        endedAt: member.activeBreak!['ended_at'] != null
            ? DateTime.parse(member.activeBreak!['ended_at'] as String).toLocal()
            : null,
        durationMinutes: member.activeBreak!['duration_minutes'] as int?,
      );
    }

    return WorkSessionState(
      session: session,
      activeBreak: activeBreak,
      completedBreaks: [],
      tasks: [],
    );
  }

  Widget _buildTeamActivityTimelineCard(BuildContext context, TeamProvider teamProvider) {
    final members = teamProvider.teamMembers;

    return DesignSystem.premiumCard(
      context: context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Team Activity Timeline', style: DesignSystem.titleLarge(context)),
              Text('Today\'s Live Activity', style: DesignSystem.caption(context)),
            ],
          ),
          const SizedBox(height: 16),
          if (members.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('No active timeline records.', style: DesignSystem.caption(context)),
            )
          else
            _ManagerTeamTimelineWidget(members: members, buildMemberState: _buildMemberState),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legendItem(const Color(0xFF2ECC71), 'Work Session'),
              const SizedBox(width: 16),
              _legendItem(const Color(0xFF3498DB), 'Break'),
              const SizedBox(width: 16),
              _legendItem(const Color(0xFFDAA520), 'Lunch/Meal'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: DesignSystem.caption(context)),
      ],
    );
  }

  Widget _buildWorkPatternsCard(BuildContext context, double totalHours, double avgHours, double breakCompliance, int extendedSessions) {
    return DesignSystem.premiumCard(
      context: context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Team Work Patterns & Metrics', style: DesignSystem.titleLarge(context)),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.8,
            children: [
              _metricTile(context, 'Average Work Hours', '${avgHours.toStringAsFixed(1)} hrs/emp', Icons.access_time, Colors.blueAccent),
              _metricTile(context, 'Break Compliance', '${breakCompliance.toStringAsFixed(1)}%', Icons.coffee_outlined, Colors.tealAccent),
              _metricTile(context, 'Extended Sessions', '$extendedSessions flagged', Icons.warning_amber_rounded, Colors.orangeAccent),
              _metricTile(context, 'Workload Distribution', 'Balanced', Icons.bar_chart, Colors.purpleAccent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricTile(BuildContext context, String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: DesignSystem.caption(context), overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: DesignSystem.titleLarge(context)),
        ],
      ),
    );
  }

  Widget _buildRecoverySummaryCard(BuildContext context) {
    final employees = _weeklyOverview?.employees ?? <EmployeeRiskSummary>[];
    final breakCount = employees.where((e) => e.riskTier == RiskTier.high || e.riskTier == RiskTier.critical).length;
    final leaveCount = employees.where((e) => e.riskTier == RiskTier.critical && e.topEvidence.any((item) => item.toLowerCase().contains('recurring overwork'))).length;
    final unknownCount = employees.where((e) => e.riskTier == RiskTier.insufficientData).length;
    return DesignSystem.premiumCard(
      context: context,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Recovery Support', style: DesignSystem.titleLarge(context)),
        const SizedBox(height: 8),
        Text('$breakCount employees may need a recovery break', style: DesignSystem.body(context)),
        const SizedBox(height: 4),
        Text('$leaveCount employees may benefit from discussing time off', style: DesignSystem.body(context)),
        if (unknownCount > 0) ...[
          const SizedBox(height: 6),
          Text('$unknownCount employees could not be assessed this week.', style: DesignSystem.caption(context)),
        ],
        const SizedBox(height: 6),
        Text('Advisory counts based on this week’s risk assessment. Managers should discuss options with employees; leave remains subject to employee choice and normal approval.', style: DesignSystem.caption(context)),
      ]),
    );
  }

  Widget _buildAttentionRequiredCard(BuildContext context) {
    final employees = _weeklyOverview?.employees ?? <EmployeeRiskSummary>[];
    final flaggedEmployees = employees.where((employee) =>
      employee.riskTier == RiskTier.high || employee.riskTier == RiskTier.critical
    ).toList();
    final insufficientCount = employees.where((employee) =>
      employee.riskTier == RiskTier.insufficientData
    ).length;

    return DesignSystem.premiumCard(
      context: context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 20),
                  const SizedBox(width: 8),
                  Text('Attention Required', style: DesignSystem.titleLarge(context)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${flaggedEmployees.length} alerts',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (flaggedEmployees.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Center(
                child: Column(
                  children: [
                    const Icon(Icons.check_circle_outline, size: 36, color: Colors.green),
                    const SizedBox(height: 8),
                    Text('No high or critical risk cases for this week.', style: DesignSystem.body(context)),
                    if (insufficientCount > 0) ...[
                      const SizedBox(height: 4),
                      Text('$insufficientCount employees have insufficient data and could not be assessed.', style: DesignSystem.caption(context), textAlign: TextAlign.center),
                    ],
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: flaggedEmployees.length,
              separatorBuilder: (context, index) => const Divider(height: 16),
              itemBuilder: (context, index) {
                final emp = flaggedEmployees[index];
                final name = emp.employeeName;
                final concern = emp.primaryConcern;
                final evidence = emp.topEvidence.join(', ');
                final empId = emp.employeeId;
                final isCritical = emp.riskTier == RiskTier.critical;
                final riskLabel = isCritical ? 'Critical Risk' : 'High Risk';
                final riskColor = isCritical ? Colors.red : Colors.deepOrange;

                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: riskColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(riskLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: riskColor)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('Concern: $concern', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text('Evidence: $evidence', style: DesignSystem.caption(context)),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: empId.isNotEmpty ? () => _navigateToEmployee(empId) : null,
                          icon: const Icon(Icons.arrow_forward, size: 14),
                          label: const Text('View Employee', style: TextStyle(fontSize: 12)),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _ManagerTeamTimelineWidget extends StatelessWidget {
  final List<TeamMember> members;
  final WorkSessionState Function(TeamMember) buildMemberState;

  const _ManagerTeamTimelineWidget({
    required this.members,
    required this.buildMemberState,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day, 8, 0);
    final endOfDay = DateTime(now.year, now.month, now.day, 17, 0);
    final totalMs = endOfDay.difference(startOfDay).inMilliseconds.toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...members.take(5).map((member) {
          final memberState = buildMemberState(member);
          return Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          member.userName,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: member.status == 'Working'
                              ? Colors.green.withValues(alpha: 0.1)
                              : member.status == 'On Break'
                                  ? Colors.orange.withValues(alpha: 0.1)
                                  : Colors.grey.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          member.status,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: member.status == 'Working'
                                ? Colors.green
                                : member.status == 'On Break'
                                    ? Colors.orange.shade800
                                    : Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 7,
                  child: SizedBox(
                    height: 24,
                    child: CustomPaint(
                      painter: _CompactTrackPainter(
                        state: memberState,
                        now: now,
                        startOfDay: startOfDay,
                        endOfDay: endOfDay,
                        totalMs: totalMs,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 4),
        // Shared Time Axis
        Row(
          children: [
            const Spacer(flex: 3),
            const SizedBox(width: 12),
            Expanded(
              flex: 7,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text('08:00', style: TextStyle(fontSize: 10, color: Colors.grey)),
                  Text('10:00', style: TextStyle(fontSize: 10, color: Colors.grey)),
                  Text('12:00', style: TextStyle(fontSize: 10, color: Colors.grey)),
                  Text('14:00', style: TextStyle(fontSize: 10, color: Colors.grey)),
                  Text('16:00', style: TextStyle(fontSize: 10, color: Colors.grey)),
                  Text('17:00', style: TextStyle(fontSize: 10, color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CompactTrackPainter extends CustomPainter {
  final WorkSessionState state;
  final DateTime now;
  final DateTime startOfDay;
  final DateTime endOfDay;
  final double totalMs;

  _CompactTrackPainter({
    required this.state,
    required this.now,
    required this.startOfDay,
    required this.endOfDay,
    required this.totalMs,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Guard against invalid size
    if (size.width <= 0 || !size.width.isFinite || size.height <= 0 || !size.height.isFinite) {
      return;
    }

    // Background track
    final bgPaint = Paint()..color = const Color(0xFF2A2E35);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 4, size.width, size.height - 8),
        const Radius.circular(4),
      ),
      bgPaint,
    );

    if (totalMs <= 0) return;

    final session = state.session;
    if (session != null) {
      final sStart = session.startedAt;
      final sEnd = session.endedAt ?? (state.isActive && !state.isOnBreak ? now : null);
      if (sStart.isBefore(endOfDay) && (sEnd == null || sEnd.isAfter(startOfDay))) {
        final segStart = sStart.isBefore(startOfDay) ? startOfDay : sStart;
        final segEnd = sEnd == null ? (state.isActive ? now : endOfDay) : (sEnd.isAfter(endOfDay) ? endOfDay : sEnd);

        final x1 = ((segStart.difference(startOfDay).inMilliseconds / totalMs) * size.width).clamp(0.0, size.width);
        final x2 = ((segEnd.difference(startOfDay).inMilliseconds / totalMs) * size.width).clamp(0.0, size.width);
        if (x2 > x1) {
          final workPaint = Paint()..color = const Color(0xFF2ECC71).withValues(alpha: 0.85);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(x1, 4, x2 - x1, size.height - 8),
              const Radius.circular(3),
            ),
            workPaint,
          );
        }
      }
    }

    if (state.activeBreak != null && state.activeBreak?.startedAt != null) {
      final bStart = state.activeBreak!.startedAt;
      final bEnd = now;
      if (bStart.isBefore(endOfDay) && bEnd.isAfter(startOfDay)) {
        final segStart = bStart.isBefore(startOfDay) ? startOfDay : bStart;
        final segEnd = bEnd.isAfter(endOfDay) ? endOfDay : bEnd;

        final x1 = ((segStart.difference(startOfDay).inMilliseconds / totalMs) * size.width).clamp(0.0, size.width);
        final x2 = ((segEnd.difference(startOfDay).inMilliseconds / totalMs) * size.width).clamp(0.0, size.width);
        if (x2 > x1) {
          final breakPaint = Paint()..color = const Color(0xFF3498DB).withValues(alpha: 0.85);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(x1, 4, x2 - x1, size.height - 8),
              const Radius.circular(3),
            ),
            breakPaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
