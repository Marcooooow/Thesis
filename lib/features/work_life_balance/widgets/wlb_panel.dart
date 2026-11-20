import 'package:flutter/material.dart';

/// Flat, bordered surface used across the work-life balance screens.
class WlbPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final String? title;
  final String? subtitle;
  final Widget? trailing;

  const WlbPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = theme.dividerTheme.color ?? theme.colorScheme.outline;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title!, style: theme.textTheme.titleMedium),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 20),
          ],
          child,
        ],
      ),
    );
  }
}

/// Small pill describing the direction of the score.
class WlbTrendChip extends StatelessWidget {
  final String trend; // improving | stable | declining
  final double? change;

  const WlbTrendChip({super.key, required this.trend, this.change});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    late final IconData icon;
    late final Color color;
    late final String label;
    switch (trend) {
      case 'improving':
        icon = Icons.trending_up_rounded;
        color = const Color(0xFF2F8F6B);
        label = 'Improving';
        break;
      case 'declining':
        icon = Icons.trending_down_rounded;
        color = const Color(0xFFC2573F);
        label = 'Declining';
        break;
      default:
        icon = Icons.trending_flat_rounded;
        color = theme.colorScheme.onSurface.withValues(alpha: 0.65);
        label = 'Stable';
    }
    final delta = (change == null || change == 0)
        ? ''
        : '  ${change! > 0 ? '+' : ''}${change!.toStringAsFixed(0)} vs last week';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text('$label$delta',
              style: theme.textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
