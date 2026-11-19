import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intellibreak/core/design_system.dart';

/// Bar chart for class distribution (accepted vs dismissed/ignored)
class MLClassDistributionChart extends StatelessWidget {
  final int acceptedCount;
  final int dismissedCount;
  final int ignoredCount;

  const MLClassDistributionChart({
    super.key,
    required this.acceptedCount,
    required this.dismissedCount,
    required this.ignoredCount,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    final classes = [
      {'label': 'Accepted', 'count': acceptedCount, 'color': Colors.green},
      {'label': 'Dismissed', 'count': dismissedCount, 'color': Colors.orange},
      {'label': 'Ignored', 'count': ignoredCount, 'color': Colors.grey},
    ];

    final total = acceptedCount + dismissedCount + ignoredCount;

    if (total == 0) {
      return _buildEmptyState(context, 'No feedback data available');
    }

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
          Text(
            'Class Distribution',
            style: DesignSystem.title(context).copyWith(
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: DesignSystem.spacingM),
          SizedBox(
            height: 220,
            child: BarChart(_buildBarChartData(context, isDark, classes, total)),
          ),
          const SizedBox(height: DesignSystem.spacingM),
          _buildSummaryRow(context, isDark, classes, total),
        ],
      ),
    );
  }

  BarChartData _buildBarChartData(
    BuildContext context,
    bool isDark,
    List<Map<String, dynamic>> classes,
    int total,
  ) {
    final maxCount = classes.map((c) => c['count'] as int).reduce((a, b) => a > b ? a : b);

    return BarChartData(
      alignment: BarChartAlignment.spaceAround,
      maxY: (maxCount * 1.3).ceilToDouble(),
      minY: 0,
      barTouchData: BarTouchData(
        enabled: true,
        touchTooltipData: BarTouchTooltipData(
          getTooltipColor: (group) =>
              isDark ? Colors.grey[800] ?? Colors.black : Colors.grey[100] ?? Colors.white,
          getTooltipItem: (group, groupIndex, rod, rodIndex) {
            final cls = classes[group.x.toInt()];
            final percentage = total > 0 ? (cls['count'] as int) / total * 100 : 0.0;
            return BarTooltipItem(
              '${cls['label']}\nCount: ${cls['count']} (${percentage.toStringAsFixed(1)}%)',
              TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontWeight: FontWeight.w500,
                fontSize: 12,
              ),
            );
          },
        ),
      ),
      titlesData: FlTitlesData(
        show: true,
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (value, meta) {
              final index = value.toInt();
              if (index >= 0 && index < classes.length) {
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Padding(
                    padding: const EdgeInsets.only(top: DesignSystem.spacingXS),
                    child: Text(
                      classes[index]['label'] as String,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white70 : Colors.grey.shade600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              return const SideTitleWidget(axisSide: AxisSide.top, child: SizedBox.shrink());
            },
            interval: 1,
            reservedSize: 35,
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 50,
            getTitlesWidget: (value, meta) {
              return SideTitleWidget(
                axisSide: meta.axisSide,
                child: Text(
                  value.toInt().toString(),
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white70 : Colors.grey.shade600,
                  ),
                ),
              );
            },
            interval: maxCount > 10 ? (maxCount / 5).ceilToDouble() : 1,
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
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: maxCount > 10 ? (maxCount / 5).ceilToDouble() : 1,
        getDrawingHorizontalLine: (value) {
          return FlLine(
            color: Theme.of(context).dividerTheme.color?.withAlpha(40) ?? Colors.grey.withAlpha(40),
            strokeWidth: 0.5,
          );
        },
      ),
      barGroups: List.generate(classes.length, (index) {
        final cls = classes[index];
        return BarChartGroupData(
          x: index,
          barRods: [
            BarChartRodData(
              toY: (cls['count'] as int).toDouble(),
              color: cls['color'] as Color,
              width: 40,
              borderRadius: BorderRadius.circular(DesignSystem.radiusXS),
              backDrawRodData: BackgroundBarChartRodData(
                show: true,
                toY: (maxCount * 1.3).ceilToDouble(),
                color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.1),
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildSummaryRow(
    BuildContext context,
    bool isDark,
    List<Map<String, dynamic>> classes,
    int total,
  ) {
    return Wrap(
      spacing: DesignSystem.spacingM,
      runSpacing: DesignSystem.spacingS,
      children: classes.map((cls) {
        final count = cls['count'] as int;
        final color = cls['color'] as Color;
        final percentage = total > 0 ? count / total * 100 : 0.0;

        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignSystem.spacingM,
            vertical: DesignSystem.spacingS,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(DesignSystem.radiusM),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
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
              const SizedBox(width: DesignSystem.spacingS),
              Text(
                '${cls['label']}: $count (${percentage.toStringAsFixed(1)}%)',
                style: DesignSystem.label(context).copyWith(
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
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
              Icons.pie_chart_outline,
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