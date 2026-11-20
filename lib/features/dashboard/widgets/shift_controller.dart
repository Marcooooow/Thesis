import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intellibreak/core/theme/theme_controller.dart';
import 'package:intellibreak/core/motion.dart';
import 'package:intellibreak/providers/work_session_provider.dart';
import 'package:intellibreak/providers/work_session_models.dart';
import 'package:provider/provider.dart';
import 'package:intellibreak/core/error_handling.dart';
import 'package:intellibreak/core/design_system.dart';
import 'package:intellibreak/features/dashboard/services/work_service.dart';
import 'package:intellibreak/features/wellbeing/session_wellbeing_checkin.dart';
import 'package:intellibreak/features/dashboard/providers/break_coach_state.dart';
import 'package:intellibreak/core/app_confirmation_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Controller widget that manages shift and break actions.
/// Now consumes WorkSessionProvider as the single source of truth.
/// Break buttons show accurate availability states: Available, Active, Completed, Disabled.
class ShiftController extends StatefulWidget {
  final bool readOnly;
  final String? employeeName;
  final Map<String, dynamic>? liveStatus;

  const ShiftController({
    super.key,
    this.readOnly = false,
    this.employeeName,
    this.liveStatus,
  });

  @override
  State<ShiftController> createState() => _ShiftControllerState();
}

class _ShiftControllerState extends State<ShiftController> {
  Timer? _pollingTimer;
  Timer? _uiTimer;
  final String _instanceId = DateTime.now().millisecondsSinceEpoch.toString();
  final WorkService _workService = WorkService();
  WorkTask? _preShiftSelectedTask;

  WorkSessionState _getPreviewState() {
    final activeWorkSession =
        widget.liveStatus?['active_work_session'] as Map<String, dynamic>?;
    final activeBreakMap =
        widget.liveStatus?['active_break'] as Map<String, dynamic>?;
    final completedBreaksList =
        widget.liveStatus?['completed_breaks'] as List<dynamic>? ?? [];
    final tasksList = widget.liveStatus?['tasks'] as List<dynamic>? ?? [];

    if (activeWorkSession == null) {
      return const WorkSessionState();
    }

    final startTime = activeWorkSession['started_at'] != null
        ? DateTime.parse(activeWorkSession['started_at'])
        : null;
    final session = WorkSession(
      id: activeWorkSession['id']?.toString() ?? '',
      startedAt: startTime ?? DateTime.now(),
      endedAt: activeWorkSession['ended_at'] != null
          ? DateTime.parse(activeWorkSession['ended_at'])
          : null,
    );

    WorkBreak? activeBreak;
    if (activeBreakMap != null) {
      activeBreak = WorkBreak(
        id: activeBreakMap['id']?.toString() ?? '',
        workSessionId: session.id,
        type: BreakType.fromWire(
          activeBreakMap['break_type']?.toString().toUpperCase(),
        ),
        startedAt: activeBreakMap['started_at'] != null
            ? DateTime.parse(activeBreakMap['started_at'])
            : DateTime.now(),
        endedAt: activeBreakMap['ended_at'] != null
            ? DateTime.parse(activeBreakMap['ended_at'])
            : null,
        durationMinutes: activeBreakMap['duration_minutes'] as int?,
      );
    }

    final completedBreaks = completedBreaksList.map((b) {
      final map = b is Map<String, dynamic> ? b : <String, dynamic>{};
      return WorkBreak(
        id: map['id']?.toString() ?? '',
        workSessionId: session.id,
        type: BreakType.fromWire(map['break_type']?.toString().toUpperCase()),
        startedAt: map['started_at'] != null
            ? DateTime.parse(map['started_at'])
            : DateTime.now(),
        endedAt: map['ended_at'] != null
            ? DateTime.parse(map['ended_at'])
            : null,
        durationMinutes: map['duration_minutes'] as int?,
      );
    }).toList();

    final tasks = tasksList.map((t) {
      final map = t is Map<String, dynamic> ? t : <String, dynamic>{};
      return WorkTask(
        id: map['id']?.toString() ?? '',
        title: map['title']?.toString() ?? 'Task',
        category: map['category']?.toString() ?? 'Work',
        status: map['status']?.toString() ?? 'pending',
        workSessionId: map['work_session_id']?.toString(),
        startedAt: map['started_at'] != null
            ? DateTime.parse(map['started_at'])
            : null,
        endedAt: map['ended_at'] != null
            ? DateTime.parse(map['ended_at'])
            : null,
        actualMinutes: map['actual_minutes'] as int?,
      );
    }).toList();

    WorkTask? currentTask =
        tasks
            .where(
              (t) =>
                  t.status == 'in_progress' ||
                  (t.startedAt != null && t.endedAt == null),
            )
            .firstOrNull ??
        tasks.firstOrNull;

    return WorkSessionState(
      session: session,
      currentTask: currentTask,
      activeBreak: activeBreak,
      completedBreaks: completedBreaks,
      tasks: tasks,
    );
  }

