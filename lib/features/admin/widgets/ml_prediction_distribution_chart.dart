import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intellibreak/core/design_system.dart';

/// Histogram for prediction probability distribution
class MLPredictionDistributionChart extends StatelessWidget {
  final List<Map<String, dynamic>> predictions; // Each: {probability, action, session_id, etc.}

  const MLPredictionDistributionChart({
    super.key,
    required this.predictions,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    if (predictions.isEmpty) {
      return _buildEmptyState(context, 'No prediction data available');
    }

    // Build histogram bins (0.0-0.1, 0.1-0.2, ..., 0.9-1.0)
    final bins = List.generate(10, (i) {
      final lower = i * 0.1;
      final upper = (i + 1) * 0.1;
      final binPredictions = predictions.where((p) {
        final prob = (p['probability'] as num).toDouble();
        return prob >= lower && prob < upper;
      }).toList();

      final accepted = binPredictions.where((p) => p['action'] == 'accepted').length;
      final dismissed = binPredictions.where((p) => p['action'] == 'dismissed').length;
      final ignored = binPredictions.where((p) => p['action'] == 'ignored').length;

      return {
        'range': '$lower-${upper == 1.0 ? '1.0' : upper.toStringAsFixed(1)}',
        'lower': lower,
        'upper': upper,
        'total': binPredictions.length,
        'accepted': accepted,
        'dismissed': dismissed,
        'ignored': ignored,
      };
    });

    final maxCount = bins.map((b) => b['total'] as int).reduce((a, b) => a > b ? a : b);

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
                'Prediction Probability Distribution',
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
            child: BarChart(_buildBarChartData(context, isDark, bins, maxCount)),
          ),
          const SizedBox(height: DesignSystem.spacingM),
          _buildStatsRow(context, isDark, bins),
        ],
      ),
    );
  }

  BarChartData _buildBarChartData(
    BuildContext context,
    bool isDark,
    List<Map<String, dynamic>> bins,
    int maxCount,
  ) {
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
            final bin = bins[group.x.toInt()];
            final actionLabels = <String>[];
            if ((bin['accepted'] as int) > 0) actionLabels.add('Accepted: ${bin['accepted']}');
            if ((bin['dismissed'] as int) > 0) actionLabels.add('Dismissed: ${bin['dismissed']}');
            if ((bin['ignored'] as int) > 0) actionLabels.add('Ignored: ${bin['ignored']}');

            return BarTooltipItem(
              'Probability: ${bin['range']}\nTotal: ${bin['total']}\n${actionLabels.join('\n')}',
              TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontWeight: FontWeight.w500,
                fontSize: 11,
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
              if (index >= 0 && index < bins.length) {
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Padding(
                    padding: const EdgeInsets.only(top: DesignSystem.spacingXS),
                    child: Text(
                      bins[index]['range'] as String,
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
            interval: 1,
            reservedSize: 35,
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 45,
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
      barGroups: List.generate(bins.length, (index) {
        final bin = bins[index];
        final accepted = bin['accepted'] as int;
        final dismissed = bin['dismissed'] as int;
        final ignored = bin['ignored'] as int;

        return BarChartGroupData(
          x: index,
          barRods: [
            if (accepted > 0)
              BarChartRodData(
                toY: accepted.toDouble(),
                color: Colors.green.shade600,
                width: 16,
                borderRadius: BorderRadius.circular(DesignSystem.radiusXS),
              ),
            if (dismissed > 0)
              BarChartRodData(
                toY: dismissed.toDouble(),
                color: Colors.orange.shade600,
                width: 16,
                borderRadius: BorderRadius.circular(DesignSystem.radiusXS),
              ),
            if (ignored > 0)
              BarChartRodData(
                toY: ignored.toDouble(),
                color: Colors.grey.shade600,
                width: 16,
                borderRadius: BorderRadius.circular(DesignSystem.radiusXS),
              ),
          ],
          barsSpace: 2,
        );
      }),
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

  Widget _buildStatsRow(
    BuildContext context,
    bool isDark,
    List<Map<String, dynamic>> bins,
  ) {
    final totalPredictions = bins.map((b) => b['total'] as int).reduce((a, b) => a + b);
    final highConfAccepted = bins.where((b) => (b['lower'] as double) >= 0.7).map((b) => b['accepted'] as int).reduce((a, b) => a + b);
    final lowConfDismissed = bins.where((b) => (b['upper'] as double) <= 0.3).map((b) => b['dismissed'] as int).reduce((a, b) => a + b);

    return Wrap(
      spacing: DesignSystem.spacingM,
      runSpacing: DesignSystem.spacingS,
      children: [
        _statChip(context, 'Total Predictions', totalPredictions.toString(), Icons.analytics, isDark),
        _statChip(context, 'High-Conf Accepted', highConfAccepted.toString(), Icons.check_circle, isDark, Colors.green),
        _statChip(context, 'Low-Conf Dismissed', lowConfDismissed.toString(), Icons.cancel, isDark, Colors.orange),
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
              Icons.pie_chart,
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