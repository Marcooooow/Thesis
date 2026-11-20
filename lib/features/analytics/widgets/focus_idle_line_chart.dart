import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../services/analytics_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FocusIdleLineChart extends StatefulWidget {
  final String? token;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? endpoint;

  const FocusIdleLineChart({
    super.key,
    this.token,
    this.startDate,
    this.endDate,
    this.endpoint,
  });

  const FocusIdleLineChart.demo()
    : token = null,
      startDate = null,
      endDate = null,
      endpoint = null,
      super(key: const Key('demo-focus-idle-line-chart'));

  @override
  State<FocusIdleLineChart> createState() => _FocusIdleLineChartState();
}

class _FocusIdleLineChartState extends State<FocusIdleLineChart> {
  final AnalyticsService _analyticsService = AnalyticsService();
  List<Map<String, dynamic>> _dailyData = List.generate(
    7,
    (index) => {
      'day': ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][index],
      'focusHours': 0.0,
      'idleHours': 0.0,
    },
  );
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    // If token is null, we are in demo mode
    if (widget.token == null) {
      // Simulate loading delay for demo
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      setState(() {
        _dailyData = [
          {'day': 'Mon', 'focusHours': 5.0, 'idleHours': 2.0},
          {'day': 'Tue', 'focusHours': 6.0, 'idleHours': 1.5},
          {'day': 'Wed', 'focusHours': 4.5, 'idleHours': 2.5},
          {'day': 'Thu', 'focusHours': 5.5, 'idleHours': 1.0},
          {'day': 'Fri', 'focusHours': 7.0, 'idleHours': 0.5},
          {'day': 'Sat', 'focusHours': 1.0, 'idleHours': 4.0},
          {'day': 'Sun', 'focusHours': 0.5, 'idleHours': 5.0},
        ];
        _isLoading = false;
      });
      return;
    } else if (widget.endpoint != null) {
      // Admin endpoint directly via ApiService
      try {
        final response = await _analyticsService.getListWithAuthDirect(
          widget.endpoint!,
          widget.token!,
        );
        if (mounted) {
          setState(() {
            _dailyData = (response as List?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [];
            _isLoading = false;
          });
        }
      } catch (e) {
        if (mounted) {
          // If the error is due to an invalid token, clear it.
          if (e.toString().contains('401') || e.toString().contains('Unauthorized')) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove('jwt_token');
          }
          setState(() {
            _error = e.toString();
            _isLoading = false;
          });
        }
      }
    } else {
      // Default behavior: use the non-admin endpoint with query string
      try {
        final data = await _analyticsService.getDailyFocusIdle(
          widget.token!,
          startDate: widget.startDate,
          endDate: widget.endDate,
        );
        if (mounted) {
          setState(() {
            _dailyData = data;
            _isLoading = false;
          });
        }
      } catch (e) {
        if (mounted) {
          // If the error is due to an invalid token, clear it.
          if (e.toString().contains('401') || e.toString().contains('Unauthorized')) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove('jwt_token');
          }
          setState(() {
            _error = e.toString();
            _isLoading = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Text(
          'Error loading data: $_error',
          style: TextStyle(color: isDark ? Colors.white : Colors.black),
          textAlign: TextAlign.center,
        ),
      );
    }

    // Check if we have any meaningful data
    final hasData = _dailyData.any((day) {
      final focus = (day['focusHours'] as num?)?.toDouble() ?? 0.0;
      final idle = (day['idleHours'] as num?)?.toDouble() ?? 0.0;
      return focus > 0 || idle > 0;
    });
    if (!hasData) {
      return Center(
        child: Text(
          'No focus/idle data available',
          style: TextStyle(color: isDark ? Colors.white70 : Colors.grey[600]),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(flex: 1, fit: FlexFit.loose, child: LineChart(mainData())),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegendItem('Focus Time', const Color(0xFF0F766E), isDark),
              const SizedBox(width: 16),
              _buildLegendItem(
                'Idle / Break Time',
                const Color(0xFF4CAF50),
                isDark,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLegendItem(String label, Color color, bool isDark) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.white : const Color(0xFF111827),
          ),
        ),
      ],
    );
  }

  LineChartData mainData() {
    final double maxY = _dailyData.fold(0.0, (max, day) {
      final focus = (day['focusHours'] as num?)?.toDouble() ?? 0.0;
      final idle = (day['idleHours'] as num?)?.toDouble() ?? 0.0;
      return max > focus + idle ? max : focus + idle;
    });

    // Calculate dynamic interval for 5-7 Y-axis ticks
    double interval = 1;
    if (maxY > 0) {
      const int targetTickCount = 6; // Aim for 5-7 ticks
      interval = (maxY / targetTickCount).ceilToDouble();
      // Ensure interval is at least 1 and rounded to nice numbers
      if (interval < 1) {
        interval = 1;
      } else if (interval <= 1.5) {
        interval = 1;
      } else if (interval <= 3) {
        interval = 2;
      } else if (interval <= 5) {
        interval = 5;
      } else if (interval <= 10) {
        interval = 10;
      } else if (interval <= 20) {
        interval = 20;
      } else if (interval <= 50) {
        interval = 50;
      } else if (interval <= 100) {
        interval = 100;
      } else {
        interval = ((interval / 100).ceilToDouble()) * 100;
      }
    }

    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: interval, // dynamic interval based on data
        verticalInterval: 1,
        getDrawingHorizontalLine: (value) {
          return FlLine(
            color: Theme.of(context).dividerTheme.color?.withAlpha(40) ?? Colors.grey.withAlpha(40),
            strokeWidth: 0.5,
          );
        },
        getDrawingVerticalLine: (value) => FlLine(color: Colors.transparent, strokeWidth: 0),
      ),
      titlesData: FlTitlesData(
        show: true,
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (value, meta) {
              final index = value.toInt();
              if (index >= 0 && index < _dailyData.length) {
                final day = _dailyData[index]['day'] as String;
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text(
                    day,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white70
                          : Colors.grey[600],
                    ),
                  ),
                );
              }
              return const SideTitleWidget(
                axisSide: AxisSide.top,
                child: SizedBox.shrink(),
              );
            },
            interval: 1,
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 60, // Increased to prevent clipping of labels
            getTitlesWidget: (value, meta) {
              return SideTitleWidget(
                axisSide: meta.axisSide,
                child: Text(
                  '${value.toInt()}h',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white70
                        : Colors.grey[600],
                  ),
                ),
              );
            },
            interval: interval, // Use dynamic interval
          ),
        ),
      ),
      borderData: FlBorderData(
        show: true,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerTheme.color ?? Colors.grey,
            width: 1,
          ),
          left: BorderSide(
            color: Theme.of(context).dividerTheme.color ?? Colors.grey,
            width: 1,
          ),
          top: BorderSide.none,
          right: BorderSide.none,
        ),
      ),
      minX: 0,
      maxX: _dailyData.length.toDouble() - 1,
      minY: 0,
      maxY: maxY,
      lineBarsData: [
        LineChartBarData(
          spots: _dailyData.asMap().entries.map((entry) {
            final index = entry.key.toDouble();
            final focusHours = (entry.value['focusHours'] as num?)?.toDouble() ?? 0.0;
            return FlSpot(index, focusHours);
          }).toList(),
          isCurved: false,
          color: const Color(0xFF0F766E), // Purple/blue primary accent
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, barData, index) =>
                FlDotCirclePainter(
                  radius: 4,
                  color: const Color(0xFF0F766E),
                  strokeWidth: 2,
                  strokeColor: const Color(0xFFFFFFFF),
                ),
          ),
          belowBarData: BarAreaData(
            show: true,
            color: const Color(0xFF0F766E).withValues(alpha: 0.1),
          ),
        ),
        LineChartBarData(
          spots: _dailyData.asMap().entries.map((entry) {
            final index = entry.key.toDouble();
            final idleHours = (entry.value['idleHours'] as num?)?.toDouble() ?? 0.0;
            return FlSpot(index, idleHours);
          }).toList(),
          isCurved: false,
          color: const Color(0xFF4CAF50), // Green for idle (productive break)
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, barData, index) =>
                FlDotCirclePainter(
                  radius: 4,
                  color: const Color(0xFF4CAF50),
                  strokeWidth: 2,
                  strokeColor: const Color(0xFFFFFFFF),
                ),
          ),
          belowBarData: BarAreaData(
            show: true,
            color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
          ),
        ),
      ],
    );
  }
}