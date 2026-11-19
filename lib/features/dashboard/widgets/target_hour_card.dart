import 'package:flutter/material.dart';
import 'package:intellibreak/core/design_system.dart';

class TargetHourCard extends StatelessWidget {
  final String targetHour;
  final String description;

  const TargetHourCard({
    super.key,
    required this.targetHour,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return DesignSystem.premiumCard(
      context: context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with icon + label pattern (accessibility)
          DesignSystem.sectionHeader(context, 'Target Hour', Icons.access_time),
          const SizedBox(height: DesignSystem.spacingM),

          // Main value
          Text(
            targetHour,
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
