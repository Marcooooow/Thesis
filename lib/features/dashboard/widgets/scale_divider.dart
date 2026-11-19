import 'package:flutter/material.dart';

class ScaleDivider extends StatelessWidget {
  const ScaleDivider({
    Key? key,
    this.color,
    this.height = 1,
    this.tickLength = 2,
    this.tickInterval = 4,
  }) : super(key: key);

  final Color? color;
  final double height;
  final double tickLength;
  final double tickInterval;

  @override
  Widget build(BuildContext context) {
    final Color lineColor = color ?? Theme.of(context).dividerColor;
    return CustomPaint(
      size: Size(double.infinity, height),
      painter: _ScaleDividerPainter(
        lineColor: lineColor,
        tickLength: tickLength,
        tickInterval: tickInterval,
      ),
    );
  }
}

class _ScaleDividerPainter extends CustomPainter {
  _ScaleDividerPainter({
    required this.lineColor,
    required this.tickLength,
    required this.tickInterval,
  });

  final Color lineColor;
  final double tickLength;
  final double tickInterval;

  @override
  void paint(Canvas canvas, Size size) {
    // Guard against invalid size
    if (size.width <= 0 || !size.width.isFinite || size.height <= 0 || !size.height.isFinite) {
      return;
    }

    final double lineY = size.height / 2;
    final Paint linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.0;

    // Draw the main line
    canvas.drawLine(Offset(0, lineY), Offset(size.width, lineY), linePaint);

    final Paint tickPaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.0;

    // Draw tick marks
    double x = 0;
    while (x < size.width) {
      // Draw tick mark above the line
      canvas.drawLine(
        Offset(x, lineY - tickLength / 2),
        Offset(x, lineY + tickLength / 2),
        tickPaint,
      );
      x += tickInterval;
    }
  }

  @override
  bool shouldRepaint(covariant _ScaleDividerPainter oldDelegate) {
    return oldDelegate.lineColor != lineColor ||
        oldDelegate.tickLength != tickLength ||
        oldDelegate.tickInterval != tickInterval;
  }
}