  @override
  void initState() {
    super.initState();
    debugPrint('ShiftController[$_instanceId] initState');
    _startBreakCoachPolling();
    _startTickTimer();
  }

  @override
  void dispose() {
    debugPrint('ShiftController[$_instanceId] dispose');
    _stopBreakCoachPolling();
    _stopTickTimer();
    super.dispose();
  }

  void _startBreakCoachPolling() {
    if (_pollingTimer != null) return;
    _pollingTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      _checkBreakCoach();
    });
  }

  void _stopBreakCoachPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  void _startTickTimer() {
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _stopTickTimer() {
    _uiTimer?.cancel();
    _uiTimer = null;
  }

  Future<void> _checkBreakCoach() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null) return;

    if (!mounted) return;
    final sessionProvider = Provider.of<WorkSessionProvider>(
      context,
      listen: false,
    );

    // Only check recommendations when actively working (not on break)
    if (!sessionProvider.isActive || sessionProvider.isOnBreak) return;
    final breakCoachState = Provider.of<BreakCoachState>(
      context,
      listen: false,
    );
    await breakCoachState.checkRecommendation(token);
  }

  String _formatElapsedTimeFromStart(DateTime? startTime) {
    if (startTime == null) {
      return '00:00:00';
    }
    final elapsed = DateTime.now().difference(startTime).inSeconds;
    final h = elapsed ~/ 3600;
    final m = (elapsed % 3600) ~/ 60;
    final s = elapsed % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final themeController = Provider.of<ThemeController>(context);
    final sessionProvider = Provider.of<WorkSessionProvider>(context);
    final state = widget.readOnly ? _getPreviewState() : sessionProvider.state;

    debugPrint('[SHIFT_UI] sessionId=${state.session?.id}');
    debugPrint('[SHIFT_UI] isActive=${state.isActive}');
    debugPrint('[SHIFT_UI] startTime=${state.startTime}');
    debugPrint('[SHIFT_UI] currentTaskId=${state.currentTask?.id}');

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = themeController.isHighContrast;

    return Stack(
      children: [
        // Main shift controller UI
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.readOnly) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.visibility, size: 18, color: Colors.blue),
                    const SizedBox(width: 8),
                    Text(
                      'Read-Only Preview${widget.employeeName != null ? ' — ${widget.employeeName}' : ''}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // Header
            Row(
              children: [
                Icon(
                  Icons.timelapse_outlined,
                  size: 22,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                const SizedBox(width: 10),
                Text(
                  'Shift Controller',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark
                        ? (isHighContrast
                              ? Colors.white
                              : const Color(0xFFE8EBEF))
                        : const Color(0xFF111827),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: state.isActive
                        ? Colors.green.withValues(alpha: 0.15)
                        : Colors.grey.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: state.isActive ? Colors.green : Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        state.isActive ? 'Working — Active' : 'Shift Inactive',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: state.isActive ? Colors.green.shade700 : Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Large readable timer and current task display matching Figma
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF14151A) : const Color(0xFFF8F9FC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
                ),
              ),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SESSION TIMER',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                          color: isDark ? Colors.white54 : const Color(0xFF5B6472),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatElapsedTimeFromStart(state.startTime),
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                          color: isDark ? Colors.white : const Color(0xFF111827),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    height: 36,
                    width: 1,
                    color: isDark ? Colors.white24 : Colors.black12,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CURRENT TASK',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                            color: isDark ? Colors.white54 : const Color(0xFF5B6472),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          state.currentTask?.title ?? (_preShiftSelectedTask?.title ?? 'No active task selected'),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: (state.currentTask != null || _preShiftSelectedTask != null)
                                ? (isDark ? Colors.white : const Color(0xFF111827))
                                : (isDark ? Colors.white38 : const Color(0xFF9CA3AF)),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (!widget.readOnly)
              _buildTaskSelector(context, sessionProvider, state, isDark, isHighContrast),
            AnimatedSection(
              visible: true,
              duration: MotionDurations.component,
              slideDirection: SlideDirection.bottomToTop,
              child: widget.readOnly
                  ? _buildReadOnlyButtons(
                      context,
                      isDark,
                      isHighContrast,
                      state,
                    )
                  : (isDesktop(context)
                        ? _buildDesktopButtons(
                            context,
                            isDark,
                            isHighContrast,
                            sessionProvider,
                            state,
                          )
                        : _buildMobileButtons(
                            context,
                            isDark,
                            isHighContrast,
                            sessionProvider,
                            state,
                          )),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReadOnlyButtons(
    BuildContext context,
    bool isDark,
    bool isHighContrast,
    WorkSessionState state,
  ) {
    final meeting = state.meetingTask;
    final meetingActive = meeting != null && meeting.endedAt == null;

    final actions = [
      {
        'type': ControlType.startShift,
        'label': 'Start Shift',
        'active': state.isActive,
        'completed': state.session != null,
      },
      {
        'type': ControlType.break1,
        'label': 'Break 1',
        'active': state.activeBreak?.type == BreakType.break1,
        'completed': state.completedBreaks.any(
          (b) => b.type == BreakType.break1,
        ),
      },
      {
        'type': ControlType.break2,
        'label': 'Break 2',
        'active': state.activeBreak?.type == BreakType.break2,
        'completed': state.completedBreaks.any(
          (b) => b.type == BreakType.break2,
        ),
      },
      {
        'type': ControlType.lunch,
        'label': 'Lunch',
        'active': state.activeBreak?.type == BreakType.lunch,
        'completed': state.completedBreaks.any(
          (b) => b.type == BreakType.lunch,
        ),
      },
      {
        'type': ControlType.meeting,
        'label': meetingActive ? 'Meeting' : 'Meeting',
        'active': meetingActive,
        'completed': meeting != null && !meetingActive,
      },
      {
        'type': ControlType.endShift,
        'label': 'End Shift',
        'active': false,
        'completed': state.session?.endedAt != null,
      },
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: actions.map((action) {
        final type = action['type'] as ControlType;
        final isActive = action['active'] as bool;
        final isCompleted = action['completed'] as bool;
        return SizedBox(
          width: 125,
          height: 44,
          child: Opacity(
            opacity:
                (isActive ||
                    isCompleted ||
                    (!state.isActive && type == ControlType.startShift))
                ? 1.0
                : 0.65,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: isActive
                    ? Colors.green.withValues(alpha: 0.2)
                    : (isCompleted
                          ? Colors.blue.withValues(alpha: 0.12)
                          : (isDark
                                ? const Color(0xFF2A2D32)
                                : const Color(0xFFF0F2F5))),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isActive
                      ? Colors.green
                      : (isCompleted
                            ? Colors.blue.withValues(alpha: 0.5)
                            : (isDark ? Colors.grey[800]! : Colors.grey[300]!)),
                  width: isActive ? 1.5 : 1.0,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    type == ControlType.startShift
                        ? Icons.play_circle_outline
                        : type == ControlType.break1
                        ? Icons.coffee_outlined
                        : type == ControlType.break2
                        ? Icons.nightlight_round_outlined
                        : type == ControlType.lunch
                        ? Icons.local_dining_outlined
                        : type == ControlType.meeting
                        ? Icons.video_call
                        : Icons.power_settings_new,
                    size: 16,
                    color: isActive
                        ? Colors.green
                        : (isCompleted
                              ? Colors.blue
                              : (isDark ? Colors.grey[400] : Colors.grey[700])),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      action['label'] as String,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isActive
                            ? FontWeight.bold
                            : FontWeight.w500,
                        color: isActive
                            ? Colors.green[300]
                            : (isDark ? Colors.white70 : Colors.black87),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  bool isDesktop(BuildContext context) {
    return MediaQuery.of(context).size.width >= 1100;
  }

  Widget _buildDesktopButtons(
    BuildContext context,
    bool isDark,
    bool isHighContrast,
    WorkSessionProvider sessionProvider,
    WorkSessionState state,
  ) {
    final bool meetingActive =
        state.meetingTask != null && state.meetingTask!.endedAt == null;

    if (state.isActive && state.isOnBreak) {
      return Row(
        children: [
          Expanded(
            child: _buildControlButton(
              context: context,
              type: ControlType.endBreak,
              sessionProvider: sessionProvider,
              state: state,
              isDark: isDark,
              isHighContrast: isHighContrast,
              onPressed: () => _endBreak(sessionProvider),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildControlButton(
              context: context,
              type: ControlType.endShift,
              sessionProvider: sessionProvider,
              state: state,
              isDark: isDark,
              isHighContrast: isHighContrast,
              onPressed: () => _endShift(sessionProvider),
            ),
          ),
        ],
      );
    } else if (state.isActive && meetingActive) {
      return Row(
        children: [
          Expanded(
            child: _buildControlButton(
              context: context,
              type: ControlType.endMeeting,
              sessionProvider: sessionProvider,
              state: state,
              isDark: isDark,
              isHighContrast: isHighContrast,
              onPressed: () => _endMeeting(sessionProvider),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildControlButton(
              context: context,
              type: ControlType.endShift,
              sessionProvider: sessionProvider,
              state: state,
              isDark: isDark,
              isHighContrast: isHighContrast,
              onPressed: () => _endShift(sessionProvider),
            ),
          ),
        ],
      );
    } else if (state.isActive) {
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _buildControlButton(
            context: context,
            type: ControlType.startShift,
            sessionProvider: sessionProvider,
            state: state,
            isDark: isDark,
            isHighContrast: isHighContrast,
            enabled: false,
          ),
          _buildControlButton(
            context: context,
            type: ControlType.breakAction,
            sessionProvider: sessionProvider,
            state: state,
            isDark: isDark,
            isHighContrast: isHighContrast,
            onPressed: () => _startBreak(sessionProvider, BreakType.breakGeneric),
          ),
          _buildControlButton(
            context: context,
            type: ControlType.away,
            sessionProvider: sessionProvider,
            state: state,
            isDark: isDark,
            isHighContrast: isHighContrast,
            onPressed: () => _startBreak(sessionProvider, BreakType.other),
          ),
          _buildControlButton(
            context: context,
            type: ControlType.meal,
            sessionProvider: sessionProvider,
            state: state,
            isDark: isDark,
            isHighContrast: isHighContrast,
            onPressed: () => _startBreak(sessionProvider, BreakType.meal),
          ),
          _buildControlButton(
            context: context,
            type: ControlType.meeting,
            sessionProvider: sessionProvider,
            state: state,
            isDark: isDark,
            isHighContrast: isHighContrast,
            onPressed: () => _startMeeting(sessionProvider),
          ),
          _buildControlButton(
            context: context,
            type: ControlType.endShift,
            sessionProvider: sessionProvider,
            state: state,
            isDark: isDark,
            isHighContrast: isHighContrast,
            onPressed: () => _endShift(sessionProvider),
          ),
        ],
      );
    } else {
      return Row(
        children: [
          Expanded(
            child: _buildControlButton(
              context: context,
              type: ControlType.startShift,
              sessionProvider: sessionProvider,
              state: state,
              isDark: isDark,
              isHighContrast: isHighContrast,
              onPressed: () => _startShift(sessionProvider),
            ),
          ),
        ],
      );
    }
  }

  Widget _buildMobileButtons(
    BuildContext context,
    bool isDark,
    bool isHighContrast,
    WorkSessionProvider sessionProvider,
    WorkSessionState state,
  ) {
    final bool meetingActive =
        state.meetingTask != null && state.meetingTask!.endedAt == null;

    if (state.isActive && state.isOnBreak) {
      return Column(
        children: [
          _buildControlButton(
            context: context,
            type: ControlType.endBreak,
            sessionProvider: sessionProvider,
            state: state,
            isDark: isDark,
            isHighContrast: isHighContrast,
            onPressed: () => _endBreak(sessionProvider),
            fullWidth: true,
          ),
          const SizedBox(height: 12),
          _buildControlButton(
            context: context,
            type: ControlType.endShift,
            sessionProvider: sessionProvider,
            state: state,
            isDark: isDark,
            isHighContrast: isHighContrast,
            onPressed: () => _endShift(sessionProvider),
            fullWidth: true,
          ),
        ],
      );
    } else if (state.isActive && meetingActive) {
      return Column(
        children: [
          _buildControlButton(
            context: context,
            type: ControlType.endMeeting,
            sessionProvider: sessionProvider,
            state: state,
            isDark: isDark,
            isHighContrast: isHighContrast,
            onPressed: () => _endMeeting(sessionProvider),
            fullWidth: true,
          ),
          const SizedBox(height: 12),
          _buildControlButton(
            context: context,
            type: ControlType.endShift,
            sessionProvider: sessionProvider,
            state: state,
            isDark: isDark,
            isHighContrast: isHighContrast,
            onPressed: () => _endShift(sessionProvider),
            fullWidth: true,
          ),
        ],
      );
    } else if (state.isActive) {
      return Column(
        children: [
          _buildControlButton(
            context: context,
            type: ControlType.startShift,
            sessionProvider: sessionProvider,
            state: state,
            isDark: isDark,
            isHighContrast: isHighContrast,
            enabled: false,
            fullWidth: true,
          ),
          const SizedBox(height: 12),
          _buildControlButton(
            context: context,
            type: ControlType.breakAction,
            sessionProvider: sessionProvider,
            state: state,
            isDark: isDark,
            isHighContrast: isHighContrast,
            onPressed: () => _startBreak(sessionProvider, BreakType.breakGeneric),
            fullWidth: true,
          ),
          const SizedBox(height: 12),
          _buildControlButton(
            context: context,
            type: ControlType.away,
            sessionProvider: sessionProvider,
            state: state,
            isDark: isDark,
            isHighContrast: isHighContrast,
            onPressed: () => _startBreak(sessionProvider, BreakType.other),
            fullWidth: true,
          ),
          const SizedBox(height: 12),
          _buildControlButton(
            context: context,
            type: ControlType.meal,
            sessionProvider: sessionProvider,
            state: state,
            isDark: isDark,
            isHighContrast: isHighContrast,
            onPressed: () => _startBreak(sessionProvider, BreakType.meal),
            fullWidth: true,
          ),
          const SizedBox(height: 12),
          _buildControlButton(
            context: context,
            type: ControlType.meeting,
            sessionProvider: sessionProvider,
            state: state,
            isDark: isDark,
            isHighContrast: isHighContrast,
            onPressed: () => _startMeeting(sessionProvider),
            fullWidth: true,
          ),
          const SizedBox(height: 12),
          _buildControlButton(
            context: context,
            type: ControlType.endShift,
            sessionProvider: sessionProvider,
            state: state,
            isDark: isDark,
            isHighContrast: isHighContrast,
            onPressed: () => _endShift(sessionProvider),
            fullWidth: true,
          ),
        ],
      );
    } else {
      return Column(
        children: [
          _buildControlButton(
            context: context,
            type: ControlType.startShift,
            sessionProvider: sessionProvider,
            state: state,
            isDark: isDark,
            isHighContrast: isHighContrast,
            onPressed: () => _startShift(sessionProvider),
            fullWidth: true,
          ),
        ],
      );
    }
  }

  BreakType? typeToBreakType(ControlType type) {
    switch (type) {
      case ControlType.break1:
        return BreakType.break1;
      case ControlType.break2:
        return BreakType.break2;
      case ControlType.lunch:
        return BreakType.lunch;
      case ControlType.meal:
        return BreakType.meal;
      case ControlType.other:
        return BreakType.other;
      default:
        return null;
    }
  }

  Widget _buildControlButton({
    required BuildContext context,
    required ControlType type,
    required WorkSessionProvider sessionProvider,
    required WorkSessionState state,
    required bool isDark,
    required bool isHighContrast,
    bool enabled = true,
    VoidCallback? onPressed,
    bool fullWidth = false,
  }) {
    bool isEnabled = enabled && !widget.readOnly;
    String label;
    Color color;
    IconData icon;
    String? tooltip;

    switch (type) {
      case ControlType.startShift:
        label = 'Start Shift';
        color = DesignSystem.getSemanticColor(
          context,
          SemanticColor.shiftStart,
        );
        icon = Icons.play_circle_outline;
        isEnabled = isEnabled && !state.isActive;
        tooltip = 'Start your work shift';
        break;
      case ControlType.breakAction:
        label = 'Break';
        color = const Color(0xFF3498DB);
        icon = Icons.coffee_outlined;
        if (isEnabled) {
          final bool break1Done = state.breaksTaken.contains(BreakType.break1);
          final bool break2Done = state.breaksTaken.contains(BreakType.break2);
          if (!break1Done) {
            isEnabled = state.isActive &&
                !state.isOnBreak &&
                sessionProvider.availabilityFor(BreakType.break1).status ==
                    BreakStatus.available;
            tooltip = 'Take Break 1';
          } else if (!break2Done) {
            isEnabled = state.isActive &&
                !state.isOnBreak &&
                sessionProvider.availabilityFor(BreakType.break2).status ==
                    BreakStatus.available;
            tooltip = 'Take Break 2';
          } else {
            isEnabled = false;
            tooltip = 'All scheduled breaks completed';
          }
        } else {
          tooltip = 'Break unavailable';
        }
        break;
      case ControlType.away:
        label = 'Away';
        color = const Color(0xFF64748B);
        icon = Icons.access_time_outlined;
        if (isEnabled) {
          isEnabled = state.isActive && !state.isOnBreak;
        }
        tooltip = 'Mark yourself away';
        break;
      case ControlType.break1:
        label = 'Break 1';
        color = const Color(0xFF3498DB);
        icon = Icons.coffee_outlined;
        if (isEnabled) {
          isEnabled =
              state.isActive &&
              !state.isOnBreak &&
              sessionProvider.availabilityFor(BreakType.break1).status ==
                  BreakStatus.available;
        }
        tooltip = 'Take your first break';
        break;
      case ControlType.break2:
        label = 'Break 2';
        color = const Color(0xFF3498DB);
        icon = Icons.nightlight_round_outlined;
        if (isEnabled) {
          isEnabled =
              state.isActive &&
              !state.isOnBreak &&
              sessionProvider.availabilityFor(BreakType.break2).status ==
                  BreakStatus.available;
        }
        tooltip = 'Take your second break';
        break;
      case ControlType.lunch:
        label = 'Lunch';
        color = const Color(0xFFDAA520);
        icon = Icons.local_dining_outlined;
        if (isEnabled) {
          isEnabled =
              state.isActive &&
              !state.isOnBreak &&
              sessionProvider.availabilityFor(BreakType.lunch).status ==
                  BreakStatus.available;
        }
        tooltip = 'Take your lunch break';
        break;
      case ControlType.meal:
        label = 'Meal';
        color = const Color(0xFFDAA520);
        icon = Icons.restaurant_outlined;
        if (isEnabled) {
          isEnabled =
              state.isActive &&
              !state.isOnBreak &&
              sessionProvider.availabilityFor(BreakType.meal).status ==
                  BreakStatus.available;
        }
        tooltip = 'Take a meal break';
        break;
      case ControlType.other:
        label = 'Away';
        color = const Color(0xFF64748B);
        icon = Icons.access_time_outlined;
        if (isEnabled) {
          isEnabled =
              state.isActive &&
              !state.isOnBreak &&
              sessionProvider.availabilityFor(BreakType.other).status ==
                  BreakStatus.available;
        }
        tooltip = 'Mark yourself away';
        break;
      case ControlType.meeting:
        label = 'Meeting';
        color = DesignSystem.getSemanticColor(
          context,
          SemanticColor.shiftMeeting,
        );
        icon = Icons.video_call;
        if (isEnabled) {
          isEnabled = state.isActive && !state.isOnBreak;
        }
        tooltip = 'Start a meeting';
        break;
      case ControlType.endMeeting:
        label = 'End Meeting';
        color = DesignSystem.getSemanticColor(
          context,
          SemanticColor.shiftMeeting,
        );
        icon = Icons.video_call;
        if (isEnabled) {
          isEnabled =
              state.isActive &&
              !state.isOnBreak &&
              sessionProvider.state.meetingTask != null &&
              sessionProvider.state.meetingTask!.endedAt == null;
        }
        tooltip = 'End meeting';
        break;
      case ControlType.endShift:
        label = 'End Shift';
        color = DesignSystem.getSemanticColor(context, SemanticColor.shiftEnd);
        icon = Icons.power_settings_new;
        if (isEnabled) {
          isEnabled = state.isActive && !state.isOnBreak;
        }
        tooltip = 'End your work shift';
        break;
      case ControlType.endBreak:
        final activeType = state.activeBreak?.type;
        if (activeType == BreakType.meal || activeType == BreakType.lunch) {
          label = 'End Meal';
          icon = Icons.restaurant_outlined;
          color = const Color(0xFFDAA520);
        } else if (activeType == BreakType.other) {
          label = 'End Away';
          icon = Icons.access_time_outlined;
          color = const Color(0xFF64748B);
        } else if (activeType == BreakType.coachBreak) {
          label = 'End Coach Break';
          icon = Icons.self_improvement_outlined;
          color = DesignSystem.getSemanticColor(context, SemanticColor.shiftCoachBreak);
        } else {
          label = 'End Break';
          icon = Icons.coffee_outlined;
          color = const Color(0xFF3498DB);
        }
        if (isEnabled) {
          isEnabled = state.isActive && state.isOnBreak;
        }
        tooltip = 'End your current break';
        break;
    }

    final BreakType? breakType = typeToBreakType(type);
    final bool isCompleted =
        type != ControlType.breakAction &&
        type != ControlType.meal &&
        type != ControlType.lunch &&
        type != ControlType.other &&
        type != ControlType.away &&
        breakType != null &&
        state.completedBreaks.any((b) => b.type == breakType);
    final bool isActiveBreak =
        state.activeBreak?.type == breakType && breakType != null;

    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: fullWidth ? double.infinity : null,
        height: 56,
        child: ElevatedButton(
          onPressed: isEnabled ? onPressed : null,
          style: _buildButtonState(
            context: context,
            type: type,
            color: color,
            isEnabled: isEnabled,
            isCompleted: isCompleted,
            isActiveBreak: isActiveBreak,
            isDark: isDark,
            isHighContrast: isHighContrast,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 24),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: DesignSystem.label(context)
                      .copyWith(fontSize: 16, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  ButtonStyle _buildButtonState({
    required BuildContext context,
    required ControlType type,
    required Color color,
    required bool isEnabled,
    required bool isCompleted,
    required bool isActiveBreak,
    required bool isDark,
    required bool isHighContrast,
  }) {
    final bool isEndBreakActive = type == ControlType.endBreak && isActiveBreak;

    if (!isEnabled) {
      final Color disabledBg = color.withValues(alpha: 0.12);
      final Color disabledFg =
          (isHighContrast
                  ? Colors.white
                  : (isDark ? Colors.white : const Color(0xFF111827)))
              .withValues(alpha: 0.4);
      final Color borderColor = color.withValues(alpha: 0.25);

      return ElevatedButton.styleFrom(
        backgroundColor: disabledBg,
        foregroundColor: disabledFg,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: borderColor, width: 1),
        ),
      );
    }

    if (isCompleted) {
      return ElevatedButton.styleFrom(
        backgroundColor: Colors.transparent,
        foregroundColor: color.withValues(alpha: 0.7),
        elevation: 0,
        side: BorderSide(color: color.withValues(alpha: 0.5), width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );
    }

    if (isEndBreakActive) {
      return ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );
    }

    return ElevatedButton.styleFrom(
      backgroundColor: color,
      foregroundColor: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Future<void> _startShift(WorkSessionProvider sessionProvider) async {
    debugPrint('[SHIFT UI] Start Shift pressed');
    try {
      await sessionProvider.startShift();

      if (_preShiftSelectedTask != null) {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('jwt_token');
        if (token != null) {
          await _workService.startTask(token, _preShiftSelectedTask!.id);
          sessionProvider.setCurrentTask(_preShiftSelectedTask);
          await sessionProvider.refresh();
        }
        setState(() {
          _preShiftSelectedTask = null;
        });
      }
    } catch (e) {
      if (mounted) {
        showError(context, e, isDialog: false);
      }
    }
  }

  Future<void> _endShift(WorkSessionProvider sessionProvider) async {
    debugPrint('[SHIFT UI] End Shift pressed');

    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0xB0000000),
      builder: (context) => AppConfirmationDialog(
        title: 'End Work Session?',
        message:
            'Are you sure you want to end your work session? Your current session will be finalized, and your work activity tracking will stop.',
        confirmLabel: 'End Shift',
        cancelLabel: 'Cancel',
        confirmColor: DesignSystem.getSemanticColor(
          context,
          SemanticColor.shiftEnd,
        ),
      ),
    );

    if (confirmed != true) {
      return;
    }

    if (!mounted) return;

    final breakCoachState = Provider.of<BreakCoachState>(
      context,
      listen: false,
    );
    breakCoachState.hide();
    try {
      final sessionId = sessionProvider.state.session?.id;
      await sessionProvider.endShift();
      setState(() {
        _preShiftSelectedTask = null;
      });
      if (sessionId != null && mounted) {
        await showDialog(
          context: context,
          barrierColor: const Color(0xB0000000),
          builder: (context) =>
              SessionWellbeingCheckin(workSessionId: sessionId.toString()),
        );
      }
    } catch (e) {
      if (mounted) {
        final errorString = e.toString();
        if (errorString.contains('Cannot end shift while a break is active') ||
            errorString.contains('active break')) {
          showDialog(
            context: context,
            builder: (BuildContext ctx) {
              return AlertDialog(
                title: const Text('Cannot End Shift'),
                content: const Text(
                  'You have not completed your required break for this shift. Please take your required break before ending your shift.',
                ),
                actions: <Widget>[
                  TextButton(
                    child: const Text('Cancel'),
                    onPressed: () {
                      Navigator.of(ctx).pop();
                    },
                  ),
                  ElevatedButton(
                    child: const Text('Take Break'),
                    onPressed: () async {
                      Navigator.of(ctx).pop();
                      final prefs = await SharedPreferences.getInstance();
                      final token = prefs.getString('jwt_token') ?? '';
                      breakCoachState.checkRecommendation(token);
                    },
                  ),
                ],
              );
            },
          );
        } else {
          if (mounted) {
            showError(context, 'Failed to end shift: $e', isDialog: false);
          }
        }
      }
    }
  }

  Future<void> _startBreak(
    WorkSessionProvider sessionProvider,
    BreakType type,
  ) async {
    try {
      await sessionProvider.startBreak(type);
    } catch (e) {
      if (mounted) {
        showError(context, e, isDialog: false);
      }
    }
  }

  Future<void> _startMeeting(WorkSessionProvider sessionProvider) async {
    debugPrint('[MEETING 1] CLICKED');
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null) {
        debugPrint('[MEETING ERROR] No token');
        return;
      }
      final sid = sessionProvider.state.session?.id;
      if (sid == null) {
        debugPrint('[MEETING ERROR] No session ID');
        return;
      }
      await sessionProvider.refresh();
      final workService = WorkService();
      final meetingTaskResponse = await workService.createMeetingTask(
        token,
        sid,
      );
      final meetingTaskId = meetingTaskResponse['id'];
      await workService.startTask(token, meetingTaskId);
      await sessionProvider.refresh();
    } catch (e) {
      debugPrint('[MEETING ERROR] $e');
      if (mounted) showError(context, e, isDialog: false);
    }
  }

  Future<void> _endMeeting(WorkSessionProvider sessionProvider) async {
    debugPrint('[MEETING 8] END MEETING PRESSED');
    try {
      final meeting = sessionProvider.state.meetingTask;
      if (meeting == null) {
        debugPrint('[MEETING ERROR] No meeting to end');
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null) {
        debugPrint('[MEETING ERROR] No token for end meeting');
        return;
      }
      final workService = WorkService();
      await workService.completeMeetingTask(token, meeting.id);
      await sessionProvider.refresh();
    } catch (e) {
      debugPrint('[MEETING ERROR] $e');
      if (mounted) showError(context, e, isDialog: false);
    }
  }

  Future<void> _endBreak(WorkSessionProvider sessionProvider) async {
    try {
      await sessionProvider.endBreak();
    } catch (e) {
      if (mounted) {
        showError(context, e, isDialog: false);
      }
    }
  }

  Widget _buildTaskSelector(BuildContext context, WorkSessionProvider sessionProvider, WorkSessionState state, bool isDark, bool isHighContrast) {
    final tasks = state.tasks.whereType<WorkTask>().toList();
    final bool active = state.isActive;
    final currentTask = active ? state.currentTask : _preShiftSelectedTask;

    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2028) : const Color(0xFFF7F8FC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.assignment_outlined, size: 18, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                active ? 'Active Shift Task' : 'Select Task for Shift (Optional)',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white70 : const Color(0xFF4A5568),
                ),
              ),
              const Spacer(),
              if (currentTask != null)
                TextButton.icon(
                  onPressed: () async {
                    if (active) {
                      try {
                        final prefs = await SharedPreferences.getInstance();
                        final token = prefs.getString('jwt_token');
                        if (token != null) {
                          await _workService.updateTaskStatus(token, currentTask.id, 'BLOCKED');
                          sessionProvider.setCurrentTask(null);
                          await sessionProvider.refresh();
                        }
                      } catch (e) {
                        if (context.mounted) showError(context, e, isDialog: false);
                      }
                    } else {
                      setState(() {
                        _preShiftSelectedTask = null;
                      });
                    }
                  },
                  icon: const Icon(Icons.close, size: 14),
                  label: const Text('Clear Task', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(foregroundColor: Colors.orange),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: currentTask?.id,
                  isDense: true,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    hintText: 'Select an existing task...',
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('No task selected (Shift only)'),
                    ),
                    ...tasks.map((task) {
                      return DropdownMenuItem<String>(
                        value: task.id,
                        child: Text('${task.title} (${task.category}) — ${task.status}'),
                      );
                    }),
                  ],
                  onChanged: (taskId) async {
                    if (taskId == null) {
                      if (active) {
                        sessionProvider.setCurrentTask(null);
                      } else {
                        setState(() {
                          _preShiftSelectedTask = null;
                        });
                      }
                      return;
                    }
                    final selectedTask = tasks.where((t) => t.id == taskId).firstOrNull;
                    if (selectedTask != null) {
                      if (active) {
                        try {
                          final prefs = await SharedPreferences.getInstance();
                          final token = prefs.getString('jwt_token');
                          if (token != null) {
                            if (state.currentTask != null && state.currentTask!.id != selectedTask.id) {
                              await _workService.updateTaskStatus(token, state.currentTask!.id, 'BLOCKED');
                            }
                            await _workService.startTask(token, selectedTask.id);
                            sessionProvider.setCurrentTask(selectedTask);
                            await sessionProvider.refresh();
                          }
                        } catch (e) {
                          if (context.mounted) showError(context, e, isDialog: false);
                        }
                      } else {
                        setState(() {
                          _preShiftSelectedTask = selectedTask;
                        });
                      }
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => _showCreateTaskDialog(context, sessionProvider),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New Task'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateTaskDialog(BuildContext context, WorkSessionProvider sessionProvider) async {
    final titleController = TextEditingController();
    String selectedCategory = 'Development';
    String selectedPriority = 'MEDIUM';

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Create & Start New Task'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: titleController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Task Title',
                      hintText: 'e.g. Implement feature...',
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: selectedCategory,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: const [
                      DropdownMenuItem(value: 'Development', child: Text('Development')),
                      DropdownMenuItem(value: 'Content Creation', child: Text('Content Creation')),
                      DropdownMenuItem(value: 'Design', child: Text('Design')),
                      DropdownMenuItem(value: 'Meeting', child: Text('Meeting')),
                      DropdownMenuItem(value: 'Research', child: Text('Research')),
                      DropdownMenuItem(value: 'Documentation', child: Text('Documentation')),
                      DropdownMenuItem(value: 'Other', child: Text('Other')),
                    ],
                    onChanged: (val) => setDialogState(() => selectedCategory = val ?? 'Development'),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: selectedPriority,
                    decoration: const InputDecoration(labelText: 'Priority'),
                    items: const [
                      DropdownMenuItem(value: 'LOW', child: Text('Low')),
                      DropdownMenuItem(value: 'MEDIUM', child: Text('Medium')),
                      DropdownMenuItem(value: 'HIGH', child: Text('High')),
                    ],
                    onChanged: (val) => setDialogState(() => selectedPriority = val ?? 'MEDIUM'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final title = titleController.text.trim();
                    if (title.isEmpty) return;

                    Navigator.pop(dialogContext);

                    try {
                      final prefs = await SharedPreferences.getInstance();
                      final token = prefs.getString('jwt_token');
                      if (token == null) return;

                      final taskResponse = await _workService.createTask(token, {
                        'title': title,
                        'category': selectedCategory,
                        'priority': selectedPriority,
                        'work_session_id': sessionProvider.state.session?.id,
                      });
                      final newTask = WorkTask.fromJson(taskResponse);

                      if (sessionProvider.state.isActive) {
                        await _workService.startTask(token, newTask.id);
                        sessionProvider.setCurrentTask(newTask);
                      } else {
                        setState(() {
                          _preShiftSelectedTask = newTask;
                        });
                      }

                      await sessionProvider.refresh();

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Task "${newTask.title}" created${sessionProvider.state.isActive ? ' and started' : ''}')),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        showError(context, 'Failed to create task: $e', isDialog: false);
                      }
                    }
                  },
                  child: const Text('Create & Start'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

enum ControlType {
  startShift,
  break1,
  break2,
  lunch,
  breakAction,
  away,
  meal,
  other,
  meeting,
  endMeeting,
  endShift,
  endBreak,
}
