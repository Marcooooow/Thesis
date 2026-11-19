import 'package:flutter/material.dart';
import 'package:intellibreak/core/design_system.dart';

class WorkHourTrendsCard extends StatelessWidget {
  const WorkHourTrendsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(DesignSystem.spacingM),
      decoration: BoxDecoration(
        color: DesignSystem.getSemanticColor(context, SemanticColor.surface),
        borderRadius: BorderRadius.circular(DesignSystem.radiusM),
        border: Border.all(
          color: DesignSystem.getSemanticColor(
            context,
            SemanticColor.onSurfaceVariant,
          ).withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with icon + label pattern (accessibility)
          DesignSystem.sectionHeader(
            context,
            'Work Hour Trends',
            Icons.trending_up_outlined,
          ),
          const SizedBox(height: DesignSystem.spacingM),

          // Chart placeholder
          Container(
            height: 100,
            decoration: BoxDecoration(
              color: DesignSystem.getSemanticColor(
                context,
                SemanticColor.surface,
              ),
              borderRadius: BorderRadius.circular(DesignSystem.radiusM),
              border: Border.all(
                color: DesignSystem.getSemanticColor(
                  context,
                  SemanticColor.onSurfaceVariant,
                ).withValues(alpha: 0.1),
              ),
            ),
            child: Center(
              child: Text(
                'Weekly Work Hour Trend',
                style: DesignSystem.label(context).copyWith(
                  color: DesignSystem.getSemanticColor(
                    context,
                    SemanticColor.onSurfaceVariant,
                  ).withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
