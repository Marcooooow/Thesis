import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../services/analytics_service.dart';

class DailyWorkHoursBarChart extends StatefulWidget {
  final String? token;
  final DateTime? startDate;
  final DateTime? endDate;

  const DailyWorkHoursBarChart({
    super.key,
    this.token,
    this.startDate,
    this.endDate,
  });

  const DailyWorkHoursBarChart.demo()
    : token = null,
      startDate = null,
      endDate = null,
      super(key: const Key('demo-daily-work-hours-bar-chart'));

  @override
  State<DailyWorkHoursBarChart> createState() => _DailyWorkHoursBarChartState();
}

class _DailyWorkHoursBarChartState extends State<DailyWorkHoursBarChart> {
  final AnalyticsService _analyticsService = AnalyticsService();
  List<Map<String, dynamic>> _weeklyData = List.generate(
    7,
    (index) => {
      'day': ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][index],
      'actualHours': 0.0,
      'targetHours': 8.0,
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
        _weeklyData = [
          {'day': 'Mon', 'actualHours': 7.5, 'targetHours': 8.0},
          {'day': 'Tue', 'actualHours': 6.5, 'targetHours': 8.0},
          {'day': 'Wed', 'actualHours': 8.0, 'targetHours': 8.0},
          {'day': 'Thu', 'actualHours': 7.0, 'targetHours': 8.0},
          {'day': 'Fri', 'actualHours': 6.0, 'targetHours': 8.0},
          {'day': 'Sat', 'actualHours': 2.0, 'targetHours': 8.0},
          {'day': 'Sun', 'actualHours': 1.0, 'targetHours': 8.0},
        ];
        _isLoading = false;
      });
      return;
    }

    try {
      final data = await _analyticsService.getDailyWorkHours(
        widget.token!,
        startDate: widget.startDate,
        endDate: widget.endDate,
      );
      if (mounted) {
        setState(() {
          _weeklyData = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
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
    final hasData = _weeklyData.any((day) {
      final actual = (day['actualHours'] as num?)?.toDouble() ?? 0.0;
      final target = (day['targetHours'] as num?)?.toDouble() ?? 0.0;
      return actual > 0 || target > 0;
    });
    if (!hasData) {
      return Center(
        child: Text(
          'No work hours data available',
          style: TextStyle(color: isDark ? Colors.white70 : Colors.grey[600]),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(flex: 1, fit: FlexFit.loose, child: BarChart(mainBarData())),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegendItem('Actual Hours', const Color(0xFF6C63FF), isDark),
              const SizedBox(width: 16),
              _buildLegendItem('Target Hours', const Color(0xFF9CA3AF), isDark),
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
            color: isDark ? Colors.white : const Color(0xFF171923),
          ),
        ),
      ],
    );
  }

  BarChartData mainBarData() {
    return BarChartData(
      alignment: BarChartAlignment.spaceAround,
      maxY: (() {
        final all = [
          ..._weeklyData.map((d) => (d['actualHours'] as num?)?.toDouble() ?? 0.0),
          ..._weeklyData.map((d) => (d['targetHours'] as num?)?.toDouble() ?? 8.0),
        ];
        double m = 0.0;
        for (final v in all) {
          if (v > m) {
            m = v;
          }
        }
        return m * 1.2;
      })(),
      barTouchData: BarTouchData(
        enabled: true,
        touchTooltipData: BarTouchTooltipData(
          getTooltipColor: (group) =>
              Theme.of(context).brightness == Brightness.dark
              ? Colors.grey[800] ?? Colors.black
              : Colors.grey[100] ?? Colors.white,
        ),
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
              if (index >= 0 && index < _weeklyData.length) {
                final day = _weeklyData[index]['day'] as String;
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
            reservedSize: 48,
            getTitlesWidget: (value, meta) {
              return SideTitleWidget(
                axisSide: meta.axisSide,
                child: Text(
                  '${value.toInt()}h',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white70
                        : Colors.grey[600],
                  ),
                ),
              );
            },
            interval: 2,
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
      barGroups: _weeklyData.asMap().entries.map((entry) {
        final index = entry.key;
        final dayData = entry.value;
        final actualHours = (dayData['actualHours'] as num?)?.toDouble() ?? 0.0;
        final targetHours = (dayData['targetHours'] as num?)?.toDouble() ?? 8.0;

        return BarChartGroupData(
          x: index,
          barRods: [
            BarChartRodData(
              toY: actualHours,
              color: const Color(0xFF6C63FF), // Purple/blue primary accent
              width: 16,
            ),
            BarChartRodData(
              toY: targetHours,
              color: const Color(0xFF9CA3AF), // Gray for target
              width: 16,
            ),
          ],
        );
      }).toList(),
    );
  }
}
