import 'package:flutter/material.dart';

class BreakAnalytics extends StatelessWidget {
  final int activeBreaksCount;
  final bool isDark;
  final bool isHighContrast;

  const BreakAnalytics({
    super.key,
    required this.activeBreaksCount,
    required this.isDark,
    required this.isHighContrast,
  });

  @override
  Widget build(BuildContext context) {
    final Color textColor = isDark ? (isHighContrast ? Colors.white : const Color(0xFFE8EBEF)) : const Color(0xFF111827);
    final Color labelColor = isDark ? (isHighContrast ? Colors.white.withValues(alpha: 0.8) : const Color(0xFFE8EBEF).withValues(alpha: 0.8)) : const Color(0xFF5B6472);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
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
        children: [
          Text('Break Analytics', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: -0.3, color: textColor)),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
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
              children: [
                Text('Currently on Break', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: -0.2, color: labelColor)),
                const SizedBox(height: 8),
                Text(activeBreaksCount.toString(), style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: -0.5, color: textColor, fontFeatures: const [FontFeature.tabularFigures()])),
                const SizedBox(height: 4),
                Text('employees', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, letterSpacing: -0.1, color: labelColor)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}