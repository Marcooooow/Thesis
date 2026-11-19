import 'package:flutter/material.dart';
import '../models/wellbeing_models.dart';

class RiskTierBadge extends StatelessWidget {
  final RiskTier riskTier;
  final String? customLabel;
  final bool compact;

  const RiskTierBadge({
    super.key,
    required this.riskTier,
    this.customLabel,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final label = customLabel ?? riskTier.label;
    final color = riskTier.color;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: compact ? 4 : 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: compact ? 12 : 13,
            ),
          ),
        ],
      ),
    );
  }
}
