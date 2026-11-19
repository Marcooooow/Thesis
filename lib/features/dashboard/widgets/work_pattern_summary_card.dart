import 'package:flutter/material.dart';
import 'package:intellibreak/core/design_system.dart';
import 'package:intellibreak/features/analytics/services/analytics_service.dart';
import 'package:intellibreak/features/auth/services/api_service.dart';
import 'package:intellibreak/providers/work_session_provider.dart';
import 'package:provider/provider.dart';

/// Work Pattern & Break Compliance Summary widget for Employee Personalized Dashboard.
/// Displays break frequency, compliance score, average break duration, and missed/delayed break indicators.
class WorkPatternSummaryCard extends StatefulWidget {
  const WorkPatternSummaryCard({super.key});

  @override
  State<WorkPatternSummaryCard> createState() => _WorkPatternSummaryCardState();
}

class _WorkPatternSummaryCardState extends State<WorkPatternSummaryCard> {
  bool _isLoading = true;
  Map<String, dynamic>? _breakAnalysis;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchBreakAnalysis();
  }

  Future<void> _fetchBreakAnalysis() async {
    try {
      final token = await ApiService().getToken();
      if (token == null) {
        if (mounted) setState(() { _isLoading = false; });
        return;
      }
      final result = await AnalyticsService().getBreakAnalysis(token);
      if (mounted) {
        setState(() {
          _breakAnalysis = result;
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
    final sessionProvider = context.watch<WorkSessionProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Refresh if session state changes
    if (_breakAnalysis == null && !_isLoading && sessionProvider.isActive) {
      _fetchBreakAnalysis();
    }

    final data = _breakAnalysis ?? {};
    final int totalBreaks = data['totalBreaks'] ?? 0;
    final double totalBreakSeconds = (data['totalBreakSeconds'] as num?)?.toDouble() ?? 0.0;
    final double avgBreakSecs = (data['avgBreakDurationSeconds'] as num?)?.toDouble() ?? 0.0;
    final double complianceScore = (data['complianceScore'] as num?)?.toDouble() ?? 100.0;

    final avgBreakMins = (avgBreakSecs / 60).round();
    final totalBreakMins = (totalBreakSeconds / 60).round();

    return DesignSystem.premiumCard(
      context: context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.analytics_outlined,
                size: 22,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Text(
                'Work Pattern & Break Compliance',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                  color: isDark ? Colors.white : const Color(0xFF171923),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: complianceScore >= 80 ? Colors.green.withValues(alpha: 0.15) : Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Compliance: ${complianceScore.toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: complianceScore >= 80 ? Colors.green.shade700 : Colors.orange.shade700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_error != null && _breakAnalysis == null)
            Text(
              'Unable to load work patterns.',
              style: TextStyle(color: Colors.red.shade400, fontSize: 13),
            )
          else
            Row(
              children: [
                Expanded(
                  child: _buildMetricTile(
                    context,
                    title: 'Break Frequency',
                    value: '$totalBreaks breaks',
                    subtitle: 'Today\'s Records (Historical)',
                    icon: Icons.repeat_outlined,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetricTile(
                    context,
                    title: 'Avg Duration',
                    value: '${avgBreakMins}m',
                    subtitle: 'Target: 15m - 30m',
                    icon: Icons.timer_outlined,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetricTile(
                    context,
                    title: 'Total Break Time',
                    value: '${totalBreakMins}m',
                    subtitle: 'Rest & Recovery',
                    icon: Icons.spa_outlined,
                    isDark: isDark,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildMetricTile(
    BuildContext context, {
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF121218) : const Color(0xFFF8F8FB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Theme.of(context).colorScheme.secondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : const Color(0xFF6B7280),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
              color: isDark ? Colors.white : const Color(0xFF171923),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white54 : const Color(0xFF9CA3AF),
            ),
          ),
        ],
      ),
    );
  }
}
