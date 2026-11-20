import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../services/analytics_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TodayFocusRatioChart extends StatefulWidget {
  final String? token;
  final DateTime? startDate;
  final DateTime? endDate;

  const TodayFocusRatioChart({
    super.key,
    this.token,
    this.startDate,
    this.endDate,
  });

  const TodayFocusRatioChart.demo()
    : token = null,
      startDate = null,
      endDate = null,
      super(key: const Key('demo-today-focus-ratio-chart'));

  @override
  State<TodayFocusRatioChart> createState() => _TodayFocusRatioChartState();
}

class _TodayFocusRatioChartState extends State<TodayFocusRatioChart> {
  final AnalyticsService _analyticsService = AnalyticsService();
  Map<String, double> _focusRatioData = {
    'activeFocus': 0.0,
    'nonActive': 0.0,
    'idle': 0.0,
  };
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
        _focusRatioData = {
          'activeFocus': 65.0,
          'nonActive': 20.0,
          'idle': 15.0,
        };
        _isLoading = false;
      });
      return;
    }

    try {
      final data = await _analyticsService.getFocusRatio(
        widget.token!,
        startDate: widget.startDate,
        endDate: widget.endDate,
      );
      if (mounted) {
        setState(() {
          _focusRatioData = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        // If the error is due to an invalid token, clear it.
        if (e.toString().contains('401') || e.toString().contains('Unauthorized')) {
          // Clear the token from SharedPreferences.
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

    // Calculate total to ensure we have valid data
    final total = _focusRatioData.values.fold(0.0, (sum, value) => sum + value);
    if (total == 0) {
      // Show placeholder when no data available
      return Center(
        child: Text(
          'No focus data available',
          style: TextStyle(color: isDark ? Colors.white70 : Colors.grey[600]),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 100,
          child: PieChart(
            PieChartData(
              pieTouchData: PieTouchData(
                touchCallback: (FlTouchEvent event, pieTouchResponse) {
                  // Handle touch events if needed
                },
              ),
              borderData: FlBorderData(show: false),
              sectionsSpace: 0,
              centerSpaceRadius: 20,
              sections: [
                PieChartSectionData(
                  color: const Color(0xFF0F766E), // Purple/blue primary accent
                  value: _focusRatioData['activeFocus'] ?? 0.0,
                  title:
                      '${(_focusRatioData['activeFocus'] ?? 0.0).toStringAsFixed(0)}%',
                  radius: 40,
                  titleStyle: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                PieChartSectionData(
                  color: const Color(0xFF9CA3AF), // Gray for non-active
                  value: _focusRatioData['nonActive'] ?? 0.0,
                  title:
                      '${(_focusRatioData['nonActive'] ?? 0.0).toStringAsFixed(0)}%',
                  radius: 30,
                  titleStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                PieChartSectionData(
                  color: const Color(
                    0xFF4CAF50,
                  ), // Green for idle (productive break)
                  value: _focusRatioData['idle'] ?? 0.0,
                  title:
                      '${(_focusRatioData['idle'] ?? 0.0).toStringAsFixed(0)}%',
                  radius: 20,
                  titleStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegendItem(
                'Active Focus',
                const Color(0xFF0F766E),
                _focusRatioData['activeFocus'] ?? 0.0,
                isDark,
              ),
              const SizedBox(width: 8),
              _buildLegendItem(
                'Non-Active',
                const Color(0xFF9CA3AF),
                _focusRatioData['nonActive'] ?? 0.0,
                isDark,
              ),
              const SizedBox(width: 8),
              _buildLegendItem(
                'Idle',
                const Color(0xFF4CAF50),
                _focusRatioData['idle'] ?? 0.0,
                isDark,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLegendItem(
    String label,
    Color color,
    double value,
    bool isDark,
  ) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$label: ${value.toStringAsFixed(0)}%',
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white : const Color(0xFF111827),
          ),
        ),
      ],
    );
  }
}
