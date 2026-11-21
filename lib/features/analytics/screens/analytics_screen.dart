import 'package:flutter/material.dart';
import 'package:intellibreak/core/theme/theme_controller.dart';
import 'package:intellibreak/core/motion.dart';
import 'package:intellibreak/features/analytics/widgets/focus_idle_line_chart.dart';
import 'package:intellibreak/features/analytics/widgets/today_focus_ratio_chart.dart';
import 'package:intellibreak/features/analytics/widgets/focus_rate_progress.dart';
import 'package:intellibreak/features/analytics/widgets/daily_work_hours_bar_chart.dart';
import 'package:intellibreak/features/analytics/widgets/daily_progress_summary_card.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AnalyticsScreenContent extends StatefulWidget {
  const AnalyticsScreenContent({super.key});

  @override
  State<AnalyticsScreenContent> createState() => _AnalyticsScreenContentState();
}

class _AnalyticsScreenContentState extends State<AnalyticsScreenContent> {
  String? _token;
  bool _isLoading = true;
  String _selectedPeriod = 'Today'; // Default period

  // Helper method to convert period string to start and end dates
  (DateTime?, DateTime?) _getDateRangeForPeriod(String period) {
    final now = DateTime.now();
    DateTime startDate;
    DateTime endDate;

    switch (period) {
      case 'Today':
        startDate = DateTime(now.year, now.month, now.day);
        endDate = now;
        break;
      case 'Yesterday':
        final yesterday = now.subtract(const Duration(days: 1));
        startDate = DateTime(yesterday.year, yesterday.month, yesterday.day);
        endDate = DateTime(
          yesterday.year,
          yesterday.month,
          yesterday.day,
          23,
          59,
          59,
        );
        break;
      case 'Last 7 Days':
        startDate = now.subtract(const Duration(days: 7));
        endDate = now;
        break;
      case 'Last 30 Days':
        startDate = now.subtract(const Duration(days: 30));
        endDate = now;
        break;
      case 'This Week':
        // Start of week (Monday)
        int dayOffset = now.weekday - 1; // Monday is 1, Sunday is 7
        if (dayOffset < 0) dayOffset = 6; // Adjust for Sunday
        startDate = DateTime(now.year, now.month, now.day - dayOffset);
        endDate = now;
        break;
      case 'This Month':
        startDate = DateTime(now.year, now.month, 1);
        endDate = now;
        break;
      default:
        // Default to today
        startDate = DateTime(now.year, now.month, now.day);
        endDate = now;
    }

    return (startDate, endDate);
  }

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (!mounted) return;
    setState(() {
      _token = token;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isDesktop = MediaQuery.of(context).size.width >= 1100;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight,
              maxWidth: constraints.maxWidth,
            ),
            child: isDesktop
                ? _buildDesktopLayout(context, isDark)
                : _buildMobileLayout(context, isDark),
          ),
        );
      },
    );
  }

  Widget _buildDesktopLayout(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row with date filter
          DelayedAnimatedSection(
            delay: Duration.zero,
            slideDirection: SlideDirection.topToBottom,
            visible: true,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Analytics',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                _buildDateFilterDropdown(context, isDark),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Top row: Focus Rate + Today's Focus Ratio
          DelayedAnimatedSection(
            delay: Duration(milliseconds: MotionDurations.stagger.inMilliseconds),
            slideDirection: SlideDirection.topToBottom,
            visible: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 1,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 280),
                    child: _buildFocusRateCard(context, period: _selectedPeriod),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 1,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 280),
                    child: _buildFocusRatioCard(context, period: _selectedPeriod),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Daily Progress Summary Card
          DelayedAnimatedSection(
            delay: MotionDurations.stagger * 1.5,
            slideDirection: SlideDirection.topToBottom,
            visible: true,
            child: _token == null
                ? const Center(child: Text('Please sign in to view analytics'))
                : DailyProgressSummaryCard(token: _token!),
          ),
          const SizedBox(height: 24),

          // Weekly Focus vs Idle chart (full width)
          DelayedAnimatedSection(
            delay: Duration(milliseconds: MotionDurations.stagger.inMilliseconds * 2),
            slideDirection: SlideDirection.topToBottom,
            visible: true,
            child: _buildChartCard(
              context: context,
              title: 'Weekly Focus vs Idle Time',
              height: 320,
              child: _token == null
                  ? const Center(child: Text('Please sign in to view analytics'))
                  : FocusIdleLineChart(token: _token!),
            ),
          ),
          const SizedBox(height: 24),

          // Weekly Work Hours chart (full width)
          DelayedAnimatedSection(
            delay: Duration(milliseconds: MotionDurations.stagger.inMilliseconds * 3),
            slideDirection: SlideDirection.topToBottom,
            visible: true,
            child: _buildChartCard(
              context: context,
              title: 'Weekly Work Hours',
              height: 320,
              child: _token == null
                  ? const Center(child: Text('Please sign in to view analytics'))
                  : DailyWorkHoursBarChart(token: _token!),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title with filter
          DelayedAnimatedSection(
            delay: Duration.zero,
            slideDirection: SlideDirection.topToBottom,
            visible: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Analytics',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 12),
                _buildDateFilterDropdown(context, isDark),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Focus Rate Card
          DelayedAnimatedSection(
            delay: Duration(milliseconds: MotionDurations.stagger.inMilliseconds),
            slideDirection: SlideDirection.topToBottom,
            visible: true,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 240),
              child: _buildFocusRateCard(context, period: _selectedPeriod),
            ),
          ),
          const SizedBox(height: 16),

          // Today's Focus Ratio Card
          DelayedAnimatedSection(
            delay: Duration(milliseconds: MotionDurations.stagger.inMilliseconds * 2),
            slideDirection: SlideDirection.topToBottom,
            visible: true,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 240),
              child: _buildFocusRatioCard(context, period: _selectedPeriod),
            ),
          ),
          const SizedBox(height: 16),

          // Daily Progress Summary Card
          DelayedAnimatedSection(
            delay: MotionDurations.stagger * 2.5,
            slideDirection: SlideDirection.topToBottom,
            visible: true,
            child: _token == null
                ? const Center(child: Text('Please sign in to view analytics'))
                : DailyProgressSummaryCard(token: _token!),
          ),
          const SizedBox(height: 16),

          // Weekly Focus vs Idle chart
          DelayedAnimatedSection(
            delay: Duration(milliseconds: MotionDurations.stagger.inMilliseconds * 3),
            slideDirection: SlideDirection.topToBottom,
            visible: true,
            child: _buildChartCard(
              context: context,
              title: 'Weekly Focus vs Idle Time',
              height: 280,
              child: _token == null
                  ? const Center(child: Text('Please sign in to view analytics'))
                  : FocusIdleLineChart(token: _token!),
            ),
          ),
          const SizedBox(height: 16),

          // Weekly Work Hours chart
          DelayedAnimatedSection(
            delay: Duration(milliseconds: MotionDurations.stagger.inMilliseconds * 4),
            slideDirection: SlideDirection.topToBottom,
            visible: true,
            child: _buildChartCard(
              context: context,
              title: 'Weekly Work Hours',
              height: 280,
              child: _token == null
                  ? const Center(child: Text('Please sign in to view analytics'))
                  : DailyWorkHoursBarChart(token: _token!),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFocusRateCard(BuildContext context, {String? period}) {
    final themeController = Provider.of<ThemeController>(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = themeController.isHighContrast;

    // Get date range for the period
    final (startDate, endDate) = period != null
        ? _getDateRangeForPeriod(period)
        : (null, null);

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? (isHighContrast
                  ? const Color(0xFF0D0D0D)
                  : const Color(0xFF1A1A1A))
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? (isHighContrast
                    ? Colors.white.withValues(alpha: 0.1)
                    : const Color(0xFF2D3643))
              : Colors.grey.withValues(alpha: 0.2),
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondary
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.trending_up,
                  size: 20,
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Focus Rate',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? (isHighContrast
                            ? Colors.white.withValues(alpha: 0.8)
                            : const Color(0xFF9AA3AF))
                      : const Color(0xFF5B6472),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            period != null
                ? 'Focus rate for $period'
                : 'Shows today\'s focus rate',
            style: TextStyle(
              fontSize: 12,
              color: isDark
                  ? (isHighContrast
                        ? Colors.white.withValues(alpha: 0.6)
                        : const Color(0xFF9AA3AF))
                  : const Color(0xFF9CA3AF),
            ),
          ),
          const SizedBox(height: 12),
          Flexible(
            flex: 1,
            fit: FlexFit.loose,
            child: Center(
              child: _token == null
                  ? const Center(child: Text('Please sign in to view analytics'))
                  : FocusRateProgress(
                      token: _token!,
                      startDate: startDate,
                      endDate: endDate,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFocusRatioCard(BuildContext context, {String? period}) {
    final themeController = Provider.of<ThemeController>(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = themeController.isHighContrast;

    // Get date range for the period
    final (startDate, endDate) = period != null
        ? _getDateRangeForPeriod(period)
        : (null, null);

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? (isHighContrast
                  ? const Color(0xFF0D0D0D)
                  : const Color(0xFF1A1A1A))
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? (isHighContrast
                    ? Colors.white.withValues(alpha: 0.1)
                    : const Color(0xFF2D3643))
              : Colors.grey.withValues(alpha: 0.2),
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondary
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.show_chart,
                  size: 20,
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Today\'s Focus Ratio',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? (isHighContrast
                            ? Colors.white.withValues(alpha: 0.8)
                            : const Color(0xFF9AA3AF))
                      : const Color(0xFF5B6472),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            period != null
                ? 'Focus ratio for $period'
                : 'Shows today\'s focus ratio',
            style: TextStyle(
              fontSize: 12,
              color: isDark
                  ? (isHighContrast
                        ? Colors.white.withValues(alpha: 0.6)
                        : const Color(0xFF9AA3AF))
                  : const Color(0xFF9CA3AF),
            ),
          ),
          const SizedBox(height: 8),
          Flexible(
            flex: 1,
            fit: FlexFit.loose,
            child: Center(
              child: _token == null
                  ? const Center(child: Text('Please sign in to view analytics'))
                  : TodayFocusRatioChart(
                      token: _token!,
                      startDate: startDate,
                      endDate: endDate,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartCard({
    required BuildContext context,
    required String title,
    required Widget child,
    IconData icon = Icons.analytics_outlined,
    double height = 320,
  }) {
    final themeController = Provider.of<ThemeController>(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = themeController.isHighContrast;
    final color = Theme.of(context).colorScheme.secondary;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? (isHighContrast
                  ? const Color(0xFF0D0D0D)
                  : const Color(0xFF1A1A1A))
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? (isHighContrast
                    ? Colors.white.withValues(alpha: 0.1)
                    : const Color(0xFF2D3643))
              : Colors.grey.withValues(alpha: 0.2),
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? (isHighContrast
                            ? Colors.white.withValues(alpha: 0.8)
                            : const Color(0xFF9AA3AF))
                      : const Color(0xFF5B6472),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, height: height, child: child),
        ],
      ),
    );
  }

  Widget _buildDateFilterDropdown(BuildContext context, bool isDark) {
    final themeController = Provider.of<ThemeController>(context);
    final bool isHighContrast = themeController.isHighContrast;

    final periods = [
      'Today',
      'Yesterday',
      'Last 7 Days',
      'Last 30 Days',
      'This Week',
      'This Month',
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? (isHighContrast
                  ? const Color(0xFF0D0D0D)
                  : const Color(0xFF182029))
            : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark
              ? (isHighContrast
                    ? Colors.white.withValues(alpha: 0.2)
                    : const Color(0xFF2D3643))
              : Colors.grey.shade300,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedPeriod,
          isDense: true,
          onChanged: (String? newValue) {
            if (newValue != null) {
              setState(() {
                _selectedPeriod = newValue;
              });
            }
          },
          items: periods.map<DropdownMenuItem<String>>((String period) {
            return DropdownMenuItem<String>(
              value: period,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.date_range,
                    size: 16,
                    color: isDark
                        ? (isHighContrast
                              ? Colors.white
                              : const Color(0xFF9AA3AF))
                        : Colors.grey.shade700,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    period,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          dropdownColor: isDark
              ? (isHighContrast
                    ? const Color(0xFF0D0D0D)
                    : const Color(0xFF182029))
              : Colors.white,
          icon: Icon(
            Icons.arrow_drop_down,
            color: isDark
                ? (isHighContrast ? Colors.white : const Color(0xFF9AA3AF))
                : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }
}
