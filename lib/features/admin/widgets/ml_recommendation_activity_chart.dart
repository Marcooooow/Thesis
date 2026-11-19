import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intellibreak/core/design_system.dart';

/// Line chart for recommendation activity over time (accepted/dismissed/ignored)
class MLRecommendationActivityChart extends StatelessWidget {
  final List<Map<String, dynamic>> activityData; // Each: {date, accepted, dismissed, ignored}

  const MLRecommendationActivityChart({
    super.key,
    required this.activityData,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    if (activityData.isEmpty) {
      return _buildEmptyState(context, 'No recommendation activity data available');
    }

    // Sort by date
    final sortedData = List<Map<String, dynamic>>.from(activityData)
      ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));

    // Build line chart data
    final acceptedSpots = <FlSpot>[];
    final dismissedSpots = <FlSpot>[];
    final ignoredSpots = <FlSpot>[];

    for (int i = 0; i < sortedData.length; i++) {
      final data = sortedData[i];
      acceptedSpots.add(FlSpot(i.toDouble(), (data['accepted'] as num).toDouble()));
      dismissedSpots.add(FlSpot(i.toDouble(), (data['dismissed'] as num).toDouble()));
      ignoredSpots.add(FlSpot(i.toDouble(), (data['ignored'] as num).toDouble()));
    }

