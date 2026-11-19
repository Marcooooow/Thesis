import 'dart:async';

import 'package:flutter/material.dart';

import 'package:intellibreak/core/theme/theme_controller.dart';
import 'package:intellibreak/features/analytics/services/analytics_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intellibreak/providers/work_session_provider.dart';

class MetricsSection extends StatefulWidget {
  const MetricsSection({super.key});

  @override
  State<MetricsSection> createState() => _MetricsSectionState();
}

class _MetricsSectionState extends State<MetricsSection> {
  String? _token;
  bool _isLoading = true;
  String? _error;

  Map<String, dynamic>? _summary;

  late final WorkSessionProvider _workSessionProvider;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _workSessionProvider = Provider.of<WorkSessionProvider>(context, listen: false);
    _loadToken();
    _workSessionProvider.addListener(_onWorkSessionUpdate);
  }

  void _onWorkSessionUpdate() {
    if (_token != null) {
      _scheduleRefresh();
    }
  }

  void _scheduleRefresh() {
    if (_debounce?.isActive ?? false) {
      _debounce?.cancel();
    }
    _debounce = Timer(const Duration(milliseconds: 500), _loadData);
  }

  @override
  void dispose() {
    _workSessionProvider.removeListener(_onWorkSessionUpdate);
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (!mounted) return;
    setState(() {
      _token = token;
      _isLoading = false;
    });
    if (_token != null) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final analyticsService = AnalyticsService();

    try {
      final summary = await analyticsService.getTodaySummary(_token!);
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_token == null) {
      return Center(
        child: Text(
          'Please sign in to view your metrics',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }

    if (_isLoading && _summary == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _summary == null) {
      return Center(child: Text('Error loading metrics: $_error'));
    }

    final themeController = Provider.of<ThemeController>(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = themeController.isHighContrast;
    final bool isDesktop = MediaQuery.of(context).size.width >= 1100;

    final summary = _summary ?? {};
    final double focusRate = (summary['focusRate'] as num?)?.toDouble() ?? 0.0;
    final num focusedSeconds = summary['focusedSeconds'] ?? 0;
    final num? idleSeconds = summary['idleSeconds'];
    final double workedHours = (summary['workedHours'] as num?)?.toDouble() ?? 0.0;
    final double targetDailyHours = (summary['targetDailyHours'] as num?)?.toDouble() ?? 8.0;
    final String targetHoursStr = '${workedHours.toStringAsFixed(1)} / ${targetDailyHours.toStringAsFixed(0)}';

    String formatHMS(num? seconds) {
      if (seconds == null) return 'N/A';
      final sInt = seconds.round();
      final h = sInt ~/ 3600;
      final m = (sInt % 3600) ~/ 60;
      final s = sInt % 60;
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }

    final String idleText = idleSeconds != null ? formatHMS(idleSeconds) : 'N/A';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Today's Metrics",
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
            color: isDark
                ? (isHighContrast ? Colors.white : const Color(0xFFF2F2F2))
                : const Color(0xFF171923),
          ),
        ),
        const SizedBox(height: 16),
        FocusRateHero(rate: focusRate, isLoading: _isLoading),
        const SizedBox(height: 16),
        isDesktop
            ? _buildSecondaryRow(formatHMS(focusedSeconds), idleText, targetHoursStr)
            : _buildSecondaryScroll(formatHMS(focusedSeconds), idleText, targetHoursStr),
      ],
    );
  }

  Widget _buildSecondaryRow(String focusedTime, String idleTime, String targetHour) {
    return Row(
      children: [
        Expanded(
          child: SecondaryMetricCard(
            value: focusedTime,
            label: 'Focused Time',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SecondaryMetricCard(
            value: idleTime,
            label: 'Idle Time',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SecondaryMetricCard(
            value: targetHour,
            label: 'Target Hour',
          ),
        ),
      ],
    );
  }

  Widget _buildSecondaryScroll(String focusedTime, String idleTime, String targetHour) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: SecondaryMetricCard(
              value: focusedTime,
              label: 'Focused Time',
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 150,
            child: SecondaryMetricCard(
              value: idleTime,
              label: 'Idle Time',
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 150,
            child: SecondaryMetricCard(
              value: targetHour,
              label: 'Target Hour',
            ),
          ),
        ],
      ),
    );
  }
}

class FocusRateHero extends StatelessWidget {
  final double rate;
  final bool isLoading;
  const FocusRateHero({super.key, required this.rate, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = Theme.of(context).colorScheme.secondary;
    final value = isLoading ? '--' : '${rate.toStringAsFixed(0)}%';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
          width: 0.8,
        ),
        color: isDark ? const Color(0xFF121218) : const Color(0xFFF8F8FB),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'FOCUS RATE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
              color: isDark ? Colors.white.withValues(alpha: 0.5) : const Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              height: 1.0,
              letterSpacing: -2.5,
              color: color,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: isLoading ? 0 : rate / 100,
              minHeight: 4,
              backgroundColor: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

class SecondaryMetricCard extends StatelessWidget {
  final String value;
  final String label;
  const SecondaryMetricCard({super.key, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
          width: 0.8,
        ),
        color: isDark ? const Color(0xFF121218) : const Color(0xFFF8F8FB),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.8,
              height: 1.1,
              color: isDark ? Colors.white : const Color(0xFF171923),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF6B7280),
            ),
          ),
        ],
      ),
    );
  }
}
