import 'package:flutter/material.dart';
import 'package:intellibreak/core/design_system.dart';
import 'package:intellibreak/providers/work_session_provider.dart';
import 'package:intellibreak/providers/work_session_models.dart';
import 'package:intellibreak/features/dashboard/providers/profile_provider.dart';
import 'package:provider/provider.dart';

/// Daily Work and Break Timeline widget for Employee Personalized Dashboard.
/// Displays progress against recorded schedule, schedule ruler timeline, and completed events.
class DailyTimelineCard extends StatefulWidget {
  final WorkSessionState? sessionState;
  const DailyTimelineCard({super.key, this.sessionState});

  @override
  State<DailyTimelineCard> createState() => _DailyTimelineCardState();
}

class _DailyTimelineCardState extends State<DailyTimelineCard> {
  int? _hoveredSegmentIndex;
  TimeOfDay? _scheduleStart;
  TimeOfDay? _scheduleEnd;
  ProfileProvider? _profileProvider;
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    if (widget.sessionState == null) {
      _profileProvider = Provider.of<ProfileProvider>(context, listen: false);
      _profileProvider?.addListener(_onProfileChanged);
      _loadProfileSchedule();
    }
  }

  @override
  void dispose() {
    _hideTooltip();
    _profileProvider?.removeListener(_onProfileChanged);
    super.dispose();
  }

  void _onProfileChanged() {
    if (mounted) {
      _loadProfileSchedule();
    }
  }

  void _loadProfileSchedule() {
    if (_profileProvider != null && _profileProvider?.profile != null) {
      final startStr = _profileProvider?.profile?.shiftStartTime;
      final endStr = _profileProvider?.profile?.shiftEndTime;
      TimeOfDay? startTime;
      TimeOfDay? endTime;
      if (startStr != null) {
        startTime = _parseTimeOfDay(startStr);
      }
      if (endStr != null) {
        endTime = _parseTimeOfDay(endStr);
      }
      if (mounted) {
        setState(() {
          _scheduleStart = startTime;
          _scheduleEnd = endTime;
        });
      }
    }
  }

  TimeOfDay? _parseTimeOfDay(String timeStr) {
    final parts = timeStr.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23) return null;
    if (minute < 0 || minute > 59) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  void _showTooltip(Offset globalOffset, String text) {
    _hideTooltip();
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: globalOffset.dx + 10,
        top: globalOffset.dy - 40,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1D21),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.grey[700]!, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideTooltip() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _onHover(PointerEvent event, Size size, WorkSessionState state) {
    final x = event.localPosition.dx;

    // Guard against invalid size.width
    if (size.width <= 0 || !size.width.isFinite) {
      _hideTooltip();
      setState(() => _hoveredSegmentIndex = null);
      return;
    }

    if (x < 0 || x > size.width) {
      _hideTooltip();
      setState(() => _hoveredSegmentIndex = null);
      return;
    }

    final now = DateTime.now();
    final startHour = _scheduleStart?.hour ?? 8;
    final startMinute = _scheduleStart?.minute ?? 0;
    final endHour = _scheduleEnd?.hour ?? 17;
    final endMinute = _scheduleEnd?.minute ?? 0;
    final startOfDay = DateTime(
      now.year,
      now.month,
      now.day,
      startHour,
      startMinute,
    );
    var endOfDay = DateTime(now.year, now.month, now.day, endHour, endMinute);
    if (!endOfDay.isAfter(startOfDay)) {
      endOfDay = endOfDay.add(const Duration(days: 1));
    }
    final totalMs = endOfDay.difference(startOfDay).inMilliseconds;

    final hoverTime = startOfDay.add(
      Duration(milliseconds: ((x / size.width) * totalMs).toInt()),
    );

    final segments = <_Segment>[];

    // 1. Work session
    final session = state.session;
    if (session != null) {
      final sStart = session.startedAt;
      final sEnd =
          session.endedAt ?? (state.isActive && !state.isOnBreak ? now : null);
      if (sStart.isBefore(endOfDay) &&
          (sEnd == null || sEnd.isAfter(startOfDay))) {
        final segStart = sStart.isBefore(startOfDay) ? startOfDay : sStart;
        final segEnd = sEnd == null
            ? (state.isActive ? now : endOfDay)
            : (sEnd.isAfter(endOfDay) ? endOfDay : sEnd);
        segments.add(
          _Segment(segStart, segEnd, const Color(0xFF2ECC71), 'Work'),
        );
      }
    }

    // 2. Completed breaks
    for (final b in state.completedBreaks) {
      final bStart = b.startedAt;
      final bEnd = b.endedAt ?? b.startedAt.add(const Duration(minutes: 10));
      if (bStart.isBefore(endOfDay) && bEnd.isAfter(startOfDay)) {
        final segStart = bStart.isBefore(startOfDay) ? startOfDay : bStart;
        final segEnd = bEnd.isAfter(endOfDay) ? endOfDay : bEnd;
        final color = b.type == BreakType.break1
            ? const Color(0xFF20B2AA)
            : (b.type == BreakType.break2
                  ? const Color(0xFF4682B4)
                  : (b.type == BreakType.coachBreak
                        ? const Color(0xFFE6A8C0)
                        : const Color(0xFFDAA520)));
        segments.add(_Segment(segStart, segEnd, color, b.type.label));
      }
    }

    // 3. Active break
    if (state.activeBreak?.startedAt != null) {
      final bStart = state.activeBreak!.startedAt;
      final bEnd = now;
      if (bStart.isBefore(endOfDay) && bEnd.isAfter(startOfDay)) {
        final segStart = bStart.isBefore(startOfDay) ? startOfDay : bStart;
        final segEnd = bEnd.isAfter(endOfDay) ? endOfDay : bEnd;
        final color = state.activeBreak!.type == BreakType.break1
            ? const Color(0xFF20B2AA)
            : (state.activeBreak!.type == BreakType.break2
                  ? const Color(0xFF4682B4)
                  : const Color(0xFFDAA520));
        segments.add(
          _Segment(segStart, segEnd, color, state.activeBreak!.type.label),
        );
      }
    }

    // 4. Meetings
    if (state.session != null) {
      for (final task in state.tasks) {
        if (task == null) continue;
        if (task.category == 'Meeting' &&
            task.workSessionId == state.session?.id &&
            task.startedAt != null) {
          final mStart = task.startedAt!;
          final mEnd = task.endedAt ?? now;
          if (mStart.isBefore(endOfDay) && mEnd.isAfter(startOfDay)) {
            final segStart = mStart.isBefore(startOfDay) ? startOfDay : mStart;
            final segEnd = mEnd.isAfter(endOfDay) ? endOfDay : mEnd;
            segments.add(
              _Segment(segStart, segEnd, const Color(0xFF9370DB), 'Meeting'),
            );
          }
        }
      }
    }

    segments.sort((a, b) => a.start.compareTo(b.start));
    int? hoveredIndex;
    for (int i = segments.length - 1; i >= 0; i--) {
      final seg = segments[i];
      if (!hoverTime.isBefore(seg.start) && hoverTime.isBefore(seg.end)) {
        hoveredIndex = i;
        break;
      }
    }

    if (hoveredIndex != null) {
      if (_hoveredSegmentIndex != hoveredIndex) {
        setState(() => _hoveredSegmentIndex = hoveredIndex);
      }
      final hovered = segments[hoveredIndex];
      final duration = hovered.end.difference(hovered.start);
      final minutes = duration.inMinutes;
      final timeStr =
          "${hovered.start.hour.toString().padLeft(2, '0')}:${hovered.start.minute.toString().padLeft(2, '0')}";
      _showTooltip(event.position, "${hovered.label}\n$timeStr • ${minutes}m");
    } else {
      if (_hoveredSegmentIndex != null) {
        setState(() => _hoveredSegmentIndex = null);
      }
      _hideTooltip();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.sessionState ?? context.watch<WorkSessionProvider>().state;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final completedBreaks = state.completedBreaks;
    final bool hasActiveSession = state.isActive;

    return DesignSystem.premiumCard(
      context: context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.timeline_outlined,
                size: 22,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Text(
                'Daily Work & Break Timeline',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                  color: isDark ? Colors.white : const Color(0xFF111827),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: hasActiveSession ? Colors.green.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  hasActiveSession ? 'Shift Active' : 'Shift Inactive',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: hasActiveSession ? Colors.green.shade700 : Colors.grey.shade700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Schedule Ruler Timeline
          LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = constraints.maxWidth;

              // Guard against invalid constraints during layout transitions
              if (maxWidth <= 0 || !maxWidth.isFinite) {
                return const SizedBox(height: 36);
              }

              final size = Size(maxWidth, 36);
              return MouseRegion(
                onHover: (event) => _onHover(event, size, state),
                onExit: (_) {
                  _hideTooltip();
                  setState(() => _hoveredSegmentIndex = null);
                },
                child: CustomPaint(
                  painter: _RulerTimelinePainter(
                    state: state,
                    now: DateTime.now(),
                    scheduleStart: _scheduleStart,
                    scheduleEnd: _scheduleEnd,
                    hoveredSegmentIndex: _hoveredSegmentIndex,
                  ),
                  size: size,
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          if (!hasActiveSession && completedBreaks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'Start a work session to track your daily timeline and achievements.',
                  style: TextStyle(
                    fontSize: 13.5,
                    color: isDark ? Colors.white60 : const Color(0xFF5B6472),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTimelineEvent(
                  context,
                  time: state.startTime != null ? _formatTime(state.startTime!) : 'Start',
                  title: 'Shift Started',
                  subtitle: 'Active work session in progress',
                  isDone: true,
                  isDark: isDark,
                ),
                ...completedBreaks.map((b) => _buildTimelineEvent(
                  context,
                  time: _formatTime(b.startedAt),
                  title: '${b.type.label} Completed',
                  subtitle: 'Duration: ${b.durationMinutes ?? 15}m',
                  isDone: true,
                  isDark: isDark,
                )),
                if (state.isOnBreak)
                  _buildTimelineEvent(
                    context,
                    time: state.activeBreak != null ? _formatTime(state.activeBreak!.startedAt) : 'Now',
                    title: 'Current Break (${state.activeBreak?.type.label ?? "Break"})',
                    subtitle: 'Resting & recharging away from screen',
                    isDone: false,
                    isDark: isDark,
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildTimelineEvent(
    BuildContext context, {
    required String time,
    required String title,
    required String subtitle,
    required bool isDone,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 54,
            alignment: Alignment.centerLeft,
            child: Text(
              time,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white60 : const Color(0xFF5B6472),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              const SizedBox(height: 4),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDone ? Colors.green.shade600 : Theme.of(context).colorScheme.primary,
                ),
              ),
              Container(
                width: 2,
                height: 24,
                color: isDark ? Colors.white12 : Colors.grey.shade300,
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white60 : const Color(0xFF5B6472),
                  ),
                ),
              ],
            ),
          ),
        ],
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

class _RulerTimelinePainter extends CustomPainter {
  final WorkSessionState state;
  final DateTime now;
  final TimeOfDay? scheduleStart;
  final TimeOfDay? scheduleEnd;
  final int? hoveredSegmentIndex;

  _RulerTimelinePainter({
    required this.state,
    required this.now,
    this.scheduleStart,
    this.scheduleEnd,
    required this.hoveredSegmentIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final startHour = scheduleStart?.hour ?? 8;
    final startMinute = scheduleStart?.minute ?? 0;
    final endHour = scheduleEnd?.hour ?? 17;
    final endMinute = scheduleEnd?.minute ?? 0;
    final startOfDay = DateTime(
      now.year,
      now.month,
      now.day,
      startHour,
      startMinute,
    );
    var endOfDay = DateTime(now.year, now.month, now.day, endHour, endMinute);
    if (!endOfDay.isAfter(startOfDay)) {
      endOfDay = endOfDay.add(const Duration(days: 1));
    }
    final totalMs = (endOfDay.difference(startOfDay).inMilliseconds).toDouble();

    // Guard against invalid size
    if (size.width <= 0 || !size.width.isFinite || size.height <= 0 || !size.height.isFinite) {
      return;
    }

    if (totalMs <= 0) return;

    final bgColor = const Color(0xFF2A2E35);
    final tickColor = Colors.grey[600]!;
    final tickPaint = Paint()..color = tickColor;
    final labelColor = Colors.grey[500]!;
    final labelStyle = const TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w500,
    );

    // Background track
    final bgPaint = Paint()..color = bgColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 8, size.width, size.height - 16),
        const Radius.circular(6),
      ),
      bgPaint,
    );

    final hourlyTimestamps = <DateTime>[];
    DateTime t = startOfDay;
    while (t.isBefore(endOfDay) || t.isAtSameMomentAs(endOfDay)) {
      hourlyTimestamps.add(t);
      t = t.add(const Duration(hours: 1));
    }

    for (int i = 0; i < hourlyTimestamps.length; i++) {
      final hourTime = hourlyTimestamps[i];
      final x =
          ((hourTime.difference(startOfDay).inMilliseconds / totalMs) *
                  size.width)
              .clamp(0.0, size.width);

      final tickHeight = 10.0;
      canvas.drawLine(
        Offset(x, size.height / 2 - tickHeight / 2),
        Offset(x, size.height / 2 + tickHeight / 2),
        tickPaint,
      );

      final hour12 = hourTime.hour % 12;
      final displayHour = hour12 == 0 ? 12 : hour12;
      final period = hourTime.hour >= 12 ? 'PM' : 'AM';
      final labelText = '$displayHour $period';

      final textPainter = TextPainter(
        text: TextSpan(
          text: labelText,
          style: labelStyle.copyWith(color: labelColor),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x - textPainter.width / 2, 0));
    }

    for (int i = 0; i < hourlyTimestamps.length - 1; i++) {
      final halfHour = hourlyTimestamps[i].add(const Duration(minutes: 30));
      if (halfHour.isAfter(endOfDay)) break;
      final x =
          ((halfHour.difference(startOfDay).inMilliseconds / totalMs) *
                  size.width)
              .clamp(0.0, size.width);
      final tickHeight = 5.0;
      canvas.drawLine(
        Offset(x, size.height / 2 - tickHeight / 2),
        Offset(x, size.height / 2 + tickHeight / 2),
        tickPaint,
      );
    }

    final segments = <_Segment>[];

    final session = state.session;
    if (session != null) {
      final sStart = session.startedAt;
      final sEnd =
          session.endedAt ?? (state.isActive && !state.isOnBreak ? now : null);
      if (sStart.isBefore(endOfDay) &&
          (sEnd == null || sEnd.isAfter(startOfDay))) {
        final segStart = sStart.isBefore(startOfDay) ? startOfDay : sStart;
        final segEnd = sEnd == null
            ? (state.isActive ? now : endOfDay)
            : (sEnd.isAfter(endOfDay) ? endOfDay : sEnd);
        segments.add(
          _Segment(segStart, segEnd, const Color(0xFF2ECC71), 'Work'),
        );
      }
    }

    Color breakColor(BreakType type) {
      switch (type) {
        case BreakType.breakGeneric:
        case BreakType.break1:
        case BreakType.break2:
          return const Color(0xFF3498DB);
        case BreakType.other:
          return const Color(0xFF64748B);
        case BreakType.meal:
        case BreakType.lunch:
          return const Color(0xFFDAA520);
        case BreakType.coachBreak:
          return const Color(0xFFE6A8C0);
      }
    }

    for (final b in state.completedBreaks) {
      final bStart = b.startedAt;
      final bEnd = b.endedAt ?? bStart.add(const Duration(minutes: 10));
      if (bStart.isBefore(endOfDay) && bEnd.isAfter(startOfDay)) {
        final segStart = bStart.isBefore(startOfDay) ? startOfDay : bStart;
        final segEnd = bEnd.isAfter(endOfDay) ? endOfDay : bEnd;
        final color = breakColor(b.type);
        segments.add(_Segment(segStart, segEnd, color, b.type.label));
      }
    }

    if (state.activeBreak != null && state.activeBreak?.startedAt != null) {
      final bStart = state.activeBreak!.startedAt;
      final bEnd = now;
      if (bStart.isBefore(endOfDay) && bEnd.isAfter(startOfDay)) {
        final segStart = bStart.isBefore(startOfDay) ? startOfDay : bStart;
        final segEnd = bEnd.isAfter(endOfDay) ? endOfDay : bEnd;
        final color = breakColor(state.activeBreak!.type);
        segments.add(
          _Segment(segStart, segEnd, color, state.activeBreak!.type.label),
        );
      }
    }

    final sessionId = state.session?.id;
    if (sessionId != null) {
      for (final task in state.tasks) {
        if (task == null) continue;
        if (task.category == 'Meeting' &&
            task.workSessionId == sessionId &&
            task.startedAt != null) {
          final mStart = task.startedAt!;
          final mEnd = task.endedAt ?? now;
          if (mStart.isBefore(endOfDay) && mEnd.isAfter(startOfDay)) {
            final segStart = mStart.isBefore(startOfDay) ? startOfDay : mStart;
            final segEnd = mEnd.isAfter(endOfDay) ? endOfDay : mEnd;
            segments.add(
              _Segment(segStart, segEnd, const Color(0xFF9370DB), 'Meeting'),
            );
          }
        }
      }
    }

    segments.sort((a, b) => a.start.compareTo(b.start));
    final int? hoveredIndex = hoveredSegmentIndex;
    for (int i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final x1 =
          ((seg.start.difference(startOfDay).inMilliseconds / totalMs) *
                  size.width)
              .clamp(0.0, size.width);
      final x2 =
          ((seg.end.difference(startOfDay).inMilliseconds / totalMs) *
                  size.width)
              .clamp(0.0, size.width);
      if (x2 <= x1) continue;
      final rect = Rect.fromLTWH(x1, 14, x2 - x1, size.height - 28);
      final bool isHovered = (i == hoveredIndex);
      final bool hasHover = hoveredIndex != null;
      final double alpha = (isHovered || !hasHover) ? 0.85 : 0.25;
      final double strokeWidth = isHovered ? 3.0 : 0.0;
      final segmentPaint = Paint()
        ..color = seg.color.withValues(alpha: alpha)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        segmentPaint,
      );
      if (isHovered) {
        final borderPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth;
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(4)),
          borderPaint,
        );
      }
    }

    if (now.isAfter(startOfDay) && now.isBefore(endOfDay)) {
      final progress = now.difference(startOfDay).inMilliseconds / totalMs;
      final x = (progress * size.width).clamp(0.0, size.width);
      final linePaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 2;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
      canvas.drawCircle(Offset(x, 4), 3, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _Segment {
  final DateTime start;
  final DateTime end;
  final Color color;
  final String label;
  _Segment(this.start, this.end, this.color, this.label);
}
