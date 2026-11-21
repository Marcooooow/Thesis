import 'package:flutter/material.dart';
import 'package:intellibreak/features/work_life_balance/services/wlb_service.dart';
import 'package:intellibreak/features/work_life_balance/widgets/wlb_panel.dart';
import 'package:intellibreak/features/work_life_balance/widgets/wlb_score_ring.dart';

/// Demo sandbox: simulate a work situation and see, side by side, the
/// notifications, the Break Coach recommendation and the work-life balance
/// score the system would produce.
///
/// Everything here is local and simulated; nothing is sent to the server or
/// saved. The rules mirror the thesis' heuristic baseline (SHORT_BREAK, WALK,
/// HYDRATE, STRETCH, LUNCH) and the survey score formula
/// ((sum of ratings - 5) / 20) * 100.
class DemoSandboxScreen extends StatefulWidget {
  const DemoSandboxScreen({super.key});

  @override
  State<DemoSandboxScreen> createState() => _DemoSandboxScreenState();
}

class _Scenario {
  final String name;
  final IconData icon;
  final double focusMinutes;
  final double breaksToday;
  final bool lunchTaken;
  final double weeklyHours;
  final double afterHoursDays;
  final List<int> ratings; // in kWlbDimensions order
  const _Scenario(this.name, this.icon, this.focusMinutes, this.breaksToday, this.lunchTaken,
      this.weeklyHours, this.afterHoursDays, this.ratings);
}

const _scenarios = <_Scenario>[
  _Scenario('Healthy rhythm', Icons.spa_outlined, 40, 3, true, 38, 0, [4, 4, 5, 4, 4]),
  _Scenario('Long focus block', Icons.timer_outlined, 125, 0, true, 40, 0, [4, 3, 4, 4, 3]),
  _Scenario('Skipped lunch', Icons.lunch_dining_outlined, 70, 1, false, 42, 1, [3, 3, 3, 3, 3]),
  _Scenario('Overtime week', Icons.work_history_outlined, 95, 2, true, 54, 4, [2, 2, 2, 3, 2]),
  _Scenario('Burnout risk', Icons.warning_amber_rounded, 150, 0, false, 60, 6, [1, 1, 2, 1, 1]),
];

class _DemoSandboxScreenState extends State<DemoSandboxScreen> {
  double _focus = 40;
  double _breaks = 3;
  bool _lunch = true;
  double _weekly = 38;
  double _afterHours = 0;
  List<int> _ratings = [4, 4, 5, 4, 4];
  String _scenario = 'Healthy rhythm';
  String? _feedback;

  void _apply(_Scenario s) => setState(() {
        _scenario = s.name;
        _focus = s.focusMinutes;
        _breaks = s.breaksToday;
        _lunch = s.lunchTaken;
        _weekly = s.weeklyHours;
        _afterHours = s.afterHoursDays;
        _ratings = List.of(s.ratings);
        _feedback = null;
      });

  double get _score => ((_ratings.fold<int>(0, (a, b) => a + b) - 5) / 20 * 100).clamp(0, 100).toDouble();

  String get _trend => _score >= 70 ? 'improving' : (_score < 50 ? 'declining' : 'stable');

  /// Notifications the system would raise for the current inputs.
  List<(IconData, String, String)> get _notifications {
    final n = <(IconData, String, String)>[];
    if (!_lunch) {
      n.add((Icons.lunch_dining_outlined, 'Lunch reminder', 'You have not logged lunch today. A proper meal break helps recovery.'));
    }
    if (_focus >= 90 && _breaks < 1) {
      n.add((Icons.coffee_outlined, 'Time for a short break', 'You have focused for ${_focus.round()} minutes without a break.'));
    } else if (_focus >= 60) {
      n.add((Icons.self_improvement_outlined, 'Stretch suggestion', '${_focus.round()} minutes of continuous focus. A quick stretch can help.'));
    }
    if (_weekly > 45) {
      n.add((Icons.work_history_outlined, 'Overtime pattern this week', 'You have logged ${_weekly.round()} hours so far this week.'));
    }
    if (_afterHours >= 3) {
      n.add((Icons.nightlight_outlined, 'Protect your evenings', 'Work was recorded outside your usual hours on ${_afterHours.round()} days.'));
    }
    if (_score < 50) {
      n.add((Icons.balance_rounded, 'Work-life balance check-in', 'Your balance score is ${_score.round()}/100. Open the Work-Life Balance screen for habits to try.'));
    }
    if (n.isEmpty) {
      n.add((Icons.check_circle_outline, 'On a healthy rhythm', 'Breaks, hours and balance look sustainable right now.'));
    }
    return n;
  }

