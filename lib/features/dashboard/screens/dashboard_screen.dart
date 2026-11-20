import 'package:flutter/material.dart';
import 'package:intellibreak/core/design_system.dart';
import 'package:intellibreak/core/motion.dart';
import 'package:intellibreak/features/dashboard/widgets/ai_wellness_card.dart';
import 'package:intellibreak/features/dashboard/widgets/shift_controller.dart';
import 'package:intellibreak/features/dashboard/widgets/metrics_section.dart';
import 'package:intellibreak/features/dashboard/widgets/work_pattern_summary_card.dart';
import 'package:intellibreak/features/dashboard/widgets/daily_timeline_card.dart';
import 'package:intellibreak/features/dashboard/widgets/greeting_section.dart';
import 'package:intellibreak/features/work_life_balance/widgets/wlb_hero_card.dart';
import 'package:intellibreak/features/wellbeing/session_wellbeing_checkin.dart';
import 'package:intellibreak/features/auth/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intellibreak/features/dashboard/screens/app_shell.dart';
import 'package:provider/provider.dart';
import 'package:intellibreak/features/dashboard/providers/break_coach_state.dart';
import 'package:intellibreak/features/dashboard/models/break_coach_models.dart';
import 'package:intellibreak/features/dashboard/widgets/break_coach_notification.dart';
import 'package:intellibreak/providers/work_session_provider.dart';
import 'package:intellibreak/providers/work_session_models.dart';

/// Wrapper for backward compatibility - redirects to AppShell
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppShell();
  }
}

class DashboardScreenContent extends StatefulWidget {
  final String? userName;
  final String? userEmail;

  /// Navigates to the full Work-Life Balance screen.
  final VoidCallback? onOpenWorkLifeBalance;

  const DashboardScreenContent({
    super.key,
    this.userName,
    this.userEmail,
    this.onOpenWorkLifeBalance,
  });

  @override
  State<DashboardScreenContent> createState() {
    return _DashboardScreenContentState();
  }
}

