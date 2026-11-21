import 'package:flutter/material.dart';

class WorkTimeCard extends StatelessWidget {
  const WorkTimeCard({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast =
        Theme.of(context).colorScheme.brightness == Brightness.dark &&
        Theme.of(context).dividerTheme.color ==
            Colors.white.withValues(alpha: 0.15) &&
        Theme.of(context).dividerTheme.thickness == 2;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? (isHighContrast
                  ? const Color(0xFF0D0D0D)
                  : const Color(0xFF182029))
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? (isHighContrast
                    ? Colors.white.withValues(alpha: 0.3)
                    : const Color(0xFF2D3643))
              : const Color(0xFFD3D9E1),
        ),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with icon + label pattern (accessibility)
          Row(
            children: [
              Icon(
                Icons.access_time_outlined,
                size: 24,
                color: Theme.of(context).colorScheme.secondary,
              ),
              const SizedBox(width: 12),
              Text(
                'Work Time',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark
                      ? (isHighContrast ? Colors.white : Color(0xFFE8EBEF))
                      : Color(0xFF111827),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Main value
          Text(
            '03:42:00',
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.bold,
              color: isDark
                  ? (isHighContrast ? Colors.white : Color(0xFFE8EBEF))
                  : Color(0xFF111827),
            ),
          ),

          const SizedBox(height: 16),

          // Progress bar
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  'Today\'s Target:',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? (isHighContrast ? Colors.white : Color(0xFF9AA3AF))
                        : Color(0xFF5B6472),
                  ),
                ),
              ),
              Expanded(
                flex: 7,
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: isDark
                        ? (isHighContrast
                              ? Color(0xFF1A1A1A)
                              : Color(0xFF2A2D3A))
                        : Color(0xFFF0F0F0),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Stack(
                        children: [
                          Container(
                            width: constraints.maxWidth * 0.45, // 45% of target
                            height: 8,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.secondary,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Progress text
          Text(
            '3.6 | 8.0 hours',
            style: TextStyle(
              fontSize: 12,
              color: isDark
                  ? (isHighContrast
                        ? Colors.white.withValues(alpha: 0.7)
                        : Color(0xFF9AA3AF))
                  : Color(0xFF9CA3AF),
            ),
          ),
        ],
      ),
    );
  }
}
