import 'package:flutter/material.dart';
import 'package:intellibreak/core/design_system.dart';

import '../../analytics/services/analytics_service.dart';

class FocusRateCard extends StatefulWidget {
  final String? token;

  const FocusRateCard({super.key, this.token});

  const FocusRateCard.demo()
    : token = null,
      super(key: const Key('demo-focus-rate-card'));

  @override
  State<FocusRateCard> createState() => _FocusRateCardState();
}

class _FocusRateCardState extends State<FocusRateCard> {
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
    // If token is null, we are in demo mode
    if (widget.token == null) {
      // Simulate loading delay for demo
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      setState(() {
        _focusRate = 88.0; // Demo focus rate: 88%
        _isLoading = false;
      });
      return;
    }

    try {
      final rate = await _analyticsService.getFocusRate(widget.token!);
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
    if (_isLoading) {
      return DesignSystem.statCardWithProgress(
        context: context,
        label: 'Focus Rate',
        value: 'Loading...',
        progress: 0.0,
        icon: Icons.psychology_outlined,
        color: DesignSystem.getSemanticColor(context, SemanticColor.success),
        description: 'Calculating your focus rate...',
      );
    }

    if (_error != null) {
      return DesignSystem.statCardWithProgress(
        context: context,
        label: 'Focus Rate',
        value: 'Error',
        progress: 0.0,
        icon: Icons.psychology_outlined,
        color: DesignSystem.getSemanticColor(context, SemanticColor.error),
        description: 'Failed to load focus rate data',
      );
    }

    final percentage = _focusRate.toStringAsFixed(0);
    final description = _focusRate >= 80
        ? 'Your focus rate is above average. Keep up the good work!'
        : _focusRate >= 60
        ? 'Your focus rate is good. Try to minimize distractions.'
        : 'Your focus rate needs improvement. Consider taking regular breaks.';

    return DesignSystem.statCardWithProgress(
      context: context,
      label: 'Focus Rate',
      value: '$percentage%',
      progress: _focusRate / 100,
      icon: Icons.psychology_outlined,
      color: DesignSystem.getSemanticColor(context, SemanticColor.success),
      description: description,
    );
  }
}
