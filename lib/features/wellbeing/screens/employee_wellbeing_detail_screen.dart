import 'package:flutter/material.dart';
import 'package:intellibreak/core/design_system.dart';
import 'package:intellibreak/features/wellbeing/services/wellbeing_service.dart';
import 'package:intellibreak/features/wellbeing/models/wellbeing_models.dart';

/// Employee Wellbeing Detail Screen - Phase 4
/// Provides detailed drill-down for a single employee's wellbeing data
class EmployeeWellbeingDetailScreen extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  final String? teamName;
  final DateTime? initialWeekStart;

  const EmployeeWellbeingDetailScreen({
    super.key,
    required this.employeeId,
    required this.employeeName,
    this.teamName,
    this.initialWeekStart,
  });

  @override
  State<EmployeeWellbeingDetailScreen> createState() => _EmployeeWellbeingDetailScreenState();
}

class _EmployeeWellbeingDetailScreenState extends State<EmployeeWellbeingDetailScreen> {
  final WellbeingService _wellbeingService = WellbeingService();

  bool _isLoading = true;
  String? _error;
  EmployeeDetailResponse? _detail;
  DateTime? _selectedWeekStart;
  bool _isLoadingWeekChange = false;

  @override
  void initState() {
    super.initState();
    _selectedWeekStart = widget.initialWeekStart;
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final detail = await _wellbeingService.getEmployeeDetail(
        widget.employeeId,
        weekStart: _selectedWeekStart,
      );
      if (mounted) {
        setState(() {
          _detail = detail;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _changeWeek(DateTime weekStart) async {
    if (!mounted) return;
    setState(() {
      _selectedWeekStart = weekStart;
      _isLoadingWeekChange = true;
    });
    await _loadDetail();
    if (mounted) {
      setState(() => _isLoadingWeekChange = false);
    }
  }

  DateTime _getMonday(DateTime date) {
    return date.subtract(Duration(days: date.weekday - 1));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.employeeName),
        titleSpacing: 0,
        bottom: widget.teamName != null
            ? PreferredSize(
                preferredSize: const Size.fromHeight(24),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4.0, left: 16.0),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Text(
                      widget.teamName!,
                      style: DesignSystem.caption(context).copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today, size: 20),
            onPressed: _isLoadingWeekChange ? null : _showWeekPicker,
            tooltip: 'Select Week',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _isLoading ? null : _loadDetail,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? _buildLoadingState(context)
          : _error != null
              ? _buildErrorState(context, _error!)
              : _detail == null
                  ? _buildEmptyState(context)
                  : _buildDetailContent(context, _detail!),
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        DesignSystem.skeletonMetricCard(context: context),
        const SizedBox(height: 16),
        DesignSystem.skeletonMetricCard(context: context),
        const SizedBox(height: 16),
        DesignSystem.skeletonMetricCard(context: context),
        const SizedBox(height: 16),
        DesignSystem.skeletonMetricCard(context: context),
        const SizedBox(height: 16),
        DesignSystem.skeletonMetricCard(context: context),
      ],
    );
  }

  Widget _buildErrorState(BuildContext context, String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text('Failed to load wellbeing detail', style: DesignSystem.titleLarge(context)),
            const SizedBox(height: 8),
            Text(error, style: DesignSystem.body(context).copyWith(color: Colors.red)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _loadDetail, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.info_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text('No wellbeing data available', style: DesignSystem.titleLarge(context)),
            const SizedBox(height: 8),
            Text('Insufficient sessions or check-ins for this period', style: DesignSystem.body(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailContent(BuildContext context, EmployeeDetailResponse detail) {
    final weekLabel = '${_formatDate(detail.weekStart)} - ${_formatDate(detail.weekEnd)}';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Week selector bar
          _buildWeekSelectorBar(context, weekLabel),
          const SizedBox(height: 24),

          // A. Employee Overview
          _buildEmployeeOverviewSection(context, detail),
          const SizedBox(height: 24),

          // B. Work Patterns
          _buildWorkPatternsSection(context, detail),
          const SizedBox(height: 24),

          // C. Break Adherence
          _buildBreakAdherenceSection(context, detail),
          const SizedBox(height: 24),

          // D. Wellbeing Trends
          _buildWellbeingTrendsSection(context, detail),
          const SizedBox(height: 24),

          // E. Behavioral Patterns
          _buildBehavioralPatternsSection(context, detail),
          const SizedBox(height: 24),

          // F. Risk Assessment
          _buildRiskAssessmentSection(context, detail),
          const SizedBox(height: 24),

          // G. Historical Trends (week-over-week)
          _buildHistoricalTrendsSection(context, detail),
          const SizedBox(height: 24),

          // H. Suggested Manager Actions
          _buildSuggestedActionsSection(context, detail),
        ],
      ),
    );
  }

  Widget _buildWeekSelectorBar(BuildContext context, String weekLabel) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(DesignSystem.radiusM),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.date_range, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Text('Reporting Week: ', style: DesignSystem.body(context).copyWith(fontWeight: FontWeight.w500)),
          Text(weekLabel, style: DesignSystem.body(context)),
          const Spacer(),
          if (_isLoadingWeekChange) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        ],
      ),
    );
  }

  Future<void> _showWeekPicker() async {
    final now = DateTime.now();
    final currentWeekStart = _getMonday(now);
    final initialDate = _selectedWeekStart ?? currentWeekStart;

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(now.year - 1),
      lastDate: currentWeekStart,
      helpText: 'Select Reporting Week (Monday)',
    );

    if (picked != null && mounted) {
      final monday = _getMonday(picked);
      if (monday != _selectedWeekStart) {
        await _changeWeek(monday);
      }
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  Widget _buildEmployeeOverviewSection(BuildContext context, EmployeeDetailResponse detail) {
    final riskColor = _getRiskColor(detail.riskTier);
    final riskLabel = detail.riskLabel;

    return DesignSystem.premiumCard(
      context: context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Employee Overview', style: DesignSystem.titleLarge(context)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: riskColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(DesignSystem.radiusL),
                  border: Border.all(color: riskColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_getRiskIcon(detail.riskTier), size: 16, color: riskColor),
                    const SizedBox(width: 6),
                    Text(
                      riskLabel,
                      style: DesignSystem.body(context).copyWith(
                        color: riskColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildInfoTile(context, 'Employee', detail.employeeName, Icons.person_outline)),
              const SizedBox(width: 12),
              Expanded(child: _buildInfoTile(context, 'Team', detail.employeeName, Icons.groups_outlined)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildInfoTile(context, 'Week', _formatDate(detail.weekStart), Icons.calendar_today)),
              const SizedBox(width: 12),
              Expanded(child: _buildInfoTile(context, 'Employee ID', detail.employeeId, Icons.badge_outlined)),
            ],
          ),
          if (detail.dataQuality.classificationPossible == false) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(DesignSystem.radiusS),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 20, color: Colors.orange),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Insufficient data for reliable classification. '
                      'Minimum: 3 sessions and 2 check-ins per week.',
                      style: DesignSystem.body(context).copyWith(color: Colors.orange.shade800),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoTile(BuildContext context, String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(DesignSystem.radiusS),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(label, style: DesignSystem.caption(context).copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 4),
          Text(value, style: DesignSystem.body(context)),
        ],
      ),
    );
  }

  Widget _buildWorkPatternsSection(BuildContext context, EmployeeDetailResponse detail) {
    final agg = detail.weeklyAggregates;

    return DesignSystem.premiumCard(
      context: context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Work Patterns', style: DesignSystem.titleLarge(context)),
          const SizedBox(height: 16),
          _buildMetricGrid(context, [
            _MetricItem('Weekly Hours', '${agg.avgWorkedHours.toStringAsFixed(1)}h', Icons.schedule, Colors.blue),
            _MetricItem('Avg Daily Hours', '${agg.avgWorkedHours.toStringAsFixed(1)}h', Icons.today_outlined, Colors.indigo),
            _MetricItem('Overtime Sessions', '${detail.evidenceItems.where((e) => e.type == EvidenceType.workedHoursExcess).length}', Icons.access_time_filled, Colors.orange),
            _MetricItem('Break Compliance Low', '${detail.evidenceItems.where((e) => e.type == EvidenceType.breakComplianceLow).length}', Icons.block, Colors.red),
            _MetricItem('Total Sessions', '${detail.dailyBreakdown.length}', Icons.work_outline, Colors.teal),
            _MetricItem('Focus Rate', '${agg.avgFocusRatePct.toStringAsFixed(0)}%', Icons.center_focus_strong, Colors.purple),
          ]),
        ],
      ),
    );
  }

  Widget _buildBreakAdherenceSection(BuildContext context, EmployeeDetailResponse detail) {
    final agg = detail.weeklyAggregates;
    final missedBreaks = detail.dailyBreakdown
        .where((d) => d.patternsDetected.contains('skipped_breaks'))
        .length;

    return DesignSystem.premiumCard(
      context: context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Break Adherence', style: DesignSystem.titleLarge(context)),
          const SizedBox(height: 16),
          _buildMetricGrid(context, [
            _MetricItem('Total Check-ins', '${agg.totalCheckins}', Icons.coffee_outlined, Colors.brown),
            _MetricItem('Avg Break Compliance', '${agg.avgBreakCompliancePct}%', Icons.check_circle_outline,
              agg.avgBreakCompliancePct >= 80 ? Colors.green : Colors.orange),
            _MetricItem('Focus Rate', '${agg.avgFocusRatePct.toStringAsFixed(0)}%', Icons.center_focus_strong, Colors.purple),
            _MetricItem('Missed Scheduled', '$missedBreaks', Icons.block, missedBreaks > 0 ? Colors.red : Colors.green),
            _MetricItem('Days Tracked', '${detail.dailyBreakdown.length}', Icons.calendar_month, Colors.blue),
          ]),
        ],
      ),
    );
  }

  Widget _buildWellbeingTrendsSection(BuildContext context, EmployeeDetailResponse detail) {
    final agg = detail.weeklyAggregates;

    return DesignSystem.premiumCard(
      context: context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Wellbeing Trends', style: DesignSystem.titleLarge(context)),
          const SizedBox(height: 16),
          _buildMetricGrid(context, [
            if (agg.avgStressLevel != null)
              _MetricItem('Avg Stress Level', '${agg.avgStressLevel!.toStringAsFixed(1)}/5', Icons.psychology, agg.avgStressLevel! >= 4 ? Colors.red : Colors.green),
            if (agg.avgEnergyLevel != null)
              _MetricItem('Avg Energy Level', '${agg.avgEnergyLevel!.toStringAsFixed(1)}/5', Icons.battery_full, agg.avgEnergyLevel! <= 2 ? Colors.red : Colors.green),
            if (agg.avgWorkloadManageability != null)
              _MetricItem('Workload Manageability', '${agg.avgWorkloadManageability!.toStringAsFixed(1)}/5', Icons.balance, agg.avgWorkloadManageability! <= 2 ? Colors.red : Colors.green),
            _MetricItem('Total Check-ins', '${agg.totalCheckins}', Icons.assessment_outlined, Colors.blue),
          ]),
          if (agg.trendWorkedHours != null || agg.trendBreakCompliance != null || agg.trendFocusRate != null) ...[
            const SizedBox(height: 16),
            Text('Week-over-Week Comparison', style: DesignSystem.title(context)),
            const SizedBox(height: 12),
            if (agg.trendWorkedHours != null)
              _buildComparisonRow(context, 'Working Hours',
                agg.avgWorkedHours.toStringAsFixed(1),
                agg.previousWeekAvgWorkedHours.toStringAsFixed(1),
                agg.trendWorkedHours!.value),
            if (agg.trendBreakCompliance != null)
              _buildComparisonRow(context, 'Break Compliance',
                agg.avgBreakCompliancePct.toString(),
                agg.previousWeekAvgBreakCompliancePct.toString(),
                agg.trendBreakCompliance!.value),
            if (agg.trendFocusRate != null)
              _buildComparisonRow(context, 'Focus Rate',
                agg.avgFocusRatePct.toStringAsFixed(0),
                agg.previousWeekAvgFocusRatePct.toStringAsFixed(0),
                agg.trendFocusRate!.value),
          ],
        ],
      ),
    );
  }

  Widget _buildComparisonRow(BuildContext context, String label, String current, String previous, String trend) {
    Color trendColor;
    IconData trendIcon;
    switch (trend) {
      case 'improving':
        trendColor = Colors.green;
        trendIcon = Icons.trending_up;
        break;
      case 'worsening':
        trendColor = Colors.red;
        trendIcon = Icons.trending_down;
        break;
      case 'stable':
        trendColor = Colors.blue;
        trendIcon = Icons.trending_flat;
        break;
      default:
        trendColor = Colors.grey;
        trendIcon = Icons.help_outline;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(label, style: DesignSystem.body(context))),
          Expanded(flex: 2, child: Text('$current (current)', style: DesignSystem.body(context).copyWith(fontWeight: FontWeight.w600))),
          Expanded(flex: 2, child: Text('$previous (prev)', style: DesignSystem.body(context).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant))),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(trendIcon, size: 18, color: trendColor),
                const SizedBox(width: 4),
                Text(trend.capitalize(), style: DesignSystem.body(context).copyWith(color: trendColor, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBehavioralPatternsSection(BuildContext context, EmployeeDetailResponse detail) {
    final patterns = detail.detectedPatterns;

    return DesignSystem.premiumCard(
      context: context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Behavioral Patterns', style: DesignSystem.titleLarge(context)),
          const SizedBox(height: 8),
          Text(
            'Detected patterns from work sessions and check-ins (privacy-preserved)',
            style: DesignSystem.caption(context),
          ),
          const SizedBox(height: 16),
          if (patterns.isEmpty)
            _buildSuppressedIndicator(context, 'No significant behavioral patterns detected this week')
          else
            ...patterns.map((p) => _buildPatternTile(context, p)),
        ],
      ),
    );
  }

  Widget _buildPatternTile(BuildContext context, DetectedPattern pattern) {
    final color = _getPatternColor(pattern.patternId);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(DesignSystem.radiusM),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pattern.displayName, style: DesignSystem.body(context).copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(pattern.measurement, style: DesignSystem.caption(context)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${pattern.daysTriggered} days', style: DesignSystem.caption(context)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRiskAssessmentSection(BuildContext context, EmployeeDetailResponse detail) {
    final riskColor = _getRiskColor(detail.riskTier);
    final evidence = detail.evidenceItems;

    return DesignSystem.premiumCard(
      context: context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Risk Assessment', style: DesignSystem.titleLarge(context)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: riskColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(DesignSystem.radiusL),
                  border: Border.all(color: riskColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_getRiskIcon(detail.riskTier), size: 18, color: riskColor),
                    const SizedBox(width: 8),
                    Text(
                      detail.riskLabel,
                      style: DesignSystem.body(context).copyWith(color: riskColor, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (evidence.isEmpty)
            _buildSuppressedIndicator(context, 'No risk factors identified. Classification based on available metrics.')
          else
            ...evidence.map((e) => _buildEvidenceTile(context, e)),
          const SizedBox(height: 16),
          _buildThresholdInfo(context),
        ],
      ),
    );
  }

  Widget _buildEvidenceTile(BuildContext context, EvidenceItem evidence) {
    final icon = _getEvidenceIcon(evidence.type);
    final color = _getEvidenceColor(evidence.type);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(DesignSystem.radiusS),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(evidence.description, style: DesignSystem.body(context)),
                const SizedBox(height: 4),
                Text(
                  'Threshold: ${evidence.threshold} | Days affected: ${evidence.daysAffected}',
                  style: DesignSystem.caption(context).copyWith(color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThresholdInfo(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(DesignSystem.radiusS),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Classification Thresholds', style: DesignSystem.caption(context).copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('• Overtime: >120% of target daily hours', style: DesignSystem.caption(context)),
          Text('• Stress/Fatigue: ≥4.0/5 average', style: DesignSystem.caption(context)),
          Text('• Break Compliance: <80%', style: DesignSystem.caption(context)),
          Text('• Extended Sessions: >2h continuous work', style: DesignSystem.caption(context)),
          Text('• Recurring patterns: Medium/high evidence strength', style: DesignSystem.caption(context)),
        ],
      ),
    );
  }

  Widget _buildHistoricalTrendsSection(BuildContext context, EmployeeDetailResponse detail) {
    return DesignSystem.premiumCard(
      context: context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Historical Trends', style: DesignSystem.titleLarge(context)),
          const SizedBox(height: 8),
          Text(
            'Week-over-week comparison and risk progression',
            style: DesignSystem.caption(context),
          ),
          const SizedBox(height: 16),
          if (detail.weeklyAggregates.trendWorkedHours == null &&
              detail.weeklyAggregates.trendBreakCompliance == null &&
              detail.weeklyAggregates.trendFocusRate == null)
            _buildSuppressedIndicator(context, 'Historical comparison not available for this period')
          else ...[
            if (detail.weeklyAggregates.trendWorkedHours != null)
              _buildTrendIndicator(
                context,
                'Working Hours Trend',
                detail.weeklyAggregates.trendWorkedHours!.value,
                detail.weeklyAggregates.avgWorkedHours,
                detail.weeklyAggregates.previousWeekAvgWorkedHours,
              ),
            if (detail.weeklyAggregates.trendBreakCompliance != null)
              _buildTrendIndicator(
                context,
                'Break Compliance Trend',
                detail.weeklyAggregates.trendBreakCompliance!.value,
                detail.weeklyAggregates.avgBreakCompliancePct.toDouble(),
                detail.weeklyAggregates.previousWeekAvgBreakCompliancePct.toDouble(),
              ),
            if (detail.weeklyAggregates.trendFocusRate != null)
              _buildTrendIndicator(
                context,
                'Focus Rate Trend',
                detail.weeklyAggregates.trendFocusRate!.value,
                detail.weeklyAggregates.avgFocusRatePct,
                detail.weeklyAggregates.previousWeekAvgFocusRatePct,
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildTrendIndicator(BuildContext context, String label, String trend, double current, double previous) {
    Color trendColor;
    IconData trendIcon;
    switch (trend) {
      case 'improving':
        trendColor = Colors.green;
        trendIcon = Icons.trending_up;
        break;
      case 'worsening':
        trendColor = Colors.red;
        trendIcon = Icons.trending_down;
        break;
      case 'stable':
        trendColor = Colors.blue;
        trendIcon = Icons.trending_flat;
        break;
      default:
        trendColor = Colors.grey;
        trendIcon = Icons.help_outline;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: trendColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(DesignSystem.radiusM),
        border: Border.all(color: trendColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(trendIcon, size: 24, color: trendColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: DesignSystem.body(context).copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  'Current: ${current.toStringAsFixed(1)} | Previous: ${previous.toStringAsFixed(1)} | ${trend.capitalize()}',
                  style: DesignSystem.caption(context).copyWith(color: trendColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestedActionsSection(BuildContext context, EmployeeDetailResponse detail) {
    final actions = detail.recommendedActions;

    return DesignSystem.premiumCard(
      context: context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, size: 24, color: Colors.amber),
              const SizedBox(width: 12),
              Text('Suggested Manager Actions', style: DesignSystem.titleLarge(context)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Supportive recommendations based on current wellbeing assessment',
            style: DesignSystem.caption(context),
          ),
          const SizedBox(height: 16),
          if (actions.isEmpty)
            _buildSuppressedIndicator(context, 'No specific actions recommended at this time')
          else
            ...actions.map((action) => _buildActionTile(context, action)),
        ],
      ),
    );
  }

  Widget _buildActionTile(BuildContext context, String action) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(DesignSystem.radiusM),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.arrow_forward_rounded, size: 20, color: Colors.amber.shade700),
          const SizedBox(width: 12),
          Expanded(
            child: Text(action, style: DesignSystem.body(context).copyWith(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _buildSuppressedIndicator(BuildContext context, String message) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(DesignSystem.radiusM),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 24, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: DesignSystem.body(context))),
        ],
      ),
    );
  }

  Widget _buildMetricGrid(BuildContext context, List<_MetricItem> metrics) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: metrics.map((m) => _buildMetricTile(context, m)).toList(),
    );
  }

  Widget _buildMetricTile(BuildContext context, _MetricItem metric) {
    final width = MediaQuery.of(context).size.width;
    final tileWidth = width < 600 ? (width - 48) / 2 : (width - 72) / 3;

    return Container(
      width: tileWidth,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: metric.color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(DesignSystem.radiusM),
        border: Border.all(color: metric.color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(metric.icon, size: 20, color: metric.color),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 12),
          Text(metric.value, style: DesignSystem.title(context).copyWith(color: metric.color)),
          const SizedBox(height: 4),
          Text(metric.label, style: DesignSystem.caption(context)),
        ],
      ),
    );
  }

  Color _getRiskColor(RiskTier tier) {
    switch (tier) {
      case RiskTier.low:
        return Colors.green;
      case RiskTier.moderate:
        return Colors.orange;
      case RiskTier.high:
        return Colors.deepOrange;
      case RiskTier.critical:
        return Colors.red;
      case RiskTier.insufficientData:
        return Colors.grey;
    }
  }

  IconData _getRiskIcon(RiskTier tier) {
    switch (tier) {
      case RiskTier.low:
        return Icons.check_circle;
      case RiskTier.moderate:
        return Icons.warning_amber_rounded;
      case RiskTier.high:
        return Icons.error_outline;
      case RiskTier.critical:
        return Icons.dangerous;
      case RiskTier.insufficientData:
        return Icons.help_outline;
    }
  }

  Color _getPatternColor(String patternId) {
    switch (patternId) {
      case 'RECURRING_OVERWORK':
      case 'recurring_overwork':
        return Colors.deepOrange;
      case 'REPEATED_SKIPPED_BREAKS':
      case 'repeated_skipped_breaks':
        return Colors.red;
      case 'INCONSISTENT_SCHEDULE':
      case 'inconsistent_schedule':
        return Colors.orange;
      case 'LATE_NIGHT_WORK':
      case 'late_night_work':
        return Colors.purple;
      case 'WEEKEND_WORK':
      case 'weekend_work':
        return Colors.indigo;
      case 'DECLINING_WELLBEING':
      case 'declining_wellbeing':
        return Colors.red;
      default:
        return Colors.blue;
    }
  }

  IconData _getEvidenceIcon(EvidenceType type) {
    switch (type) {
      case EvidenceType.workedHoursExcess:
        return Icons.access_time_filled;
      case EvidenceType.breakComplianceLow:
        return Icons.block;
      case EvidenceType.wellbeingDeclining:
        return Icons.psychology;
      case EvidenceType.focusDeclining:
        return Icons.center_focus_weak;
      case EvidenceType.skippedBreaks:
        return Icons.coffee_outlined;
      case EvidenceType.unknown:
        return Icons.info_outline;
    }
  }

  Color _getEvidenceColor(EvidenceType type) {
    switch (type) {
      case EvidenceType.workedHoursExcess:
        return Colors.deepOrange;
      case EvidenceType.breakComplianceLow:
        return Colors.red;
      case EvidenceType.wellbeingDeclining:
        return Colors.red;
      case EvidenceType.focusDeclining:
        return Colors.orange;
      case EvidenceType.skippedBreaks:
        return Colors.red;
      case EvidenceType.unknown:
        return Colors.blue;
    }
  }
}

class _MetricItem {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  _MetricItem(this.label, this.value, this.icon, this.color);
}

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1).toLowerCase()}';
  }
}