import 'package:flutter/material.dart';
import 'package:intellibreak/core/design_system.dart';
import '../models/wellbeing_models.dart';

/// Phase 3: Team Wellbeing Dashboard UI Widget
/// Embeds team wellbeing overview into Manager Dashboard
class TeamWellbeingDashboardWidget extends StatefulWidget {
  final WeeklyOverviewResponse? weeklyData;
  final bool isLoading;
  final VoidCallback? onRefresh;
  final Function(DateTime)? onWeekChange;
  final DateTime? selectedWeekStart;
  final Function(String employeeId, String employeeName, String? teamName)? onEmployeeSelected;

  const TeamWellbeingDashboardWidget({
    super.key,
    this.weeklyData,
    this.isLoading = false,
    this.onRefresh,
    this.onWeekChange,
    this.selectedWeekStart,
    this.onEmployeeSelected,
  });

  @override
  State<TeamWellbeingDashboardWidget> createState() => _TeamWellbeingDashboardWidgetState();
}

class _TeamWellbeingDashboardWidgetState extends State<TeamWellbeingDashboardWidget> {
  void _onEmployeeTap(EmployeeRiskSummary emp) {
    if (widget.onEmployeeSelected != null) {
      widget.onEmployeeSelected!(emp.employeeId, emp.employeeName, widget.weeklyData?.teamSummary.name);
    }
  }
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDesktop = MediaQuery.of(context).size.width >= 1100;

