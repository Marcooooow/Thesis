import 'package:flutter/material.dart';

class TodaysFocusSection extends StatelessWidget {
  const TodaysFocusSection({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast =
        Theme.of(context).colorScheme.brightness == Brightness.dark &&
        Theme.of(context).dividerTheme.color ==
            Colors.white.withValues(alpha: 0.15) &&
        Theme.of(context).dividerTheme.thickness == 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with icon + label pattern (accessibility)
        Row(
          children: [
            Icon(
              Icons.feedback_outlined,
              size: 24,
              color: Theme.of(context).colorScheme.secondary,
            ),
            const SizedBox(width: 12),
            Text(
              'Today\'s Focus',
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
        const SizedBox(height: 16),

        // Focus activities
        _buildFocusActivity(
          context: context,
          icon: Icons.check_circle_outline,
          label: 'Deep Work Session',
          time: '09:00 - 11:00',
          status: 'completed',
        ),
        const SizedBox(height: 12),
        _buildFocusActivity(
          context: context,
          icon: Icons.pending_actions_outlined,
          label: 'Team Meeting',
          time: '11:30 - 12:00',
          status: 'upcoming',
        ),
        const SizedBox(height: 12),
        _buildFocusActivity(
          context: context,
          icon: Icons.check_circle_outline,
          label: 'Code Review',
          time: '13:00 - 14:30',
          status: 'completed',
        ),
        const SizedBox(height: 12),
        _buildFocusActivity(
          context: context,
          icon: Icons.pending_actions_outlined,
          label: 'Client Call',
          time: '15:00 - 15:30',
          status: 'upcoming',
        ),
      ],
    );
  }

  Widget _buildFocusActivity({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String time,
    required String status,
  }) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast =
        Theme.of(context).colorScheme.brightness == Brightness.dark &&
        Theme.of(context).dividerTheme.color ==
            Colors.white.withValues(alpha: 0.15) &&
        Theme.of(context).dividerTheme.thickness == 2;

    // Determine status colors and icons
    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (status) {
      case 'completed':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusText = 'Done';
        break;
      case 'upcoming':
        statusColor = Colors.blue;
        statusIcon = Icons.pending_actions;
        statusText = 'Upcoming';
        break;
      case 'in-progress':
        statusColor = Colors.orange;
        statusIcon = Icons.play_circle_outline;
        statusText = 'In Progress';
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.circle_outlined;
        statusText = 'Pending';
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? (isHighContrast ? const Color(0xFF0D0D0D) : Color(0xFF1A1A1A))
            : Colors.grey.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? (isHighContrast
                    ? Colors.white.withValues(alpha: 0.1)
                    : Color(0xFF2D3643))
              : Colors.grey.withValues(alpha: 0.2),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: isDark
                ? (isHighContrast
                      ? Colors.white.withValues(alpha: 0.8)
                      : Color(0xFF9AA3AF))
                : Color(0xFF5B6472),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? (isHighContrast ? Colors.white : Color(0xFFE8EBEF))
                        : Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  time,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark
                        ? (isHighContrast
                              ? Colors.white.withValues(alpha: 0.7)
                              : Color(0xFF9AA3AF))
                        : Color(0xFF5B6472),
                  ),
                ),
              ],
            ),
          ),
          // Status indicator (icon + label + color for accessibility)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: statusColor, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(statusIcon, size: 14, color: statusColor),
                const SizedBox(width: 4),
                Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
