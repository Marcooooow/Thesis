import 'package:flutter/material.dart';
import 'package:intellibreak/core/design_system.dart';

/// Stepper widget showing the recommendation pipeline stages
class MLRecommendationPipelineStepper extends StatelessWidget {
  final Map<String, dynamic>? pipelineData;

  const MLRecommendationPipelineStepper({
    super.key,
    this.pipelineData,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final double width = MediaQuery.of(context).size.width;
    final bool isCompact = width < 600;

    final steps = [
      _PipelineStep(
        title: 'Feature\nExtraction',
        subtitle: pipelineData?['feature_extraction']?['status'] ?? 'Complete',
        value: pipelineData?['feature_extraction']?['details'] ?? 'Session length, time since break, completion rate, focus rate, preferences',
        icon: Icons.analytics,
        color: Colors.blue,
        isComplete: true,
      ),
      _PipelineStep(
        title: 'Candidate\nGeneration',
        subtitle: pipelineData?['candidate_generation']?['status'] ?? 'Complete',
        value: '${pipelineData?['candidate_generation']?['count'] ?? 5} candidates',
        icon: Icons.filter_list,
        color: Colors.purple,
        isComplete: true,
      ),
      _PipelineStep(
        title: 'Heuristic\nScoring',
        subtitle: pipelineData?['scoring']?['status'] ?? 'Complete',
        value: pipelineData?['scoring']?['details'] ?? 'Rule-based ranking',
        icon: Icons.score,
        color: Colors.orange,
        isComplete: true,
      ),
      _PipelineStep(
        title: 'Model\nInference',
        subtitle: pipelineData?['inference']?['status'] ?? 'Cold-start baseline',
        value: pipelineData?['inference']?['details'] ?? 'LogisticRegression or baseline',
        icon: Icons.psychology,
        color: Colors.green,
        isComplete: pipelineData?['inference']?['is_ml'] == true,
      ),
      _PipelineStep(
        title: 'Final\nRanking',
        subtitle: pipelineData?['ranking']?['status'] ?? 'Complete',
        value: 'Top ${pipelineData?['ranking']?['top_k'] ?? 3} recommendations',
        icon: Icons.leaderboard,
        color: Colors.teal,
        isComplete: true,
      ),
    ];

    if (isCompact) {
      return _buildVerticalStepper(context, isDark, steps);
    }
    return _buildHorizontalStepper(context, isDark, steps);
  }

  Widget _buildHorizontalStepper(
    BuildContext context,
    bool isDark,
    List<_PipelineStep> steps,
  ) {
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
            'Recommendation Pipeline',
            style: DesignSystem.title(context).copyWith(
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: DesignSystem.spacingL),
          Row(
            children: List.generate(steps.length, (index) {
              final step = steps[index];
              final isLast = index == steps.length - 1;

              return Expanded(
                child: Row(
                  children: [
                    _buildStepNode(context, isDark, step, index),
                    if (!isLast)
                      Expanded(
                        child: _buildConnector(context, isDark, step.isComplete),
                      ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildVerticalStepper(
    BuildContext context,
    bool isDark,
    List<_PipelineStep> steps,
  ) {
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
            'Recommendation Pipeline',
            style: DesignSystem.title(context).copyWith(
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: DesignSystem.spacingL),
          ...List.generate(steps.length, (index) {
            final step = steps[index];
            final isLast = index == steps.length - 1;

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    _buildVerticalStepNode(context, isDark, step, index),
                    if (!isLast)
                      _buildVerticalConnector(context, isDark, step.isComplete),
                  ],
                ),
                const SizedBox(width: DesignSystem.spacingM),
                Expanded(
                  child: _buildVerticalStepContent(context, isDark, step),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildStepNode(
    BuildContext context,
    bool isDark,
    _PipelineStep step,
    int index,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: step.isComplete
                ? step.color.withValues(alpha: 0.15)
                : isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade100,
            shape: BoxShape.circle,
            border: Border.all(
              color: step.isComplete ? step.color : (isDark ? Colors.grey.shade600 : Colors.grey.shade300),
              width: 2,
            ),
          ),
          child: Icon(
            step.isComplete ? Icons.check : step.icon,
            size: 20,
            color: step.isComplete ? step.color : (isDark ? Colors.white60 : Colors.grey.shade600),
          ),
        ),
        const SizedBox(height: DesignSystem.spacingXS),
        Text(
          step.title,
          style: DesignSystem.caption(context).copyWith(
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
            height: 1.2,
          ),
          textAlign: TextAlign.center,
        ),
        Text(
          step.subtitle,
          style: DesignSystem.caption(context).copyWith(
            fontSize: 10,
            color: step.isComplete
                ? (isDark ? Colors.green.shade300 : Colors.green.shade700)
                : (isDark ? Colors.orange.shade300 : Colors.orange.shade700),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: DesignSystem.spacingXS),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 80),
          child: Text(
            step.value,
            style: DesignSystem.caption(context).copyWith(
              fontSize: 9,
              color: isDark ? Colors.white54 : Colors.grey.shade500,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildConnector(BuildContext context, bool isDark, bool isComplete) {
    return Container(
      height: 2,
      margin: const EdgeInsets.only(top: 19),
      decoration: BoxDecoration(
        color: isComplete
            ? (isDark ? Colors.green.withValues(alpha: 0.5) : Colors.green.withValues(alpha: 0.3))
            : (isDark ? Colors.grey.withValues(alpha: 0.3) : Colors.grey.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }

  Widget _buildVerticalStepNode(
    BuildContext context,
    bool isDark,
    _PipelineStep step,
    int index,
  ) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: step.isComplete
            ? step.color.withValues(alpha: 0.15)
            : isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade100,
        shape: BoxShape.circle,
        border: Border.all(
          color: step.isComplete ? step.color : (isDark ? Colors.grey.shade600 : Colors.grey.shade300),
          width: 2,
        ),
      ),
      child: Icon(
        step.isComplete ? Icons.check : step.icon,
        size: 14,
        color: step.isComplete ? step.color : (isDark ? Colors.white60 : Colors.grey.shade600),
      ),
    );
  }

  Widget _buildVerticalConnector(BuildContext context, bool isDark, bool isComplete) {
    return Container(
      width: 2,
      height: 36,
      margin: const EdgeInsets.only(left: 11),
      decoration: BoxDecoration(
        color: isComplete
            ? (isDark ? Colors.green.withValues(alpha: 0.5) : Colors.green.withValues(alpha: 0.3))
            : (isDark ? Colors.grey.withValues(alpha: 0.3) : Colors.grey.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }

  Widget _buildVerticalStepContent(
    BuildContext context,
    bool isDark,
    _PipelineStep step,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignSystem.spacingL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            step.title.replaceAll('\n', ' '),
            style: DesignSystem.label(context).copyWith(
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: DesignSystem.spacingXXS),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: step.isComplete
                      ? (isDark ? Colors.green.withValues(alpha: 0.15) : Colors.green.withValues(alpha: 0.1))
                      : (isDark ? Colors.orange.withValues(alpha: 0.15) : Colors.orange.withValues(alpha: 0.1)),
                  borderRadius: BorderRadius.circular(DesignSystem.radiusXS),
                ),
                child: Text(
                  step.subtitle,
                  style: DesignSystem.caption(context).copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: step.isComplete
                        ? (isDark ? Colors.green.shade300 : Colors.green.shade700)
                        : (isDark ? Colors.orange.shade300 : Colors.orange.shade700),
                  ),
                ),
              ),
              const SizedBox(width: DesignSystem.spacingS),
              Expanded(
                child: Text(
                  step.value,
                  style: DesignSystem.caption(context).copyWith(
                    color: isDark ? Colors.white60 : Colors.grey.shade600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PipelineStep {
  final String title;
  final String subtitle;
  final String value;
  final IconData icon;
  final Color color;
  final bool isComplete;

  _PipelineStep({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.icon,
    required this.color,
    required this.isComplete,
  });
}