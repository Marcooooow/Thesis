import 'package:flutter/material.dart';

class WorkSessionSummary extends StatelessWidget {
  final Map<String, dynamic>? workSessionSummary;
  final bool isDark;
  final bool isHighContrast;

  const WorkSessionSummary({
    super.key,
    required this.workSessionSummary,
    required this.isDark,
    required this.isHighContrast,
  });

  @override
  Widget build(BuildContext context) {
    final Color textColor = isDark ? (isHighContrast ? Colors.white : const Color(0xFFF2F2F2)) : const Color(0xFF171923);
    final Color labelColor = isDark ? (isHighContrast ? Colors.white.withValues(alpha: 0.8) : const Color(0xFFF2F2F2).withValues(alpha: 0.8)) : const Color(0xFF6B7280);

    return SizedBox(
      width: double.infinity,
      child: Container(
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
            Text('Work Session Summary', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: -0.3, color: textColor)),
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
                  Text('Data not available', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: labelColor)),
                  const SizedBox(height: 4),
                  Text('Organization-level session summaries (completed sessions, average duration) are not provided by the current analytics endpoints.', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: labelColor)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