    final maxY = [
      ...acceptedSpots.map((s) => s.y),
      ...dismissedSpots.map((s) => s.y),
      ...ignoredSpots.map((s) => s.y),
    ].reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(DesignSystem.spacingL),
      decoration: BoxDecoration(
        color: isDark
            ? DesignSystem.getSemanticColor(context, SemanticColor.background)
            : Colors.white,
        borderRadius: BorderRadius.circular(DesignSystem.radiusL),
        border: Border.all(
          color: isDark
              ? Colors.grey.withValues(alpha: 0.15)
              : Colors.grey.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recommendation Activity (Last ${sortedData.length} Days)',
                style: DesignSystem.title(context).copyWith(
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              _buildLegend(context, isDark),
            ],
          ),
          const SizedBox(height: DesignSystem.spacingM),
          SizedBox(
            height: 220,
            child: LineChart(_buildLineChartData(context, isDark, sortedData, acceptedSpots, dismissedSpots, ignoredSpots, maxY)),
          ),
          const SizedBox(height: DesignSystem.spacingM),
          _buildSummaryRow(context, isDark, sortedData),
        ],
      ),
    );
  }

  LineChartData _buildLineChartData(
    BuildContext context,
    bool isDark,
    List<Map<String, dynamic>> sortedData,
    List<FlSpot> acceptedSpots,
    List<FlSpot> dismissedSpots,
    List<FlSpot> ignoredSpots,
    double maxY,
  ) {
    return LineChartData(
      lineTouchData: LineTouchData(
        enabled: true,
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (spot) =>
              isDark ? Colors.grey[800] ?? Colors.black : Colors.grey[100] ?? Colors.white,
          getTooltipItems: (touchedSpots) {
            return touchedSpots.map((spot) {
              final index = spot.x.toInt();
              if (index >= 0 && index < sortedData.length) {
                final data = sortedData[index];
                final seriesName = spot.barIndex == 0
                    ? 'Accepted'
                    : spot.barIndex == 1
                        ? 'Dismissed'
                        : 'Ignored';
                final color = spot.barIndex == 0
                    ? Colors.green.shade600
                    : spot.barIndex == 1
                        ? Colors.orange.shade600
                        : Colors.grey.shade600;
                return LineTooltipItem(
                  '${data['date']}\n$seriesName: ${spot.y.toInt()}',
                  TextStyle(
                    color: color,
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                  ),
                );
              }
              return null;
            }).where((item) => item != null).cast<LineTooltipItem>().toList();
          },
        ),
      ),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: maxY > 10 ? (maxY / 5).ceilToDouble() : 1,
        getDrawingHorizontalLine: (value) {
          return FlLine(
            color: Theme.of(context).dividerTheme.color?.withAlpha(40) ?? Colors.grey.withAlpha(40),
            strokeWidth: 0.5,
          );
        },
      ),
      titlesData: FlTitlesData(
        show: true,
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 35,
            interval: (sortedData.length / 5).ceil().clamp(1, sortedData.length).toDouble(),
            getTitlesWidget: (value, meta) {
              final index = value.toInt();
              if (index >= 0 && index < sortedData.length) {
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Padding(
                    padding: const EdgeInsets.only(top: DesignSystem.spacingXS),
                    child: Text(
                      _formatDate(sortedData[index]['date'] as String),
                      style: TextStyle(
                        fontSize: 10,
                        color: isDark ? Colors.white60 : Colors.grey.shade500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              return const SideTitleWidget(axisSide: AxisSide.top, child: SizedBox.shrink());
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            interval: maxY > 10 ? (maxY / 5).ceilToDouble() : 1,
            getTitlesWidget: (value, meta) {
              return SideTitleWidget(
                axisSide: meta.axisSide,
                child: Text(
                  value.toInt().toString(),
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark ? Colors.white60 : Colors.grey.shade500,
                  ),
                ),
              );
            },
          ),
        ),
      ),
      borderData: FlBorderData(
        show: true,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerTheme.color ?? Colors.grey,
            width: 1,
          ),
          left: BorderSide(
            color: Theme.of(context).dividerTheme.color ?? Colors.grey,
            width: 1,
          ),
          top: BorderSide.none,
          right: BorderSide.none,
        ),
      ),
      minX: 0,
      maxX: (sortedData.length - 1).toDouble(),
      minY: 0,
      maxY: (maxY * 1.3).ceilToDouble().clamp(1.0, double.infinity),
      lineBarsData: [
        _buildLineBarData(acceptedSpots, Colors.green.shade600, 'Accepted'),
        _buildLineBarData(dismissedSpots, Colors.orange.shade600, 'Dismissed'),
        _buildLineBarData(ignoredSpots, Colors.grey.shade600, 'Ignored'),
      ],
    );
  }

  LineChartBarData _buildLineBarData(List<FlSpot> spots, Color color, String name) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      curveSmoothness: 0.3,
      color: color,
      barWidth: 2.5,
      isStrokeCapRound: true,
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, percent, barData, index) {
          return FlDotCirclePainter(
            radius: 3.5,
            color: color,
            strokeWidth: 2,
            strokeColor: Colors.white,
          );
        },
      ),
      belowBarData: BarAreaData(
        show: true,
        color: color.withValues(alpha: 0.1),
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.15),
            color.withValues(alpha: 0.0),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
    );
  }

  Widget _buildLegend(BuildContext context, bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _legendItem(context, 'Accepted', Colors.green.shade600, isDark),
        const SizedBox(width: DesignSystem.spacingM),
        _legendItem(context, 'Dismissed', Colors.orange.shade600, isDark),
        const SizedBox(width: DesignSystem.spacingM),
        _legendItem(context, 'Ignored', Colors.grey.shade600, isDark),
      ],
    );
  }

  Widget _legendItem(BuildContext context, String label, Color color, bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: DesignSystem.spacingXS),
        Text(
          label,
          style: DesignSystem.caption(context).copyWith(
            color: isDark ? Colors.white70 : Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(
    BuildContext context,
    bool isDark,
    List<Map<String, dynamic>> sortedData,
  ) {
    final totalAccepted = sortedData.map((d) => d['accepted'] as int).reduce((a, b) => a + b);
    final totalDismissed = sortedData.map((d) => d['dismissed'] as int).reduce((a, b) => a + b);
    final totalIgnored = sortedData.map((d) => d['ignored'] as int).reduce((a, b) => a + b);
    final total = totalAccepted + totalDismissed + totalIgnored;
    final acceptanceRate = total > 0 ? (totalAccepted / total * 100) : 0.0;

    return Wrap(
      spacing: DesignSystem.spacingM,
      runSpacing: DesignSystem.spacingS,
      children: [
        _statChip(context, 'Total Activity', total.toString(), Icons.analytics, isDark),
        _statChip(context, 'Acceptance Rate', '${acceptanceRate.toStringAsFixed(1)}%', Icons.trending_up, isDark, Colors.green),
        _statChip(context, 'Accepted', totalAccepted.toString(), Icons.check_circle, isDark, Colors.green),
        _statChip(context, 'Dismissed', totalDismissed.toString(), Icons.cancel, isDark, Colors.orange),
      ],
    );
  }

  Widget _statChip(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    bool isDark, [
    Color? color,
  ]) {
    final chipColor = color ?? (isDark ? Colors.blue.shade400 : Colors.blue.shade600);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignSystem.spacingM,
        vertical: DesignSystem.spacingS,
      ),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(DesignSystem.radiusM),
        border: Border.all(color: chipColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: chipColor),
          const SizedBox(width: DesignSystem.spacingS),
          Text(
            '$label: $value',
            style: DesignSystem.caption(context).copyWith(
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String dateStr) {
    // Format: "2026-10-25" -> "10/25"
    try {
      final parts = dateStr.split('-');
      if (parts.length >= 3) {
        return '${parts[1]}/${parts[2]}';
      }
    } catch (_) {}
    return dateStr;
  }

  Widget _buildEmptyState(BuildContext context, String message) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 280,
      padding: const EdgeInsets.all(DesignSystem.spacingXL),
      decoration: BoxDecoration(
        color: isDark
            ? DesignSystem.getSemanticColor(context, SemanticColor.background)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(DesignSystem.radiusL),
        border: Border.all(
          color: isDark
              ? Colors.grey.withValues(alpha: 0.15)
              : Colors.grey.withValues(alpha: 0.1),
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.timeline,
              size: 48,
              color: isDark ? Colors.white30 : Colors.grey.shade400,
            ),
            const SizedBox(height: DesignSystem.spacingM),
            Text(
              message,
              style: DesignSystem.body(context).copyWith(
                color: isDark ? Colors.white60 : Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}