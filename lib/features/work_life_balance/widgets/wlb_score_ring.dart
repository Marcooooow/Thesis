import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intellibreak/features/work_life_balance/services/wlb_service.dart';

/// Circular gauge for the 0-100 work-life balance score.
class WlbScoreRing extends StatelessWidget {
  final double? score;
  final double size;
  final double strokeWidth;

  const WlbScoreRing({
    super.key,
    required this.score,
    this.size = 148,
    this.strokeWidth = 12,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = wlbBandColor(score);
    final track = theme.colorScheme.onSurface.withValues(alpha: 0.08);
    final value = ((score ?? 0) / 100).clamp(0.0, 1.0);

    return Semantics(
      label: score == null
          ? 'Work-life balance score not available yet'
          : 'Work-life balance score ${score!.round()} out of 100, ${wlbBandLabel(score)}',
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size.square(size),
              painter: _RingPainter(
                progress: value,
                color: color,
                track: track,
                stroke: strokeWidth,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  score == null ? '—' : score!.round().toString(),
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontSize: size * 0.30,
                    fontWeight: FontWeight.w600,
                    height: 1.0,
                    letterSpacing: -1,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  score == null ? 'No check-in yet' : wlbBandLabel(score),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: score == null
                        ? theme.colorScheme.onSurface.withValues(alpha: 0.6)
                        : color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color track;
  final double stroke;

  _RingPainter({
    required this.progress,
    required this.color,
    required this.track,
    required this.stroke,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (math.min(size.width, size.height) - stroke) / 2;

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawCircle(center, radius, trackPaint);

    if (progress <= 0) return;
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.color != color || old.track != track || old.stroke != stroke;
}
