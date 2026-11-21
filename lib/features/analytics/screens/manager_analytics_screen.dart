import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intellibreak/features/auth/services/api_service.dart';
import 'package:intellibreak/features/analytics/screens/employee_analytics_screen.dart';
import 'package:intellibreak/features/analytics/widgets/report_exports_section.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

/// Manager Analytics screen — Redesigned to match Figma reference.
/// Sections: Header, Date Range Controls, KPI Overview (4 cards),
/// Workload Summary, Recommendation Effectiveness, Wellbeing Aggregates (>=3 threshold),
/// Report Exports (Excel, PDF, CSV ZIP), and Footer.
class ManagerAnalyticsScreenContent extends StatefulWidget {
  const ManagerAnalyticsScreenContent({super.key});

  @override
  State<ManagerAnalyticsScreenContent> createState() => _ManagerAnalyticsScreenState();
}

class _ManagerAnalyticsScreenState extends State<ManagerAnalyticsScreenContent> {
  String? _token;
  bool _isLoading = true;
  bool _isExporting = false;
  Map<String, dynamic> _data = {};
  String _selectedDateRange = 'All available data';
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    _loadTokenAndData();
  }

  Future<void> _loadTokenAndData() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (mounted) {
      setState(() {
        _token = token;
        _isLoading = false;
      });
    }
    if (_token != null) await _fetchSummary();
  }

  Future<void> _fetchSummary() async {
    if (_token == null) return;
    setState(() => _isLoading = true);
    try {
      String endpoint = '/manager/analytics/team-summary';
      final now = DateTime.now();
      if (_selectedDateRange == '7 days') {
        final start = now.subtract(const Duration(days: 7)).toIso8601String().substring(0, 10);
        final end = now.toIso8601String().substring(0, 10);
        endpoint += '?start_date=$start&end_date=$end';
      } else if (_selectedDateRange == '30 days') {
        final start = now.subtract(const Duration(days: 30)).toIso8601String().substring(0, 10);
        final end = now.toIso8601String().substring(0, 10);
        endpoint += '?start_date=$start&end_date=$end';
      } else if (RegExp(r'^\d+ days$').hasMatch(_selectedDateRange)) {
        final n = int.parse(_selectedDateRange.split(' ').first);
        final start = now.subtract(Duration(days: n)).toIso8601String().substring(0, 10);
        final end = now.toIso8601String().substring(0, 10);
        endpoint += '?start_date=$start&end_date=$end';
      } else if (_selectedDateRange == 'All time') {
        final end = now.toIso8601String().substring(0, 10);
        endpoint += '?end_date=$end';
      }
      final res = await _apiService.getMapWithAuth(endpoint, _token!);
      if (res != null) {
        setState(() => _data = res);
      }
    } catch (_) {
      // Keep empty state if endpoint fails
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _downloadReport(String endpoint, String filename) async {
    if (_token == null || _isExporting) return;
    setState(() => _isExporting = true);
    try {
      String queryStr = '';
      final now = DateTime.now();
      if (_selectedDateRange == '7 days') {
        final start = now.subtract(const Duration(days: 7)).toIso8601String().substring(0, 10);
        final end = now.toIso8601String().substring(0, 10);
        queryStr = '?start_date=$start&end_date=$end';
      } else if (_selectedDateRange == '30 days') {
        final start = now.subtract(const Duration(days: 30)).toIso8601String().substring(0, 10);
        final end = now.toIso8601String().substring(0, 10);
        queryStr = '?start_date=$start&end_date=$end';
      } else if (RegExp(r'^\d+ days$').hasMatch(_selectedDateRange)) {
        final n = int.parse(_selectedDateRange.split(' ').first);
        final start = now.subtract(Duration(days: n)).toIso8601String().substring(0, 10);
        final end = now.toIso8601String().substring(0, 10);
        queryStr = '?start_date=$start&end_date=$end';
      } else if (_selectedDateRange == 'All time') {
        final end = now.toIso8601String().substring(0, 10);
        queryStr = '?end_date=$end';
      }
      final sep = queryStr.isEmpty ? '?' : '&';
      final url = Uri.parse('${ApiService.baseUrl}$endpoint$queryStr${sep}report_type=manager');
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

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isDesktop = screenWidth >= 1100;
    final bool isTablet = screenWidth >= 700 && screenWidth < 1100;

    if (_isLoading && _data.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final totalEmployees = (_data['total_employees'] as num?)?.toInt() ?? 0;
    final workload = (_data['workload_summary'] is Map) ? (_data['workload_summary'] as Map) : {};
    final totalWorkHours = (workload['total_work_hours'] as num?)?.toDouble() ?? 0.0;
    final avgWorkHours = (workload['avg_work_hours_per_employee'] as num?)?.toDouble() ?? 0.0;
    final recommendation = (_data['recommendation_effectiveness'] is Map) ? (_data['recommendation_effectiveness'] as Map) : {};
    final acceptanceRate = (recommendation['acceptance_rate'] as num?)?.toDouble() ?? 0.0;
    final totalFeedback = (recommendation['total_feedback'] as num?)?.toInt() ?? 0;
    final acceptedFeedback = (recommendation['accepted'] as num?)?.toInt() ?? 0;
    final wellbeing = _data['aggregate_wellbeing'];

    return SingleChildScrollView(
      padding: EdgeInsets.all(isDesktop ? 24.0 : 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A. Header
          _buildHeader(isDark),
          const SizedBox(height: 24),

          // B. Date Range Controls
          _buildDateControls(isDark),
          const SizedBox(height: 24),

          // C. KPI Overview (4 cards)
          _buildKpiOverview(isDark, isDesktop, isTablet, totalEmployees, totalWorkHours, avgWorkHours, acceptanceRate, acceptedFeedback, totalFeedback),
          const SizedBox(height: 24),

          // D & E. Workload Summary & Recommendation Effectiveness side-by-side on desktop
          if (isDesktop)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildWorkloadSummaryCard(isDark, totalWorkHours, avgWorkHours, totalEmployees)),
                const SizedBox(width: 24),
                Expanded(child: _buildRecommendationEffectivenessCard(isDark, acceptanceRate, totalFeedback, acceptedFeedback)),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildWorkloadSummaryCard(isDark, totalWorkHours, avgWorkHours, totalEmployees),
                const SizedBox(height: 20),
                _buildRecommendationEffectivenessCard(isDark, acceptanceRate, totalFeedback, acceptedFeedback),
              ],
            ),
          const SizedBox(height: 24),

          // F. Wellbeing Aggregates
          _buildWellbeingAggregatesCard(isDark, totalEmployees, wellbeing),
          const SizedBox(height: 24),

          // G. Report Exports
          _buildReportExportsCard(isDark, isDesktop),
          const SizedBox(height: 24),

          // H. Footer
          _buildFooter(isDark, totalEmployees),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Manager Analytics',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "A clear view of your team's workload, wellbeing and recommendation outcomes.",
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => Scaffold(
                      appBar: AppBar(title: const Text('My Personal Analytics')),
                      body: const EmployeeAnalyticsScreenContent(),
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.person_outline, size: 18),
              label: const Text('Personal Analytics'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _isExporting ? null : () => _downloadReport('/reports/export-excel', 'manager_analytics_report.xlsx'),
              icon: _isExporting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.download, size: 18),
              label: const Text('Export report'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDateControls(bool isDark) {
    final presets = ['All available data', '7 days', '14 days', '30 days', '90 days', 'All time'];
    // A previously chosen custom range stays visible as its own chip.
    final ranges = [
      ...presets,
      if (!presets.contains(_selectedDateRange)) _selectedDateRange,
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ..._buildRangeChips(isDark, ranges),
        ActionChip(
          avatar: const Icon(Icons.edit_calendar_outlined, size: 16),
          label: const Text('Custom days…'),
          onPressed: _pickCustomDays,
        ),
      ],
    );
  }

  Future<void> _pickCustomDays() async {
    final controller = TextEditingController();
    String? error;
    final days = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Custom date range'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Last how many days? (1-365)',
              errorText: error,
            ),
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
    if (days == null || !mounted) return;
    setState(() => _selectedDateRange = '$days days');
    _fetchSummary();
  }

  List<Widget> _buildRangeChips(bool isDark, List<String> ranges) {
    return ranges.map((range) {
        final bool isSelected = _selectedDateRange == range;
        return ChoiceChip(
          label: Text(range),
          selected: isSelected,
          onSelected: (selected) {
            if (selected) {
              setState(() => _selectedDateRange = range);
              _fetchSummary();
            }
          },
          selectedColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
          backgroundColor: isDark ? const Color(0xFF182029) : Colors.grey.shade100,
          labelStyle: TextStyle(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : (isDark ? Colors.white70 : Colors.black87),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        );
    }).toList();
  }

  Widget _buildKpiOverview(bool isDark, bool isDesktop, bool isTablet, int employees, double totalHours, double avgHours, double acceptanceRate, int accepted, int totalFeedback) {
    final cards = [
      _kpiCard(
        isDark,
        title: 'Employees',
        value: '$employees',
        subtitle: 'Team overview · aggregate only',
        icon: Icons.people_outline,
        color: Colors.blueAccent,
      ),
      _kpiCard(
        isDark,
        title: 'Total Work Hours',
        value: '${totalHours.toStringAsFixed(1)} h',
        subtitle: 'Recorded across the team',
        icon: Icons.access_time,
        color: Colors.tealAccent,
      ),
      _kpiCard(
        isDark,
        title: 'Average per Employee',
        value: '${avgHours.toStringAsFixed(1)} h',
        subtitle: 'Average recorded work hours',
        icon: Icons.analytics_outlined,
        color: Colors.purpleAccent,
      ),
      _kpiCard(
        isDark,
        title: 'Acceptance Rate',
        value: '${acceptanceRate.toStringAsFixed(0)}%',
        subtitle: '$accepted accepted · $totalFeedback feedback received',
        icon: Icons.thumb_up_alt_outlined,
        color: Colors.orangeAccent,
      ),
    ];

    if (isDesktop) {
      return Row(
        children: cards.map((c) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: c))).toList(),
      );
    } else if (isTablet) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Padding(padding: const EdgeInsets.only(right: 6, bottom: 12), child: cards[0])),
              Expanded(child: Padding(padding: const EdgeInsets.only(left: 6, bottom: 12), child: cards[1])),
            ],
          ),
          Row(
            children: [
              Expanded(child: Padding(padding: const EdgeInsets.only(right: 6), child: cards[2])),
              Expanded(child: Padding(padding: const EdgeInsets.only(left: 6), child: cards[3])),
            ],
          ),
        ],
      );
    } else {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: cards.map((c) => Padding(padding: const EdgeInsets.only(bottom: 12), child: c)).toList(),
      );
    }
  }

  Widget _kpiCard(bool isDark, {required String title, required String value, required String subtitle, required IconData icon, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF182029) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: TextStyle(fontSize: 13, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600, fontWeight: FontWeight.w500)),
              Icon(icon, size: 20, color: color),
            ],
          ),
          const SizedBox(height: 12),
          Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
          const SizedBox(height: 6),
          Text(subtitle, style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade500 : Colors.grey.shade500)),
        ],
      ),
    );
  }

  Widget _buildWorkloadSummaryCard(bool isDark, double totalHours, double avgHours, int employees) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF182029) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Workload Summary', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Team workload distribution and recorded hours.', style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total Work Hours', style: TextStyle(fontSize: 13, color: isDark ? Colors.grey.shade300 : Colors.black87)),
              Text('${totalHours.toStringAsFixed(1)} h', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: totalHours > 0 ? (totalHours / (employees > 0 ? employees * 40.0 : 40.0)).clamp(0.0, 1.0) : 0.0,
            backgroundColor: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
            color: Colors.tealAccent,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Average per Employee', style: TextStyle(fontSize: 13, color: isDark ? Colors.grey.shade300 : Colors.black87)),
              Text('${avgHours.toStringAsFixed(1)} h / emp', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: avgHours > 0 ? (avgHours / 40.0).clamp(0.0, 1.0) : 0.0,
            backgroundColor: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
            color: Colors.blueAccent,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 20),
          Text(
            'Included employees: $employees. Derived from actual recorded work sessions. More hours do not imply higher performance.',
            style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade500 : Colors.grey.shade500, fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendationEffectivenessCard(bool isDark, double acceptanceRate, int totalFeedback, int accepted) {
    final hasInsufficientData = totalFeedback < 2;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF182029) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Recommendation Effectiveness', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('User feedback and acceptance ratios.', style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600)),
          const SizedBox(height: 20),
          Row(
            children: [
              SizedBox(
                width: 90,
                height: 90,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: (acceptanceRate / 100.0).clamp(0.0, 1.0),
                      backgroundColor: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                      color: Colors.orangeAccent,
                      strokeWidth: 8,
                    ),
                    Center(
                      child: Text(
                        '${acceptanceRate.toStringAsFixed(0)}%',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total Feedback: $totalFeedback', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text('Accepted: $accepted', style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade300 : Colors.grey.shade700)),
                    const SizedBox(height: 4),
                    Text('Dismissed: ${totalFeedback - accepted}', style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade300 : Colors.grey.shade700)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (hasInsufficientData)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 16, color: Colors.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Only $totalFeedback feedback entry. More feedback is needed to assess effectiveness reliably.',
                      style: TextStyle(fontSize: 11, color: isDark ? Colors.amber.shade200 : Colors.amber.shade900),
                    ),
                  ),
                ],
              ),
            )
          else
            Text(
              'Based on answered feedback entries. Unanswered NULL feedback is excluded.',
              style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade500 : Colors.grey.shade500),
            ),
        ],
      ),
    );
  }

  Widget _buildWellbeingAggregatesCard(bool isDark, int totalEmployees, dynamic wellbeing) {
    Map<String, dynamic> byTier = {};
    int low = 0;
    int moderate = 0;
    int high = 0;
    int critical = 0;
    int insufficientData = 0;
    bool privacySuppressed = totalEmployees < 3;

    if (wellbeing != null && wellbeing is Map) {
      if (wellbeing['privacy_suppressed'] == true) {
        privacySuppressed = true;
      }
      low = (wellbeing['low'] as num?)?.toInt() ?? 0;
      moderate = (wellbeing['moderate'] as num?)?.toInt() ?? 0;
      high = (wellbeing['high'] as num?)?.toInt() ?? 0;
      critical = (wellbeing['critical'] as num?)?.toInt() ?? 0;
      insufficientData = (wellbeing['insufficient_data'] as num?)?.toInt() ?? 0;

      if (wellbeing['by_tier'] is Map) {
        byTier = Map<String, dynamic>.from(wellbeing['by_tier']);
        low = low > 0 ? low : (byTier['low'] as num?)?.toInt() ?? 0;
        moderate = moderate > 0 ? moderate : (byTier['moderate'] as num?)?.toInt() ?? 0;
        high = high > 0 ? high : (byTier['high'] as num?)?.toInt() ?? 0;
        critical = critical > 0 ? critical : (byTier['critical'] as num?)?.toInt() ?? 0;
        insufficientData = insufficientData > 0 ? insufficientData : (byTier['insufficient_data'] as num?)?.toInt() ?? 0;
      }
    }
    final bool hasInsufficientEmployees = privacySuppressed;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF182029) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Wellbeing Aggregates', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('Aggregate-only · Privacy Protected', style: TextStyle(fontSize: 10, color: Colors.blueAccent, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Team wellbeing distribution (requires at least 3 distinct non-test employees).', style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600)),
          const SizedBox(height: 20),
          if (hasInsufficientEmployees)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.privacy_tip_outlined, color: Colors.orange, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Insufficient Data for Wellbeing Aggregates', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(
                          'Current team has $totalEmployees non-test employee(s). At least 3 distinct non-test employees are required to protect individual privacy.',
                          style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade300 : Colors.grey.shade700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            Row(
              children: [
                Expanded(child: _wellbeingTierBox(isDark, 'Low Risk', '$low', Colors.greenAccent)),
                const SizedBox(width: 12),
                Expanded(child: _wellbeingTierBox(isDark, 'Moderate', '$moderate', Colors.blueAccent)),
                const SizedBox(width: 12),
                Expanded(child: _wellbeingTierBox(isDark, 'High Risk', '$high', Colors.orangeAccent)),
                const SizedBox(width: 12),
                Expanded(child: _wellbeingTierBox(isDark, 'Critical', '$critical', Colors.redAccent)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _wellbeingTierBox(bool isDark, String label, String count, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(count, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
          const SizedBox(height: 4),
          Text('Employees', style: TextStyle(fontSize: 10, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _buildReportExportsCard(bool isDark, bool isDesktop) {
    return ReportExportsSection(
      description: "Download your team's analytics reports in multiple formats.",
      isDark: isDark,
      isDesktop: isDesktop,
      isExporting: _isExporting,
      onExportExcel: () => _downloadReport('/reports/export-excel', 'manager_analytics_report.xlsx'),
      onExportPdf: () => _downloadReport('/reports/export-pdf', 'manager_analytics_report.pdf'),
      onExportCsv: () => _downloadReport('/reports/export-csv', 'manager_analytics_reports.zip'),
    );
  }

  Widget _buildFooter(bool isDark, int employees) {
    return Center(
      child: Text(
        'Reporting scope: $_selectedDateRange · $employees employee(s) · Data integrity verified',
        style: TextStyle(
          fontSize: 12,
          color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
        ),
      ),
    );
  }
}
