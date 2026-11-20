import 'package:flutter/material.dart';
import 'package:intellibreak/core/theme/theme_controller.dart';
import 'package:intellibreak/core/design_system.dart';
import 'package:intellibreak/features/analytics/widgets/focus_idle_line_chart.dart';
import 'package:intellibreak/features/analytics/widgets/today_focus_ratio_chart.dart';
import 'package:intellibreak/widgets/state_display.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AnalyticsSection extends StatefulWidget {
  const AnalyticsSection({super.key});

  @override
  State<AnalyticsSection> createState() => _AnalyticsSectionState();
}

class _AnalyticsSectionState extends State<AnalyticsSection> {
  String? _token;
  bool _isLoading = true;
  String? _errorMessage;

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

  Future<void> _refreshData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await _loadToken();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return StateDisplay(
      isLoading: _isLoading,
      errorMessage: _errorMessage,
      isEmpty: _token == null || _token!.isEmpty,
      content: _buildAnalyticsContent(context),
      onRetry: _refreshData,
      loadingMessage: 'Loading your analytics...',
      emptyMessage: 'Not enough data yet',
      emptyAction: ElevatedButton(
        onPressed: _refreshData,
        child: const Text('Try again'),
      ),
    );
  }

  Widget _buildAnalyticsContent(BuildContext context) {
    if (_token == null || _token!.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_outline,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: DesignSystem.spacingM),
            Text(
              'Please sign in to view your analytics',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Sign in to see your work patterns and progress',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    final themeController = Provider.of<ThemeController>(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = themeController.isHighContrast;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with icon + label pattern (accessibility)
        Row(
          children: [
            Icon(
              Icons.analytics_outlined,
              size: 24,
              color: Theme.of(context).colorScheme.secondary,
            ),
            const SizedBox(width: 12),
            Text(
              'Analytics',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark
                    ? (isHighContrast ? Colors.white : Color(0xFFE8EBEF))
                    : Color(0xFF111827),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Stats overview (now replaced with charts)
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 600) {
              // Desktop: Two column layout
              return Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: _buildChartCard(
                      context: context,
                      title: 'Focus vs Idle Time',
                      height: 180,
                      child: FocusIdleLineChart(token: _token!),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 1,
                    child: _buildChartCard(
                      context: context,
                      title: 'Focus Distribution',
                      height: 180,
                      child: TodayFocusRatioChart(token: _token!),
                    ),
                  ),
                ],
              );
            } else {
              // Mobile: Vertical stack
              return Column(
                children: [
                  // Focus vs Idle Time (Weekly Line Chart)
                  _buildChartCard(
                    context: context,
                    title: 'Focus vs Idle Time',
                    height: 180,
                    child: FocusIdleLineChart(token: _token!),
                  ),
                  const SizedBox(height: 24),
                  // Focus Distribution (Donut Chart)
                  _buildChartCard(
                    context: context,
                    title: 'Focus Distribution',
                    height: 180,
                    child: TodayFocusRatioChart(token: _token!),
                  ),
                ],
              );
            }
          },
        ),
      ],
    );
  }

  Widget _buildChartCard({
    required BuildContext context,
    required String title,
    required Widget child,
    IconData icon = Icons.analytics_outlined,
    double height = 200,
  }) {
    final themeController = Provider.of<ThemeController>(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = themeController.isHighContrast;
    final color = Theme.of(context).colorScheme.secondary;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? (isHighContrast ? const Color(0xFF0D0D0D) : Color(0xFF1A1A1A))
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? (isHighContrast
                    ? Colors.white.withValues(alpha: 0.1)
                    : Color(0xFF262D37))
              : Colors.grey.withValues(alpha: 0.2),
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon + Label (accessibility)
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
                            : Color(0xFF9AA3AF))
                      : Color(0xFF5B6472),
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
}