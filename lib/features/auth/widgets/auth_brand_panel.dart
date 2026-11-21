import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Left-hand brand panel for the desktop sign-in screen.
///
/// Leads with the product's purpose (sustainable focus and work-life balance)
/// and carries a restrained animated clock: the dial's second hand steps once
/// per second with a small mechanical settle, and two escapement gears turn
/// slowly behind it. Animation is disabled when the OS asks for reduced motion.
class AuthBrandPanel extends StatelessWidget {
  const AuthBrandPanel({super.key});

  static const _features = <(IconData, String, String)>[
    (Icons.balance_rounded, 'Work-life balance', 'A weekly check-in and score that shows how sustainable your week really is.'),
    (Icons.coffee_outlined, 'Break Coach', 'Rule-based pacing with an optional ML layer; every suggestion is explained.'),
    (Icons.edit_note_rounded, 'Session check-ins', 'Quick post-shift reflections on recovery, focus and stress factors.'),
    (Icons.verified_user_outlined, 'Privacy by design', 'No screen or keystroke monitoring. Managers see anonymised cohorts only.'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final border = theme.dividerTheme.color ?? scheme.outline;
    final muted = scheme.onSurface.withValues(alpha: 0.68);

    return Container(
      decoration: BoxDecoration(
        color: Color.alphaBlend(scheme.primary.withValues(alpha: 0.06), scheme.surface),
        border: Border(right: BorderSide(color: border)),
      ),
      padding: const EdgeInsets.fromLTRB(56, 40, 56, 32),
      child: LayoutBuilder(builder: (context, constraints) {
        final compactHeight = constraints.maxHeight < 760;
        // Scrolls instead of overflowing on short windows.
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: _content(context, theme, scheme, border, muted, compactHeight),
            ),
          ),
        );
      }),
    );
  }

  Widget _content(BuildContext context, ThemeData theme, ColorScheme scheme, Color border, Color muted,
      bool compactHeight) {
    return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(9)),
                  child: Icon(Icons.schedule_rounded, size: 20, color: scheme.onPrimary),
                ),
                const SizedBox(width: 12),
                Text('IntelliBreak',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4)),
              ],
            ),
            const Spacer(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('WORK-LIFE BALANCE & FOCUS RECOVERY',
                          style: theme.textTheme.labelSmall?.copyWith(
                            letterSpacing: 1.1,
                            fontWeight: FontWeight.w700,
                            color: scheme.primary,
                          )),
                      const SizedBox(height: 14),
                      Text('Sustainable focus.\nStructured breaks.\nBalanced weeks.',
                          style: theme.textTheme.displaySmall?.copyWith(
                            fontSize: compactHeight ? 32 : 40,
                            height: 1.12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1.2,
                          )),
                      const SizedBox(height: 16),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: Text(
                          'IntelliBreak pairs live shift pacing with non-diagnostic coaching and a weekly work-life balance score, so remote workers can see and protect the boundary between work and the rest of their day.',
                          style: theme.textTheme.bodyLarge?.copyWith(color: muted, height: 1.55),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                ExcludeSemantics(child: AnimatedClock(size: compactHeight ? 120 : 148)),
              ],
            ),
            const SizedBox(height: 36),
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (final f in _features)
                  Container(
                    width: 252,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(f.$1, size: 20, color: scheme.primary),
                        const SizedBox(height: 10),
                        Text(f.$2, style: theme.textTheme.titleSmall),
                        const SizedBox(height: 4),
                        Text(f.$3, style: theme.textTheme.bodySmall?.copyWith(height: 1.45)),
                      ],
                    ),
                  ),
              ],
            ),
            const Spacer(),
            Text(
              'Behavioural patterns and scores are advisory reflections, not medical or psychological diagnoses.',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurface.withValues(alpha: 0.55)),
            ),
          ],
    );
  }
}

/// A small analogue clock: stepping second hand and slowly turning gears.
class AnimatedClock extends StatefulWidget {
  final double size;
  const AnimatedClock({super.key, this.size = 148});

  @override
  State<AnimatedClock> createState() => _AnimatedClockState();
}

