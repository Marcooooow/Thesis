import 'package:flutter/material.dart';
import 'package:intellibreak/core/design_system.dart';

/// Reusable empty state widget for ML charts
class MLChartEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double? height;

  const MLChartEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: height ?? 280,
      padding: const EdgeInsets.all(DesignSystem.spacingXL),
      decoration: BoxDecoration(
        color: isDark
            ? DesignSystem.getSemanticColor(context, SemanticColor.background)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(DesignSystem.radiusL),
        border: Border.all(
          color: isDark
              ? Colors.grey.withValues(alpha: 0.15)
              : Colors.grey.withValues(alpha: 0.1),
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 48,
              color: isDark ? Colors.white30 : Colors.grey.shade400,
            ),
            const SizedBox(height: DesignSystem.spacingM),
            Text(
              title,
              style: DesignSystem.title(context).copyWith(
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: DesignSystem.spacingS),
            Text(
              message,
              style: DesignSystem.body(context).copyWith(
                color: isDark ? Colors.white60 : Colors.grey.shade500,
              ),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: DesignSystem.spacingL),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(actionLabel!),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: DesignSystem.spacingL,
                    vertical: DesignSystem.spacingM,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(DesignSystem.radiusM),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Empty state for no trained model
class MLNoModelState extends StatelessWidget {
  final VoidCallback? onTrainModel;

  const MLNoModelState({
    super.key,
    this.onTrainModel,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(DesignSystem.spacingXL),
      decoration: BoxDecoration(
        color: isDark
            ? DesignSystem.getSemanticColor(context, SemanticColor.background)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(DesignSystem.radiusL),
        border: Border.all(
          color: isDark
              ? Colors.grey.withValues(alpha: 0.15)
              : Colors.grey.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.model_training,
            size: 56,
            color: isDark ? Colors.blue.shade300 : Colors.blue.shade600,
          ),
          const SizedBox(height: DesignSystem.spacingM),
          Text(
            'No Trained Model Available',
            style: DesignSystem.titleLarge(context).copyWith(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: DesignSystem.spacingS),
          Text(
            'The recommendation system is currently using the cold-start baseline. '
            'Train a model with sufficient labeled feedback data to enable ML-powered recommendations.',
            style: DesignSystem.body(context).copyWith(
              color: isDark ? Colors.white60 : Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: DesignSystem.spacingL),
          if (onTrainModel != null)
            FilledButton.icon(
              onPressed: onTrainModel,
              icon: const Icon(Icons.play_arrow, size: 18),
              label: const Text('Train Model'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: DesignSystem.spacingXL,
                  vertical: DesignSystem.spacingM,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(DesignSystem.radiusM),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Error state for failed data loading
class MLChartErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const MLChartErrorState({
    super.key,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(DesignSystem.spacingXL),
      decoration: BoxDecoration(
        color: isDark ? Colors.red.withValues(alpha: 0.1) : Colors.red.shade50,
        borderRadius: BorderRadius.circular(DesignSystem.radiusL),
        border: Border.all(
          color: isDark ? Colors.red.withValues(alpha: 0.3) : Colors.red.shade200,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: isDark ? Colors.red.shade300 : Colors.red.shade600,
          ),
          const SizedBox(height: DesignSystem.spacingM),
          Text(
            'Failed to Load Data',
            style: DesignSystem.title(context).copyWith(
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.red.shade300 : Colors.red.shade700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: DesignSystem.spacingS),
          Text(
            message,
            style: DesignSystem.body(context).copyWith(
              color: isDark ? Colors.red.shade200 : Colors.red.shade700,
            ),
            textAlign: TextAlign.center,
          ),
          if (onRetry != null) ...[
            const SizedBox(height: DesignSystem.spacingL),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: DesignSystem.spacingL,
                  vertical: DesignSystem.spacingM,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(DesignSystem.radiusM),
                ),
                foregroundColor: isDark ? Colors.red.shade300 : Colors.red.shade700,
                side: BorderSide(
                  color: isDark ? Colors.red.shade300 : Colors.red.shade700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Loading state for charts
class MLChartLoadingState extends StatelessWidget {
  final String? message;
  final double? height;

  const MLChartLoadingState({
    super.key,
    this.message,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: height ?? 280,
      padding: const EdgeInsets.all(DesignSystem.spacingXL),
      decoration: BoxDecoration(
        color: isDark
            ? DesignSystem.getSemanticColor(context, SemanticColor.background)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(DesignSystem.radiusL),
        border: Border.all(
          color: isDark
              ? Colors.grey.withValues(alpha: 0.15)
              : Colors.grey.withValues(alpha: 0.1),
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: isDark ? Colors.blue.shade400 : Colors.blue.shade600,
              ),
            ),
            const SizedBox(height: DesignSystem.spacingM),
            Text(
              message ?? 'Loading chart data...',
              style: DesignSystem.body(context).copyWith(
                color: isDark ? Colors.white60 : Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}