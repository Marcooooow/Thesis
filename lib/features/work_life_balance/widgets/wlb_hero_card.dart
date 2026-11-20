import 'package:flutter/material.dart';
import 'package:intellibreak/features/work_life_balance/services/wlb_service.dart';
import 'package:intellibreak/features/work_life_balance/widgets/wlb_panel.dart';
import 'package:intellibreak/features/work_life_balance/widgets/wlb_score_ring.dart';
import 'package:intellibreak/features/work_life_balance/widgets/wlb_survey_dialog.dart';

/// Headline work-life balance summary shown at the top of the dashboard.
class WlbHeroCard extends StatefulWidget {
  /// Opens the full Work-Life Balance screen.
  final VoidCallback? onOpenDetails;

  const WlbHeroCard({super.key, this.onOpenDetails});

  @override
  State<WlbHeroCard> createState() => _WlbHeroCardState();
}

class _WlbHeroCardState extends State<WlbHeroCard> {
  final WlbService _service = WlbService();
  WlbOverview? _overview;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final data = await _service.load();
      if (!mounted) return;
      setState(() {
        _overview = data;
        _failed = false;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  Future<void> _openSurvey() async {
    final saved = await WlbSurveyDialog.show(context);
    if (saved) _load();
  }

  /// The weakest dimension of the latest check-in, used as a focus hint.
  String? _focusArea(WlbOverview o) {
    final r = o.latest?.ratings;
    if (r == null || r.isEmpty) return null;
    WlbDimension? weakest;
    for (final d in kWlbDimensions) {
      final v = r[d.field];
      if (v == null) continue;
      if (weakest == null || v < (r[weakest.field] ?? 6)) weakest = d;
    }
    if (weakest == null) return null;
    final v = r[weakest.field]!;
    if (v >= 4) return null; // nothing worth flagging
    return '${weakest.label} ($v/5)';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.65);

    return WlbPanel(
      padding: const EdgeInsets.all(24),
      child: _loading
          ? const SizedBox(height: 148, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
          : _failed || _overview == null
              ? _buildError(theme, muted)
              : _buildContent(theme, muted, _overview!),
    );
  }

  Widget _buildError(ThemeData theme, Color muted) {
    return Row(
      children: [
        Icon(Icons.cloud_off_outlined, color: muted),
        const SizedBox(width: 12),
        Expanded(
          child: Text('Work-life balance data is unavailable right now.',
              style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
        ),
        TextButton(onPressed: _load, child: const Text('Retry')),
      ],
    );
  }

  Widget _buildContent(ThemeData theme, Color muted, WlbOverview o) {
    final focus = _focusArea(o);
    final narrow = MediaQuery.sizeOf(context).width < 720;

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('WORK-LIFE BALANCE',
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 1.0,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            )),
        const SizedBox(height: 8),
        Text(
          o.hasData
              ? 'Your balance is ${wlbBandLabel(o.score).toLowerCase()}'
              : 'Start with a weekly check-in',
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          o.hasData
              ? (o.message?.isNotEmpty == true
                  ? o.message!
                  : 'Based on your latest weekly check-in and recorded work patterns.')
              : 'A one-minute weekly check-in lets IntelliBreak tailor break and habit recommendations to how your week actually felt.',
          style: theme.textTheme.bodyMedium?.copyWith(color: muted, height: 1.45),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (o.hasData) WlbTrendChip(trend: o.trend, change: o.scoreChange),
            if (focus != null)
              Text('Focus area: $focus', style: theme.textTheme.labelMedium?.copyWith(color: muted)),
          ],
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            if (!o.submittedThisWeek)
              ElevatedButton.icon(
                onPressed: _openSurvey,
                icon: const Icon(Icons.edit_note_rounded, size: 18),
                label: const Text("Complete this week's check-in"),
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline, size: 18, color: wlbBandColor(80)),
                  const SizedBox(width: 6),
                  Text("This week's check-in is done", style: theme.textTheme.labelLarge),
                ],
              ),
            if (widget.onOpenDetails != null)
              OutlinedButton(onPressed: widget.onOpenDetails, child: const Text('View full report')),
          ],
        ),
      ],
    );

    final ring = WlbScoreRing(score: o.score);

    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Center(child: ring), const SizedBox(height: 20), details],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [ring, const SizedBox(width: 32), Expanded(child: details)],
    );
  }
}
