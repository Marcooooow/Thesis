import 'package:flutter/material.dart';

class WeeklyWorkHoursChart extends StatelessWidget {
  final List<Map<String, dynamic>> weeklyWorkHours;
  final bool isDark;
  final bool isHighContrast;

  const WeeklyWorkHoursChart({
    super.key,
    required this.weeklyWorkHours,
    required this.isDark,
    required this.isHighContrast,
  });

  @override
  Widget build(BuildContext context) {
    if (weeklyWorkHours.isEmpty) {
      return const Center(child: Text('No work hours data available'));
    }

    double maxHours = 0.0;
    for (final day in weeklyWorkHours) {
      final actual = (day['actualHours'] as num?)?.toDouble() ?? 0.0;
      if (actual > maxHours) maxHours = actual;
    }
    maxHours = (maxHours * 1.15).ceilToDouble();
    if (maxHours < 8) maxHours = 8;

    final Color barColor = isDark ? (isHighContrast ? Colors.white : const Color(0xFF6C63FF)) : const Color(0xFF6C63FF);
    final Color targetColor = isDark ? (isHighContrast ? Colors.white.withValues(alpha: 0.5) : const Color(0xFFF2F2F2).withValues(alpha: 0.5)) : const Color(0xFF6B7280).withValues(alpha: 0.3);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Weekly Work Hours', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: -0.3, color: isDark ? (isHighContrast ? Colors.white : const Color(0xFFF2F2F2)) : const Color(0xFF171923))),
        const SizedBox(height: 12),
        // Chart: fixed total height 260px, Expanded plotting area
        SizedBox(
          height: 260,
          child: Column(
            children: [
              // Chart bars + labels area expands to fill available space
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: weeklyWorkHours.map((dayData) {
                    final name = (dayData['day'] as String?) ?? '';
                    final actualHours = (dayData['actualHours'] as num?)?.toDouble() ?? 0.0;

                    final barHeightRatio = maxHours > 0 ? actualHours / maxHours : 0.0;

                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            // Bar area takes remaining space inside Expanded column
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  // Actual bar
                                  Container(
                                    width: 20,
                                    height: 60 * barHeightRatio,
                                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: barColor),
                                  ),
                                  const SizedBox(height: 2),
                                  // Target line marker at fixed height
                                  Container(
                                    width: 20,
                                    height: 2,
                                    color: targetColor,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            // Day label at bottom
                            Text(
                              name.length > 3 ? name.substring(0, 3) : name,
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, letterSpacing: -0.1, color: isDark ? (isHighContrast ? Colors.white : const Color(0xFFF2F2F2)) : const Color(0xFF6B7280)),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              // Legend row: fixed, does not expand
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(children: [Container(width: 12, height: 12, decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: barColor)), const SizedBox(width: 4), const Text('Actual Hours', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, letterSpacing: -0.1))]),
                    const SizedBox(width: 16),
                    Row(children: [Container(width: 12, height: 12, decoration: BoxDecoration(border: Border.all(color: targetColor, width: 1))), const SizedBox(width: 4), const Text('Target Hours', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, letterSpacing: -0.1))]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
