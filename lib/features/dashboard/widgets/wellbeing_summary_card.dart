import 'package:flutter/material.dart';
import 'package:intellibreak/core/design_system.dart';
import 'package:intellibreak/features/analytics/services/analytics_service.dart';
import 'package:intellibreak/features/auth/services/api_service.dart';
import 'package:intellibreak/providers/work_session_provider.dart';
import 'package:provider/provider.dart';

/// Daily Wellbeing Summary widget for Employee Personalized Dashboard.
/// Displays latest session wellbeing check-in scores, trends, and pattern explanations.
class WellbeingSummaryCard extends StatefulWidget {
  const WellbeingSummaryCard({super.key});

  @override
  State<WellbeingSummaryCard> createState() => _WellbeingSummaryCardState();
}

class _WellbeingSummaryCardState extends State<WellbeingSummaryCard> {
  bool _isLoading = true;
  Map<String, dynamic> _wellbeingSummary = {};
  Map<String, dynamic> _wellnessInsights = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchWellbeingData();
  }

  Future<void> _fetchWellbeingData() async {
    try {
      final token = await ApiService().getToken();
      if (token == null) {
        if (mounted) setState(() { _isLoading = false; });
        return;
      }
      final analyticsService = AnalyticsService();
      final results = await Future.wait([
        analyticsService.getWellbeingSummary(token),
        ApiService().getMapWithAuth('/analytics/wellness/summary', token, allowNotFound: true),
      ]);

      if (mounted) {
        setState(() {
          _wellbeingSummary = results[0] ?? {};
          _wellnessInsights = results[1] ?? {};
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

    if (_wellbeingSummary.isEmpty && !_isLoading && sessionProvider.isActive) {
      _fetchWellbeingData();
    }

    final int checkinCount = _wellbeingSummary['checkinCount'] ?? 0;
    final double overallWellbeing = (_wellbeingSummary['avgOverallWellbeing'] as num?)?.toDouble() ?? 0.0;
    final double mentalFatigue = (_wellbeingSummary['avgMentalFatigue'] as num?)?.toDouble() ?? 0.0;
    final double workload = (_wellbeingSummary['avgWorkloadManageability'] as num?)?.toDouble() ?? 0.0;

    final String statusMessage = _wellnessInsights['message']?.toString() ?? 'No wellbeing patterns recorded yet.';

    return DesignSystem.premiumCard(
      context: context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.balance_outlined,
                size: 22,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Text(
                'Work–Life Balance',
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
                  color: Colors.blue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$checkinCount check-ins',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'A personal view of your wellbeing, workload, and recovery during work.',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: isDark ? Colors.white70 : const Color(0xFF596579),
            ),
          ),
          const SizedBox(height: 16),
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_error != null && _wellbeingSummary.isEmpty)
            Text(
              'Unable to load wellbeing summary.',
              style: TextStyle(color: Colors.red.shade400, fontSize: 13),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildScoreTile(
                        context,
                        label: 'Overall Wellbeing',
                        value: checkinCount > 0 ? '${overallWellbeing.toStringAsFixed(1)} / 5' : 'N/A',
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildScoreTile(
                        context,
                        label: 'Mental Fatigue',
                        value: checkinCount > 0 ? '${mentalFatigue.toStringAsFixed(1)} / 5' : 'N/A',
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildScoreTile(
                        context,
                        label: 'Workload Balance',
                        value: checkinCount > 0 ? '${workload.toStringAsFixed(1)} / 5' : 'N/A',
                        isDark: isDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF121218) : const Color(0xFFF8F8FB),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 18, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          statusMessage,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white70 : const Color(0xFF4B5563),
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Based on your check-ins. This is for reflection and is not a medical assessment.',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.35,
                    color: isDark ? Colors.white54 : const Color(0xFF788397),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildScoreTile(
    BuildContext context, {
    required String label,
    required String value,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF121218) : const Color(0xFFF8F8FB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white60 : const Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF171923),
            ),
          ),
        ],
      ),
    );
  }
}
