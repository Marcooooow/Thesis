import 'package:flutter/material.dart';
import 'package:intellibreak/core/design_system.dart';
import 'package:intellibreak/core/motion.dart';
import 'package:intellibreak/features/dashboard/providers/break_coach_state.dart';
import 'package:provider/provider.dart';
import 'package:intellibreak/features/auth/services/api_service.dart';

/// Permanent inline Wellness Coach card.
/// Consumes real behavioral analytics summaries (/analytics/wellness/summary)
/// and BreakCoachState to display weekly WLB insights and active break guidance.
class AIWellnessCard extends StatefulWidget {
  final bool useInternalScroll;

  const AIWellnessCard({super.key, this.useInternalScroll = false});

  @override
  State<AIWellnessCard> createState() => _AIWellnessCardState();
}

class _AIWellnessCardState extends State<AIWellnessCard> {
  bool _isLoadingAnalytics = true;
  String? _analyticsError;
  Map<String, dynamic>? _wellnessSummary;
  final ScrollController _scrollController = ScrollController();
  final Set<String> _submittingFeedback = {};
  final Map<String, String> _submittedFeedback = {};
  final Set<String> _dismissedRecommendationIds = {};
  int _selectedRecommendationIndex = 0;

  @override
  void initState() {
    super.initState();
    _fetchWellnessSummary();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchWellnessSummary() async {
    setState(() {
      _isLoadingAnalytics = true;
      _analyticsError = null;
    });

    try {
      final apiService = ApiService();
      final token = await apiService.getToken();
      if (token == null) {
        if (mounted) setState(() { _isLoadingAnalytics = false; });
        return;
      }
      final response = await apiService.getMapWithAuth('/analytics/wellness/summary', token, allowNotFound: true);
      if (mounted) {
        setState(() {
          _wellnessSummary = response ?? {};
          _isLoadingAnalytics = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _analyticsError = e.toString();
          _isLoadingAnalytics = false;
        });
      }
    }
  }

  bool _isBreakRecommendation(Map<String, dynamic> rec) {
    final category = (rec['category']?.toString() ?? '').toUpperCase();
    final actionType = (rec['action_type']?.toString() ?? '').toLowerCase();
    final recId = (rec['id']?.toString() ?? '').toLowerCase();
    final title = (rec['title']?.toString() ?? '').toLowerCase();

    if (category.contains('WLB') || recId.startsWith('wlb_survey')) {
      return false;
    }
    if (category.contains('HABIT') || actionType.contains('habit')) {
      return category.contains('BREAK') || actionType.contains('break') || title.contains('break');
    }
    if (category.contains('BREAK') || actionType.contains('break') ||
        actionType.contains('walk') || actionType.contains('hydrate') ||
        actionType.contains('stretch') || actionType.contains('increase_breaks') ||
        actionType.contains('short_break') || title.contains('break') || title.contains('walk') || title.contains('hydrate') || title.contains('stretch')) {
      return true;
    }
    return false;
  }

  Future<void> _submitFeedback({
    required String recommendationId,
    required String userAction,
  }) async {
    if (_submittingFeedback.contains(recommendationId)) return;
    setState(() => _submittingFeedback.add(recommendationId));

    try {
      final apiService = ApiService();
      final token = await apiService.getToken();
      if (token == null) {
        if (mounted) _showSnackBar('Session expired', isError: true);
        return;
      }
      await apiService.postWithAuth(
        '/recommend/feedback',
        token,
        {'recommendation_id': recommendationId, 'user_action': userAction},
      );
      if (mounted) {
        setState(() {
          _submittedFeedback[recommendationId] = userAction;
          if (userAction == 'dismissed') {
            _dismissedRecommendationIds.add(recommendationId);
          }
        });
        _showSnackBar('Feedback recorded');
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Failed: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _submittingFeedback.remove(recommendationId));
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? DesignSystem.getSemanticColor(context, SemanticColor.error)
            : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DelayedAnimatedSection(
      visible: true,
      delay: Duration.zero,
      duration: MotionDurations.component,
      slideDirection: SlideDirection.topToBottom,
      child: _buildHeader(context),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final wlbAnalysis = _wellnessSummary?['wlb_analysis'] as Map<String, dynamic>?;
    final status = _determineStatus(wlbAnalysis);

    final Widget header = Row(
      children: [
        Container(
          padding: const EdgeInsets.all(DesignSystem.spacingXS),
          decoration: BoxDecoration(
            color: DesignSystem.getSemanticColor(context, SemanticColor.primary)
                .withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(DesignSystem.radiusS),
          ),
          child: Icon(
            Icons.psychology_alt_outlined,
            size: 20,
            color: DesignSystem.getSemanticColor(context, SemanticColor.primary),
          ),
        ),
        const SizedBox(width: DesignSystem.spacingS),
        Expanded(
          child: Text(
            'Your Wellness Coach',
            style: DesignSystem.titleLarge(context).copyWith(
              fontWeight: FontWeight.w600,
              color: DesignSystem.getSemanticColor(context, SemanticColor.onSurface),
            ),
          ),
        ),
        _StatusChip(status: status),
      ],
    );

    return DelayedAnimatedSection(
      visible: true,
      delay: Duration.zero,
      duration: MotionDurations.component,
      slideDirection: SlideDirection.topToBottom,
      child: DesignSystem.premiumCard(
        context: context,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            const SizedBox(height: DesignSystem.spacingM),
            widget.useInternalScroll
                ? Expanded(
                    child: Scrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        child: _buildBodyContent(context, _wellnessSummary),
                      ),
                    ),
                  )
                : _buildBodyContent(context, _wellnessSummary),
          ],
        ),
      ),
    );
  }

  Widget _buildBodyContent(BuildContext context, Map<String, dynamic>? summary) {
    if (_isLoadingAnalytics) {
      return const _LoadingState();
    }
    if (_analyticsError != null) {
      return _ErrorState(message: _analyticsError!, onRetry: _fetchWellnessSummary);
    }
    if (summary == null) {
      return const _EmptyState(
        message: 'More data is needed, or the Coach couldn\'t load your information.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPersonalSummarySection(context, summary),
        const SizedBox(height: DesignSystem.spacingL),
        _buildNextBestActionSection(context, summary),
        const SizedBox(height: DesignSystem.spacingL),
        _buildWorkIndicatorsSection(context, summary),
        const SizedBox(height: DesignSystem.spacingL),
        _buildProgressInsightsSection(context, summary),
        const SizedBox(height: DesignSystem.spacingL),
      ],
    );
  }

  _Status _determineStatus(Map<String, dynamic>? wlbAnalysis) {
    if (wlbAnalysis == null || wlbAnalysis['has_survey'] != true) {
      return _Status.unavailable;
    }
    final score = wlbAnalysis['survey']?['score'];
    if (score == null) return _Status.unavailable;
    if (score >= 70) return _Status.doingWell;
    return _Status.needsAttention;
  }

  // ──────────────────────────────────────────────────────────────────
  // Section 1: Personal Work Summary
  // ──────────────────────────────────────────────────────────────────
  Widget _buildPersonalSummarySection(BuildContext context, Map<String, dynamic> summary) {
    final wlbAnalysis = summary['wlb_analysis'] as Map<String, dynamic>?;
    final comparison = wlbAnalysis?['weekly_comparison'] as Map<String, dynamic>?;
    final recommendations = summary['wlb_recommendations'] as List<dynamic>?;
    final hasSurvey = wlbAnalysis?['has_survey'] == true;

    String summaryText;
    String? periodLabel;
    final status = _determineStatus(wlbAnalysis);

    if (status == _Status.unavailable) {
      summaryText = 'More work history is needed before personalized insights are available.';
    } else if (recommendations != null && recommendations.isNotEmpty) {
      final primaryRec = recommendations.first;
      final reason = primaryRec['reason']?.toString() ?? primaryRec['evidence']?.toString() ?? '';
      summaryText = reason.isNotEmpty
          ? 'Here\'s what stood out this week: $reason'
          : 'Your weekly work patterns are ready to review.';
    } else if (hasSurvey) {
      summaryText = 'No specific suggestion from the current information.';
    } else {
      summaryText = 'More work history is needed before personalized insights are available.';
    }

    // Determine reporting period
    final survey = wlbAnalysis?['survey'] as Map<String, dynamic>?;
    if (survey != null) {
      final weekStart = survey['week_start'];
      final weekEnd = survey['week_end'];
      if (weekStart != null && weekEnd != null) {
        periodLabel = 'Reporting period: ${_formatDate(weekStart)} – ${_formatDate(weekEnd)}';
      }
    } else if (comparison != null) {
      final baselineStart = comparison['baseline_start'];
      final baselineEnd = comparison['baseline_end'];
      if (baselineStart != null && baselineEnd != null) {
        periodLabel = 'Comparison period: ${_formatDate(baselineStart)} – ${_formatDate(baselineEnd)}';
      }
    }

    return _SectionCard(
      title: 'Personal Work Summary',
      icon: Icons.summarize_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            summaryText,
            style: DesignSystem.body(context).copyWith(
              color: DesignSystem.getSemanticColor(context, SemanticColor.onSurface),
              height: 1.5,
            ),
          ),
          if (periodLabel != null) ...[
            const SizedBox(height: DesignSystem.spacingXS),
            Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 12,
                  color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant),
                ),
                const SizedBox(width: DesignSystem.spacingXS),
                Text(
                  periodLabel,
                  style: DesignSystem.caption(context).copyWith(
                    color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────
  // Section 2: Personal Work Indicators
  // ──────────────────────────────────────────────────────────────────
  Widget _buildWorkIndicatorsSection(BuildContext context, Map<String, dynamic> summary) {
    final wlbAnalysis = summary['wlb_analysis'] as Map<String, dynamic>?;
    final survey = wlbAnalysis?['survey'] as Map<String, dynamic>?;
    final behavioral = wlbAnalysis?['behavioral_indicators'] as Map<String, dynamic>?;
    final comparison = wlbAnalysis?['weekly_comparison'] as Map<String, dynamic>?;

    final metrics = <_MetricData>[];

    // Weekly working hours (from behavioral indicators or survey)
    final hours = behavioral?['total_work_hours'];
    if (hours != null) {
      final obs = behavioral?['work_days_observed'] ?? 1;
      metrics.add(_MetricData(
        label: 'Weekly Working Hours',
        value: hours is int ? '$hours h' : '${hours.toStringAsFixed(1)} h',
        note: 'Based on $obs observed work day${obs == 1 ? '' : 's'}',
        icon: Icons.access_time_rounded,
        trend: _extractTrend(comparison, 'work_hours'),
        isImputed: false,
      ));
    } else {
      metrics.add(_MetricData(
        label: 'Weekly Working Hours',
        value: 'Not enough data yet',
        note: 'Requires completed work sessions',
        icon: Icons.access_time_rounded,
        trend: null,
        isImputed: false,
      ));
    }

    // Break consistency
    final breakConsistency = behavioral?['break_consistency_pct'];
    if (breakConsistency != null) {
      final denominator = behavioral?['eligible_scheduled_breaks'] ?? 0;
      metrics.add(_MetricData(
        label: 'Break Consistency',
        value: '${breakConsistency.toStringAsFixed(0)}%',
        note: 'Of $denominator eligible scheduled breaks',
        icon: Icons.coffee_outlined,
        trend: _extractTrend(comparison, 'break_consistency'),
        isImputed: false,
      ));
    } else {
      metrics.add(_MetricData(
        label: 'Break Consistency',
        value: 'Not enough data yet',
        note: 'Requires scheduled breaks and break records',
        icon: Icons.coffee_outlined,
        trend: null,
        isImputed: false,
      ));
    }

    // Workload manageability (survey-based)
    final workloadScore = survey?['workload_manageability'];
    if (workloadScore != null && survey != null) {
      final isImputed = survey['is_imputed'] == true;
      metrics.add(_MetricData(
        label: 'Workload Manageability',
        value: '$workloadScore / 5',
        note: isImputed ? 'Estimated (imputed baseline)' : 'Employee-reported this week',
        icon: Icons.balance_outlined,
        trend: _extractTrend(comparison, 'workload'),
        isImputed: isImputed,
      ));
    } else {
      metrics.add(_MetricData(
        label: 'Workload Manageability',
        value: 'Not enough data yet',
        note: 'Requires wellbeing check-in submission',
        icon: Icons.balance_outlined,
        trend: null,
        isImputed: false,
      ));
    }

    // Recorded work duration (avg per session)
    final avgDuration = behavioral?['avg_session_minutes'];
    if (avgDuration != null) {
      metrics.add(_MetricData(
        label: 'Avg Session Duration',
        value: '${avgDuration.round()} min',
        note: 'Average per work session',
        icon: Icons.timer_outlined,
        trend: _extractTrend(comparison, 'session_duration'),
        isImputed: false,
      ));
    } else {
      metrics.add(_MetricData(
        label: 'Avg Session Duration',
        value: 'Not enough data yet',
        note: 'Requires completed work sessions',
        icon: Icons.timer_outlined,
        trend: null,
        isImputed: false,
      ));
    }

    return _SectionCard(
      title: 'Personal Work Indicators',
      icon: Icons.analytics_outlined,
      child: Column(
        children: metrics
            .map((m) => _buildMetricTile(context, m))
            .expand((widget) => [widget, const SizedBox(height: DesignSystem.spacingS)])
            .take(metrics.length * 2 - 1)
            .toList(),
      ),
    );
  }

  Widget _buildMetricTile(BuildContext context, _MetricData metric) {
    final trend = metric.trend;
    final trendColor = trend?.startsWith('+') == true
        ? DesignSystem.getSemanticColor(context, SemanticColor.success)
        : trend?.startsWith('-') == true
            ? DesignSystem.getSemanticColor(context, SemanticColor.error)
            : DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant);

    return Container(
      padding: const EdgeInsets.all(DesignSystem.spacingM),
      decoration: BoxDecoration(
        color: DesignSystem.getSemanticColor(context, SemanticColor.surface).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(DesignSystem.radiusM),
        border: Border.all(
          color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant).withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(DesignSystem.spacingS),
            decoration: BoxDecoration(
              color: DesignSystem.getSemanticColor(context, SemanticColor.primary).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(DesignSystem.radiusS),
            ),
            child: Icon(
              metric.icon,
              size: 20,
              color: DesignSystem.getSemanticColor(context, SemanticColor.primary),
            ),
          ),
          const SizedBox(width: DesignSystem.spacingM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metric.label,
                  style: DesignSystem.labelMedium(context).copyWith(
                    color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant),
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      metric.value,
                      style: DesignSystem.title(context).copyWith(
                        fontWeight: FontWeight.w600,
                        color: metric.isImputed
                            ? DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant)
                            : DesignSystem.getSemanticColor(context, SemanticColor.onSurface),
                      ),
                    ),
                    if (metric.isImputed) ...[
                      const SizedBox(width: DesignSystem.spacingXS),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: DesignSystem.getSemanticColor(context, SemanticColor.warning).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(DesignSystem.radiusS),
                        ),
                        child: Text(
                          'Estimated',
                          style: DesignSystem.caption(context).copyWith(
                            fontSize: 9,
                            color: DesignSystem.getSemanticColor(context, SemanticColor.warning),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  metric.note,
                  style: DesignSystem.caption(context).copyWith(
                    color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          if (trend != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: DesignSystem.spacingS, vertical: 4),
              decoration: BoxDecoration(
                color: trendColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(DesignSystem.radiusS),
              ),
              child: Text(
                trend,
                style: DesignSystem.caption(context).copyWith(
                  color: trendColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────
  // Section 3: Your Next Best Action
  // ──────────────────────────────────────────────────────────────────
  Widget _buildNextBestActionSection(BuildContext context, Map<String, dynamic> summary) {
    final recommendations = summary['wlb_recommendations'] as List<dynamic>?;

    final filteredRecs = (recommendations ?? [])
        .where((rec) {
          final id = rec['id']?.toString() ?? '';
          return id.isEmpty || !_dismissedRecommendationIds.contains(id);
        })
        .toList();

    if (filteredRecs.isEmpty) {
      return _SectionCard(
        title: 'Your Next Best Action',
        icon: Icons.lightbulb_outline_rounded,
        child: _EmptyState(
          message: 'No recommendations at this time. Complete a wellbeing check-in to get personalized suggestions.',
          icon: Icons.lightbulb_outline_rounded,
        ),
      );
    }

    // Clamp selection index to valid range
    if (_selectedRecommendationIndex >= filteredRecs.length) {
      _selectedRecommendationIndex = 0;
    }

    final primaryRec = filteredRecs[_selectedRecommendationIndex];
    final recommendationId = primaryRec['id']?.toString() ?? '';
    final title = primaryRec['title']?.toString() ?? 'Recommendation';
    final category = primaryRec['category']?.toString() ?? 'General';
    final priority = primaryRec['priority']?.toString().toUpperCase() ?? 'MEDIUM';
    final reason = primaryRec['reason']?.toString() ?? primaryRec['evidence']?.toString() ?? 'Based on your recent work patterns.';
    final actionStep = primaryRec['action_step']?.toString();
    final expectedOutcome = primaryRec['expected_outcome']?.toString();
    final duration = primaryRec['estimated_duration_minutes'];
    final submittedAction = _submittedFeedback[recommendationId];

    final priorityColor = _getPriorityColor(context, priority);

    return _SectionCard(
      title: 'Your Next Best Action',
      icon: Icons.directions_run_rounded,
      child: Container(
        padding: const EdgeInsets.all(DesignSystem.spacingM),
        decoration: BoxDecoration(
          color: priorityColor.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(DesignSystem.radiusM),
          border: Border.all(
            color: priorityColor.withValues(alpha: 0.25),
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row with category and priority
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: DesignSystem.spacingS, vertical: 4),
                  decoration: BoxDecoration(
                    color: priorityColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(DesignSystem.radiusS),
                  ),
                  child: Text(
                    category,
                    style: DesignSystem.caption(context).copyWith(
                      color: priorityColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: DesignSystem.spacingS),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: DesignSystem.spacingS, vertical: 4),
                  decoration: BoxDecoration(
                    color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(DesignSystem.radiusS),
                  ),
                  child: Text(
                    priority,
                    style: DesignSystem.caption(context).copyWith(
                      color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: DesignSystem.spacingM),
            // Title
            Text(
              title,
              style: DesignSystem.title(context).copyWith(
                fontWeight: FontWeight.w600,
                color: DesignSystem.getSemanticColor(context, SemanticColor.onSurface),
              ),
            ),
            const SizedBox(height: DesignSystem.spacingS),
            // Evidence / Why
            if (reason.isNotEmpty)
              _EvidenceBox(
                text: reason,
                isImputed: primaryRec['is_imputed'] == true,
              ),
            // Duration if available
            if (duration != null) ...[
              const SizedBox(height: DesignSystem.spacingS),
              Row(
                children: [
                  Icon(
                    Icons.timer_outlined,
                    size: 16,
                    color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant),
                  ),
                  const SizedBox(width: DesignSystem.spacingXS),
                  Text(
                    'Estimated time: $duration min',
                    style: DesignSystem.caption(context).copyWith(
                      color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ],
            // Action step
            if (actionStep != null && actionStep.isNotEmpty) ...[
              const SizedBox(height: DesignSystem.spacingM),
              _ActionField(label: 'Suggested action', value: actionStep),
            ],
            // Expected outcome
            if (expectedOutcome != null && expectedOutcome.isNotEmpty) ...[
              const SizedBox(height: DesignSystem.spacingS),
              _ActionField(label: 'Expected outcome', value: expectedOutcome, isOutcome: true),
            ],
            const SizedBox(height: DesignSystem.spacingM),
            // Feedback actions
            _FeedbackActions(
              recommendationId: recommendationId,
              submittedAction: submittedAction,
              isSubmitting: _submittingFeedback.contains(recommendationId),
              showStartBreak: _isBreakRecommendation(primaryRec),
              onSubmit: (userAction) => _submitFeedback(
                recommendationId: recommendationId,
                userAction: userAction,
              ),
              onBreakAction: () async {
                final breakCoach = context.read<BreakCoachState>();
                final success = await breakCoach.acceptRecommendationMap(context, primaryRec);
                if (success) {
                  setState(() {
                    _submittedFeedback[recommendationId] = 'accepted';
                  });
                  _showSnackBar('Break initiated successfully!');
                } else {
                  _showSnackBar('Unable to start break. Ensure you have an active work session.', isError: true);
                }
              },
            ),
            // Recommendation selector
            if (filteredRecs.length > 1) ...[
              const SizedBox(height: DesignSystem.spacingM),
              Container(
                padding: const EdgeInsets.all(DesignSystem.spacingS),
                decoration: BoxDecoration(
                  color: DesignSystem.getSemanticColor(context, SemanticColor.surface).withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(DesignSystem.radiusS),
                  border: Border.all(
                    color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant).withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.menu_book_rounded,
                          size: 16,
                          color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant),
                        ),
                        const SizedBox(width: DesignSystem.spacingXS),
                        Text(
                          'Available Suggestions (${filteredRecs.length})',
                          style: DesignSystem.label(context).copyWith(
                            color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: DesignSystem.spacingXS),
                    Wrap(
                      spacing: DesignSystem.spacingXS,
                      runSpacing: DesignSystem.spacingXS,
                      children: List.generate(filteredRecs.length, (index) {
                        final rec = filteredRecs[index];
                        final recId = rec['id']?.toString() ?? '';
                        final recTitle = rec['title']?.toString() ?? 'Recommendation';
                        final isSelected = index == _selectedRecommendationIndex;
                        final isDismissed = _dismissedRecommendationIds.contains(recId);
                        return FilterChip(
                          label: Text(
                            recTitle,
                            style: DesignSystem.caption(context).copyWith(
                              color: isSelected
                                  ? DesignSystem.getSemanticColor(context, SemanticColor.primary)
                                  : DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          selected: isSelected,
                          onSelected: isDismissed ? null : (selected) {
                            if (selected) {
                              setState(() {
                                _selectedRecommendationIndex = index;
                              });
                            }
                          },
                          backgroundColor: isDismissed
                              ? DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant).withValues(alpha: 0.1)
                              : DesignSystem.getSemanticColor(context, SemanticColor.surface),
                          selectedColor: DesignSystem.getSemanticColor(context, SemanticColor.primary).withValues(alpha: 0.1),
                          checkmarkColor: DesignSystem.getSemanticColor(context, SemanticColor.primary),
                          side: BorderSide(
                            color: isSelected
                                ? DesignSystem.getSemanticColor(context, SemanticColor.primary)
                                : isDismissed
                                    ? DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant).withValues(alpha: 0.3)
                                    : DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant).withValues(alpha: 0.2),
                          ),
                          showCheckmark: false,
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────
  // Section 4: Progress & Weekly Insights
  // ──────────────────────────────────────────────────────────────────
  Widget _buildProgressInsightsSection(BuildContext context, Map<String, dynamic> summary) {
    final wlbAnalysis = summary['wlb_analysis'] as Map<String, dynamic>?;
    final comparison = wlbAnalysis?['weekly_comparison'] as Map<String, dynamic>?;
    final behavioral = wlbAnalysis?['behavioral_indicators'] as Map<String, dynamic>?;

    final insights = <_InsightData>[];

    if (comparison != null && comparison['has_comparison'] == true) {
      // Break consistency change
      final breakChange = comparison['break_consistency_change'];
      if (breakChange != null) {
        final direction = breakChange > 0 ? 'improved' : breakChange < 0 ? 'declined' : 'remained stable';
        final magnitude = (breakChange.abs()).toStringAsFixed(0);
        insights.add(_InsightData(
          title: 'Break Consistency',
          description: '$direction by ${magnitude}pp compared to prior period',
          icon: direction == 'improved' ? Icons.trending_up_rounded : direction == 'declined' ? Icons.trending_down_rounded : Icons.trending_flat_rounded,
          iconColor: direction == 'improved'
              ? DesignSystem.getSemanticColor(context, SemanticColor.success)
              : direction == 'declined'
                  ? DesignSystem.getSemanticColor(context, SemanticColor.error)
                  : DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant),
          isPositive: direction == 'improved',
        ));
      }

      // Work hours change
      final hoursChange = comparison['work_hours_change'];
      if (hoursChange != null) {
        final direction = hoursChange > 0 ? 'increased' : hoursChange < 0 ? 'decreased' : 'remained stable';
        final magnitude = hoursChange.abs().toStringAsFixed(1);
        insights.add(_InsightData(
          title: 'Weekly Work Hours',
          description: '$direction by ${magnitude}h compared to prior period',
          icon: hoursChange < 0 ? Icons.trending_up_rounded : hoursChange > 0 ? Icons.trending_down_rounded : Icons.trending_flat_rounded,
          iconColor: hoursChange < 0
              ? DesignSystem.getSemanticColor(context, SemanticColor.success)
              : hoursChange > 0
                  ? DesignSystem.getSemanticColor(context, SemanticColor.error)
                  : DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant),
          isPositive: hoursChange < 0,
        ));
      }

      // Completed recommendations
      final completedRecs = comparison['completed_recommendations'];
      if (completedRecs != null && completedRecs > 0) {
        insights.add(_InsightData(
          title: 'Actions Completed',
          description: '$completedRecs recommendation${completedRecs == 1 ? '' : 's'} completed this period',
          icon: Icons.check_circle_outline_rounded,
          iconColor: DesignSystem.getSemanticColor(context, SemanticColor.success),
          isPositive: true,
        ));
      }

      // Dismissed recommendations
      final dismissedRecs = comparison['dismissed_recommendations'];
      if (dismissedRecs != null && dismissedRecs > 0) {
        insights.add(_InsightData(
          title: 'Suggestions Dismissed',
          description: '$dismissedRecs suggestion${dismissedRecs == 1 ? '' : 's'} dismissed — alternatives prioritized',
          icon: Icons.close_rounded,
          iconColor: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant),
          isPositive: false,
        ));
      }
    }

    // Stability insight for stable employees
    if (insights.isEmpty && behavioral != null) {
      final concerns = behavioral['concerns'] as List<dynamic>? ?? [];
      if (concerns.isEmpty && behavioral['total_work_hours'] != null) {
        insights.add(_InsightData(
          title: 'Work Patterns',
          description: 'Work patterns remain stable — no significant changes detected',
          icon: Icons.trending_flat_rounded,
          iconColor: DesignSystem.getSemanticColor(context, SemanticColor.primary),
          isPositive: true,
        ));
      }
    }

    if (insights.isEmpty) {
      return _SectionCard(
        title: 'Progress & Weekly Insights',
        icon: Icons.timeline_rounded,
        child: _EmptyState(
          message: 'Not enough historical data for comparison yet. Complete more weeks to see progress trends.',
          icon: Icons.timeline_rounded,
        ),
      );
    }

    return _SectionCard(
      title: 'Progress & Weekly Insights',
      icon: Icons.timeline_rounded,
      child: Column(
        children: insights
            .map((insight) => _buildInsightTile(context, insight))
            .expand((widget) => [widget, const SizedBox(height: DesignSystem.spacingS)])
            .take(insights.length * 2 - 1)
            .toList(),
      ),
    );
  }

  Widget _buildInsightTile(BuildContext context, _InsightData insight) {
    return Container(
      padding: const EdgeInsets.all(DesignSystem.spacingM),
      decoration: BoxDecoration(
        color: insight.iconColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(DesignSystem.radiusM),
        border: Border.all(
          color: insight.iconColor.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(DesignSystem.spacingS),
            decoration: BoxDecoration(
              color: insight.iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(DesignSystem.radiusS),
            ),
            child: Icon(
              insight.icon,
              size: 20,
              color: insight.iconColor,
            ),
          ),
          const SizedBox(width: DesignSystem.spacingM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  insight.title,
                  style: DesignSystem.labelMedium(context).copyWith(
                    fontWeight: FontWeight.w600,
                    color: DesignSystem.getSemanticColor(context, SemanticColor.onSurface),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  insight.description,
                  style: DesignSystem.caption(context).copyWith(
                    color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────────────────────────
  String? _extractTrend(Map<String, dynamic>? comparison, String key) {
    if (comparison == null) return null;
    final changeKey = '${key}_change';
    final change = comparison[changeKey];
    if (change == null) return null;
    final prefix = change > 0 ? '+' : '';
    final suffix = key == 'work_hours' ? 'h' : key == 'session_duration' ? 'min' : 'pp';
    return '$prefix${change.toStringAsFixed(key == 'work_hours' ? 1 : 0)}$suffix';
  }

  String _formatDate(String? isoString) {
    if (isoString == null) return '';
    try {
      final date = DateTime.parse(isoString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (_) {
      return isoString;
    }
  }

  Color _getPriorityColor(BuildContext context, String priority) {
    switch (priority) {
      case 'HIGH':
        return DesignSystem.getSemanticColor(context, SemanticColor.error);
      case 'MEDIUM':
        return DesignSystem.getSemanticColor(context, SemanticColor.warning);
      default:
        return DesignSystem.getSemanticColor(context, SemanticColor.primary);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────
// Supporting Widgets
// ─────────────────────────────────────────────────────────────────────

enum _Status { doingWell, needsAttention, unavailable }

class _StatusChip extends StatelessWidget {
  final _Status status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      _Status.doingWell => ('Doing Well', DesignSystem.getSemanticColor(context, SemanticColor.success)),
      _Status.needsAttention => ('Needs Attention', DesignSystem.getSemanticColor(context, SemanticColor.warning)),
      _Status.unavailable => ('Building Profile', DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: DesignSystem.spacingS, vertical: DesignSystem.spacingXS),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(DesignSystem.radiusS),
      ),
      child: Text(
        label,
        style: DesignSystem.caption(context).copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: DesignSystem.getSemanticColor(context, SemanticColor.primary),
            ),
            const SizedBox(width: DesignSystem.spacingS),
            Text(
              title,
              style: DesignSystem.title(context).copyWith(
                fontWeight: FontWeight.w600,
                color: DesignSystem.getSemanticColor(context, SemanticColor.onSurface),
              ),
            ),
          ],
        ),
        const SizedBox(height: DesignSystem.spacingM),
        child,
      ],
    );
  }
}

class _MetricData {
  final String label;
  final String value;
  final String note;
  final IconData icon;
  final String? trend;
  final bool isImputed;

  const _MetricData({
    required this.label,
    required this.value,
    required this.note,
    required this.icon,
    this.trend,
    required this.isImputed,
  });
}

class _InsightData {
  final String title;
  final String description;
  final IconData icon;
  final Color iconColor;
  final bool isPositive;

  const _InsightData({
    required this.title,
    required this.description,
    required this.icon,
    required this.iconColor,
    required this.isPositive,
  });
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(DesignSystem.spacingL),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              color: DesignSystem.getSemanticColor(context, SemanticColor.primary),
            ),
            const SizedBox(height: DesignSystem.spacingM),
            Text(
              'Loading your wellness insights...',
              style: DesignSystem.body(context).copyWith(
                color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(DesignSystem.spacingL),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: DesignSystem.getSemanticColor(context, SemanticColor.error),
            ),
            const SizedBox(height: DesignSystem.spacingM),
            Text(
              'Unable to load insights',
              style: DesignSystem.title(context).copyWith(
                color: DesignSystem.getSemanticColor(context, SemanticColor.onSurface),
              ),
            ),
            const SizedBox(height: DesignSystem.spacingXS),
            Text(
              message,
              textAlign: TextAlign.center,
              style: DesignSystem.caption(context).copyWith(
                color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: DesignSystem.spacingM),
            DesignSystem.primaryButton(
              context: context,
              onPressed: onRetry,
              label: 'Retry',
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;
  final IconData icon;

  const _EmptyState({required this.message, this.icon = Icons.info_outline_rounded});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(DesignSystem.spacingL),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(DesignSystem.spacingM),
              decoration: BoxDecoration(
                color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(DesignSystem.radiusL),
              ),
              child: Icon(
                icon,
                size: 32,
                color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: DesignSystem.spacingM),
            Text(
              message,
              textAlign: TextAlign.center,
              style: DesignSystem.body(context).copyWith(
                color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EvidenceBox extends StatelessWidget {
  final String text;
  final bool isImputed;

  const _EvidenceBox({required this.text, this.isImputed = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignSystem.spacingM),
      decoration: BoxDecoration(
        color: isImputed
            ? DesignSystem.getSemanticColor(context, SemanticColor.warning).withValues(alpha: 0.08)
            : DesignSystem.getSemanticColor(context, SemanticColor.primary).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(DesignSystem.radiusS),
        border: Border.all(
          color: isImputed
              ? DesignSystem.getSemanticColor(context, SemanticColor.warning).withValues(alpha: 0.2)
              : DesignSystem.getSemanticColor(context, SemanticColor.primary).withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isImputed ? Icons.auto_fix_high_outlined : Icons.lightbulb_outline_rounded,
            size: 18,
            color: isImputed
                ? DesignSystem.getSemanticColor(context, SemanticColor.warning)
                : DesignSystem.getSemanticColor(context, SemanticColor.primary),
          ),
          const SizedBox(width: DesignSystem.spacingS),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isImputed)
                  Text(
                    'Based on estimated data',
                    style: DesignSystem.caption(context).copyWith(
                      color: DesignSystem.getSemanticColor(context, SemanticColor.warning),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                Text(
                  text,
                  style: DesignSystem.caption(context).copyWith(
                    color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionField extends StatelessWidget {
  final String label;
  final String value;
  final bool isOutcome;

  const _ActionField({required this.label, required this.value, this.isOutcome = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: DesignSystem.caption(context).copyWith(
            color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: DesignSystem.body(context).copyWith(
            color: DesignSystem.getSemanticColor(context, SemanticColor.onSurface),
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _FeedbackActions extends StatelessWidget {
  final String recommendationId;
  final String? submittedAction;
  final bool isSubmitting;
  final bool showStartBreak;
  final void Function(String) onSubmit;
  final VoidCallback onBreakAction;

  const _FeedbackActions({
    required this.recommendationId,
    required this.submittedAction,
    required this.isSubmitting,
    this.showStartBreak = true,
    required this.onSubmit,
    required this.onBreakAction,
  });

  @override
  Widget build(BuildContext context) {
    final isDismissed = submittedAction == 'dismissed';
    final isHelpful = submittedAction == 'helpful';
    final isNotHelpful = submittedAction == 'not_helpful';
    final isAccepted = submittedAction == 'accepted' || submittedAction == 'completed';

    if (isDismissed) {
      return Container(
        padding: const EdgeInsets.all(DesignSystem.spacingS),
        decoration: BoxDecoration(
          color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(DesignSystem.radiusS),
        ),
        child: Row(
          children: [
            Icon(
              Icons.close_rounded,
              size: 18,
              color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant),
            ),
            const SizedBox(width: DesignSystem.spacingS),
            Text(
              'Dismissed — won\'t show again unless new evidence appears',
              style: DesignSystem.caption(context).copyWith(
                color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
    }

    if (isAccepted) {
      return Wrap(
        spacing: DesignSystem.spacingS,
        runSpacing: DesignSystem.spacingS,
        children: [
          _FeedbackButton(
            label: isHelpful ? '✓ Helpful' : 'Helpful',
            onPressed: isSubmitting ? null : () => onSubmit(isHelpful ? 'not_helpful' : 'helpful'),
            isSelected: isHelpful,
            variant: ButtonVariant.outline,
          ),
          _FeedbackButton(
            label: isNotHelpful ? '✓ Not helpful' : 'Not helpful',
            onPressed: isSubmitting ? null : () => onSubmit(isNotHelpful ? 'helpful' : 'not_helpful'),
            isSelected: isNotHelpful,
            variant: ButtonVariant.outline,
          ),
          _FeedbackButton(
            label: 'Dismiss',
            onPressed: isSubmitting ? null : () => onSubmit('dismissed'),
            variant: ButtonVariant.ghost,
            icon: Icons.close_rounded,
          ),
        ],
      );
    }

    // Default state - accept / dismiss
    return Wrap(
      spacing: DesignSystem.spacingS,
      runSpacing: DesignSystem.spacingS,
      children: [
        if (showStartBreak)
          _FeedbackButton(
            label: 'Start Break',
            onPressed: isSubmitting ? null : onBreakAction,
            variant: ButtonVariant.primary,
            icon: Icons.play_arrow_rounded,
          ),
        _FeedbackButton(
          label: 'Accept',
          onPressed: isSubmitting ? null : () => onSubmit('accepted'),
          variant: ButtonVariant.primary,
        ),
        _FeedbackButton(
          label: 'Dismiss',
          onPressed: isSubmitting ? null : () => onSubmit('dismissed'),
          variant: ButtonVariant.ghost,
          icon: Icons.close_rounded,
        ),
      ],
    );
  }
}

class _FeedbackButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isSelected;
  final ButtonVariant variant;
  final IconData? icon;

  const _FeedbackButton({
    required this.label,
    required this.onPressed,
    this.isSelected = false,
    this.variant = ButtonVariant.outline,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return switch (variant) {
      ButtonVariant.primary => FilledButton.icon(
          onPressed: onPressed,
          icon: icon != null ? Icon(icon, size: 16) : const SizedBox.shrink(),
          label: Text(label, style: DesignSystem.labelMedium(context)),
          style: FilledButton.styleFrom(
            backgroundColor: isSelected
                ? DesignSystem.getSemanticColor(context, SemanticColor.onSurface)
                : null,
            foregroundColor: isSelected
                ? DesignSystem.getSemanticColor(context, SemanticColor.primary)
                : null,
            padding: const EdgeInsets.symmetric(horizontal: DesignSystem.spacingM, vertical: DesignSystem.spacingS),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignSystem.radiusS)),
          ),
        ),
      ButtonVariant.outline => OutlinedButton.icon(
          onPressed: onPressed,
          icon: icon != null ? Icon(icon, size: 16) : const SizedBox.shrink(),
          label: Text(label, style: DesignSystem.labelMedium(context)),
          style: OutlinedButton.styleFrom(
            foregroundColor: isSelected
                ? DesignSystem.getSemanticColor(context, SemanticColor.onSurface)
                : DesignSystem.getSemanticColor(context, SemanticColor.primary),
            backgroundColor: isSelected
                ? DesignSystem.getSemanticColor(context, SemanticColor.primary)
                : null,
            side: BorderSide(
              color: isSelected
                  ? DesignSystem.getSemanticColor(context, SemanticColor.primary)
                  : DesignSystem.getSemanticColor(context, SemanticColor.primary).withValues(alpha: 0.5),
            ),
            padding: const EdgeInsets.symmetric(horizontal: DesignSystem.spacingM, vertical: DesignSystem.spacingS),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignSystem.radiusS)),
          ),
        ),
      ButtonVariant.ghost => TextButton.icon(
          onPressed: onPressed,
          icon: icon != null ? Icon(icon, size: 16) : const SizedBox.shrink(),
          label: Text(label, style: DesignSystem.labelMedium(context)),
          style: TextButton.styleFrom(
            foregroundColor: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant),
            padding: const EdgeInsets.symmetric(horizontal: DesignSystem.spacingM, vertical: DesignSystem.spacingS),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignSystem.radiusS)),
          ),
        ),
    };
  }
}

enum ButtonVariant { primary, outline, ghost }