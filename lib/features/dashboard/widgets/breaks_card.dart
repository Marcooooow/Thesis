import 'package:flutter/material.dart';
import 'package:intellibreak/core/motion.dart';
import 'package:intellibreak/providers/work_session_provider.dart';
import 'package:intellibreak/providers/work_session_models.dart';
import 'package:provider/provider.dart';
import 'package:intellibreak/widgets/state_display.dart';

/// Simplified card that displays active break monitoring, overdue alerts,
/// extensions, and break history without redundant availability status cards.
class BreaksCard extends StatelessWidget {
  const BreaksCard({super.key});

  @override
  Widget build(BuildContext context) {
    final sessionProvider = Provider.of<WorkSessionProvider>(context);
    final state = sessionProvider.state;

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast =
        Theme.of(context).colorScheme.brightness == Brightness.dark &&
        Theme.of(context).dividerTheme.color ==
            Colors.white.withValues(alpha: 0.15) &&
        Theme.of(context).dividerTheme.thickness == 2;

    final bool isEmpty = !state.isActive && state.completedBreaks.isEmpty && !state.isOnBreak;

    return StateDisplay(
      isLoading: state.isLoading,
      errorMessage: state.lastError,
      isEmpty: isEmpty,
      content: _buildBreaksCardContent(context, sessionProvider, state, isDark, isHighContrast),
      onRetry: () => sessionProvider.refresh(),
      loadingMessage: 'Loading break information...',
      emptyMessage: 'No break data available',
      emptyAction: ElevatedButton(
        onPressed: () {},
        child: const Text('Start a shift'),
      ),
    );
  }

