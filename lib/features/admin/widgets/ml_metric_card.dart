import 'package:flutter/material.dart';
import 'package:intellibreak/core/design_system.dart';

/// A compact metric card for ML dashboard KPIs with clear typographic hierarchy
class MLMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? description;
  final bool showProgress;
  final double progress;

  const MLMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.description,
    this.showProgress = false,
    this.progress = 0.0,
  });

  bool get _isNumeric {
    // Check if value looks like a number or decimal
    return double.tryParse(value.replaceAll(RegExp(r'[^0-9.-]'), '')) != null &&
        value.length <= 10 &&
        !value.contains(' ');
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    // Determine font size based on whether it's numeric (30px) or status text (24px)
    final double valueFontSize = _isNumeric ? 30.0 : 24.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isDark
            ? DesignSystem.getSemanticColor(context, SemanticColor.background).withValues(alpha: 0.85)
            : DesignSystem.getSemanticColor(context, SemanticColor.surface),
        borderRadius: BorderRadius.circular(DesignSystem.radiusM),
        border: Border.all(
          color: isDark
              ? DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant).withValues(alpha: 0.2)
              : DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant).withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.all(Radius.circular(DesignSystem.radiusS)),
                ),
                child: Icon(icon, size: 14, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? DesignSystem.getSemanticColor(context, SemanticColor.onSurface).withValues(alpha: 0.7)
                        : DesignSystem.getSemanticColor(context, SemanticColor.onSurface).withValues(alpha: 0.7),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: valueFontSize,
              fontWeight: FontWeight.bold,
              height: 1.1,
              color: isDark
                  ? DesignSystem.getSemanticColor(context, SemanticColor.onSurface)
                  : DesignSystem.getSemanticColor(context, SemanticColor.onSurface),
            ),
            overflow: TextOverflow.ellipsis,
          ),
          if (description != null && description!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              description!,
              style: TextStyle(
                fontSize: 11,
                color: isDark
                    ? DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant).withValues(alpha: 0.6)
                    : DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant).withValues(alpha: 0.6),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (showProgress) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 4,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    children: [
                      Container(
                        width: constraints.maxWidth,
                        height: 4,
                        decoration: BoxDecoration(
                          color: DesignSystem.getSemanticColor(
                            context,
                            SemanticColor.onSurfaceVariant,
                          ).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Container(
                        width: constraints.maxWidth * progress.clamp(0.0, 1.0),
                        height: 4,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
