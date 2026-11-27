import 'package:flutter/material.dart';

class PredictiveOutlookCard extends StatelessWidget {
  const PredictiveOutlookCard({
    super.key,
    required this.outlook,
    required this.isLoading,
    this.error,
  });

  final Map<String, dynamic>? outlook;
  final bool isLoading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final data = outlook ?? <String, dynamic>{};
    final work = _readMetric(data['work_hours_per_person']);
    final wlb = _readMetric(data['work_life_balance_score']);
    final forecastWeek = _formatForecastWeek(data['forecast_week_start'] as String?);
    final border = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.grey.withValues(alpha: 0.2);
    final muted = isDark ? Colors.grey.shade400 : Colors.grey.shade600;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF182029) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_outlined, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Predictive Team Outlook', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              Chip(label: Text(forecastWeek)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Group-level planning estimates from recent weekly patterns.',
            style: TextStyle(fontSize: 12, color: muted),
          ),
          const SizedBox(height: 16),
          if (isLoading)
            const LinearProgressIndicator(minHeight: 3)
          else if (error != null)
            Text(error!, style: TextStyle(color: muted))
          else if (data['available'] != true)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                data['note'] as String? ?? 'More weekly team data is needed before a projection can be shown.',
                style: TextStyle(fontSize: 12, color: muted, height: 1.4),
              ),
            )
          else ...[
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                if (work != null)
                  _metric(context, 'Recorded work hours per person', work, isDark),
                if (wlb != null)
                  _metric(context, 'Work-life balance score', wlb, isDark, higherIsBetter: true),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Method: simple linear trend over up to four completed weeks; this is not ML. '
              'Work-life balance projections are shown only when at least five people responded in each week. '
              'Use these group estimates for planning, not as individual ratings or diagnoses.',
              style: TextStyle(fontSize: 11, color: muted, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  Map<String, dynamic>? _readMetric(dynamic value) {
    if (value is! Map) return null;
    return Map<String, dynamic>.from(value);
  }

  String _formatForecastWeek(String? value) {
    final date = value == null ? null : DateTime.tryParse(value);
    if (date == null) return 'Next full week';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return 'Week of ${months[date.month - 1]} ${date.day}';
  }

  Widget _metric(
    BuildContext context,
    String title,
    Map<String, dynamic> metric,
    bool isDark, {
    bool? higherIsBetter,
  }) {
    final last = (metric['last_week'] as num?)?.toDouble();
    final projected = (metric['projected_next_week'] as num?)?.toDouble();
    final change = (metric['change'] as num?)?.toDouble() ?? 0;
    final unit = metric['unit'] as String? ?? '';
    final isUp = change > 0.05;
    final isDown = change < -0.05;
    final favorable = higherIsBetter == null
        ? null
        : (higherIsBetter ? change >= 0 : change <= 0);
    final color = favorable == null
        ? Theme.of(context).colorScheme.primary
        : (favorable ? Colors.green : Colors.orange);
    final arrow = isUp
        ? Icons.trending_up
        : isDown
            ? Icons.trending_down
            : Icons.trending_flat;
    final valueUnit = unit.startsWith('hours') ? 'h / person / week' : 'pts / 100';
    final changeUnit = unit.startsWith('hours') ? 'h' : 'pts';
    final signedChange = '${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)} $changeUnit';

    return Container(
      width: 275,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF11171D) : const Color(0xFFF7F9FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade300 : Colors.grey.shade700)),
          const SizedBox(height: 8),
          Text(
            projected == null ? 'Not enough data' : '${projected.toStringAsFixed(1)} $valueUnit',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Icon(arrow, size: 16, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '${last?.toStringAsFixed(1) ?? '—'} last week  ·  $signedChange',
                  style: TextStyle(fontSize: 11, color: color),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
