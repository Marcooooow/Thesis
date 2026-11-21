import 'package:flutter/material.dart';

import '../services/analytics_service.dart';

class FocusRateProgress extends StatefulWidget {
  final String token;
  final double size; // Size of the progress circle
  final DateTime? startDate;
  final DateTime? endDate;

  const FocusRateProgress({
    super.key,
    required this.token,
    this.size = 120.0, // Default size
    this.startDate,
    this.endDate,
  });

  const FocusRateProgress.demo()
    : token = 'demo',
      size = 120.0,
      startDate = null,
      endDate = null,
      super(key: const Key('demo-focus-rate-progress'));

  @override
  State<FocusRateProgress> createState() => _FocusRateProgressState();
}

class _FocusRateProgressState extends State<FocusRateProgress> {
  final AnalyticsService _analyticsService = AnalyticsService();
  double _focusRate = 0.0;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final rate = await _analyticsService.getFocusRate(
        widget.token,
        startDate: widget.startDate,
        endDate: widget.endDate,
      );
      if (mounted) {
        setState(() {
          _focusRate = rate;
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
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: const CircularProgressIndicator(strokeWidth: 3),
      );
    }

    if (_error != null) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: isDark ? Colors.white70 : Colors.grey,
              ),
              const SizedBox(height: 8),
              Text(
                'Error loading data',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _error!.length > 50
                    ? '${_error!.substring(0, 50)}...'
                    : _error!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.grey[600],
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_focusRate == 0.0) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.info_outline,
                size: 48,
                color: isDark ? Colors.white70 : Colors.grey,
              ),
              const SizedBox(height: 8),
              Text(
                'No data',
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.grey,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background circle
          SizedBox(
            width: widget.size,
            height: widget.size,
            child: CircularProgressIndicator(
              value: 1.0, // Full circle as background
              strokeWidth: 12,
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF111827).withValues(alpha: 0.2)
                  : Colors.grey[300] ?? const Color(0xFFD3D9E1),
            ),
          ),
          // Progress circle
          SizedBox(
            width: widget.size,
            height: widget.size,
            child: CircularProgressIndicator(
              value: _focusRate / 100.0, // Convert percentage to 0-1 range
              strokeWidth: 12,
              color: _getProgressColor(),
            ),
          ),
          // Center text
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${_focusRate.toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF111827),
                ),
              ),
              Text(
                'Focus Rate',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white70 : Colors.grey[600],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getProgressColor() {
    if (_focusRate >= 80) {
      return const Color(0xFF4CAF50); // Green for excellent
    } else if (_focusRate >= 60) {
      return const Color(0xFF8BC34A); // Light green for good
    } else if (_focusRate >= 40) {
      return const Color(0xFFFFC107); // Amber for fair
    } else {
      return const Color(0xFFF44336); // Red for poor
    }
  }
}
