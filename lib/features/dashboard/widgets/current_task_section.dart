import 'package:flutter/material.dart';

class CurrentTaskSection extends StatelessWidget {
  const CurrentTaskSection({super.key});

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
              Icons.work_outlined,
              size: 24,
              color: Theme.of(context).colorScheme.secondary,
            ),
            const SizedBox(width: 12),
            Text(
              'Current Task',
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

        // Current task card
        _buildTaskCard(
          context: context,
          title: 'IntelliBreak UI Redesign',
          description: 'Implementing new dashboard interface with accessibility improvements',
          duration: '2h 15m',
          progress: 0.65,
          status: 'in-progress',
          isDark: isDark,
          isHighContrast: isHighContrast,
        ),
        const SizedBox(height: 16),

        // Quick actions
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                context: context,
                label: 'Take Break',
                icon: Icons.timelapse_outlined,
                color: Colors.orange,
                isDark: isDark,
                isHighContrast: isHighContrast,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionButton(
                context: context,
                label: 'Mark Complete',
                icon: Icons.check_circle_outline,
                color: Colors.green,
                isDark: isDark,
                isHighContrast: isHighContrast,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTaskCard({
    required BuildContext context,
    required String title,
    required String description,
    required String duration,
    required double progress,
    required String status,
    required bool isDark,
    required bool isHighContrast,
  }) {
    // Status colors and icons
    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (status) {
      case 'in-progress':
        statusColor = Colors.blue;
        statusIcon = Icons.play_circle_outline;
        statusText = 'In Progress';
        break;
      case 'completed':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusText = 'Completed';
        break;
      case 'pending':
        statusColor = Colors.grey;
        statusIcon = Icons.pending_actions_outlined;
        statusText = 'Pending';
        break;
      case 'review':
        statusColor = Colors.orange;
        statusIcon = Icons.edit_outlined;
        statusText = 'In Review';
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.circle_outlined;
        statusText = 'Unknown';
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? (isHighContrast ? const Color(0xFF0D0D0D) : Color(0xFF1A1A1A))
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? (isHighContrast
                    ? Colors.white.withValues(alpha: 0.1)
                    : Color(0xFF2D3643))
              : Color(0xFFD3D9E1),
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Task header
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? (isHighContrast
                                  ? Colors.white
                                  : Color(0xFFE8EBEF))
                            : Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark
                            ? (isHighContrast
                                  ? Colors.white.withValues(alpha: 0.8)
                                  : Color(0xFF9AA3AF))
                            : Color(0xFF5B6472),
                      ),
                    ),
                  ],
                ),
              ),
              // Status indicator (icon + label + color for accessibility)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
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
          const SizedBox(height: 16),

          // Progress bar
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  'Progress:',
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
                            width: constraints.maxWidth * progress,
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

          // Progress text and duration
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${(progress * 100).round()}%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isDark
                      ? (isHighContrast ? Colors.white : Color(0xFF9AA3AF))
                      : Color(0xFF5B6472),
                ),
              ),
              Text(
                duration,
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
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required BuildContext context,
    required String label,
    required IconData icon,
    required Color color,
    required bool isDark,
    required bool isHighContrast,
  }) {
    return ElevatedButton.icon(
      onPressed: () {},
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: isDark ? Colors.white : Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      icon: Icon(icon, size: 20),
      label: Text(
        label,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
  }
}
