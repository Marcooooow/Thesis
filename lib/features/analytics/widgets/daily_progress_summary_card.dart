import 'package:flutter/material.dart';
import 'package:intellibreak/core/design_system.dart';
import 'package:intellibreak/features/analytics/services/analytics_service.dart';

/// Comprehensive Daily Progress Summary widget displaying Work, Task, Break,
/// Wellbeing, Recommendation, and Target progress metrics for a selected date.
class DailyProgressSummaryCard extends StatefulWidget {
  final String token;
  final String? initialDate; // YYYY-MM-DD

  const DailyProgressSummaryCard({
    super.key,
    required this.token,
    this.initialDate,
  });

  @override
  State<DailyProgressSummaryCard> createState() => _DailyProgressSummaryCardState();
}

class _DailyProgressSummaryCardState extends State<DailyProgressSummaryCard> {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic> _summaryData = {};
  late String _selectedDateStr;

  @override
  void initState() {
    super.initState();
    _selectedDateStr = widget.initialDate ?? DateTime.now().toIso8601String().split('T')[0];
    _fetchSummary();
  }

  Future<void> _fetchSummary() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final service = AnalyticsService();
      final data = await service.getDailyProgressSummary(widget.token, date: _selectedDateStr);
      if (mounted) {
        setState(() {
          _summaryData = data;
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

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_selectedDateStr) ?? DateTime.now(),
      firstDate: DateTime(2025, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() {
        _selectedDateStr = picked.toIso8601String().split('T')[0];
      });
      _fetchSummary();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DesignSystem.premiumCard(
      context: context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with Title & Date Picker
          Row(
            children: [
              Icon(
                Icons.assessment_outlined,
                size: 22,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Text(
                'Daily Progress Summary',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                  color: isDark ? Colors.white : const Color(0xFF171923),
                ),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () => _selectDate(context),
                icon: const Icon(Icons.calendar_today, size: 14),
                label: Text(_selectedDateStr),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Loading state
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                children: [
                  Text(
                    'Failed to load daily progress summary.',
                    style: TextStyle(color: Colors.red.shade400, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _fetchSummary,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          else if (_summaryData.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Center(
                child: Text(
                  'No activity recorded for $_selectedDateStr.',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white60 : const Color(0xFF6B7280),
                  ),
                ),
              ),
            )
          else
            _buildSummaryContent(context, isDark),
        ],
      ),
    );
  }

  Widget _buildSummaryContent(BuildContext context, bool isDark) {
    final work = _summaryData['workSummary'] ?? {};
    final task = _summaryData['taskSummary'] ?? {};
    final brk = _summaryData['breakSummary'] ?? {};
    final wellbeing = _summaryData['wellbeingSummary'] ?? {};
    final rec = _summaryData['recommendationSummary'] ?? {};
    final target = _summaryData['dailyTarget'] ?? {};

    final double targetHours = (target['targetHours'] as num?)?.toDouble() ?? 8.0;
    final double workedHours = (target['workedHours'] as num?)?.toDouble() ?? 0.0;
    final double progressPct = (target['progressPercentage'] as num?)?.toDouble() ?? 0.0;
    final bool targetMet = target['targetMet'] ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Target Progress Banner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: (targetMet ? Colors.green : Theme.of(context).colorScheme.primary).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: (targetMet ? Colors.green : Theme.of(context).colorScheme.primary).withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Daily Work Target (${workedHours.toStringAsFixed(1)}h / ${targetHours.toStringAsFixed(1)}h)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF171923),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: targetMet ? Colors.green.withValues(alpha: 0.2) : Colors.orange.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      targetMet ? 'Target Met' : '${progressPct.toStringAsFixed(0)}% Completed',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: targetMet ? Colors.green.shade700 : Colors.orange.shade800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: (progressPct / 100.0).clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: isDark ? Colors.white12 : Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    targetMet ? Colors.green : Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Grid of Summary Metrics
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 600;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildMetricTile(
                  context,
                  title: 'Work Summary',
                  icon: Icons.work_outline,
                  isWide: isWide,
                  children: [
                    _metricRow('Total Sessions', '${work['totalSessions'] ?? 0} (${work['completedSessions'] ?? 0} completed)'),
                    _metricRow('Working Hours', '${(work['totalWorkingHours'] ?? 0.0).toStringAsFixed(1)}h'),
                    _metricRow('Focus Rate', '${(work['focusPercentage'] ?? 0.0).toStringAsFixed(1)}%'),
                  ],
                ),
                _buildMetricTile(
                  context,
                  title: 'Task Summary',
                  icon: Icons.task_alt,
                  isWide: isWide,
                  children: [
                    _metricRow('Total Tasks', '${task['totalTasks'] ?? 0}'),
                    _metricRow('Completed', '${task['completedTasks'] ?? 0}'),
                    _metricRow('Task Hours', '${(task['actualTaskHours'] ?? 0.0).toStringAsFixed(1)}h'),
                  ],
                ),
                _buildMetricTile(
                  context,
                  title: 'Break Adherence',
                  icon: Icons.coffee_outlined,
                  isWide: isWide,
                  children: [
                    _metricRow('Total Breaks', '${brk['totalBreaks'] ?? 0}'),
                    _metricRow('Break Duration', '${(brk['totalBreakMinutes'] ?? 0.0).toStringAsFixed(0)}m'),
                    _metricRow('Compliance', '${(brk['complianceScore'] ?? 100.0).toStringAsFixed(0)}%'),
                  ],
                ),
                _buildMetricTile(
                  context,
                  title: 'Wellbeing Check-ins',
                  icon: Icons.favorite_border,
                  isWide: isWide,
                  children: [
                    _metricRow('Check-in Count', '${wellbeing['checkinCount'] ?? 0}'),
                    _metricRow('Overall Wellbeing', '${(wellbeing['avgOverallWellbeing'] ?? 0.0).toStringAsFixed(1)} / 5'),
                    _metricRow('Mental Fatigue', '${(wellbeing['avgMentalFatigue'] ?? 0.0).toStringAsFixed(1)} / 5'),
                  ],
                ),
                _buildMetricTile(
                  context,
                  title: 'Recommendations',
                  icon: Icons.lightbulb_outline,
                  isWide: isWide,
                  children: [
                    _metricRow('Total Suggested', '${rec['totalRecommendations'] ?? 0}'),
                    _metricRow('Accepted', '${rec['acceptedCount'] ?? 0}'),
                    _metricRow('Acceptance Rate', '${(rec['acceptanceRate'] ?? 0.0).toStringAsFixed(0)}%'),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildMetricTile(
    BuildContext context, {
    required String title,
    required IconData icon,
    required bool isWide,
    required List<Widget> children,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final width = isWide ? 300.0 : double.infinity;

    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2028) : const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF171923),
                ),
              ),
            ],
          ),
          const Divider(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _metricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
