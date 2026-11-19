import 'package:flutter/material.dart';
import 'package:intellibreak/core/design_system.dart';

/// Training readiness progress bar / gauge component
class MLTrainingReadinessWidget extends StatelessWidget {
  final int labeledCount;
  final int minRequired;
  final int acceptedCount;
  final int dismissedCount;
  final bool sufficient;

  const MLTrainingReadinessWidget({
    super.key,
    required this.labeledCount,
    required this.minRequired,
    required this.acceptedCount,
    required this.dismissedCount,
    required this.sufficient,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final double sampleProgress = (labeledCount / minRequired).clamp(0.0, 1.0);
    final int remaining = (minRequired - labeledCount) > 0 ? (minRequired - labeledCount) : 0;
    final bool classBalanceSufficient = acceptedCount >= 5 && dismissedCount >= 5;

    return Container(
      padding: const EdgeInsets.all(DesignSystem.spacingL),
      decoration: BoxDecoration(
        color: isDark
            ? DesignSystem.getSemanticColor(context, SemanticColor.background)
            : Colors.white,
        borderRadius: BorderRadius.circular(DesignSystem.radiusL),
        border: Border.all(
          color: sufficient
              ? Colors.green.withValues(alpha: 0.3)
              : Colors.orange.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Training Eligibility Status',
                style: DesignSystem.title(context).copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: sufficient ? Colors.green.withValues(alpha: 0.15) : Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(DesignSystem.radiusXS),
                ),
                child: Text(
                  sufficient ? 'Ready for Training' : 'Training Blocked',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: sufficient ? Colors.green.shade700 : Colors.orange.shade700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignSystem.spacingM),
          // Sample count progress bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Labeled Samples ($labeledCount / $minRequired min)',
                style: DesignSystem.label(context).copyWith(
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              Text(
                remaining > 0 ? '$remaining remaining' : 'Threshold met',
                style: DesignSystem.caption(context).copyWith(
                  fontWeight: FontWeight.w600,
                  color: remaining > 0 ? Colors.orange : Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignSystem.spacingS),
          ClipRRect(
            borderRadius: BorderRadius.circular(DesignSystem.radiusXS),
            child: LinearProgressIndicator(
              value: sampleProgress,
              minHeight: 8,
              backgroundColor: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(
                sufficient ? Colors.green : Colors.orange,
              ),
            ),
          ),
          const SizedBox(height: DesignSystem.spacingL),
          // Class balance check
          Text(
            'Class Balance Requirement (>= 5 per class)',
            style: DesignSystem.label(context).copyWith(
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          const SizedBox(height: DesignSystem.spacingS),
          Row(
            children: [
              Expanded(
                child: _classCountChip(
                  context,
                  'Accepted',
                  acceptedCount,
                  5,
                  acceptedCount >= 5,
                  Colors.green,
                  isDark,
                ),
              ),
              const SizedBox(width: DesignSystem.spacingM),
              Expanded(
                child: _classCountChip(
                  context,
                  'Dismissed/Ignored',
                  dismissedCount,
                  5,
                  dismissedCount >= 5,
                  Colors.orange,
                  isDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _classCountChip(
    BuildContext context,
    String label,
    int count,
    int required,
    bool met,
    Color color,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.all(DesignSystem.spacingM),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(DesignSystem.radiusM),
        border: Border.all(
          color: met ? color.withValues(alpha: 0.3) : Colors.orange.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            met ? Icons.check_circle : Icons.warning_amber_rounded,
            size: 18,
            color: met ? color : Colors.orange,
          ),
          const SizedBox(width: DesignSystem.spacingS),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: DesignSystem.caption(context).copyWith(
                    color: isDark ? Colors.white60 : Colors.grey.shade600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '$count / $required min',
                  style: DesignSystem.labelLarge(context).copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}