import 'package:flutter/material.dart';
import 'package:intellibreak/core/design_system.dart';

class ActiveFocusCard extends StatelessWidget {
  final String activeFocusTime;
  final String description;

  const ActiveFocusCard({
    super.key,
    required this.activeFocusTime,
    required this.description,
  });

  const ActiveFocusCard.demo()
    : activeFocusTime = '03:15:00',
      description = 'Focused work time',
      super(key: const Key('demo-active-focus-card'));

  @override
  Widget build(BuildContext context) {
    return DesignSystem.premiumCard(
      context: context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with icon + label pattern (accessibility)
          DesignSystem.sectionHeader(
            context,
            'Active Focus',
            Icons.play_circle_outline,
          ),
          const SizedBox(height: DesignSystem.spacingM),

          // Main value
          Text(
            activeFocusTime,
            style: DesignSystem.titleXL(context).copyWith(
              fontWeight: FontWeight.bold,
              color: DesignSystem.getSemanticColor(
                context,
                SemanticColor.onSurface,
              ),
            ),
          ),

          if (description.isNotEmpty) ...[
            const SizedBox(height: DesignSystem.spacingM),
            Text(description, style: DesignSystem.body(context)),
          ],
        ],
      ),
    );
  }
}
