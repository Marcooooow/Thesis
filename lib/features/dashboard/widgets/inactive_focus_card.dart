import 'package:flutter/material.dart';
import 'package:intellibreak/core/design_system.dart';

class InactiveFocusCard extends StatelessWidget {
  final String inactiveFocusTime;
  final String description;

  const InactiveFocusCard({
    super.key,
    required this.inactiveFocusTime,
    required this.description,
  });

  const InactiveFocusCard.demo()
    : inactiveFocusTime = '00:27:00',
      description = 'Light tasks & breaks',
      super(key: const Key('demo-inactive-focus-card'));

  @override
  Widget build(BuildContext context) {
    return DesignSystem.premiumCard(
      context: context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with icon + label pattern (accessibility)
          DesignSystem.sectionHeader(context, 'Idle Active', Icons.timer_off),
          const SizedBox(height: DesignSystem.spacingM),

          // Main value
          Text(
            inactiveFocusTime,
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
