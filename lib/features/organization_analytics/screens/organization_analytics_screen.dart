import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intellibreak/core/design_system.dart';
import 'package:intellibreak/core/config/api_config.dart';
import 'package:intellibreak/features/organization_analytics/services/admin_analytics_service.dart';
import 'package:intellibreak/features/analytics/widgets/report_exports_section.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

class OrganizationAnalyticsScreen extends StatefulWidget {
  const OrganizationAnalyticsScreen({super.key});

  @override
  State<OrganizationAnalyticsScreen> createState() => _OrganizationAnalyticsScreenState();
}

class _OrganizationAnalyticsScreenState extends State<OrganizationAnalyticsScreen> {
  String? _token;
  bool _isLoading = true;
  bool _isExporting = false;
  String? _error;

  Map<String, dynamic>? _reportsPreview;
  String _selectedPeriod = 'This Week'; // UI label: Today, This Week, Last Week, This Month

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (!mounted) return;
    setState(() { _token = token; });
    if (_token != null) _loadData();
  }

  String _mapPeriodToApi(String periodLabel) {
    switch (periodLabel) {
      case 'Today': return 'today';
      case 'This Week': return 'this_week';
      case 'Last Week': return 'last_week';
      case 'This Month': return 'this_month';
      default: return 'this_week';
    }
  }

  Future<void> _loadData() async {
    if (_token == null || !mounted) return;
    setState(() { _isLoading = true; _error = null; });

    try {
      final adminAnalyticsService = AdminAnalyticsService();
      final apiPeriod = _mapPeriodToApi(_selectedPeriod);
      final preview = await adminAnalyticsService.getReportsPreview(_token!, period: apiPeriod);

      if (!mounted) return;
      setState(() {
        _reportsPreview = preview;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _downloadReport(String endpoint, String filename) async {
    if (_token == null || _isExporting) return;
    setState(() => _isExporting = true);
    try {
      final apiPeriod = _mapPeriodToApi(_selectedPeriod);
      final url = Uri.parse('${ApiConfig.baseUrl}$endpoint?period=$apiPeriod');
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $_token'},
      );

      if (response.statusCode == 200) {
        if (kIsWeb) {
          final blob = html.Blob([response.bodyBytes]);
          final urlBlob = html.Url.createObjectUrlFromBlob(blob);
          html.AnchorElement(href: urlBlob)
            ..setAttribute('download', filename)
            ..click();
          html.Url.revokeObjectUrl(urlBlob);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Successfully downloaded $filename'), backgroundColor: Colors.green),
          );
        }
      } else {
        throw Exception('Export failed: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error downloading report: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_token == null) {
      return const Center(child: Text('Please sign in to view organization analytics'));
    }

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121218) : const Color(0xFFF8F8FB),
      body: SafeArea(
        child: _isLoading && _reportsPreview == null
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header & Controls
                      _buildHeaderAndControls(isDark),
                      const SizedBox(height: 24),

                      if (_error != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                          child: Text('Error: $_error', style: const TextStyle(color: Colors.red)),
                        ),

                      // 1. Organization Overview Section
                      _buildSectionHeader('1. Organization Overview', 'High-level workforce metrics and period summary'),
                      const SizedBox(height: 12),
                      _buildOverviewSection(isDark),
                      const SizedBox(height: 24),

                      // 2. Work Patterns & Sustainability Section
                      _buildSectionHeader('2. Work Patterns & Sustainability', 'Sustainability index, overtime frequency, and break compliance'),
                      const SizedBox(height: 12),
                      _buildWorkSustainabilitySection(isDark),
                      const SizedBox(height: 24),

                      // 3. Work-Life Balance Section
                      _buildSectionHeader('3. Work-Life Balance', 'Employee-reported WLB weekly survey scores and participation'),
                      const SizedBox(height: 12),
                      _buildWorkLifeBalanceSection(isDark),
                      const SizedBox(height: 24),

                      // 4. Team Comparison Section
                      _buildSectionHeader('4. Team Comparison', 'Cross-team productivity, sustainability, and wellbeing with N >= 3 privacy suppression'),
                      const SizedBox(height: 12),
                      _buildTeamComparisonSection(isDark),
                      const SizedBox(height: 24),

                      // 5. Organizational Wellbeing Section
                      _buildSectionHeader('5. Organizational Wellbeing', 'Wellbeing check-ins, mental fatigue, workload, and work-pattern risk tiers'),
                      const SizedBox(height: 12),
                      _buildWellbeingSection(isDark),
                      const SizedBox(height: 24),

                      // 6. Recommendation Effectiveness Section
                      _buildSectionHeader('6. Recommendation Effectiveness', 'AI recommendation generation, action rates, and category breakdown'),
                      const SizedBox(height: 12),
                      _buildRecommendationEffectivenessSection(isDark),
                      const SizedBox(height: 24),

                      // 7. Organizational Insights Section
                      _buildSectionHeader('7. Organizational Insights', 'Deterministic insights across focus, recovery, sustainability, and workload'),
                      const SizedBox(height: 12),
                      _buildOrganizationalInsightsSection(isDark),
                      const SizedBox(height: 24),

                      // 8. Reports & Exports Section
                      _buildSectionHeader('8. Reports & Exports', 'Download comprehensive PDF reports, Excel workbooks, or CSV archives'),
                      const SizedBox(height: 12),
                      ReportExportsSection(
                        title: 'Executive Report Exports',
                        description: 'Download verified reports for period: $_selectedPeriod',
                        isDark: isDark,
                        isDesktop: isDesktop,
                        isExporting: _isExporting,
                        onExportExcel: () => _downloadReport('/analytics/admin/reports/export/xlsx', 'intellibreak_admin_report.xlsx'),
                        onExportPdf: () => _downloadReport('/analytics/admin/reports/export/pdf', 'intellibreak_admin_report.pdf'),
                        onExportCsv: () => _downloadReport('/analytics/admin/reports/export/csv', 'intellibreak_admin_report_csv.zip'),
                      ),
                      const SizedBox(height: 24),

                      // 9. ML Dataset Export (Thesis Research)
                      _buildSectionHeader('9. ML Dataset Export (Thesis Research)', 'Export actual production/development records into a multi-sheet research workbook (.xlsx)'),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1B1D24) : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Combined Dataset (.xlsx)', style: DesignSystem.title(context)),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Includes Combined_Dataset, Feature_Dictionary, and Dataset_Summary worksheets with actual database records.',
                                    style: DesignSystem.body(context).copyWith(
                                      color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            ElevatedButton.icon(
                              onPressed: _isExporting ? null : () => _downloadReport('/admin/dataset/export', 'intellibreak_ml_dataset.xlsx'),
                              icon: const Icon(Icons.download, size: 18),
                              label: const Text('Export Dataset (.xlsx)'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.teal,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildHeaderAndControls(bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Organization Analytics', style: DesignSystem.titleXXL(context)),
              const SizedBox(height: 4),
              Text(
                'Comprehensive organization-wide wellness, productivity, and behavior analytics dashboard',
                style: DesignSystem.bodyLarge(context).copyWith(
                  color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1B1D24) : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
              ),
              child: DropdownButton<String>(
                value: _selectedPeriod,
                underline: const SizedBox.shrink(),
                onChanged: (val) {
                  if (val != null && mounted) {
                    setState(() { _selectedPeriod = val; });
                    _loadData();
                  }
                },
                items: ['Today', 'This Week', 'Last Week', 'This Month']
                    .map((p) => DropdownMenuItem(value: p, child: Text(p, style: const TextStyle(fontSize: 14))))
                    .toList(),
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadData,
              tooltip: 'Refresh Analytics',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      ],
    );
  }

  Widget _buildOverviewSection(bool isDark) {
    final exec = _reportsPreview?['executive_summary'] ?? {};
    final quality = _reportsPreview?['data_quality_indicator'] ?? 'adequate';

    return Column(
      children: [
        if (quality == 'insufficient_data')
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange),
                SizedBox(width: 8),
                Expanded(child: Text('Notice: Insufficient data for this reporting period. Displaying baseline or zero values.', style: TextStyle(color: Colors.orange, fontSize: 13))),
              ],
            ),
          ),
        Row(
          children: [
            Expanded(child: _kpiCard('Active Employees', '${exec['total_active_employees'] ?? '--'}', 'members', isDark)),
            const SizedBox(width: 12),
            Expanded(child: _kpiCard('Total Work Hours', '${(exec['total_work_hours'] ?? 0.0).toStringAsFixed(1)}', 'hrs', isDark)),
            const SizedBox(width: 12),
            Expanded(child: _kpiCard('Avg Hours / Emp', '${(exec['avg_work_hours_per_employee'] ?? 0.0).toStringAsFixed(1)}', 'hrs', isDark)),
            const SizedBox(width: 12),
            Expanded(child: _kpiCard('Focus Rate', '${(exec['focus_rate'] ?? 0.0).toStringAsFixed(1)}', '%', isDark)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _kpiCard('Sustainability Index', '${(exec['work_sustainability_index'] ?? 0.0).toStringAsFixed(1)}', '/ 100', isDark)),
            const SizedBox(width: 12),
            Expanded(child: _kpiCard('Avg WLB Score', '${(exec['avg_wlb_score'] ?? 0.0).toStringAsFixed(1)}', '/ 100', isDark)),
            const SizedBox(width: 12),
            Expanded(child: _kpiCard('Overall Wellbeing', '${(exec['overall_wellbeing'] ?? 0.0).toStringAsFixed(1)}', '/ 5.0', isDark)),
            const SizedBox(width: 12),
            Expanded(child: _kpiCard('Recommendation Acceptance', '${(exec['recommendation_acceptance_rate'] ?? 0.0).toStringAsFixed(1)}', '%', isDark)),
          ],
        ),
      ],
    );
  }

  Widget _kpiCard(String title, String value, String unit, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B1D24) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(width: 4),
              Text(unit, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWorkSustainabilitySection(bool isDark) {
    final wsi = _reportsPreview?['work_sustainability'] ?? {};
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B1D24) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Work Sustainability Index (WSI)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Chip(
                label: Text('${(wsi['sustainability_index'] ?? 100.0).toStringAsFixed(1)} / 100', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                backgroundColor: Colors.blue,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _metricTile('Overtime Frequency', '${(wsi['overtime_frequency'] ?? 0.0).toStringAsFixed(1)}%', isDark)),
              Expanded(child: _metricTile('Break Compliance', '${(wsi['break_compliance'] ?? 100.0).toStringAsFixed(1)}%', isDark)),
              Expanded(child: _metricTile('Long Sessions', '${wsi['long_sessions_count'] ?? 0}', isDark)),
              Expanded(child: _metricTile('Late Shift Endings', '${wsi['late_shift_endings_count'] ?? 0}', isDark)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricTile(String label, String val, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        const SizedBox(height: 4),
        Text(val, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildWorkLifeBalanceSection(bool isDark) {
    final wlb = _reportsPreview?['work_life_balance'] ?? {};
    final ratings = wlb['rating_averages'] ?? {};
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B1D24) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Work-Life Balance Weekly Surveys', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text('Participation: ${wlb['survey_participation_rate'] ?? 0.0}% (${wlb['survey_respondents'] ?? 0} respondents)', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ],
          ),
          const SizedBox(height: 8),
          Text('Note: Work-Life Balance is employee-reported via weekly survey check-ins (1-5 scale). Individual responses are strictly confidential.', style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _metricTile('Avg WLB Score', '${(wlb['avg_wlb_score'] ?? 0.0).toStringAsFixed(1)} / 100', isDark)),
              Expanded(child: _metricTile('Disconnect', '${(ratings['disconnect'] ?? 0.0).toStringAsFixed(1)} / 5', isDark)),
              Expanded(child: _metricTile('Personal Time', '${(ratings['personal_time'] ?? 0.0).toStringAsFixed(1)} / 5', isDark)),
              Expanded(child: _metricTile('Recovery', '${(ratings['recovery'] ?? 0.0).toStringAsFixed(1)} / 5', isDark)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTeamComparisonSection(bool isDark) {
    final teams = (_reportsPreview?['team_comparison'] as List?) ?? [];
    if (teams.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: isDark ? const Color(0xFF1B1D24) : Colors.white, borderRadius: BorderRadius.circular(16)),
        child: const Text('No active teams found in organization.'),
      );
    }

    return Column(
      children: teams.map((t) {
        final isSuppressed = t['privacy_suppressed'] == true;
        final prod = t['productivity'] ?? {};
        final wsi = t['work_sustainability'] ?? {};
        final wlb = t['work_life_balance'] ?? {};
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1B1D24) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.15)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(t['team_name'] ?? 'Team', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  if (isSuppressed)
                    const Chip(label: Text('Privacy Suppressed (N < 3)', style: TextStyle(fontSize: 10, color: Colors.orange)), backgroundColor: Colors.orangeAccent)
                  else
                    Text('${t['active_employees']} employees', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                ],
              ),
              const SizedBox(height: 12),
              if (isSuppressed)
                const Text('Metrics suppressed to protect employee confidentiality (fewer than 3 active members).', style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic))
              else
                Row(
                  children: [
                    Expanded(child: _metricTile('Total Work Hours', '${prod['total_work_hours'] ?? 0.0}h', isDark)),
                    Expanded(child: _metricTile('WSI', '${wsi['sustainability_index'] ?? 100.0}', isDark)),
                    Expanded(child: _metricTile('WLB Score', '${wlb['avg_wlb_score'] ?? 0.0}', isDark)),
                    Expanded(child: _metricTile('Completed Tasks', '${prod['completed_tasks'] ?? 0}', isDark)),
                  ],
                ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildWellbeingSection(bool isDark) {
    final wb = _reportsPreview?['organizational_wellbeing'] ?? {};
    final tiers = wb['risk_tier_distribution'] ?? {};
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B1D24) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Session Wellbeing Check-ins', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text('${wb['checkin_count'] ?? 0} check-ins recorded', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ],
          ),
          const SizedBox(height: 4),
          Text('Note: Session wellbeing check-ins are distinct from weekly WLB surveys and track real-time session recovery and fatigue.', style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _metricTile('Overall Wellbeing', '${(wb['overall_wellbeing'] ?? 0.0).toStringAsFixed(1)} / 5', isDark)),
              Expanded(child: _metricTile('Mental Fatigue', '${(wb['mental_fatigue'] ?? 0.0).toStringAsFixed(1)} / 5', isDark)),
              Expanded(child: _metricTile('Workload Manageability', '${(wb['workload_manageability'] ?? 0.0).toStringAsFixed(1)} / 5', isDark)),
              Expanded(child: _metricTile('Break Recovery', '${(wb['break_recovery'] ?? 0.0).toStringAsFixed(1)} / 5', isDark)),
            ],
          ),
          const Divider(height: 32),
          const Text('Employee Risk Tier Distribution', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _tierTile('Low Risk', '${tiers['low'] ?? 0}', Colors.green, isDark)),
              Expanded(child: _tierTile('Moderate', '${tiers['moderate'] ?? 0}', Colors.blue, isDark)),
              Expanded(child: _tierTile('High Risk', '${tiers['high'] ?? 0}', Colors.orange, isDark)),
              Expanded(child: _tierTile('Critical', '${tiers['critical'] ?? 0}', Colors.red, isDark)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tierTile(String label, String val, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(val, style: TextStyle(fontSize: 18, color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildRecommendationEffectivenessSection(bool isDark) {
    final rec = _reportsPreview?['recommendation_effectiveness'] ?? {};
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B1D24) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Recommendation Effectiveness', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Chip(
                label: Text('${(rec['acceptance_rate'] ?? 0.0).toStringAsFixed(1)}% Accepted', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                backgroundColor: Colors.teal,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _metricTile('Generated', '${rec['generated_count'] ?? 0}', isDark)),
              Expanded(child: _metricTile('Accepted', '${rec['accepted_count'] ?? 0}', isDark)),
              Expanded(child: _metricTile('Dismissed', '${rec['dismissed_count'] ?? 0}', isDark)),
              Expanded(child: _metricTile('Pending / Ignored', '${rec['pending_count'] ?? 0}', isDark)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOrganizationalInsightsSection(bool isDark) {
    final orgInsightsMap = _reportsPreview?['organizational_insights'];
    final insightsList = orgInsightsMap is Map
        ? ((orgInsightsMap['insights'] as List?) ?? [])
        : ((orgInsightsMap as List?) ?? []);
    final insights = insightsList;
    if (insights.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: isDark ? const Color(0xFF1B1D24) : Colors.white, borderRadius: BorderRadius.circular(16)),
        child: const Text('No organizational insights generated for this period.'),
      );
    }

    return Column(
      children: insights.map((ins) {
        final severity = ins['severity'] ?? 'medium';
        final color = severity == 'high' ? Colors.red : (severity == 'medium' ? Colors.orange : Colors.blue);
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1B1D24) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(ins['title'] ?? 'Insight', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  Chip(
                    label: Text(severity.toUpperCase(), style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
                    backgroundColor: color.withValues(alpha: 0.1),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(ins['description'] ?? '', style: TextStyle(fontSize: 13, color: isDark ? Colors.grey.shade300 : Colors.grey.shade700)),
              if (ins['recommended_action'] != null) ...[
                const SizedBox(height: 8),
                Text('Recommendation: ${ins['recommended_action']}', style: TextStyle(fontSize: 12, color: Colors.blue.shade400, fontWeight: FontWeight.w500)),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }
}
