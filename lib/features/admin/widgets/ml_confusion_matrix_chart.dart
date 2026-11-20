import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import 'package:intellibreak/core/design_system.dart';
import 'package:intellibreak/core/theme/theme_controller.dart';

/// Confusion matrix heatmap visualization for ML dashboard
class MLConfusionMatrixChart extends StatelessWidget {
  final List<List<int>> matrix; // 2x2: [[TN, FP], [FN, TP]]
  final String? label;

  const MLConfusionMatrixChart({
    super.key,
    required this.matrix,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = Provider.of<ThemeController>(context, listen: false).isHighContrast;

    if (matrix.length != 2 || matrix[0].length != 2 || matrix[1].length != 2) {
      return _buildEmptyState(context, 'Invalid confusion matrix data');
    }

    final int tn = matrix[0][0];
    final int fp = matrix[0][1];
    final int fn = matrix[1][0];
    final int tp = matrix[1][1];

    final maxValue = [tn, fp, fn, tp].reduce((a, b) => a > b ? a : b);
    final minValue = [tn, fp, fn, tp].reduce((a, b) => a < b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: DesignSystem.title(context).copyWith(
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: DesignSystem.spacingS),
        ],
        Container(
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
            children: [
              // Header row
              Row(
                children: [
                  const SizedBox(width: 80), // Space for "Actual" label
                  Expanded(
                    child: Center(
                      child: Text(
                        'Predicted',
                        style: DesignSystem.labelLarge(context).copyWith(
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: DesignSystem.spacingM),
              // Matrix rows
              ..._buildMatrixRows(context, isDark, isHighContrast, tn, fp, fn, tp, maxValue, minValue),
              const SizedBox(height: DesignSystem.spacingL),
              // Legend
              _buildLegend(context, isDark, isHighContrast, minValue, maxValue),
            ],
          ),
        ),
        const SizedBox(height: DesignSystem.spacingL),
        // Raw values table for accessibility
        _buildAccessibleTable(context, isDark, isHighContrast, tn, fp, fn, tp),
      ],
    );
  }

  List<Widget> _buildMatrixRows(
    BuildContext context,
    bool isDark,
    bool isHighContrast,
    int tn, int fp, int fn, int tp,
    int maxValue, int minValue,
  ) {
    final labels = ['Actual Dismissed', 'Actual Accepted'];
    final rows = [
      [tn, fp],
      [fn, tp],
    ];
    final cellLabels = [
      ['TN', 'FP'],
      ['FN', 'TP'],
    ];

    return List.generate(2, (rowIndex) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: DesignSystem.spacingS),
        child: Row(
          children: [
            // Actual label
            SizedBox(
              width: 80,
              child: Text(
                labels[rowIndex],
                style: DesignSystem.label(context).copyWith(
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white70 : Colors.grey.shade600,
                ),
              ),
            ),
            // Cells
            Expanded(
              child: Row(
                children: List.generate(2, (colIndex) {
                  final value = rows[rowIndex][colIndex];
                  final cellLabel = cellLabels[rowIndex][colIndex];
                  final normalized = maxValue > minValue
                      ? (value - minValue) / (maxValue - minValue)
                      : 0.5;

                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: DesignSystem.spacingXXS),
                      padding: const EdgeInsets.all(DesignSystem.spacingM),
                      decoration: BoxDecoration(
                        color: _getCellColor(normalized, isDark),
                        borderRadius: BorderRadius.circular(DesignSystem.radiusM),
                        border: Border.all(
                          color: isDark
                              ? Colors.grey.withValues(alpha: 0.2)
                              : Colors.grey.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            cellLabel,
                            style: DesignSystem.caption(context).copyWith(
                              fontWeight: FontWeight.w600,
                              color: _getTextColor(normalized, isDark),
                            ),
                          ),
                          const SizedBox(height: DesignSystem.spacingXXS),
                          Text(
                            value.toString(),
                            style: DesignSystem.dataLarge(context).copyWith(
                              color: _getTextColor(normalized, isDark),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildLegend(BuildContext context, bool isDark, bool isHighContrast, int minValue, int maxValue) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildLegendItem(context, 'Low', _getCellColor(0.0, isDark), isDark),
        const SizedBox(width: DesignSystem.spacingL),
        _buildLegendItem(context, 'High', _getCellColor(1.0, isDark), isDark),
      ],
    );
  }

  Widget _buildLegendItem(BuildContext context, String label, Color color, bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(DesignSystem.radiusXS),
          ),
        ),
        const SizedBox(width: DesignSystem.spacingS),
        Text(
          label,
          style: DesignSystem.caption(context).copyWith(
            color: isDark ? Colors.white70 : Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildAccessibleTable(
    BuildContext context,
    bool isDark,
    bool isHighContrast,
    int tn, int fp, int fn, int tp,
  ) {
    return Container(
      padding: const EdgeInsets.all(DesignSystem.spacingM),
      decoration: BoxDecoration(
        color: isDark
            ? DesignSystem.getSemanticColor(context, SemanticColor.background)
            : Colors.white,
        borderRadius: BorderRadius.circular(DesignSystem.radiusM),
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
            'Raw Values',
            style: DesignSystem.labelLarge(context).copyWith(
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: DesignSystem.spacingS),
          Table(
            border: TableBorder.all(
              color: isDark
                  ? Colors.grey.withValues(alpha: 0.15)
                  : Colors.grey.withValues(alpha: 0.1),
            ),
            children: [
              TableRow(
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.grey.withValues(alpha: 0.05),
                ),
                children: [
                  _tableCell(' ', isHeader: true),
                  _tableCell('Predicted Dismissed', isHeader: true),
                  _tableCell('Predicted Accepted', isHeader: true),
                ],
              ),
              TableRow(
                children: [
                  _tableCell('Actual Dismissed'),
                  _tableCell('TN: $tn', bold: true),
                  _tableCell('FP: $fp'),
                ],
              ),
              TableRow(
                children: [
                  _tableCell('Actual Accepted'),
                  _tableCell('FN: $fn'),
                  _tableCell('TP: $tp', bold: true),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tableCell(String text, {bool isHeader = false, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.all(DesignSystem.spacingS),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isHeader || bold ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, String message) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
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
              Icons.grid_off,
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

  Color _getCellColor(double normalized, bool isDark) {
    // Blue-green heatmap: light for low, dark for high
    if (isDark) {
      return Color.lerp(
        const Color(0xFF151A21),
        const Color(0xFF0D9488), // Teal
        normalized,
      )!;
    } else {
      return Color.lerp(
        const Color(0xFFF0FDFA),
        const Color(0xFF0D9488),
        normalized,
      )!;
    }
  }

  Color _getTextColor(double normalized, bool isDark) {
    // White text for dark cells, dark text for light cells
    return normalized > 0.5
        ? (isDark ? Colors.white : Colors.white)
        : (isDark ? Colors.white70 : Colors.black87);
  }
}