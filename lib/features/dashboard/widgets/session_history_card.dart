import 'package:flutter/material.dart';
import 'package:intellibreak/core/design_system.dart';

class SessionHistoryCard extends StatelessWidget {
  const SessionHistoryCard({super.key});

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
            'Session History',
            Icons.history_outlined,
          ),
          const SizedBox(height: DesignSystem.spacingM),

          // Session items (placeholder)
          Column(
            children: [
              _buildSessionItem(
                context: context,
                label: 'Session 1',
                duration: '2h 30m',
                date: 'Today',
              ),
              const SizedBox(height: DesignSystem.spacingM),
              _buildSessionItem(
                context: context,
                label: 'Session 2',
                duration: '1h 45m',
                date: 'Yesterday',
              ),
              const SizedBox(height: DesignSystem.spacingM),
              _buildSessionItem(
                context: context,
                label: 'Session 3',
                duration: '3h 10m',
                date: 'Jun 20',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSessionItem({
    required BuildContext context,
    required String label,
    required String duration,
    required String date,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: DesignSystem.getSemanticColor(context, SemanticColor.surface),
        borderRadius: BorderRadius.circular(DesignSystem.radiusM),
        border: Border.all(
          color: DesignSystem.getSemanticColor(
            context,
            SemanticColor.onSurfaceVariant,
          ).withValues(alpha: 0.2),
        ),
      ),
      padding: EdgeInsets.all(DesignSystem.spacingM),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: DesignSystem.bodyLarge(context).copyWith(
                    fontWeight: FontWeight.w600,
                    color: DesignSystem.getSemanticColor(
                      context,
                      SemanticColor.onSurface,
                    ),
                  ),
                ),
                const SizedBox(height: DesignSystem.spacingXS),
                Text(
                  '$duration • $date',
                  style: DesignSystem.labelLarge(context).copyWith(
                    color: DesignSystem.getSemanticColor(
                      context,
                      SemanticColor.onSurfaceVariant,
                    ).withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.check_circle_outline,
            size: 20,
            color: DesignSystem.getSemanticColor(
              context,
              SemanticColor.primary,
            ),
          ),
        ],
      ),
    );
  }
}
