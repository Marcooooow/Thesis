import 'package:flutter/material.dart';
// Removed unused import: 'package:intellibreak/core/design_system.dart';

class FocusRateChart extends StatelessWidget {
  final List<Map<String, dynamic>> focusIdleData;
  final bool isDark;
  final bool isHighContrast;

  const FocusRateChart({
    super.key,
    required this.focusIdleData,
    required this.isDark,
    required this.isHighContrast,
  });

  @override
  Widget build(BuildContext context) {
    if (focusIdleData.isEmpty) {
      return Center(
        child: Text(
          'No focus rate data available',
          style: TextStyle(
            color: isDark
                ? (isHighContrast ? Colors.white : const Color(0xFFE8EBEF))
                : const Color(0xFF5B6472),
          ),
        ),
      );
    }

    // Compute focus rate for each day from focusIdleData
    // Each item in focusIdleData has: day, focusHours, idleHours
    List<Map<String, dynamic>> chartData = [];
    for (var dayData in focusIdleData) {
      final focusHours = (dayData['focusHours'] as num?)?.toDouble() ?? 0.0;
      final idleHours = (dayData['idleHours'] as num?)?.toDouble() ?? 0.0;
      final totalHours = focusHours + idleHours;
      final focusRate = totalHours > 0 ? (focusHours / totalHours) * 100 : 0.0;

      chartData.add({
        'day': dayData['day'],
        'focusRate': focusRate,
      });
    }

    // Find max focus rate for scaling (max 100)
    // double maxFocusRate = 100.0; // Unused variable removed

    final Color lineColor = isDark
        ? (isHighContrast ? Colors.white : const Color(0xFF0F766E))
        : const Color(0xFF0F766E);
    final Color pointColor = lineColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title
        Text(
          'Focus Rate Trend',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
            color: isDark
                ? (isHighContrast ? Colors.white : const Color(0xFFE8EBEF))
                : const Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 16),
        // Chart container - fills the full column width
    Container(
      height: 280,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double width = constraints.maxWidth;
          final double height = constraints.maxHeight;

          return CustomPaint(
            size: Size(width, height),
            painter: _FocusRateChartPainter(
              chartData: chartData,
              isDark: isDark,
              isHighContrast: isHighContrast,
              lineColor: lineColor,
              pointColor: pointColor,
            ),
            child: SizedBox(width: width, height: height),
          );
        },
      ),
    ),
        const SizedBox(height: 8),
        // X-axis labels (days) - equal spacing across full width
        SizedBox(
          height: 24,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: focusIdleData.map((item) {
              final day = item['day'] as String? ?? '';
              return Expanded(
                child: Text(
                  day.length > 3 ? day.substring(0, 3) : day,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.1,
                    color: isDark
                        ? (isHighContrast ? Colors.white : const Color(0xFFE8EBEF))
                        : const Color(0xFF5B6472),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _FocusRateChartPainter extends CustomPainter {
  final List<Map<String, dynamic>> chartData;
  final bool isDark;
  final bool isHighContrast;
  final Color lineColor;
  final Color pointColor;

  _FocusRateChartPainter({
    required this.chartData,
    required this.isDark,
    required this.isHighContrast,
    required this.lineColor,
    required this.pointColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (chartData.isEmpty) return;

    final Paint linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final Paint pointPaint = Paint()
      ..color = pointColor
      ..style = PaintingStyle.fill;

    final Paint gridPaint = Paint()
      ..color = isDark
          ? (isHighContrast ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFE8EBEF).withValues(alpha: 0.1))
          : const Color(0xFF5B6472).withValues(alpha: 0.1)
      ..strokeWidth = 0.5;

    // We'll draw the chart with some padding
    final double left = 20;
    final double right = 20;
    final double top = 20;
    final double bottom = 20;
    final double chartWidth = size.width - left - right;
    final double chartHeight = size.height - top - bottom;

    // Draw horizontal grid lines and labels for focus rate (0%, 25%, 50%, 75%, 100%)
    for (int i = 0; i <= 4; i++) {
      final double y = top + (chartHeight * (1 - i / 4));
      canvas.drawLine(Offset(left, y), Offset(size.width - right, y), gridPaint);
      // Label
      final TextSpan label = TextSpan(
        text: '${i * 25}%',
        style: TextStyle(
          fontSize: 10,
          color: isDark
              ? (isHighContrast ? Colors.white : const Color(0xFFE8EBEF))
              : const Color(0xFF5B6472),
        ),
      );
      final TextPainter tp = TextPainter(
        text: label,
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(left - tp.width - 4, y - tp.height / 2));
    }

    // Draw vertical grid lines for each day
    final int steps = chartData.length - 1;
    for (int i = 0; i < chartData.length; i++) {
      final double x = left + (chartWidth * i / (steps > 0 ? steps : 1));
      canvas.drawLine(Offset(x, top), Offset(x, size.height - bottom), gridPaint);
    }

    // Draw the line and points
    List<Offset> points = [];
    for (int i = 0; i < chartData.length; i++) {
      final double focusRate = (chartData[i]['focusRate'] as num?)?.toDouble() ?? 0.0;
      // Clamp focus rate between 0 and 100
      final double clampedRate = focusRate.clamp(0.0, 100.0);
      final double x = left + (chartWidth * i / (steps > 0 ? steps : 1));
      final double y = top + chartHeight * (1 - clampedRate / 100);
      points.add(Offset(x, y));
    }

    // Draw line
    if (points.length >= 2) {
      for (int i = 0; i < points.length - 1; i++) {
        canvas.drawLine(points[i], points[i + 1], linePaint);
      }
    }

    // Draw points
    for (final Offset point in points) {
      canvas.drawCircle(point, 4, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}