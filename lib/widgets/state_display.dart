import 'package:flutter/material.dart';
import 'package:intellibreak/core/design_system.dart';

/// A robust, standardized widget that handles loading, error, empty, and content states consistently
/// across Employee, Manager, and Admin screens.
class StateDisplay extends StatelessWidget {
  const StateDisplay({
    super.key,
    required this.isLoading,
    this.errorMessage,
    required this.isEmpty,
    required this.content,
    this.onRetry,
    this.loadingMessage,
    this.emptyMessage,
    this.errorMessageOverride,
    this.emptyAction,
    this.loadingWidget,
    this.emptyIcon = Icons.outlined_flag,
    this.hasExistingData = false,
  });

  /// Whether data is currently loading
  final bool isLoading;

  /// Error message to display (null = no error)
  final String? errorMessage;

  /// Whether data is empty (after successful load)
  final bool isEmpty;

  /// Content to show when not loading/error/empty
  final Widget content;

  /// Callback for retry button in error state
  final VoidCallback? onRetry;

  /// Custom loading message (optional)
  final String? loadingMessage;

  /// Custom empty message (optional)
  final String? emptyMessage;

  /// Custom error message (optional)
  final String? errorMessageOverride;

  /// Custom action widget for empty state (optional)
  final Widget? emptyAction;

  /// Custom loading widget / skeleton (optional)
  final Widget? loadingWidget;

  /// Icon for empty state
  final IconData emptyIcon;

  /// Whether existing content is present (enables preserving content on refresh failure)
  final bool hasExistingData;

  String _sanitizeError(String error) {
    final lower = error.toLowerCase();
    if (lower.contains('socketexception') || lower.contains('failed host lookup') || lower.contains('network') || lower.contains('connection refused')) {
      return 'Connection error. Please check your network and try again.';
    }
    if (lower.contains('500') || lower.contains('internal server error') || lower.contains('sqlalchemy') || lower.contains('psycopg')) {
      return 'Server error. Our team has been notified. Please try again later.';
    }
    if (lower.contains('401') || lower.contains('403') || lower.contains('unauthorized') || lower.contains('forbidden')) {
      return 'Session expired or unauthorized access. Please sign in again.';
    }
    if (lower.contains('syntaxerror') || lower.contains('typeerror') || lower.contains('traceback')) {
      return 'An unexpected data processing error occurred. Please try again.';
    }
    if (error.length > 150 || lower.contains('select ') || lower.contains('insert into')) {
      return 'Unable to complete request. Please try again later.';
    }
    return error;
  }

  @override
  Widget build(BuildContext context) {
    // 1. Loading state (takes precedence when no existing data to preserve)
    if (isLoading && !hasExistingData) {
      if (loadingWidget != null) {
        return loadingWidget!;
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DesignSystem.appLoadingIndicator(),
            if (loadingMessage != null) ...[
              const SizedBox(height: DesignSystem.spacingS),
              Text(
                loadingMessage!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ],
        ),
      );
    }

    // 2. Error state (if no existing data to preserve on refresh failure)
    if (errorMessage != null && !hasExistingData) {
      final rawError = errorMessageOverride ?? errorMessage!;
      final displayError = _sanitizeError(rawError);
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(DesignSystem.spacingL),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: DesignSystem.spacingM),
              Text(
                'Something went wrong',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: DesignSystem.spacingXS),
              Text(
                displayError,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
              if (onRetry != null) ...[
                const SizedBox(height: DesignSystem.spacingL),
                ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // 3. Empty state (only when not loading, no error, and isEmpty is true)
    if (isEmpty && !isLoading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(DesignSystem.spacingL),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                emptyIcon,
                size: 48,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: DesignSystem.spacingM),
              Text(
                emptyMessage ?? 'No data available',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                textAlign: TextAlign.center,
              ),
              if (emptyAction != null) ...[
                const SizedBox(height: DesignSystem.spacingL),
                emptyAction!,
              ],
            ],
          ),
        ),
      );
    }

    // 4. Content state (with optional subtle refresh error banner if refresh failed but existing data is preserved)
    if (errorMessage != null && hasExistingData) {
      return Stack(
        children: [
          content,
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Material(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 18, color: Theme.of(context).colorScheme.onErrorContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Failed to refresh: ${_sanitizeError(errorMessage!)}',
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onErrorContainer),
                      ),
                    ),
                    if (onRetry != null)
                      TextButton(
                        onPressed: onRetry,
                        child: const Text('Retry', style: TextStyle(fontSize: 12)),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    return content;
  }
}
