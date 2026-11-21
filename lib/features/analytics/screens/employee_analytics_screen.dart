import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intellibreak/core/theme/theme_controller.dart';
import 'package:intellibreak/core/motion.dart';
import 'package:intellibreak/features/analytics/services/analytics_service.dart';
import 'package:intellibreak/features/auth/services/api_service.dart';
import 'package:intellibreak/features/analytics/widgets/focus_rate_progress.dart';
import 'package:intellibreak/features/analytics/widgets/focus_idle_line_chart.dart';
import 'package:intellibreak/features/analytics/widgets/daily_work_hours_bar_chart.dart';
import 'package:intellibreak/features/analytics/widgets/report_exports_section.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

/// Dedicated Employee Analytics screen — Phase 2 backend integration.
/// Sections: Performance Overview, Productivity Trends, Break Analysis,
/// Wellbeing Trends, Session History, Insights.
class EmployeeAnalyticsScreenContent extends StatefulWidget {
  const EmployeeAnalyticsScreenContent({super.key});

  @override
  State<EmployeeAnalyticsScreenContent> createState() => _EmployeeAnalyticsScreenState();
}

class _EmployeeAnalyticsScreenState extends State<EmployeeAnalyticsScreenContent> {
  String? _token;
  bool _isLoading = true;
  bool _isExporting = false;
  String _selectedPeriod = 'This Week';
  int _customDays = 14; // used when _selectedPeriod == 'Custom'
  final AnalyticsService _analyticsService = AnalyticsService();
  final ApiService _apiService = ApiService();

  // Section data
  Map<String, dynamic> _breakAnalysis = {};
  Map<String, dynamic> _wellbeingSummary = {};
  dynamic _sessionHistory = [];
  dynamic _insights = [];
  Map<String, dynamic> _todaySummary = {};

  @override
  void initState() {
    super.initState();
    _loadTokenAndData();
  }

