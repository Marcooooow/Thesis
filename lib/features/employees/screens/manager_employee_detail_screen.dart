import 'package:flutter/material.dart';
import 'package:intellibreak/core/design_system.dart';
import 'package:intellibreak/features/auth/services/api_service.dart';
import 'package:intellibreak/features/employees/models/employee_model.dart';
import 'package:intellibreak/features/employees/widgets/employee_shift_preview_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ManagerEmployeeDetailScreen extends StatefulWidget {
  final String employeeId;
  const ManagerEmployeeDetailScreen({super.key, required this.employeeId});

  @override
  State<ManagerEmployeeDetailScreen> createState() => _ManagerEmployeeDetailScreenState();
}

class _ManagerEmployeeDetailScreenState extends State<ManagerEmployeeDetailScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();
  bool _loading = true;
  String? _error;
  Employee? _employee;
  List<dynamic> _workSessions = [];
  Map<String, dynamic>? _wellbeingDetail;
  bool _loadingDetails = false;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      if (token == null) throw Exception('No authentication token found');

      // 1. Fetch basic employee details
      final empData = await _api.getMapWithAuth('/employees/${widget.employeeId}/manager', token);
      if (empData != null && mounted) {
        setState(() => _employee = Employee.fromJson(empData));
      }

      // 2. Fetch work sessions
      try {
        final sessionsData = await _api.getListWithAuth('/employees/${widget.employeeId}/work-sessions', token);
        if (sessionsData != null && mounted) {
          setState(() => _workSessions = sessionsData);
        }
      } catch (_) {}

      // 3. Fetch wellbeing detail (authorized team-scoped endpoint)
      try {
        final wellbeingData = await _api.getMapWithAuth('/manager/wellbeing/${widget.employeeId}/detail', token);
        if (wellbeingData != null && mounted) {
          setState(() => _wellbeingDetail = wellbeingData);
        }
      } catch (_) {}

    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showShiftPreview(BuildContext context) async {
    if (_employee == null) return;
    showDialog(
      context: context,
      builder: (context) => EmployeeShiftPreviewDialog(
        employeeId: widget.employeeId,
        name: _employee!.fullName,
        email: _employee!.email,
        role: _employee!.role,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(_employee?.fullName ?? 'Employee Inspection'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Overview', icon: Icon(Icons.person_outline, size: 18)),
            Tab(text: 'Work Sessions', icon: Icon(Icons.work_outline, size: 18)),
            Tab(text: 'Recommendations', icon: Icon(Icons.lightbulb_outline, size: 18)),
            Tab(text: 'Wellbeing', icon: Icon(Icons.spa_outlined, size: 18)),
          ],
        ),
        actions: [
          if (_employee != null)
            IconButton(
              icon: const Icon(Icons.monitor_heart),
              tooltip: 'Live Shift & Logs Preview',
              onPressed: () => _showShiftPreview(context),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error', style: const TextStyle(color: Colors.red)))
              : _employee == null
                  ? const Center(child: Text('Employee not found'))
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildOverviewTab(isDark),
                        _buildWorkSessionsTab(isDark),
                        _buildRecommendationsTab(isDark),
                        _buildWellbeingTab(isDark),
                      ],
                    ),
    );
  }

  Widget _buildOverviewTab(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DesignSystem.premiumCard(
            context: context,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: Colors.blueAccent.withValues(alpha: 0.1),
                  child: Text(
                    _employee!.fullName.isNotEmpty ? _employee!.fullName[0].toUpperCase() : 'E',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blueAccent),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_employee!.fullName, style: DesignSystem.titleXXL(context)),
                      const SizedBox(height: 4),
                      Text(_employee!.email, style: DesignSystem.caption(context)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _employee!.isActive ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _employee!.isActive ? 'Active' : 'Inactive',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _employee!.isActive ? Colors.green : Colors.red,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _employee!.role,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blue),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          DesignSystem.premiumCard(
            context: context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Assignment & Details', style: DesignSystem.titleLarge(context)),
                const SizedBox(height: 16),
                _detailRow('Team Assignment', _employee!.teamName ?? 'Unassigned'),
                const Divider(height: 24),
                _detailRow('Employee ID', _employee!.id),
                const Divider(height: 24),
                _detailRow('Account Status', _employee!.isActive ? 'Active & Verified' : 'Deactivated'),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: ElevatedButton.icon(
              onPressed: () => _showShiftPreview(context),
              icon: const Icon(Icons.monitor_heart),
              label: const Text('Launch Live Shift & Logs Preview'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: DesignSystem.caption(context)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildWorkSessionsTab(bool isDark) {
    if (_workSessions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.work_off_outlined, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              Text('No completed work sessions recorded yet.', style: DesignSystem.body(context)),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: _workSessions.length,
      itemBuilder: (context, index) {
        final session = _workSessions[index];
        final durationMins = session['duration_minutes'] ?? 0;
        final breaks = (session['breaks'] as List?) ?? [];
        final tasks = (session['tasks'] as List?) ?? [];
        final startedAt = session['started_at'] ?? 'Unknown';

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: DesignSystem.premiumCard(
            context: context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Session #${index + 1}', style: DesignSystem.titleLarge(context)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.purple.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('$durationMins mins', style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.purple)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Started: $startedAt', style: DesignSystem.caption(context)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.coffee_outlined, size: 16, color: Colors.teal),
                    const SizedBox(width: 6),
                    Text('${breaks.length} breaks taken', style: const TextStyle(fontSize: 13)),
                    const SizedBox(width: 20),
                    Icon(Icons.task_alt, size: 16, color: Colors.blue),
                    const SizedBox(width: 6),
                    Text('${tasks.length} tasks recorded', style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecommendationsTab(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DesignSystem.premiumCard(
            context: context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AI Recommendation Effectiveness', style: DesignSystem.titleLarge(context)),
                const SizedBox(height: 12),
                Text(
                  'Track how well this employee responds to wellness break coaching and hydration/stretch nudges.',
                  style: DesignSystem.body(context),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Recommendation Engine', style: DesignSystem.caption(context)),
                            const SizedBox(height: 6),
                            const Text('Active (Cold-Start Baseline)', style: TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Feedback Status', style: DesignSystem.caption(context)),
                            const SizedBox(height: 6),
                            const Text('Synchronized in real time', style: TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWellbeingTab(bool isDark) {
    if (_wellbeingDetail == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.spa_outlined, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              Text('Wellbeing telemetry currently unavailable or insufficient data.', style: DesignSystem.body(context)),
              const SizedBox(height: 8),
              Text('Distinguishes unavailable telemetry from zero values.', style: DesignSystem.caption(context)),
            ],
          ),
        ),
      );
    }

    final riskTier = _wellbeingDetail!['risk_tier'] ?? 'UNKNOWN';
    final weeklyScore = _wellbeingDetail!['weekly_score'];
    final evidence = (_wellbeingDetail!['evidence'] as List?) ?? [];

    Color tierColor = Colors.grey;
    if (riskTier == 'LOW') tierColor = Colors.green;
    if (riskTier == 'MODERATE') tierColor = Colors.orange;
    if (riskTier == 'HIGH') tierColor = Colors.deepOrange;
    if (riskTier == 'CRITICAL') tierColor = Colors.red;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DesignSystem.premiumCard(
            context: context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Wellbeing & Risk Assessment', style: DesignSystem.titleLarge(context)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: tierColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: tierColor.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        'Risk Tier: $riskTier',
                        style: TextStyle(fontWeight: FontWeight.bold, color: tierColor, fontSize: 13),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (weeklyScore != null)
                  Text('Weekly Score: ${weeklyScore.toStringAsFixed(1)} / 5.0', style: DesignSystem.title(context))
                else
                  Text('Weekly Score: Unavailable (insufficient data)', style: DesignSystem.caption(context)),
                const SizedBox(height: 16),
                const Text(
                  'Privacy Safeguard Notice: Private free-text check-in notes and sensitive qualitative user responses are suppressed by default to protect employee privacy.',
                  style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          DesignSystem.premiumCard(
            context: context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Monitored Behavioral Evidence', style: DesignSystem.titleLarge(context)),
                const SizedBox(height: 12),
                if (evidence.isEmpty)
                  Text('No risk flags or unusual behavioral patterns detected.', style: DesignSystem.body(context))
                else
                  ...evidence.map((item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, size: 16, color: Colors.blue),
                            const SizedBox(width: 8),
                            Expanded(child: Text(item.toString(), style: const TextStyle(fontSize: 13))),
                          ],
                        ),
                      )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
