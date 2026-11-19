import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intellibreak/core/design_system.dart';

/// Horizontal bar chart for feature importance / model coefficients
class MLFeatureImportanceChart extends StatelessWidget {
  final List<Map<String, dynamic>>
  features; // Each: {name, coefficient, importance}
  final bool magnitudeOnly;

  const MLFeatureImportanceChart({
    super.key,
    required this.features,
    this.magnitudeOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    final validFeatures = features.where((feature) {
      final value = _featureValue(feature);
      return feature['name'] is String && value != null && value.isFinite;
    }).toList();

    if (validFeatures.isEmpty) {
      return _buildEmptyState(context, 'No feature importance data available');
    }

    final sortedFeatures = validFeatures
      ..sort(
        (a, b) => _featureValue(b)!.abs().compareTo(_featureValue(a)!.abs()),
      );

    // Take top 10 features for readability
    final displayFeatures = sortedFeatures.take(10).toList();
    final double maxCoeff = displayFeatures
        .map((f) => _featureValue(f)!.abs())
        .reduce((a, b) => a > b ? a : b);

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
                'Feature Importance (Top ${displayFeatures.length})',
                style: DesignSystem.title(context).copyWith(
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              magnitudeOnly
                  ? Text(
                      'Magnitude only',
                      style: DesignSystem.caption(context).copyWith(
                        color: isDark ? Colors.white70 : Colors.grey.shade600,
                      ),
                    )
                  : _buildLegend(context, isDark),
            ],
          ),
          const SizedBox(height: DesignSystem.spacingM),
          SizedBox(
            height: (displayFeatures.length * 42.0).clamp(150.0, 450.0),
            child: BarChart(
              _buildBarChartData(
                context,
                isDark,
                displayFeatures,
                maxCoeff,
                magnitudeOnly,
              ),
            ),
          ),
          const SizedBox(height: DesignSystem.spacingM),
          _buildNote(context, isDark, magnitudeOnly),
        ],
      ),
    );
  }

  BarChartData _buildBarChartData(
    BuildContext context,
    bool isDark,
    List<Map<String, dynamic>> features,
    double maxCoeff,
    bool magnitudeOnly,
  ) {
    final axisMaximum = maxCoeff > 0 ? maxCoeff * 1.1 : 1.0;
    final axisInterval = axisMaximum > 0.5
        ? 0.2
        : (axisMaximum / 5).clamp(0.05, 0.2);
    return BarChartData(
      alignment: BarChartAlignment.spaceAround,
      maxY: axisMaximum,
      minY: magnitudeOnly ? 0 : -axisMaximum,
      barTouchData: BarTouchData(
        enabled: true,
        touchTooltipData: BarTouchTooltipData(
          getTooltipColor: (group) => isDark
              ? Colors.grey[800] ?? Colors.black
              : Colors.grey[100] ?? Colors.white,
          getTooltipItem: (group, groupIndex, rod, rodIndex) {
            final index = group.x.toInt();
            if (index < 0 || index >= features.length) return null;
            final feature = features[index];
            final value = _featureValue(feature)!;
            return BarTooltipItem(
              magnitudeOnly
                  ? '${feature['name']}\nImportance: ${value.toStringAsFixed(4)}'
                  : '${feature['name']}\nCoefficient: ${value.toStringAsFixed(4)}\n(${value >= 0 ? 'increases' : 'decreases'} acceptance)',
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
            reservedSize: 160,
            interval: 1,
            getTitlesWidget: (value, meta) {
              final index = value.toInt();
              if (index >= 0 && index < features.length) {
                final feature = features[index];
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Padding(
                    padding: const EdgeInsets.only(
                      right: DesignSystem.spacingS,
                    ),
                    child: Text(
                      _truncateFeatureName(feature['name'].toString(), 25),
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      textAlign: TextAlign.right,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                );
              }
              return const SideTitleWidget(
                axisSide: AxisSide.top,
                child: SizedBox.shrink(),
              );
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            interval: axisInterval,
            getTitlesWidget: (value, meta) {
              return SideTitleWidget(
                axisSide: meta.axisSide,
                child: Text(
                  value.toStringAsFixed(2),
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
      gridData: FlGridData(
        show: true,
        drawHorizontalLine: false,
        verticalInterval: axisInterval,
        getDrawingVerticalLine: (value) {
          if (value == 0) {
            return FlLine(
              color: Theme.of(context).dividerTheme.color ?? Colors.grey,
              strokeWidth: 1.5,
            );
          }
          return FlLine(
            color:
                Theme.of(context).dividerTheme.color?.withAlpha(40) ??
                Colors.grey.withAlpha(40),
            strokeWidth: 0.5,
          );
        },
      ),
      barGroups: List.generate(features.length, (index) {
        final feature = features[index];
        final value = _featureValue(feature)!;
        final isPositive = value >= 0;

        return BarChartGroupData(
          x: index,
          barRods: [
            BarChartRodData(
              fromY: 0,
              toY: value,
              width: 28,
              borderRadius: BorderRadius.circular(DesignSystem.radiusXS),
              color: magnitudeOnly
                  ? DesignSystem.getSemanticColor(
                      context,
                      SemanticColor.primary,
                    )
                  : isPositive
                  ? Colors.green.shade600
                  : Colors.red.shade600,
              backDrawRodData: BackgroundBarChartRodData(
                show: true,
                toY: axisMaximum,
                fromY: magnitudeOnly ? 0 : -axisMaximum,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.03)
                    : Colors.grey.withValues(alpha: 0.05),
              ),
            ),
          ],
          showingTooltipIndicators: const [0],
        );
      }),
    );
  }

  double? _featureValue(Map<String, dynamic> feature) {
    final value = magnitudeOnly
        ? feature['importance']
        : feature['coefficient'];
    return value is num ? value.toDouble() : null;
  }

  Widget _buildLegend(BuildContext context, bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _legendItem(context, 'Positive', Colors.green.shade600, isDark),
        const SizedBox(width: DesignSystem.spacingM),
        _legendItem(context, 'Negative', Colors.red.shade600, isDark),
      ],
    );
  }

  Widget _legendItem(
    BuildContext context,
    String label,
    Color color,
    bool isDark,
  ) {
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
          style: DesignSystem.caption(context)
              .copyWith(color: isDark ? Colors.white70 : Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildNote(BuildContext context, bool isDark, bool magnitudeOnly) {
    return Container(
      padding: const EdgeInsets.all(DesignSystem.spacingS),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.blue.withValues(alpha: 0.1)
            : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(DesignSystem.radiusS),
        border: Border.all(
          color: isDark
              ? Colors.blue.withValues(alpha: 0.3)
              : Colors.blue.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: isDark ? Colors.blue.shade300 : Colors.blue.shade700,
          ),
          const SizedBox(width: DesignSystem.spacingS),
          Expanded(
            child: Text(
              magnitudeOnly
                  ? 'The backend returns absolute coefficient magnitudes. Direction is not available in this response.'
                  : 'Absolute standardized coefficients from LogisticRegression. Positive = increases acceptance probability. Features with |coeff| < 0.01 may have negligible impact.',
              style: DesignSystem.caption(context).copyWith(
                color: isDark ? Colors.blue.shade300 : Colors.blue.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _truncateFeatureName(String name, int maxLength) {
    if (name.length <= maxLength) return name;
    return '${name.substring(0, maxLength - 3)}...';
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
              Icons.analytics_outlined,
              size: 48,
              color: isDark ? Colors.white30 : Colors.grey.shade400,
            ),
            const SizedBox(height: DesignSystem.spacingM),
            Text(
              message,
              style: DesignSystem.body(
                context,
              ).copyWith(color: isDark ? Colors.white60 : Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