    return Card(
      margin: EdgeInsets.zero,
      elevation: isDark ? 2 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignSystem.radiusL),
        side: BorderSide(
          color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(isDesktop ? 24.0 : 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            const SizedBox(height: 20),
            if (widget.isLoading)
              _buildLoadingState(context)
            else if (widget.weeklyData == null)
              _buildEmptyState(context)
            else
              _buildContent(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Team Wellbeing Overview',
                style: DesignSystem.titleXL(context),
              ),
              const SizedBox(height: 4),
              Text(
                _getWeekRangeText(),
                style: DesignSystem.caption(context),
              ),
            ],
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.onWeekChange != null) _buildWeekSelector(context),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: widget.onRefresh,
              tooltip: 'Refresh',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWeekSelector(BuildContext context) {
    final currentWeek = widget.selectedWeekStart ?? _getMonday(DateTime.now());

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left, size: 20),
          onPressed: () {
            final previousWeek = currentWeek.subtract(const Duration(days: 7));
            widget.onWeekChange?.call(previousWeek);
          },
          tooltip: 'Previous week',
        ),
        TextButton(
          onPressed: () {
            widget.onWeekChange?.call(_getMonday(DateTime.now()));
          },
          child: Text(
            _isCurrentWeek(currentWeek) ? 'Current Week' : 'Jump to Current',
            style: const TextStyle(fontSize: 13),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right, size: 20),
          onPressed: _isCurrentWeek(currentWeek) ? null : () {
            final nextWeek = currentWeek.add(const Duration(days: 7));
            if (nextWeek.isBefore(DateTime.now()) || _isCurrentWeek(nextWeek)) {
              widget.onWeekChange?.call(nextWeek);
            }
          },
          tooltip: 'Next week',
        ),
      ],
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    return Column(
      children: [
        DesignSystem.skeletonMetricCard(context: context),
        const SizedBox(height: 16),
        DesignSystem.skeletonMetricCard(context: context),
        const SizedBox(height: 16),
        DesignSystem.skeletonMetricCard(context: context),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.info_outline,
              size: 48,
              color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Text(
              'No wellbeing data available',
              style: DesignSystem.body(context),
            ),
            const SizedBox(height: 8),
            Text(
              'Data will appear once team members complete work sessions',
              style: DesignSystem.caption(context),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final data = widget.weeklyData!;
    final isDesktop = MediaQuery.of(context).size.width >= 1100;

    // Compute aggregates from employee data
    final aggregates = _computeTeamAggregates(data);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A. Weekly Team Overview
        _buildWeeklyOverviewSection(context, aggregates),
        const SizedBox(height: 24),

        // B. Risk Distribution + D. Break Adherence (side by side on desktop)
        if (isDesktop)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildRiskDistributionSection(context, data)),
              const SizedBox(width: 16),
              Expanded(child: _buildBreakAdherenceSection(context, aggregates)),
            ],
          )
        else ...[
          _buildRiskDistributionSection(context, data),
          const SizedBox(height: 16),
          _buildBreakAdherenceSection(context, aggregates),
        ],

        const SizedBox(height: 24),

        // C. Work Pattern Analytics
        _buildWorkPatternSection(context, aggregates),

        const SizedBox(height: 24),

        // E. Weekly Trends
        _buildWeeklyTrendsSection(context, aggregates),

        const SizedBox(height: 24),

        // F. Behavioral Patterns
        _buildBehavioralPatternsSection(context, data),

        const SizedBox(height: 24),

        // Employee List (tappable for detail drill-down)
        _buildEmployeeListSection(context, data),
      ],
    );
  }

  Map<String, dynamic> _computeTeamAggregates(WeeklyOverviewResponse data) {
    if (data.employees.isEmpty) {
      return {
        'totalWorkingHours': null,
        'avgDailyWorkingHours': null,
        'breakComplianceRate': null,
        'avgBreaksPerDay': null,
        'avgBreakDuration': null,
        'overtimeCount': 0,
        'extendedSessionCount': 0,
        'workingHoursTrend': TrendDirection.unknown,
        'breakComplianceTrend': TrendDirection.unknown,
        'riskScoreTrend': TrendDirection.unknown,
      };
    }

    int improvingCount = 0;
    int worseningCount = 0;
    int stableCount = 0;
    int overworkEmployees = 0;

    for (var emp in data.employees) {
      switch (emp.trend) {
        case TrendDirection.improving:
          improvingCount++;
          break;
        case TrendDirection.worsening:
          worseningCount++;
          break;
        case TrendDirection.stable:
          stableCount++;
          break;
        case TrendDirection.unknown:
          break;
      }
      if (emp.topEvidence.any((e) => e.toLowerCase().contains('recurring overwork'))) overworkEmployees++;
    }

    // Determine overall trend based on employee trends
    TrendDirection overallTrend = TrendDirection.unknown;
    if (improvingCount > worseningCount && improvingCount > stableCount) {
      overallTrend = TrendDirection.improving;
    } else if (worseningCount > improvingCount && worseningCount > stableCount) {
      overallTrend = TrendDirection.worsening;
    } else if (stableCount >= improvingCount && stableCount >= worseningCount) {
      overallTrend = TrendDirection.stable;
    }


    return {
      'totalWorkingHours': null,
      'avgDailyWorkingHours': null,
      'breakComplianceRate': null,
      'avgBreaksPerDay': null,
      'avgBreakDuration': null,
      'overtimeCount': overworkEmployees,
      'extendedSessionCount': 0,
      'workingHoursTrend': overallTrend,
      'breakComplianceTrend': TrendDirection.unknown,
      'riskScoreTrend': overallTrend == TrendDirection.improving ? TrendDirection.worsening :
                        overallTrend == TrendDirection.worsening ? TrendDirection.improving : TrendDirection.stable,
    };
  }

  Widget _buildWeeklyOverviewSection(BuildContext context, Map<String, dynamic> aggregates) {
    final isDesktop = MediaQuery.of(context).size.width >= 1100;
    final totalHoursLabel = aggregates['totalWorkingHours'] == null ? 'N/A' : '${(aggregates['totalWorkingHours'] as double).toStringAsFixed(1)}h';
    final dailyHoursLabel = aggregates['avgDailyWorkingHours'] == null ? 'N/A' : '${(aggregates['avgDailyWorkingHours'] as double).toStringAsFixed(1)}h';
    final breakRate = aggregates['breakComplianceRate'] as double?;
    final breakRateLabel = breakRate == null ? 'N/A' : '${breakRate.toStringAsFixed(0)}%';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Weekly Team Overview',
          style: DesignSystem.titleXL(context),
        ),
        const SizedBox(height: 12),
        if (isDesktop)
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  context,
                  'Total Working Hours',
                  totalHoursLabel,
                  Icons.schedule,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricTile(
                  context,
                  'Avg Daily Hours',
                  dailyHoursLabel,
                  Icons.today,
                  Colors.purple,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricTile(
                  context,
                  'Break Logging',
                  breakRateLabel,
                  Icons.coffee,
                  breakRate == null ? Colors.grey : (breakRate >= 80 ? Colors.green : Colors.orange),
                ),
              ),
            ],
          )
        else ...[
          _buildMetricTile(
            context,
            'Total Working Hours',
            totalHoursLabel,
            Icons.schedule,
            Colors.blue,
          ),
          const SizedBox(height: 12),
          _buildMetricTile(
            context,
            'Avg Daily Hours',
            dailyHoursLabel,
            Icons.today,
            Colors.purple,
          ),
          const SizedBox(height: 12),
          _buildMetricTile(
            context,
            'Break Logging',
            breakRateLabel,
            Icons.coffee,
            breakRate == null ? Colors.grey : (breakRate >= 80 ? Colors.green : Colors.orange),
          ),
        ],
      ],
    );
  }

  Widget _buildMetricTile(BuildContext context, String label, String value, IconData icon, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(DesignSystem.radiusM),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(DesignSystem.radiusS),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: DesignSystem.caption(context)),
                const SizedBox(height: 2),
                Text(value, style: DesignSystem.titleLarge(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiskDistributionSection(BuildContext context, WeeklyOverviewResponse data) {
    // Use the employee rows' 5-tier classification. The team summary's
    // by_tier map is a separate 3-tier Green/Amber/Red distribution.
    final green = data.employees.where((e) => e.riskTier == RiskTier.low).length;
    final amber = data.employees.where((e) => e.riskTier == RiskTier.moderate).length;
    final high = data.employees.where((e) => e.riskTier == RiskTier.high).length;
    final critical = data.employees.where((e) => e.riskTier == RiskTier.critical).length;
    final insufficient = data.employees.where((e) => e.riskTier == RiskTier.insufficientData).length;
    final total = green + amber + high + critical + insufficient;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Risk Distribution',
          style: DesignSystem.titleXL(context),
        ),
        const SizedBox(height: 12),
        if (total == 0)
          _buildSuppressedIndicator(context, 'Insufficient data or privacy suppression active')
        else ...[
          _buildRiskBar(context, [green, amber, high, critical, insufficient], total),
          const SizedBox(height: 12),
          _buildRiskLegend(context, [green, amber, high, critical, insufficient], total),
        ],
      ],
    );
  }

  Widget _buildRiskBar(BuildContext context, List<int> counts, int total) {
    const colors = [Color(0xFF4CAF50), Color(0xFFFF9800), Color(0xFFFF7043), Color(0xFFF44336), Color(0xFF78909C)];

    return ClipRRect(
      borderRadius: BorderRadius.circular(DesignSystem.radiusS),
      child: SizedBox(
        height: 32,
        child: Row(children: [
            for (var i = 0; i < counts.length; i++)
              if (counts[i] > 0) Expanded(flex: counts[i], child: Container(color: colors[i])),
          ]),
      ),
    );
  }

  Widget _buildRiskLegend(BuildContext context, List<int> counts, int total) {
    const labels = ['Normal', 'Needs Attention', 'High Risk', 'Critical', 'Insufficient Data'];
    const colors = [Color(0xFF4CAF50), Color(0xFFFF9800), Color(0xFFFF7043), Color(0xFFF44336), Color(0xFF78909C)];
    return Column(
      children: [for (var i = 0; i < counts.length; i++) ...[
        if (i > 0) const SizedBox(height: 8),
        _buildRiskLegendItem(context, labels[i], counts[i], total, colors[i]),
      ]],
    );
  }

  Widget _buildRiskLegendItem(BuildContext context, String label, int count, int total, Color color) {
    final pct = total > 0 ? (count / total * 100).toStringAsFixed(0) : '0';

    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: DesignSystem.body(context))),
        Text('$count ($pct%)', style: DesignSystem.body(context).copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildBreakAdherenceSection(BuildContext context, Map<String, dynamic> aggregates) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Break Logging',
          style: DesignSystem.titleXL(context),
        ),
        const SizedBox(height: 12),
        _buildMetricRow(context, 'Break Frequency', aggregates['avgBreaksPerDay'] == null ? 'N/A' : '${(aggregates['avgBreaksPerDay'] as double).toStringAsFixed(1)}/day', Icons.repeat),
        const SizedBox(height: 8),
        _buildMetricRow(context, 'Avg Break Duration', aggregates['avgBreakDuration'] == null ? 'N/A' : '${(aggregates['avgBreakDuration'] as double).toStringAsFixed(0)} min', Icons.timer),
        const SizedBox(height: 8),
        _buildMetricRow(context, 'Break Logging', aggregates['breakComplianceRate'] == null ? 'N/A' : '${(aggregates['breakComplianceRate'] as double).toStringAsFixed(0)}%', Icons.check_circle,
          aggregates['breakComplianceRate'] == null ? Colors.grey : ((aggregates['breakComplianceRate'] as double) >= 80 ? Colors.green : Colors.orange)),
      ],
    );
  }

  Widget _buildMetricRow(BuildContext context, String label, String value, IconData icon, [Color? valueColor]) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(DesignSystem.radiusS),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant)),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: DesignSystem.body(context))),
          Text(
            value,
            style: DesignSystem.body(context).copyWith(
              fontWeight: FontWeight.w600,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkPatternSection(BuildContext context, Map<String, dynamic> aggregates) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Work Pattern Analytics',
          style: DesignSystem.titleXL(context),
        ),
        const SizedBox(height: 12),
        _buildMetricRow(context, 'Weekly Working Hours', aggregates['totalWorkingHours'] == null ? 'N/A' : '${(aggregates['totalWorkingHours'] as double).toStringAsFixed(1)}h', Icons.work),
        const SizedBox(height: 8),
        _buildMetricRow(context, 'Employees with Overwork Evidence', '${aggregates['overtimeCount']}', Icons.schedule,
          (aggregates['overtimeCount'] as int) > 0 ? Colors.orange : Colors.green),
      ],
    );
  }

  Widget _buildWeeklyTrendsSection(BuildContext context, Map<String, dynamic> aggregates) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Weekly Trends',
          style: DesignSystem.titleXL(context),
        ),
        const SizedBox(height: 12),
        _buildTrendItem(context, 'Working Hours', aggregates['workingHoursTrend'] as TrendDirection),
        const SizedBox(height: 8),
        _buildTrendItem(context, 'Break Logging', aggregates['breakComplianceTrend'] as TrendDirection),
        const SizedBox(height: 8),
        _buildTrendItem(context, 'Risk Score', aggregates['riskScoreTrend'] as TrendDirection),
      ],
    );
  }

  Widget _buildTrendItem(BuildContext context, String label, TrendDirection trend) {
    IconData icon;
    Color color;

    switch (trend) {
      case TrendDirection.improving:
        icon = Icons.trending_up;
        color = Colors.green;
        break;
      case TrendDirection.worsening:
        icon = Icons.trending_down;
        color = Colors.red;
        break;
      case TrendDirection.stable:
        icon = Icons.trending_flat;
        color = Colors.blue;
        break;
      case TrendDirection.unknown:
        icon = Icons.help_outline;
        color = Colors.grey;
    }

    return _buildMetricRow(context, label, trend.value.toUpperCase(), icon, color);
  }

  Widget _buildBehavioralPatternsSection(BuildContext context, WeeklyOverviewResponse data) {
    // Aggregate patterns from employee data
    final patternMap = <String, int>{};
    for (var emp in data.employees) {
      // Primary concern is the top-level pattern summary
      final concern = emp.primaryConcern;
      patternMap[concern] = (patternMap[concern] ?? 0) + 1;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Behavioral Patterns',
          style: DesignSystem.titleXL(context),
        ),
        const SizedBox(height: 8),
        Text(
          'Aggregated detected patterns (privacy-preserved)',
          style: DesignSystem.caption(context),
        ),
        const SizedBox(height: 12),
        if (patternMap.isEmpty)
          _buildSuppressedIndicator(context, 'No significant patterns detected this week')
        else
          ...patternMap.entries.map((entry) => Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: _buildPatternItem(context, entry.key, entry.value),
          )),
      ],
    );
  }

  Widget _buildPatternItem(BuildContext context, String patternType, int count) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(DesignSystem.radiusS),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              patternType,
              style: DesignSystem.body(context).copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _getPatternColor(patternType).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(DesignSystem.radiusS),
            ),
            child: Text(
              '$count employees',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _getPatternColor(patternType),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuppressedIndicator(BuildContext context, String message) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(DesignSystem.radiusM),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.privacy_tip_outlined,
            size: 20,
            color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: DesignSystem.body(context).copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getPatternColor(String patternType) {
    switch (patternType.toLowerCase()) {
      case 'consecutive_overtime':
      case 'extended_work_sessions':
        return Colors.orange;
      case 'skipped_breaks':
      case 'late_night_work':
        return Colors.red;
      case 'regular_exercise_breaks':
      case 'consistent_schedule':
        return Colors.green;
      default:
        return Colors.blue;
    }
  }

  Widget _buildEmployeeListSection(BuildContext context, WeeklyOverviewResponse data) {
    if (data.employees.isEmpty) {
      return _buildSuppressedIndicator(context, 'No employee data available for this week');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Team Members',
          style: DesignSystem.titleXL(context),
        ),
        const SizedBox(height: 8),
        Text(
          'Tap an employee to view detailed wellbeing assessment',
          style: DesignSystem.caption(context),
        ),
        const SizedBox(height: 12),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: data.employees.length,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final emp = data.employees[index];
            final riskColor = _getRiskColor(emp.riskTier);
            return InkWell(
              onTap: () => _onEmployeeTap(emp),
              borderRadius: BorderRadius.circular(DesignSystem.radiusM),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(DesignSystem.radiusM),
                  border: Border.all(
                    color: riskColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: riskColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            emp.employeeName,
                            style: DesignSystem.body(context).copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Risk: ${emp.riskLabel} • Trend: ${emp.trend.value[0].toUpperCase()}${emp.trend.value.substring(1)}',
                            style: DesignSystem.caption(context).copyWith(color: riskColor),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
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

  String _getWeekRangeText() {
    if (widget.weeklyData != null) {
      final start = widget.weeklyData!.weekStart;
      final end = widget.weeklyData!.weekEnd;
      return '${_formatDate(start)} - ${_formatDate(end)}';
    }
    return 'Select a week';
  }

  String _formatDate(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  DateTime _getMonday(DateTime date) {
    return date.subtract(Duration(days: date.weekday - 1));
  }

  bool _isCurrentWeek(DateTime date) {
    final now = DateTime.now();
    final currentMonday = _getMonday(now);
    final targetMonday = _getMonday(date);
    return currentMonday.year == targetMonday.year &&
           currentMonday.month == targetMonday.month &&
           currentMonday.day == targetMonday.day;
  }
}