  Future<void> _loadTokenAndData() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('jwt_token');
    if (mounted) setState(() => _isLoading = false);
    if (_token != null) {
      try {
        await _fetchAll();
      } catch (_) {
        // If data fetch fails, we still want to show the error state
        // _isLoading will be set to false by the error handlers in _fetchAll
        rethrow;
      }
    } else {
      // No token means we're not authenticated - still finish loading
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchAll() async {
    if (_token == null) return;
    final token = _token!;
    final range = _dateRangeForPeriod(_selectedPeriod);
    final startDate = range.$1;
    final endDate = range.$2;
    final dateQuery = '?start_date=${startDate.toIso8601String().split('T')[0]}&end_date=${endDate.toIso8601String().split('T')[0]}';

    // Existing summary endpoint with date range
    try {
      _todaySummary = await _analyticsService.getTodaySummary(token, startDate: startDate, endDate: endDate);
    } catch (_) {
      _todaySummary = {};
    }

    // Phase 1 new endpoints with date range
    try {
      final breakRes = await _apiService.getMapWithAuth('/analytics/break-analysis$dateQuery', token);
      _breakAnalysis = breakRes ?? {};
    } catch (_) { _breakAnalysis = {}; }

    try {
      final wbRes = await _analyticsService.getWellbeingSummary(token, startDate: startDate, endDate: endDate);
      _wellbeingSummary = wbRes;
    } catch (_) { _wellbeingSummary = {}; }

    try {
      final sessRes = await _apiService.getMapWithAuth('/analytics/session-history$dateQuery&limit=10', token);
      if (sessRes != null && sessRes['items'] is List) {
        _sessionHistory = sessRes['items'];
      } else {
        _sessionHistory = [];
      }
    } catch (_) { _sessionHistory = []; }

    try {
      final insightRes = await _apiService.getListWithAuth('/analytics/insights', token);
      _insights = insightRes;
    } catch (_) { _insights = []; }

    if (mounted) setState(() {});
  }

  (DateTime, DateTime) _dateRangeForPeriod(String period) {
    final now = DateTime.now();
    switch (period) {
      case 'Today': return (DateTime(now.year, now.month, now.day), now);
      case 'Yesterday':
        final y = now.subtract(const Duration(days: 1));
        return (DateTime(y.year, y.month, y.day), DateTime(y.year, y.month, y.day, 23, 59, 59));
      case 'Last 7 Days': return (now.subtract(const Duration(days: 7)), now);
      case 'Last 14 Days': return (now.subtract(const Duration(days: 14)), now);
      case 'Last 30 Days': return (now.subtract(const Duration(days: 30)), now);
      case 'Last 90 Days': return (now.subtract(const Duration(days: 90)), now);
      case 'Custom': return (now.subtract(Duration(days: _customDays)), now);
      case 'This Week':
        int off = now.weekday - 1; if (off < 0) off = 6;
        return (DateTime(now.year, now.month, now.day - off), now);
      case 'This Month': return (DateTime(now.year, now.month, 1), now);
      case 'Last Month':
        final firstThisMonth = DateTime(now.year, now.month, 1);
        final lastLastMonth = firstThisMonth.subtract(const Duration(days: 1));
        final firstLastMonth = DateTime(lastLastMonth.year, lastLastMonth.month, 1);
        return (firstLastMonth, DateTime(lastLastMonth.year, lastLastMonth.month, lastLastMonth.day, 23, 59, 59));
      default: return (DateTime(now.year, now.month, now.day), now);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isDesktop = MediaQuery.of(context).size.width >= 1100;
    final themeController = Provider.of<ThemeController>(context);
    final bool isHighContrast = themeController.isHighContrast;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight, maxWidth: constraints.maxWidth),
            child: isDesktop ? _buildDesktop(context, isDark, isHighContrast) : _buildMobile(context, isDark, isHighContrast),
          ),
        );
      },
    );
  }

  Widget _buildDesktop(BuildContext context, bool isDark, bool isHighContrast) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context, isDark, isHighContrast),
          const SizedBox(height: 24),
          // A. Performance Overview
          _buildSectionCard(context, isDark, isHighContrast, title: 'Performance Overview', child: _buildPerformanceOverview()),
          const SizedBox(height: 16),
          // B. Productivity Trends (reuse existing charts)
          _buildSectionCard(context, isDark, isHighContrast, title: 'Productivity Trends', child: _buildProductivityTrends()),
          const SizedBox(height: 16),
          // C. Break Analysis
          _buildSectionCard(context, isDark, isHighContrast, title: 'Break Analysis', child: _buildBreakAnalysis()),
          const SizedBox(height: 16),
          // D. Wellbeing Trends (derived from session records — evidence only)
          _buildSectionCard(context, isDark, isHighContrast, title: 'Wellbeing Trends', child: _buildWellbeingSection()),
          const SizedBox(height: 16),
          // E. Session History
          _buildSectionCard(context, isDark, isHighContrast, title: 'Recent Sessions', child: _buildSessionHistory()),
          const SizedBox(height: 16),
          // F. Insights
          _buildSectionCard(context, isDark, isHighContrast, title: 'Evidence-Based Insights', child: _buildInsights()),
          const SizedBox(height: 16),
          // G. Report Exports
          _buildReportExportsCard(isDark, true),
        ],
      ),
    );
  }

  Widget _buildMobile(BuildContext context, bool isDark, bool isHighContrast) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context, isDark, isHighContrast),
          const SizedBox(height: 16),
          _buildSectionCard(context, isDark, isHighContrast, title: 'Performance Overview', child: _buildPerformanceOverview()),
          const SizedBox(height: 12),
          _buildSectionCard(context, isDark, isHighContrast, title: 'Productivity Trends', child: _buildProductivityTrends()),
          const SizedBox(height: 12),
          _buildSectionCard(context, isDark, isHighContrast, title: 'Break Analysis', child: _buildBreakAnalysis()),
          const SizedBox(height: 12),
          _buildSectionCard(context, isDark, isHighContrast, title: 'Wellbeing Trends', child: _buildWellbeingSection()),
          const SizedBox(height: 12),
          _buildSectionCard(context, isDark, isHighContrast, title: 'Recent Sessions', child: _buildSessionHistory()),
          const SizedBox(height: 12),
          _buildSectionCard(context, isDark, isHighContrast, title: 'Insights', child: _buildInsights()),
          const SizedBox(height: 12),
          _buildReportExportsCard(isDark, false),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark, bool isHighContrast) {
    return DelayedAnimatedSection(
      delay: Duration.zero,
      slideDirection: SlideDirection.topToBottom,
      visible: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Employee Analytics', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: isDark ? Colors.white : Colors.black)),
          _buildPeriodDropdown(context, isDark, isHighContrast),
        ],
      ),
    );
  }

  /// Asks for a number of days (1-365). Returns null when cancelled.
  Future<int?> _pickCustomDays(BuildContext context) {
    final controller = TextEditingController(text: _customDays.toString());
    String? error;
    return showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Custom date range'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Show data for the last how many days?'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'Number of days (1-365)', errorText: error),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final d in [3, 5, 10, 21, 45, 60])
                    ActionChip(
                      label: Text('$d days'),
                      onPressed: () => setDialogState(() {
                        controller.text = '$d';
                        error = null;
                      }),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final n = int.tryParse(controller.text.trim());
                if (n == null || n < 1 || n > 365) {
                  setDialogState(() => error = 'Enter a whole number from 1 to 365');
                  return;
                }
                Navigator.pop(ctx, n);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodDropdown(BuildContext context, bool isDark, bool isHighContrast) {
    final periods = [
      'Today', 'Yesterday', 'Last 7 Days', 'Last 14 Days', 'Last 30 Days', 'Last 90 Days',
      'This Week', 'This Month', 'Last Month', 'Custom',
    ];
    String labelFor(String p) => p == 'Custom' ? 'Last $_customDays days (custom)' : p;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? (isHighContrast ? const Color(0xFF0D0D0D) : const Color(0xFF182029)) : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.2) : Colors.grey.shade300),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedPeriod,
          isDense: true,
          onChanged: (v) async {
            if (v == null) return;
            if (v == 'Custom') {
              final days = await _pickCustomDays(context);
              if (days == null) return; // cancelled: keep the previous period
              setState(() {
                _customDays = days;
                _selectedPeriod = 'Custom';
              });
            } else {
              setState(() => _selectedPeriod = v);
            }
            _fetchAll();
          },
          items: periods.map((p) => DropdownMenuItem(value: p, child: Text(labelFor(p), style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black)))).toList(),
          dropdownColor: isDark ? (isHighContrast ? const Color(0xFF0D0D0D) : const Color(0xFF182029)) : Colors.white,
          icon: Icon(Icons.arrow_drop_down, size: 18, color: isDark ? Colors.white : Colors.grey.shade700),
        ),
      ),
    );
  }

  Widget _buildSectionCard(BuildContext ctx, bool isDark, bool isHC, {required String title, required Widget child}) {
    final color = Theme.of(ctx).colorScheme.secondary;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? (isHC ? const Color(0xFF0D0D0D) : const Color(0xFF1A1A1A)) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.2)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)), child: Icon(Icons.analytics_outlined, size: 18, color: color)),
            const SizedBox(width: 10),
            Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black)),
          ]),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildPerformanceOverview() {
    final summary = _todaySummary;
    final targetHoursText = summary['targetHours'] ?? '0.0 / 0h';
    final focusRate = (summary['focusRate'] as num?)?.toDouble() ?? 0.0;
    final completedSessions = (summary['completedSessionsCount'] as num?)?.toInt() ?? 0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _kpiTile('Work Hours', targetHoursText, Icons.timer)),
        const SizedBox(width: 12),
        Expanded(child: _kpiTile('Avg Focus Rate', '${focusRate.toStringAsFixed(0)}%', Icons.trending_up)),
        const SizedBox(width: 12),
        Expanded(child: _kpiTile('Completed Sessions', '$completedSessions', Icons.check_circle_outline)),
      ],
    );
  }

  Widget _kpiTile(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(icon, size: 16, color: Colors.grey.shade600), const SizedBox(width: 6), Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey))]),
        const SizedBox(height: 6), Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      ]),
    );
  }

  Widget _buildProductivityTrends() {
    final range = _dateRangeForPeriod(_selectedPeriod);
    final startDate = range.$1;
    final endDate = range.$2;
    return Column(children: [
      if (_token != null) Center(child: FocusRateProgress(token: _token!, startDate: startDate, endDate: endDate)),
      const SizedBox(height: 12),
      if (_token != null) SizedBox(height: 220, child: FocusIdleLineChart(token: _token!, startDate: startDate, endDate: endDate)),
      const SizedBox(height: 12),
      if (_token != null) SizedBox(height: 220, child: DailyWorkHoursBarChart(token: _token!, startDate: startDate, endDate: endDate)),
    ]);
  }

  String _formatDuration(double seconds) {
    if (seconds < 60) return '${seconds.toStringAsFixed(0)}s';
    int mins = (seconds / 60).round();
    if (mins < 60) return '$mins min';
    int hrs = mins ~/ 60;
    int remMins = mins % 60;
    if (remMins == 0) return '$hrs hr';
    return '$hrs hr $remMins min';
  }

  Widget _buildBreakAnalysis() {
    final data = _breakAnalysis;
    final total = (data['totalBreaks'] as num?)?.toInt() ?? 0;
    final avgDur = (data['avgBreakDurationSeconds'] as num?)?.toDouble() ?? 0.0;
    final byType = (data['byType'] as Map?) ?? {};
    return Column(children: [
      Row(children: [
        Expanded(child: _kpiTile('Total Breaks', '$total', Icons.pause_circle_outline)),
        const SizedBox(width: 12),
        Expanded(child: _kpiTile('Avg Duration', _formatDuration(avgDur), Icons.access_time)),
      ]),
      const SizedBox(height: 12),
      Text('Break Types', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      const SizedBox(height: 6),
      if (byType.isEmpty)
        const Text('No break records for this period.', style: TextStyle(fontSize: 12, color: Colors.grey))
      else
        Wrap(children: (byType.entries.map((e) {
          final type = e.key.toString();
          final count = (e.value['count'] as num?)?.toInt() ?? 0;
          return Chip(label: Text('$type ($count)'), backgroundColor: Colors.blue.withValues(alpha: 0.1), labelStyle: const TextStyle(fontSize: 12));
        })).toList()),
    ]);
  }

  Widget _buildWellbeingSection() {
    final totalCheckins = (_wellbeingSummary['checkinCount'] as num?)?.toInt() ?? 0;
    final avgMood = (_wellbeingSummary['avgOverallWellbeing'] as num?)?.toDouble();
    final avgEnergy = (_wellbeingSummary['avgMentalFatigue'] as num?)?.toDouble();
    final avgStress = (_wellbeingSummary['avgWorkloadManageability'] as num?)?.toDouble();

    if (totalCheckins == 0) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text('No wellbeing check-ins recorded for this period.', style: TextStyle(fontSize: 12, color: Colors.grey)),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: _kpiTile('Check-ins', '$totalCheckins', Icons.favorite_outline)),
        const SizedBox(width: 12),
        Expanded(child: _kpiTile('Overall', avgMood != null ? avgMood.toStringAsFixed(1) : 'N/A', Icons.mood)),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _kpiTile('Fatigue', avgEnergy != null ? avgEnergy.toStringAsFixed(1) : 'N/A', Icons.bolt)),
        const SizedBox(width: 12),
        Expanded(child: _kpiTile('Manageability', avgStress != null ? avgStress.toStringAsFixed(1) : 'N/A', Icons.spa)),
      ]),
      const SizedBox(height: 8),
      const Text('Self-reported wellbeing is tracked via session check-ins. No medical or psychological diagnosis is provided.', style: TextStyle(fontSize: 11, color: Colors.grey)),
    ]);
  }

  Widget _buildSessionHistory() {
    List sessions = [];
    if (_sessionHistory is List) {
      sessions = _sessionHistory;
    } else if (_sessionHistory is Map && _sessionHistory['items'] is List) {
      sessions = _sessionHistory['items'];
    }
    if (sessions.isEmpty) {
      return const Center(child: Text('No completed sessions for this period.', style: TextStyle(fontSize: 12, color: Colors.grey)));
    }
    return Column(children: sessions.take(5).map((s) {
      final started = s['startedAt'] ?? '';
      final metrics = s['metrics'] ?? {};
      final focusRate = (metrics['focusRate'] as num?)?.toDouble() ?? 0.0;
      return ListTile(
        dense: true,
        leading: Icon(Icons.event_note, color: Colors.blue.shade700),
        title: Text('Session ${started.toString().split('T').first}', style: const TextStyle(fontSize: 13)),
        subtitle: Text('Started: $started  | Focus: ${focusRate.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 11)),
      );
    }).toList());
  }

  Widget _buildInsights() {
    List insights = [];
    if (_insights is List) {
      insights = _insights;
    } else if (_insights is Map && _insights['items'] is List) {
      insights = _insights['items'];
    }
    if (insights.isEmpty) {
      return const Text('Continue logging sessions to receive personalized observations.', style: TextStyle(fontSize: 12, color: Colors.grey));
    }
    return Column(children: insights.map((i) {
      final title = (i['title'] as String?) ?? 'Observation';
      final desc = (i['description'] as String?) ?? '';
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(desc, style: const TextStyle(fontSize: 12)),
        ])),
      );
    }).toList());
  }

  Future<void> _downloadReport(String endpoint, String filename) async {
    if (_token == null || _isExporting) return;
    setState(() => _isExporting = true);
    try {
      final range = _dateRangeForPeriod(_selectedPeriod);
      final start = range.$1.toIso8601String().split('T')[0];
      final end = range.$2.toIso8601String().split('T')[0];
      final url = Uri.parse('${ApiService.baseUrl}$endpoint?start_date=$start&end_date=$end&report_type=employee');

      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $_token'},
      );
      if (response.statusCode == 200) {
        if (kIsWeb) {
          // ignore: avoid_web_libraries_in_flutter, deprecated_member_use
          final blob = html.Blob([response.bodyBytes]);
          // ignore: avoid_web_libraries_in_flutter, deprecated_member_use
          final urlObj = html.Url.createObjectUrlFromBlob(blob);
          // ignore: avoid_web_libraries_in_flutter, deprecated_member_use
          html.AnchorElement(href: urlObj)
            ..setAttribute('download', filename)
            ..click();
          // ignore: avoid_web_libraries_in_flutter, deprecated_member_use
          html.Url.revokeObjectUrl(urlObj);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Downloaded $filename successfully')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to download report (${response.statusCode})')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error downloading report: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Widget _buildReportExportsCard(bool isDark, bool isDesktop) {
    return ReportExportsSection(
      description: 'Download your comprehensive personal analytics reports in multiple formats.',
      isDark: isDark,
      isDesktop: isDesktop,
      isExporting: _isExporting,
      onExportExcel: () => _downloadReport('/reports/export-excel', 'employee_analytics_report.xlsx'),
      onExportPdf: () => _downloadReport('/reports/export-pdf', 'employee_analytics_report.pdf'),
      onExportCsv: () => _downloadReport('/reports/export-csv', 'employee_analytics_reports.zip'),
    );
  }
}
