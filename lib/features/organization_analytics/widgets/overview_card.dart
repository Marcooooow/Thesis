import 'package:flutter/material.dart';

class OverviewCard extends StatelessWidget {
  final String title;
  final dynamic value; // can be int, double, or String
  final String label;
  final bool isDark;
  final bool isHighContrast;

  const OverviewCard({
    super.key,
    required this.title,
    required this.value,
    required this.label,
    required this.isDark,
    required this.isHighContrast,
  });

  @override
  Widget build(BuildContext context) {
    // Determine the text color based on theme
    final Color textColor = isDark
        ? (isHighContrast ? Colors.white : const Color(0xFFE8EBEF))
        : const Color(0xFF111827);
    final Color labelColor = isDark
        ? (isHighContrast ? Colors.white.withValues(alpha: 0.8) : const Color(0xFFE8EBEF).withValues(alpha: 0.8))
        : const Color(0xFF5B6472);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
          width: 0.8,
        ),
        color: isDark ? const Color(0xFF121218) : const Color(0xFFF8F8FB),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.2,
              color: labelColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value.toString(),
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
              color: textColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              letterSpacing: -0.1,
              color: labelColor,
            ),
          ),
        ],
      ),
    );
  }
}