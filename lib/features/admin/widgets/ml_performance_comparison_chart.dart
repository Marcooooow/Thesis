import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import 'package:intellibreak/core/design_system.dart';
import 'package:intellibreak/core/theme/theme_controller.dart';

/// Grouped bar chart for comparing model performance metrics
class MLPerformanceComparisonChart extends StatelessWidget {
  final List<Map<String, dynamic>> models;
  final List<String> metrics;

  const MLPerformanceComparisonChart({
    super.key,
    required this.models,
    this.metrics = const ['Accuracy', 'Precision', 'Recall', 'F1-Score', 'ROC-AUC'],
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = Provider.of<ThemeController>(context, listen: false).isHighContrast;

    if (models.isEmpty) {
      return _buildEmptyState(context, 'No model comparison data available');
    }

    // Extract metric keys from the first model
    final firstMetrics = models.first['metrics'] as Map<String, dynamic>? ?? {};
    final metricKeys = metrics.map((m) => m.toLowerCase().replaceAll('-', '_').replaceAll(' ', '_')).toList();

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
          if (models.length > 1) ...[
            _buildLegend(context, isDark, isHighContrast),
            const SizedBox(height: DesignSystem.spacingM),
          ],
          SizedBox(
            height: 280,
            child: BarChart(_buildBarChartData(context, isDark, isHighContrast, metricKeys)),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend(BuildContext context, bool isDark, bool isHighContrast) {
    final colors = _getModelColors(models.length);
    return Wrap(
      spacing: DesignSystem.spacingL,
      runSpacing: DesignSystem.spacingS,
      children: List.generate(models.length, (index) {
        final model = models[index];
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: colors[index],
                borderRadius: BorderRadius.circular(DesignSystem.radiusXS),
              ),
            ),
            const SizedBox(width: DesignSystem.spacingXS),
            Text(
              model['algorithm']?.toString() ?? model['name']?.toString() ?? 'Model ${index + 1}',
              style: DesignSystem.caption(context).copyWith(
                color: isDark ? Colors.white70 : Colors.grey.shade600,
              ),
            ),
          ],
        );
      }),
    );
  }

  BarChartData _buildBarChartData(
    BuildContext context,
    bool isDark,
    bool isHighContrast,
    List<String> metricKeys,
  ) {
    final colors = _getModelColors(models.length);
    final barGroups = <BarChartGroupData>[];
    final maxY = _calculateMaxY();

    for (int i = 0; i < metricKeys.length; i++) {
      final barRods = <BarChartRodData>[];
      for (int m = 0; m < models.length; m++) {
        final modelMetrics = models[m]['metrics'] as Map<String, dynamic>? ?? {};
        final value = (modelMetrics[metricKeys[i]] as num?)?.toDouble() ?? 0.0;

        barRods.add(
          BarChartRodData(
            toY: value,
            color: colors[m],
            width: (models.length <= 3 ? 16.0 : 12.0),
            borderRadius: BorderRadius.circular(DesignSystem.radiusXS),
          ),
        );
      }

      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: barRods,
          barsSpace: 4,
        ),
      );
    }

    return BarChartData(
      alignment: BarChartAlignment.spaceAround,
      maxY: maxY,
      minY: 0,
      barTouchData: BarTouchData(
        enabled: true,
        touchTooltipData: BarTouchTooltipData(
          getTooltipColor: (group) =>
              isDark ? Colors.grey[800] ?? Colors.black : Colors.grey[100] ?? Colors.white,
          getTooltipItem: (group, groupIndex, rod, rodIndex) {
            final model = models[rodIndex];
            final metricName = metrics[group.x.toInt()];
            return BarTooltipItem(
              '${model['algorithm']?.toString() ?? model['name']?.toString() ?? 'Model ${rodIndex + 1}'}\n$metricName: ${rod.toY.toStringAsFixed(4)}',
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
              if (index >= 0 && index < metrics.length) {
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Padding(
                    padding: const EdgeInsets.only(top: DesignSystem.spacingXS),
                    child: Text(
                      metrics[index],
                      style: TextStyle(
                        fontSize: 11,
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
            reservedSize: 40,
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
                  value.toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white70 : Colors.grey.shade600,
                  ),
                ),
              );
            },
            interval: 0.2,
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
        horizontalInterval: 0.2,
        getDrawingHorizontalLine: (value) {
          return FlLine(
            color: Theme.of(context).dividerTheme.color?.withAlpha(40) ?? Colors.grey.withAlpha(40),
            strokeWidth: 0.5,
          );
        },
      ),
      barGroups: barGroups,
    );
  }

  double _calculateMaxY() {
    double maxY = 0.0;
    for (final model in models) {
      final metrics = model['metrics'] as Map<String, dynamic>? ?? {};
      for (final value in metrics.values) {
        if (value is num) {
          maxY = maxY > value.toDouble() ? maxY : value.toDouble();
        }
      }
    }
    return (maxY * 1.2).clamp(0.5, 1.0);
  }

  List<Color> _getModelColors(int count) {
    // Consistent color palette for models
    const palette = [
      Color(0xFF6C63FF), // Primary violet
      Color(0xFF4CAF50), // Green
      Color(0xFFFF9800), // Amber
      Color(0xFFF44336), // Red
      Color(0xFF2196F3), // Blue
      Color(0xFF9C27B0), // Purple
    ];
    return List.generate(count, (i) => palette[i % palette.length]);
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
              Icons.bar_chart,
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