class _AnimatedClockState extends State<AnimatedClock> with TickerProviderStateMixin {
  late final AnimationController _tick; // one "step" of the second hand
  late final AnimationController _gears; // continuous slow rotation
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tick = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
    _gears = AnimationController(vsync: this, duration: const Duration(seconds: 36));
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      if (!(MediaQuery.maybeOf(context)?.disableAnimations ?? false)) {
        _tick.forward(from: 0);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !(MediaQuery.maybeOf(context)?.disableAnimations ?? false)) {
        _gears.repeat();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tick.dispose();
    _gears.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([_tick, _gears]),
        builder: (context, _) => CustomPaint(
          size: Size.square(widget.size),
          painter: _ClockPainter(
            now: _now,
            settle: Curves.easeOutBack.transform(_tick.value),
            gearTurn: _gears.value,
            accent: scheme.primary,
            ink: scheme.onSurface,
            face: scheme.surface,
          ),
        ),
      ),
    );
  }
}

class _ClockPainter extends CustomPainter {
  final DateTime now;
  final double settle; // 0..1 (overshoots slightly) progress of the current second step
  final double gearTurn; // 0..1
  final Color accent;
  final Color ink;
  final Color face;

  _ClockPainter({
    required this.now,
    required this.settle,
    required this.gearTurn,
    required this.accent,
    required this.ink,
    required this.face,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;

    // Gears sit behind the dial, partly visible at the lower right.
    _gear(canvas, c + Offset(r * 0.92, r * 0.78), r * 0.34, 10, gearTurn * 2 * math.pi);
    _gear(canvas, c + Offset(r * 1.22, r * 0.34), r * 0.2, 8, -gearTurn * 2 * math.pi * 1.25);

    canvas.drawCircle(c, r - 2, Paint()..color = face);
    canvas.drawCircle(
      c,
      r - 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = ink.withValues(alpha: 0.28),
    );

    final tickPaint = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < 60; i++) {
      final major = i % 5 == 0;
      final a = i * math.pi / 30;
      final outer = r - 8;
      final inner = outer - (major ? 9 : 4);
      tickPaint
        ..strokeWidth = major ? 2 : 1
        ..color = ink.withValues(alpha: major ? 0.55 : 0.22);
      canvas.drawLine(
        c + Offset(math.sin(a), -math.cos(a)) * inner,
        c + Offset(math.sin(a), -math.cos(a)) * outer,
        tickPaint,
      );
    }

    final seconds = now.second.toDouble();
    final minutes = now.minute + seconds / 60;
    final hours = (now.hour % 12) + minutes / 60;

    void hand(double angle, double length, double width, Color color) {
      final p = Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        c - Offset(math.sin(angle), -math.cos(angle)) * (length * 0.12),
        c + Offset(math.sin(angle), -math.cos(angle)) * length,
        p,
      );
    }

    hand(hours / 12 * 2 * math.pi, r * 0.5, 3.4, ink.withValues(alpha: 0.9));
    hand(minutes / 60 * 2 * math.pi, r * 0.72, 2.4, ink.withValues(alpha: 0.9));

    // The second hand rests on the previous second and steps forward with a
    // tiny overshoot, like a quartz movement.
    final stepAngle = ((seconds - 1) + settle) / 60 * 2 * math.pi;
    hand(stepAngle, r * 0.8, 1.4, accent);

    canvas.drawCircle(c, 4.5, Paint()..color = accent);
    canvas.drawCircle(c, 1.8, Paint()..color = face);
  }

  void _gear(Canvas canvas, Offset center, double radius, int teeth, double rotation) {
    final path = Path();
    final inner = radius * 0.82;
    for (var i = 0; i < teeth; i++) {
      final a0 = rotation + i * 2 * math.pi / teeth;
      final a1 = a0 + math.pi / teeth * 0.5;
      final a2 = a0 + math.pi / teeth;
      final a3 = a0 + math.pi / teeth * 1.5;
      Offset p(double a, double rad) => center + Offset(math.cos(a), math.sin(a)) * rad;
      if (i == 0) path.moveTo(p(a0, inner).dx, p(a0, inner).dy);
      path.lineTo(p(a0, inner).dx, p(a0, inner).dy);
      path.lineTo(p(a1, radius).dx, p(a1, radius).dy);
      path.lineTo(p(a2, radius).dx, p(a2, radius).dy);
      path.lineTo(p(a3, inner).dx, p(a3, inner).dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = accent.withValues(alpha: 0.16));
    canvas.drawCircle(center, radius * 0.26, Paint()..color = face.withValues(alpha: 0.9));
  }

  @override
  bool shouldRepaint(covariant _ClockPainter old) =>
      old.now.second != now.second || old.settle != settle || old.gearTurn != gearTurn || old.accent != accent;
}
