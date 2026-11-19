import 'package:flutter/material.dart';
import 'package:intellibreak/core/design_system.dart';
import 'package:intellibreak/features/dashboard/providers/break_coach_state.dart';
import 'package:intellibreak/features/shift_logs/widgets/recommendation_history_dialog.dart';
import 'package:provider/provider.dart';

/// Personalized Recommendations & History widget for Employee Personalized Dashboard.
/// Displays active recommendations, explanations, feedback actions, and opens history dialog.
class RecommendationSummaryCard extends StatelessWidget {
  const RecommendationSummaryCard({super.key});

  @override
  Widget build(BuildContext context) {
    final breakCoachState = context.watch<BreakCoachState>();
    final rec = breakCoachState.currentRecommendation;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DesignSystem.premiumCard(
      context: context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lightbulb_outline,
                size: 22,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Text(
                'Personalized Recommendations',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                  color: isDark ? Colors.white : const Color(0xFF171923),
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => const RecommendationHistoryDialog(
                      workSessionId: 'current',
                      sessionLabel: 'Today\'s Recommendation History',
                    ),
                  );
                },
                icon: const Icon(Icons.history, size: 16),
                label: const Text('View History'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (rec != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.psychology_outlined, size: 20, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        rec.title.isNotEmpty ? rec.title : 'Suggested Break',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    rec.reason,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.4,
                      color: isDark ? Colors.white70 : const Color(0xFF4B5563),
                    ),
                  ),
                  if (rec.recommendationMethod != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            rec.recommendationMethod == 'ml_enhanced'
                                ? 'Method: ML-Enhanced'
                                : (rec.recommendationMethod == 'heuristic_fallback'
                                    ? 'Method: Heuristic Fallback'
                                    : 'Method: Heuristic Baseline'),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF121218) : const Color(0xFFF8F8FB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, size: 20, color: Colors.green.shade600),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'No pending recommendations. Your current work rhythm is well-paced.',
                      style: TextStyle(
                        fontSize: 13.5,
                        color: isDark ? Colors.white70 : const Color(0xFF6B7280),
                      ),
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