class _DashboardScreenContentState extends State<DashboardScreenContent> {
  String? _token;
  String? _lastCheckedToken;
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _loadToken();
    // Wire reactive session provider updates to Break Coach
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final breakCoachState = Provider.of<BreakCoachState>(context, listen: false);
      final sessionProvider = Provider.of<WorkSessionProvider>(context, listen: false);
      breakCoachState.attachSessionProvider(sessionProvider);
    });
  }

  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (!mounted) return;
    setState(() {
      _token = token;
    });
    _checkForBreakRecommendation();
  }

  @override
  void dispose() {
    // Ensure Break Coach listener is cleaned up when dashboard lifecycle ends
    try {
      final breakCoachState = Provider.of<BreakCoachState>(context, listen: false);
      breakCoachState.detachSessionProvider();
    } catch (_) {}
    super.dispose();
  }

  void _checkForBreakRecommendation() {
    if (_token != null && _token != _lastCheckedToken) {
      _lastCheckedToken = _token;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final breakCoachState = Provider.of<BreakCoachState>(context, listen: false);
        final sessionProvider = Provider.of<WorkSessionProvider>(context, listen: false);
        breakCoachState.checkRecommendation(_token!, sessionProvider: sessionProvider);
      });
    }
  }

  BreakType _getBreakTypeFromRecommendation(BreakCoachRecommendation recommendation) {
    switch (recommendation.suggestedBreakType) {
      case 'BREAK_1':
        return BreakType.break1;
      case 'BREAK_2':
        return BreakType.break2;
      case 'LUNCH':
        return BreakType.lunch;
      case 'COACH_BREAK':
        return BreakType.fromWire('COACH_BREAK');
      default:
        return BreakType.break1; // fallback
    }
  }

  void _onTakeBreak() async {
    if (!mounted) return;

    final breakCoachState = Provider.of<BreakCoachState>(context, listen: false);
    final workSessionProvider = Provider.of<WorkSessionProvider>(context, listen: false);

    // If an active break already exists, don't attempt to start another (backend would 400)
    if (workSessionProvider.isOnBreak) {
      // Force break-in-progress state to show guidance
      breakCoachState.setBreakInProgressFromActiveBreak();
      return;
    }

    final success = await breakCoachState.acceptRecommendation(context);

    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to start recovery break. Please try again.')),
      );
    }
  }

  void _onTakeLunch() async {
    final recommendation = Provider.of<BreakCoachState>(context, listen: false).currentRecommendation;
    if (recommendation == null) return;

    final breakCoachState = Provider.of<BreakCoachState>(context, listen: false);
    final workSessionProvider = Provider.of<WorkSessionProvider>(context, listen: false);
    final breakType = _getBreakTypeFromRecommendation(recommendation);

    breakCoachState.dismiss();

    if (!mounted) return;

    final availability = workSessionProvider.availabilityFor(breakType);
    if (availability.status != BreakStatus.available) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(availability.reason ?? 'Break not available')),
      );
      return;
    }

    try {
      await workSessionProvider.startBreak(breakType);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start break: $e')),
        );
      }
    }
  }

  void _onSnooze() {
    Provider.of<BreakCoachState>(context, listen: false).snooze();
  }

  void _onIgnore() {
    Provider.of<BreakCoachState>(context, listen: false).ignore();
  }

  void _onContinue() {
    Provider.of<BreakCoachState>(context, listen: false).dismiss();
  }

  void _onClose() {
    Provider.of<BreakCoachState>(context, listen: false).hide();
  }

  @override
  @override
  Widget build(BuildContext context) {
    final bool isDesktop = MediaQuery.of(context).size.width >= 1100;

    String displayUserName = widget.userName ?? _authService.getUserDisplayName();
    if (displayUserName.isEmpty) {
      displayUserName = 'User';
    }

    // Break Coach Notification - uses shared BreakCoachState from main.dart
    final breakCoachState = context.watch<BreakCoachState>();
    final showNotification = breakCoachState.isVisible &&
        (breakCoachState.currentRecommendation != null ||
         (breakCoachState.isBreakInProgress && breakCoachState.acceptedRecommendation != null));
    return Stack(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                  maxWidth: constraints.maxWidth,
                ),
                child: isDesktop
                    ? _buildDesktop(isGuest: false, userName: displayUserName)
                    : _buildMobile(isGuest: false, userName: displayUserName),
              ),
            );
          },
        ),
        if (showNotification)
          Positioned(
            top: 24,
            left: 24,
            right: 24,
            child: BreakCoachNotification(
              recommendation: breakCoachState.isBreakInProgress
                  ? (breakCoachState.acceptedRecommendation ?? breakCoachState.currentRecommendation)
                  : breakCoachState.currentRecommendation,
              onTakeBreak: _onTakeBreak,
              onTakeLunch: _onTakeLunch,
              onSnooze: _onSnooze,
              onIgnore: _onIgnore,
              onContinue: _onContinue,
              onClose: _onClose,
            ),
          ),
      ],
    );
  }

  Widget _buildDesktop({required bool isGuest, required String userName}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Derive a bounded height from the viewport, never from panel content.
        final panelHeight = (MediaQuery.sizeOf(context).height * 0.42)
            .clamp(320.0, 520.0);
        return Column(
          children: [
            // 1. Greeting and date at top
            Padding(
              padding: const EdgeInsets.fromLTRB(24, DesignSystem.spacingXXL, 24, 0),
              child: DelayedAnimatedSection(
                visible: true,
                duration: MotionDurations.component,
                slideDirection: SlideDirection.topToBottom,
                delay: Duration.zero,
                child: GreetingSection(isGuest: isGuest, userName: userName),
              ),
            ),
            const SizedBox(height: DesignSystem.spacingL),
            // 1b. Work-life balance headline (primary focus of the product)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: WlbHeroCard(onOpenDetails: widget.onOpenWorkLifeBalance),
            ),
            const SizedBox(height: DesignSystem.spacingL),
            // 2. Shift Controller and Contextual Break Recommendation side by side
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 6,
                    child: SizedBox(
                      height: panelHeight,
                      child: DesignSystem.premiumCard(
                        context: context,
                        child: const ShiftController(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 4,
                    child: SizedBox(
                      height: panelHeight,
                      child: const AIWellnessCard(useInternalScroll: true),
                    ),
                  ),
                ],
              ),
            ),
        const SizedBox(height: DesignSystem.spacingL),
        // 3. Compact Work Metrics
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: DesignSystem.premiumCard(
            context: context,
            child: const MetricsSection(),
          ),
        ),
        const SizedBox(height: DesignSystem.spacingL),
        // 4. Interactive Wellbeing Check-in trigger card
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: DesignSystem.premiumCard(
            context: context,
            child: Row(
              children: [
                Icon(Icons.favorite_outline, color: Theme.of(context).colorScheme.primary, size: 26),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Session Wellbeing Check-in',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Take a moment to check in with yourself. Your feedback helps IntelliBreak improve personalized break recommendations.',
                        style: TextStyle(fontSize: 13.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    final workSessionProvider = Provider.of<WorkSessionProvider>(context, listen: false);
                    final sessionId = workSessionProvider.state.session?.id;
                    if (sessionId == null || sessionId.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please start a work session first to check in.')),
                      );
                      return;
                    }
                    showDialog(
                      context: context,
                      builder: (context) => SessionWellbeingCheckin(workSessionId: sessionId),
                    );
                  },
                  icon: const Icon(Icons.rate_review_outlined, size: 18),
                  label: const Text('Start Check-In'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: DesignSystem.spacingL),
        // 5. Today's Timeline and Work Rhythm side by side
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 6,
                child: const DailyTimelineCard(),
              ),
              const SizedBox(width: 24),
              Expanded(
                flex: 6,
                child: const WorkPatternSummaryCard(),
              ),
            ],
          ),
        ),
        const SizedBox(height: DesignSystem.spacingXXL),
          ],
        );
      },
    );
  }

  Widget _buildMobile({required bool isGuest, required String userName}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, DesignSystem.spacingXL, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GreetingSection(isGuest: isGuest, userName: userName),
          const SizedBox(height: DesignSystem.spacingL),
          WlbHeroCard(onOpenDetails: widget.onOpenWorkLifeBalance),
          const SizedBox(height: DesignSystem.spacingL),
          DesignSystem.premiumCard(
            context: context,
            child: const ShiftController(),
          ),
          const SizedBox(height: DesignSystem.spacingL),
          const AIWellnessCard(),
          const SizedBox(height: DesignSystem.spacingL),
          DesignSystem.premiumCard(
            context: context,
            child: const MetricsSection(),
          ),
          const SizedBox(height: DesignSystem.spacingL),
          DesignSystem.premiumCard(
            context: context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.favorite_outline, color: Theme.of(context).colorScheme.primary, size: 22),
                    const SizedBox(width: 12),
                    Text(
                      'Session Wellbeing Check-in',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Take a moment to check in with yourself. Your feedback helps IntelliBreak improve personalized break recommendations.',
                  style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      final workSessionProvider = Provider.of<WorkSessionProvider>(context, listen: false);
                      final sessionId = workSessionProvider.state.session?.id;
                      if (sessionId == null || sessionId.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please start a work session first to check in.')),
                        );
                        return;
                      }
                      showDialog(
                        context: context,
                        builder: (context) => SessionWellbeingCheckin(workSessionId: sessionId),
                      );
                    },
                    icon: const Icon(Icons.rate_review_outlined, size: 18),
                    label: const Text('Start Check-In'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: DesignSystem.spacingL),
          const DailyTimelineCard(),
          const SizedBox(height: DesignSystem.spacingL),
          const WorkPatternSummaryCard(),
          const SizedBox(height: DesignSystem.spacingXXL),
        ],
      ),
    );
  }
}
