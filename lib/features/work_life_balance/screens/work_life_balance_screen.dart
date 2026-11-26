import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intellibreak/features/work_life_balance/services/wlb_service.dart';
import 'package:intellibreak/features/work_life_balance/widgets/wlb_panel.dart';
import 'package:intellibreak/features/work_life_balance/widgets/wlb_score_ring.dart';
import 'package:intellibreak/features/work_life_balance/widgets/wlb_survey_dialog.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _short(DateTime d) => '${_months[d.month - 1]} ${d.day}';

/// Dedicated work-life balance hub: score, dimensions, trend, work patterns,
/// habit recommendations and check-in history.
class WorkLifeBalanceScreen extends StatefulWidget {
  const WorkLifeBalanceScreen({super.key});

  @override
  State<WorkLifeBalanceScreen> createState() => _WorkLifeBalanceScreenState();
}

class _WorkLifeBalanceScreenState extends State<WorkLifeBalanceScreen> {
  final WlbService _service = WlbService();
  WlbOverview? _overview;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.load();
      if (!mounted) return;
      setState(() {
        _overview = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _openSurvey() async {
    final saved = await WlbSurveyDialog.show(context);
    if (saved) _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading && _overview == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _overview == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 40, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(_error!, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('Try again')),
          ],
        ),
      );
    }
    final o = _overview!;

    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 960;
      final summary = _SummaryPanel(overview: o, onCheckIn: _openSurvey);
      final dims = _DimensionsPanel(overview: o);
      final trend = _TrendPanel(overview: o);
      final patterns = _PatternsPanel(overview: o);
      final recs = _RecommendationsPanel(overview: o);
      final history = _HistoryPanel(overview: o);

      return RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Work-life balance', style: theme.textTheme.headlineMedium),
                            const SizedBox(height: 4),
                            Text(
                              'A project-developed weekly indicator based on your check-ins and recorded work patterns. It is not a validated research scale or clinical assessment.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      if (!o.submittedThisWeek)
                        ElevatedButton.icon(
                          onPressed: _openSurvey,
                          icon: const Icon(Icons.edit_note_rounded, size: 18),
                          label: const Text('Weekly check-in'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (wide) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 5, child: summary),
                        const SizedBox(width: 20),
                        Expanded(flex: 6, child: dims),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 6, child: trend),
                        const SizedBox(width: 20),
                        Expanded(flex: 5, child: patterns),
                      ],
                    ),
                  ] else ...[
                    summary,
                    const SizedBox(height: 20),
                    dims,
                    const SizedBox(height: 20),
                    trend,
                    const SizedBox(height: 20),
                    patterns,
                  ],
                  const SizedBox(height: 20),
                  recs,
                  const SizedBox(height: 20),
                  history,
                  const SizedBox(height: 24),
                  Text(
                    'Use this indicator to reflect on your own patterns over time. It is not a validated research scale or a medical or psychological assessment.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}

// ---------------------------------------------------------------------------

class _SummaryPanel extends StatelessWidget {
  final WlbOverview overview;
  final VoidCallback onCheckIn;
  const _SummaryPanel({required this.overview, required this.onCheckIn});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.65);
    final o = overview;
    return WlbPanel(
      title: 'Balance score',
      subtitle: o.latest == null ? null : 'Week of ${_short(o.latest!.weekStart)}',
      child: Column(
        children: [
          Center(child: WlbScoreRing(score: o.score, size: 180, strokeWidth: 14)),
          const SizedBox(height: 20),
          if (o.hasData) WlbTrendChip(trend: o.trend, change: o.scoreChange),
          const SizedBox(height: 14),
          Text(
            o.hasData
                ? (o.message?.isNotEmpty == true ? o.message! : 'Based on your latest weekly check-in.')
                : 'Complete your first weekly check-in to see your score and personalised habit recommendations.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: muted, height: 1.45),
          ),
          if (!o.hasData) ...[
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onCheckIn, child: const Text('Start check-in')),
          ],
        ],
      ),
    );
  }
}

class _DimensionsPanel extends StatelessWidget {
  final WlbOverview overview;
  const _DimensionsPanel({required this.overview});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratings = overview.latest?.ratings ?? const <String, int>{};
    return WlbPanel(
      title: 'What shapes your score',
      subtitle: 'Your latest self-ratings, 1 (low) to 5 (high)',
      child: ratings.isEmpty
          ? Text('No check-in recorded yet.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ))
          : Column(
              children: [
                for (final d in kWlbDimensions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _DimensionBar(dimension: d, value: ratings[d.field]),
                  ),
              ],
            ),
    );
  }
}