  /// Heuristic candidate generation, highest priority first.
  ({String type, String title, String why, String action, String outcome}) get _recommendation {
    if (!_lunch) {
      return (
        type: 'LUNCH',
        title: 'Take your lunch break',
        why: 'No lunch is logged today and you have been working for a while.',
        action: 'Step away for a 30 to 45 minute meal, away from your desk.',
        outcome: 'Better afternoon focus and recovery. Improvement is not guaranteed.',
      );
    }
    if (_focus >= 90) {
      return (
        type: 'SHORT_BREAK',
        title: 'Take a 10-minute break',
        why: 'Continuous focus of ${_focus.round()} minutes is above the usual safeguard.',
        action: 'Pause the task and rest for 10 minutes.',
        outcome: 'Lower fatigue build-up over the rest of the shift.',
      );
    }
    if (_weekly > 45 || _afterHours >= 3) {
      return (
        type: 'WALK',
        title: 'Take a short walk and set an end-of-day cut-off',
        why: 'Your week is running long, with work outside your usual hours.',
        action: 'Walk for 10 minutes and decide a hard stop time for today.',
        outcome: 'More time to disconnect in the evening.',
      );
    }
    if (_focus >= 60) {
      return (
        type: 'STRETCH',
        title: 'Stretch for two minutes',
        why: 'An hour of continuous work has passed.',
        action: 'Stand, roll your shoulders and stretch your wrists and neck.',
        outcome: 'Less physical strain during long sessions.',
      );
    }
    return (
      type: 'HYDRATE',
      title: 'Hydration check',
      why: 'No urgent signals, so this is a light habit prompt.',
      action: 'Drink a glass of water.',
      outcome: 'A small habit that supports steady energy.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 980;
    final controls = _buildControls(theme);
    final output = _buildOutput(theme);

    return Scaffold(
      appBar: AppBar(title: const Text('Demo sandbox')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1240),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.science_outlined, color: theme.colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Sandbox: simulated data only. Change the inputs or pick a scenario to see the notifications, Break Coach recommendation and work-life balance score the system would produce. Nothing is saved or sent.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final s in _scenarios)
                      ChoiceChip(
                        avatar: Icon(s.icon, size: 18),
                        label: Text(s.name),
                        selected: _scenario == s.name,
                        onSelected: (_) => _apply(s),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 5, child: controls),
                      const SizedBox(width: 20),
                      Expanded(flex: 6, child: output),
                    ],
                  )
                else ...[controls, const SizedBox(height: 20), output],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _slider(String label, double value, double min, double max, ValueChanged<double> onChanged,
      {String suffix = ''}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ${value.round()}$suffix', style: Theme.of(context).textTheme.bodyMedium),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: (max - min).round(),
          onChanged: (v) => setState(() {
            onChanged(v);
            _scenario = 'Custom';
            _feedback = null;
          }),
        ),
      ],
    );
  }

  Widget _buildControls(ThemeData theme) {
    return WlbPanel(
      title: 'Simulated situation',
      subtitle: 'Adjust what the user is doing',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _slider('Continuous focus', _focus, 0, 180, (v) => _focus = v, suffix: ' min'),
          _slider('Breaks taken today', _breaks, 0, 8, (v) => _breaks = v),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Lunch taken today'),
            value: _lunch,
            onChanged: (v) => setState(() {
              _lunch = v;
              _scenario = 'Custom';
              _feedback = null;
            }),
          ),
          _slider('Hours worked this week', _weekly, 0, 70, (v) => _weekly = v, suffix: ' h'),
          _slider('Days with after-hours work', _afterHours, 0, 7, (v) => _afterHours = v),
          const Divider(height: 28),
          Text('Weekly check-in answers (1 to 5)', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          for (var i = 0; i < kWlbDimensions.length; i++)
            _slider(kWlbDimensions[i].label, _ratings[i].toDouble(), 1, 5, (v) => _ratings[i] = v.round()),
        ],
      ),
    );
  }

  Widget _buildOutput(ThemeData theme) {
    final rec = _recommendation;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.65);
    return Column(
      children: [
        WlbPanel(
          title: 'Notifications',
          subtitle: 'What would appear in the bell menu',
          child: Column(
            children: [
              for (final n in _notifications)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(n.$1, size: 20, color: theme.colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text(n.$2, style: theme.textTheme.titleSmall)),
                                Text('Just now', style: theme.textTheme.labelSmall),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(n.$3, style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        WlbPanel(
          title: 'Break Coach recommendation',
          subtitle: 'Rule-based candidate: ${rec.type}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(rec.title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text('Why: ${rec.why}', style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
              const SizedBox(height: 4),
              Text('Action: ${rec.action}', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 4),
              Text('Expected outcome: ${rec.outcome}', style: theme.textTheme.bodySmall),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  ElevatedButton(
                    onPressed: () => setState(() => _feedback = 'accepted'),
                    child: const Text('Accept'),
                  ),
                  OutlinedButton(
                    onPressed: () => setState(() => _feedback = 'snoozed for 5 minutes'),
                    child: const Text('Snooze 5 min'),
                  ),
                  OutlinedButton(
                    onPressed: () => setState(() => _feedback = 'dismissed'),
                    child: const Text('Dismiss'),
                  ),
                ],
              ),
              if (_feedback != null) ...[
                const SizedBox(height: 12),
                Text('Feedback recorded: $_feedback (sandbox only, not saved)',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        WlbPanel(
          title: 'Work-life balance',
          subtitle: 'Score from the five check-in answers',
          child: Row(
            children: [
              WlbScoreRing(score: _score, size: 140, strokeWidth: 12),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    WlbTrendChip(trend: _trend),
                    const SizedBox(height: 12),
                    for (var i = 0; i < kWlbDimensions.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            SizedBox(width: 110, child: Text(kWlbDimensions[i].label, style: theme.textTheme.bodySmall)),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: _ratings[i] / 5,
                                  minHeight: 7,
                                  backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.08),
                                  valueColor: AlwaysStoppedAnimation(
                                      wlbBandColor(((_ratings[i] - 1) / 4 * 100).toDouble())),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