  Widget _buildBreaksCardContent(
      BuildContext context,
      WorkSessionProvider sessionProvider,
      WorkSessionState state,
      bool isDark,
      bool isHighContrast) {
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? (isHighContrast
                  ? const Color(0xFF0D0D0D)
                  : const Color(0xFF151A21))
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? (isHighContrast
                    ? Colors.white.withValues(alpha: 0.3)
                    : const Color(0xFF262D37))
              : const Color(0xFFE2E6EB),
        ),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.timelapse_outlined,
                size: 24,
                color: Theme.of(context).colorScheme.secondary,
              ),
              const SizedBox(width: 12),
              Text(
                'Break Management',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark
                      ? (isHighContrast ? Colors.white : const Color(0xFFE8EBEF))
                      : const Color(0xFF111827),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (state.isOnBreak && state.activeBreak != null)
            DelayedAnimatedSection(
              visible: true,
              delay: Duration.zero,
              duration: MotionDurations.component,
              slideDirection: SlideDirection.topToBottom,
              child: _buildActiveBreakSection(context, state.activeBreak!, isDark, isHighContrast),
            ),
          if (state.isOnBreak) const SizedBox(height: 20),
          if (state.completedBreaks.isNotEmpty)
            DelayedAnimatedSection(
              visible: true,
              delay: state.isOnBreak ? MotionDurations.stagger : Duration.zero,
              duration: MotionDurations.component,
              slideDirection: SlideDirection.topToBottom,
              child: _buildBreakHistorySection(context, state, isDark, isHighContrast),
            )
          else
            DelayedAnimatedSection(
              visible: true,
              delay: state.isOnBreak ? MotionDurations.stagger : Duration.zero,
              duration: MotionDurations.component,
              slideDirection: SlideDirection.topToBottom,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    state.isOnBreak ? 'No completed breaks yet today' : 'No breaks recorded during this session',
                    style: TextStyle(
                      color: isDark
                          ? (isHighContrast
                                ? Colors.white.withValues(alpha: 0.7)
                                : const Color(0xFF9AA3AF))
                          : const Color(0xFF5B6472),
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActiveBreakSection(
    BuildContext context,
    WorkBreak activeBreak,
    bool isDark,
    bool isHighContrast,
  ) {
    final sessionProvider = Provider.of<WorkSessionProvider>(context, listen: false);
    final elapsedMinutes = DateTime.now().difference(activeBreak.startedAt).inMinutes;

    int thresholdMinutes = 15;
    if (activeBreak.type == BreakType.lunch || activeBreak.type == BreakType.meal) {
      thresholdMinutes = 30;
    } else if (activeBreak.type == BreakType.other) {
      thresholdMinutes = 60;
    }

    final bool isOverdue = elapsedMinutes > thresholdMinutes;
    final bool isApproaching = !isOverdue && elapsedMinutes >= (thresholdMinutes - 3);

    Color bannerColor = Colors.blue;
    String alertTitle = 'Currently on ${activeBreak.type.label}';
    String alertSubtitle = 'Elapsed: ${elapsedMinutes}m (${thresholdMinutes}m scheduled)';

    if (isOverdue) {
      bannerColor = Colors.orange;
      alertTitle = 'Over${activeBreak.type == BreakType.lunch || activeBreak.type == BreakType.meal ? 'meal' : activeBreak.type == BreakType.other ? 'away' : 'break'} Exceeded (${elapsedMinutes}m / ${thresholdMinutes}m)';
      alertSubtitle = 'Duration exceeded. Please resume work or record an extension.';
    } else if (isApproaching) {
      bannerColor = Colors.amber;
      alertTitle = '${activeBreak.type.label} Ending Soon';
      alertSubtitle = '${thresholdMinutes - elapsedMinutes}m remaining before scheduled duration.';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? (isHighContrast ? const Color(0xFF1A1A1A) : const Color(0xFF2A2D3A))
            : bannerColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: bannerColor.withValues(alpha: 0.5),
          width: isOverdue ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                activeBreak.type.icon,
                size: 32,
                color: bannerColor,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      alertTitle,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? (isHighContrast ? Colors.white : const Color(0xFFE8EBEF))
                            : const Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      alertSubtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark
                            ? (isHighContrast
                                  ? Colors.white.withValues(alpha: 0.7)
                                  : const Color(0xFF9AA3AF))
                            : const Color(0xFF5B6472),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: bannerColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  isOverdue ? 'OVERDUE' : 'ON BREAK',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: bannerColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: () => sessionProvider.endBreak(),
                icon: const Icon(Icons.play_arrow_outlined, size: 16),
                label: const Text('Resume Work'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _showExtensionDialog(context, sessionProvider),
                icon: const Icon(Icons.schedule_outlined, size: 16),
                label: const Text('Record Extension'),
              ),
              if (activeBreak.type == BreakType.other)
                OutlinedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Away period extended / maintained as Still Away.')),
                    );
                  },
                  icon: const Icon(Icons.access_time_outlined, size: 16),
                  label: const Text('Still Away'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _showExtensionDialog(BuildContext context, WorkSessionProvider sessionProvider) {
    final TextEditingController reasonController = TextEditingController();
    int selectedExtension = 15;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Record Break Extension'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Select extension duration:'),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              value: selectedExtension,
              items: const [
                DropdownMenuItem(value: 5, child: Text('+5 minutes')),
                DropdownMenuItem(value: 10, child: Text('+10 minutes')),
                DropdownMenuItem(value: 15, child: Text('+15 minutes')),
                DropdownMenuItem(value: 30, child: Text('+30 minutes')),
              ],
              onChanged: (val) {
                if (val != null) selectedExtension = val;
              },
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                hintText: 'e.g. Cafeteria queue, stretching routine',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await sessionProvider.extendBreak(
                  extensionMinutes: selectedExtension,
                  reason: reasonController.text.trim().isNotEmpty
                      ? reasonController.text.trim()
                      : null,
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Break extended by $selectedExtension minutes.')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to extend break: $e')),
                  );
                }
              }
            },
            child: const Text('Confirm Extension'),
          ),
        ],
      ),
    );
  }

  Widget _buildBreakHistorySection(
    BuildContext context,
    WorkSessionState state,
    bool isDark,
    bool isHighContrast,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Break History',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: isDark
                ? (isHighContrast ? Colors.white : const Color(0xFFE8EBEF))
                : const Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 12),
        ...state.completedBreaks.map((breakItem) => _buildBreakHistoryItem(
              context: context,
              breakItem: breakItem,
              isDark: isDark,
              isHighContrast: isHighContrast,
            )),
      ],
    );
  }

  Widget _buildBreakHistoryItem({
    required BuildContext context,
    required WorkBreak breakItem,
    required bool isDark,
    required bool isHighContrast,
  }) {
    final startTime = _formatTime(breakItem.startedAt);
    final endTime = breakItem.endedAt != null
        ? _formatTime(breakItem.endedAt!)
        : '--:--';
    final duration = breakItem.endedAt != null
        ? '${breakItem.endedAt!.difference(breakItem.startedAt).inMinutes}m'
        : '--';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark
              ? (isHighContrast
                    ? const Color(0xFF0D0D0D)
                    : const Color(0xFF151A21))
              : Colors.grey.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDark
                ? (isHighContrast
                      ? Colors.white.withValues(alpha: 0.1)
                      : const Color(0xFF262D37))
                : const Color(0xFFE2E6EB),
          ),
        ),
        child: Row(
          children: [
            Icon(
              breakItem.type.icon,
              size: 20,
              color: isDark
                  ? (isHighContrast
                        ? Colors.white.withValues(alpha: 0.7)
                        : const Color(0xFF9AA3AF))
                  : const Color(0xFF5B6472),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    breakItem.type.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isDark
                          ? (isHighContrast ? Colors.white : const Color(0xFFE8EBEF))
                          : const Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$startTime - $endTime',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? (isHighContrast
                                ? Colors.white.withValues(alpha: 0.6)
                                : const Color(0xFF9AA3AF))
                          : const Color(0xFF5B6472),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                duration,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