class _DimensionBar extends StatelessWidget {
  final WlbDimension dimension;
  final int? value;
  const _DimensionBar({required this.dimension, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = value ?? 0;
    final color = v >= 4
        ? wlbBandColor(80)
        : v == 3
            ? wlbBandColor(60)
            : wlbBandColor(30);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(dimension.icon, size: 16, color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
            const SizedBox(width: 8),
            Expanded(child: Text(dimension.label, style: theme.textTheme.bodyMedium)),
            Text(value == null ? '—' : '$v / 5',
                style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: v / 5,
            minHeight: 8,
            backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.08),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}

class _TrendPanel extends StatelessWidget {
  final WlbOverview overview;
  const _TrendPanel({required this.overview});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weeks = overview.weeks;
    final spots = <FlSpot>[];
    for (var i = 0; i < weeks.length; i++) {
      final s = weeks[i].score;
      if (s != null) spots.add(FlSpot(i.toDouble(), s));
    }
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    final grid = theme.colorScheme.onSurface.withValues(alpha: 0.07);

    return WlbPanel(
      title: '8-week trend',
      subtitle: 'Weekly balance score',
      child: spots.length < 2
          ? SizedBox(
              height: 200,
              child: Center(
                child: Text(
                  'Two or more weekly check-ins are needed to show a trend.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                ),
              ),
            )
          : SizedBox(
              height: 220,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: 100,
                  minX: 0,
                  maxX: (weeks.length - 1).toDouble(),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 25,
                    getDrawingHorizontalLine: (_) => FlLine(color: grid, strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 32,
                        interval: 25,
                        getTitlesWidget: (value, meta) => SideTitleWidget(
                          axisSide: meta.axisSide,
                          child: Text('${value.toInt()}',
                              style: theme.textTheme.labelSmall?.copyWith(color: muted)),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= weeks.length || i % 2 != 0 && weeks.length > 6) {
                            return const SizedBox.shrink();
                          }
                          return SideTitleWidget(
                            axisSide: meta.axisSide,
                            child: Text(_short(weeks[i].weekStart),
                                style: theme.textTheme.labelSmall?.copyWith(color: muted)),
                          );
                        },
                      ),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: false,
                      color: theme.colorScheme.primary,
                      barWidth: 2.5,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                          radius: 4,
                          color: theme.colorScheme.surface,
                          strokeWidth: 2,
                          strokeColor: theme.colorScheme.primary,
                        ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: theme.colorScheme.primary.withValues(alpha: 0.08),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _PatternsPanel extends StatelessWidget {
  final WlbOverview overview;
  const _PatternsPanel({required this.overview});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final o = overview;
    String fmt(String key, {String suffix = '', int digits = 1}) {
      final v = o.indicator(key);
      return v == null ? '—' : '${v.toStringAsFixed(digits)}$suffix';
    }

    final target = o.indicator('target_daily_hours');
    final overtime = o.indicator('overtime_days');

    final tiles = <(String, String, String?)>[
      ('Hours worked', fmt('total_work_hours', suffix: ' h'), 'this week'),
      ('Average day', fmt('avg_daily_hours', suffix: ' h'), target == null ? null : 'target ${target.toStringAsFixed(0)} h'),
      ('Overtime days', overtime == null ? '—' : overtime.toStringAsFixed(0), 'beyond target hours'),
      ('Breaks taken', fmt('break_compliance_pct', suffix: '%', digits: 0), 'of expected breaks'),
    ];

    return WlbPanel(
      title: 'This week’s work patterns',
      subtitle: 'From your recorded sessions and breaks',
      child: o.indicators.isEmpty
          ? Text('Start a work session to see how your week is shaping up.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ))
          : GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 2.1,
              children: [
                for (final t in tiles)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(t.$1,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                            )),
                        const SizedBox(height: 4),
                        Text(t.$2, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                        if (t.$3 != null)
                          Text(t.$3!,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                              )),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _RecommendationsPanel extends StatelessWidget {
  final WlbOverview overview;
  const _RecommendationsPanel({required this.overview});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recs = overview.recommendations;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.65);
    return WlbPanel(
      title: 'Habits to try this week',
      subtitle: 'Weekly habit suggestions. Real-time break prompts come from Break Coach.',
      child: recs.isEmpty
          ? Text('Suggestions will appear once there is enough check-in or session data.',
              style: theme.textTheme.bodyMedium?.copyWith(color: muted))
          : Column(
              children: [
                for (var i = 0; i < recs.length; i++) ...[
                  if (i > 0) const Divider(height: 28),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Text('${i + 1}',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            )),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(recs[i].title, style: theme.textTheme.titleSmall),
                            if (recs[i].description.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(recs[i].description,
                                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.45)),
                            ],
                            if (recs[i].reason != null && recs[i].reason!.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(recs[i].reason!,
                                  style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }
}

class _HistoryPanel extends StatelessWidget {
  final WlbOverview overview;
  const _HistoryPanel({required this.overview});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = overview.history.take(8).toList();
    return WlbPanel(
      title: 'Check-in history',
      child: items.isEmpty
          ? Text('No check-ins yet.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ))
          : Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('Week of ${_short(items[i].weekStart)}', style: theme.textTheme.bodyMedium),
                        ),
                        Text(wlbBandLabel(items[i].score),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: wlbBandColor(items[i].score),
                              fontWeight: FontWeight.w600,
                            )),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 40,
                          child: Text(items[i].score.round().toString(),
                              textAlign: TextAlign.right,
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
