import 'package:flutter/material.dart';
import 'package:intellibreak/core/design_system.dart';
import 'package:intellibreak/features/dashboard/models/break_coach_models.dart';
import 'package:intellibreak/core/motion.dart';

/// Break Coach compact notification alert banner
///
/// Displays a non-intrusive, temporary notification alert without duplicating
/// the full narrative explanation in the persistent AI Wellness Coach card.
class BreakCoachNotification extends StatelessWidget {
  final BreakCoachRecommendation? recommendation;
  final String? elapsedText;
  final VoidCallback onTakeBreak;
  final VoidCallback onTakeLunch;
  final VoidCallback onSnooze;
  final VoidCallback onIgnore;
  final VoidCallback onContinue;
  final VoidCallback onClose;
  final bool visible;

  const BreakCoachNotification({
    super.key,
    required this.recommendation,
    this.elapsedText,
    required this.onTakeBreak,
    required this.onTakeLunch,
    required this.onSnooze,
    required this.onIgnore,
    required this.onContinue,
    required this.onClose,
    this.visible = true,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = _getHighContrastFromContext(context);
    return Material(
      color: Colors.transparent,
      child: Center(
        child: SingleChildScrollView(
          child: AnimatedSection(
            visible: visible,
            duration: MotionDurations.modal,
            slideDirection: SlideDirection.bottomToTop,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: DesignSystem.premiumCard(
                  context: context,
                  child: _buildContent(context, isDark, isHighContrast),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _getHighContrastFromContext(BuildContext context) {
    final divider = Theme.of(context).dividerTheme;
    return divider.thickness == 2.0 &&
        divider.color != null && divider.color == Colors.white;
  }

  Widget _buildContent(
    BuildContext context,
    bool isDark,
    bool isHighContrast,
  ) {
    final String title = recommendation?.title ?? 'Wellness Break Recommended';

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6.0),
                decoration: BoxDecoration(
                  color: const Color(0x1A0062FF),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.psychology_alt_outlined,
                  size: 20,
                  color: DesignSystem.getSemanticColor(
                    context,
                    SemanticColor.info,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Break Coach Alert',
                      style: DesignSystem.label(context).copyWith(
                        fontWeight: FontWeight.w600,
                        color: DesignSystem.getSemanticColor(
                          context,
                          SemanticColor.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      style: DesignSystem.title(context).copyWith(
                        fontWeight: FontWeight.w600,
                        color: DesignSystem.getSemanticColor(
                          context,
                          SemanticColor.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.close,
                  size: 18,
                  color: DesignSystem.getSemanticColor(
                    context,
                    SemanticColor.onSurfaceVariant,
                  ),
                ),
                onPressed: onClose,
                padding: const EdgeInsets.all(4.0),
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Action buttons
          Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            children: [
              if (recommendation?.trigger == BreakCoachTrigger.breakDurationExceeded ||
                  recommendation?.trigger == BreakCoachTrigger.lunchDurationExceeded)
                DesignSystem.secondaryButton(
                  context: context,
                  label: 'Dismiss reminder',
                  onPressed: onClose,
                )
              else if (recommendation?.type == BreakCoachRecommendationType.lunch)
                DesignSystem.primaryButton(
                  context: context,
                  label: 'Take Meal',
                  icon: Icons.restaurant_outlined,
                  onPressed: onTakeLunch,
                  width: double.infinity,
                )
              else
                DesignSystem.primaryButton(
                  context: context,
                  label: 'Take Break',
                  icon: Icons.timer_outlined,
                  onPressed: onTakeBreak,
                  width: double.infinity,
                ),
              if (!(recommendation?.trigger == BreakCoachTrigger.breakDurationExceeded ||
                  recommendation?.trigger == BreakCoachTrigger.lunchDurationExceeded))
                DesignSystem.secondaryButton(
                  context: context,
                  label: 'Snooze 5 min',
                  icon: Icons.schedule_outlined,
                  onPressed: onSnooze,
                ),
              if (!(recommendation?.trigger == BreakCoachTrigger.breakDurationExceeded ||
                  recommendation?.trigger == BreakCoachTrigger.lunchDurationExceeded))
                DesignSystem.textButton(
                  context: context,
                  label: 'Dismiss',
                  onPressed: onContinue,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
