import 'package:flutter/material.dart';
import 'package:intellibreak/features/work_life_balance/services/wlb_service.dart';

/// Weekly work-life balance check-in: five statements rated 1-5.
/// Pops with `true` once the survey was saved.
class WlbSurveyDialog extends StatefulWidget {
  const WlbSurveyDialog({super.key});

  static Future<bool> show(BuildContext context) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const WlbSurveyDialog(),
    );
    return saved == true;
  }

  @override
  State<WlbSurveyDialog> createState() => _WlbSurveyDialogState();
}

class _WlbSurveyDialogState extends State<WlbSurveyDialog> {
  static const _scaleLabels = ['Strongly\ndisagree', 'Disagree', 'Neutral', 'Agree', 'Strongly\nagree'];

  final WlbService _service = WlbService();
  final Map<String, int> _ratings = {};
  bool _submitting = false;
  String? _error;

  bool get _complete => kWlbDimensions.every((d) => _ratings.containsKey(d.field));

  Future<void> _submit() async {
    if (!_complete || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _service.submitSurvey(_ratings);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.65);

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Weekly work-life balance check-in', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 6),
                  Text(
                    'Think about this past week. There are no right or wrong answers. This project-developed check-in helps you reflect on weekly patterns; it is not a validated research scale or clinical assessment.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                  ),
                ],
              ),
            ),
            const Divider(height: 24),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 4),
                itemCount: kWlbDimensions.length,
                separatorBuilder: (_, __) => const SizedBox(height: 22),
                itemBuilder: (context, i) {
                  final d = kWlbDimensions[i];
                  final selected = _ratings[d.field];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(d.icon, size: 18, color: scheme.primary),
                          const SizedBox(width: 8),
                          Text(d.label.toUpperCase(),
                              style: theme.textTheme.labelSmall?.copyWith(
                                letterSpacing: 0.8,
                                fontWeight: FontWeight.w600,
                                color: muted,
                              )),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(d.prompt, style: theme.textTheme.bodyLarge),
                      const SizedBox(height: 12),
                      Row(
                        children: List.generate(5, (idx) {
                          final value = idx + 1;
                          final isSel = selected == value;
                          return Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(right: idx == 4 ? 0 : 8),
                              child: Semantics(
                                button: true,
                                selected: isSel,
                                label: '${d.label}: ${_scaleLabels[idx].replaceAll('\n', ' ')}',
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: _submitting
                                      ? null
                                      : () => setState(() => _ratings[d.field] = value),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 120),
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    decoration: BoxDecoration(
                                      color: isSel ? scheme.primary : Colors.transparent,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isSel
                                            ? scheme.primary
                                            : theme.dividerTheme.color ?? scheme.outline,
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        Text('$value',
                                            style: theme.textTheme.titleMedium?.copyWith(
                                              color: isSel ? scheme.onPrimary : scheme.onSurface,
                                              fontWeight: FontWeight.w600,
                                            )),
                                        const SizedBox(height: 2),
                                        Text(
                                          _scaleLabels[idx],
                                          textAlign: TextAlign.center,
                                          style: theme.textTheme.labelSmall?.copyWith(
                                            fontSize: 10,
                                            height: 1.15,
                                            color: isSel
                                                ? scheme.onPrimary.withValues(alpha: 0.9)
                                                : muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ],
                  );
                },
              ),
            ),
            const Divider(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_error != null) ...[
                    Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: scheme.error)),
                    const SizedBox(height: 10),
                  ],
                  Row(
                    children: [
                      Text(
                        '${_ratings.length} of ${kWlbDimensions.length} answered',
                        style: theme.textTheme.bodySmall?.copyWith(color: muted),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
                        child: const Text('Not now'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _complete && !_submitting ? _submit : null,
                        child: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Save check-in'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
