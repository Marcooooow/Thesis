import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intellibreak/features/dashboard/tutorial/tutorial_manager.dart';

class TutorialOverlay extends StatefulWidget {
  final Widget child;
  final VoidCallback? onDismissed;

  const TutorialOverlay({
    super.key,
    required this.child,
    this.onDismissed,
  });

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay> {
  bool _shouldShow = true;
  bool _isInitialized = false;
  bool _isDismissed = false;
  int _currentStep = -1;

  @override
  void initState() {
    super.initState();
    _checkAuthAndTutorial();
  }

  void _checkAuthAndTutorial() async {
    // Set up auth state listener to handle changes
    FirebaseAuth.instance.authStateChanges().listen((User? user) async {
      if (!mounted) return;

      // Check if tutorial should be shown based on auth state
      final shouldShow = await TutorialManager.shouldShowTutorial();

      if (!mounted) return;

      setState(() {
        _shouldShow = shouldShow;
        _isInitialized = true;
      });

      // Get current step if tutorial should be shown
      if (shouldShow && mounted) {
        final step = await TutorialManager.getCurrentStep();
        if (mounted) {
          setState(() {
            _currentStep = step;
          });
        }
      } else if (mounted) {
        // Tutorial should not be shown
        // _isInitialized is already true
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return widget.child;
    }
    if (_isDismissed) {
      return widget.child;
    }

    if (_shouldShow) {
      return _buildTutorialStack(context);
    } else {
      return widget.child;
    }
  }

  Widget _buildTutorialStack(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        _buildDimmedBackground(context),
        _buildTutorialContent(context),
      ],
    );
  }

  Widget _buildDimmedBackground(BuildContext context) => Positioned.fill(
        child: Container(
          color: Colors.black.withValues(alpha: 0.50),
        ),
      );

  Widget _buildTutorialContent(BuildContext context) {
    final step = _currentStep;
    if (step == -1) {
      return _buildWelcomeScreen(context);
    } else if (step >= TutorialStep.finish.index) {
      // Should not happen, but fallback
      return _buildWelcomeScreen(context);
    } else {
      return _buildStepScreen(context, step);
    }
  }

  Widget _buildWelcomeScreen(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 400,
          maxHeight: 400,
        ),
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1F26) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.15)
                    : const Color(0xFFD3D9E1),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Welcome to IntelliBreak',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: isDark ? const Color(0xFFF5F5F7) : const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Let\'s take a quick tour of how IntelliBreak helps you manage your work sessions, tasks, and breaks.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? const Color(0xFFA8A8B3) : const Color(0xFF4B5563),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _onSkipPressed,
                      child: Text(
                        'Skip',
                        style: TextStyle(
                          color: isDark ? const Color(0xFFA8A8B3) : const Color(0xFF4B5563),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _onStartPressed,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Start Tutorial'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepScreen(BuildContext context, int step) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final stepTitle = _getStepTitle(step);
    final stepContent = _getStepContent(step);
    final stepNumber = step + 1;
    final totalSteps = 5;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 400,
          maxHeight: 500,
        ),
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1F26) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.15)
                    : const Color(0xFFD3D9E1),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header with step indicator and Skip
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Step indicator dots
                    Row(
                      children: List.generate(totalSteps, (index) {
                        final isActive = index == step;
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isActive
                                ? Theme.of(context).colorScheme.primary
                                : (isDark
                                    ? Colors.white.withValues(alpha: 0.2)
                                    : Colors.grey.withValues(alpha: 0.3)),
                          ),
                        );
                      }),
                    ),
                    // Skip button (text)
                    TextButton(
                      onPressed: _onSkipPressed,
                      child: Text(
                        'Skip Tutorial',
                        style: TextStyle(
                          color: isDark ? const Color(0xFFA8A8B3) : const Color(0xFF4B5563),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Title
                Text(
                  stepTitle,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? const Color(0xFFF5F5F7) : const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 24),
                // Content
                Text(
                  stepContent,
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.5,
                    color: isDark ? const Color(0xFFA8A8B3) : const Color(0xFF4B5563),
                  ),
                ),
                const SizedBox(height: 24),
                // Step text
                Text(
                  'Step $stepNumber of $totalSteps',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark
                        ? const Color(0xFFA8A8B3).withValues(alpha: 0.8)
                        : const Color(0xFF5B6472),
                  ),
                ),
                const SizedBox(height: 24),
                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (step > 0) ...[
                      TextButton(
                        onPressed: _onBackPressed,
                        child: Text(
                          'Back',
                          style: TextStyle(
                            color: isDark ? const Color(0xFFA8A8B3) : const Color(0xFF4B5563),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (step < totalSteps - 1) ...[
                      ElevatedButton(
                        onPressed: _onNextPressed,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Next'),
                      ),
                    ] else ...[
                      ElevatedButton(
                        onPressed: _onFinishPressed,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Finish'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getStepTitle(int step) {
    switch (step) {
      case 0:
        return 'Start Your Shift';
      case 1:
        return 'Manage Your Tasks';
      case 2:
        return 'Track Your Work';
      case 3:
        return 'Take Breaks';
      case 4:
        return 'Review Your Work';
      default:
        return '';
    }
  }

  String _getStepContent(int step) {
    switch (step) {
      case 0:
        return 'Start a work session when you\'re ready to begin working. Your active session keeps track of your working time.';
      case 1:
        return 'Create or choose a task you want to work on. Tasks remain available across work sessions so unfinished work can be continued later.';
      case 2:
        return 'Start a task timer when you begin working. IntelliBreak records your task time so you can review how you spend your workday.';
      case 3:
        return 'Record your breaks while working. IntelliBreak helps you maintain sustainable work and break patterns.';
      case 4:
        return 'Use the dashboard to review your tasks, work sessions, breaks, and Focus Rate.';
      default:
        return '';
    }
  }

  Future<void> _onStartPressed() async {
    await TutorialManager.setCurrentStep(0);
    _currentStep = 0;
    if (mounted) setState(() {});
  }

  Future<void> _onBackPressed() async {
    final current = await TutorialManager.getCurrentStep();
    if (current > 0) {
      await TutorialManager.setCurrentStep(current - 1);
      _currentStep = current - 1;
      if (mounted) setState(() {});
    }
  }

  Future<void> _onNextPressed() async {
    final current = await TutorialManager.getCurrentStep();
    if (current < 4) {
      await TutorialManager.setCurrentStep(current + 1);
      _currentStep = current + 1;
      if (mounted) setState(() {});
    }
  }

  Future<void> _onSkipPressed() async {
    // Set dismissed state immediately to prevent re-opening
    if (mounted) {
      setState(() {
        _isDismissed = true;
      });
    }
    await TutorialManager.markTutorialAsSkipped();
    if (mounted) {
      widget.onDismissed?.call();
    }
  }

  Future<void> _onFinishPressed() async {
    // Set dismissed state immediately to prevent re-opening
    if (mounted) {
      setState(() {
        _isDismissed = true;
      });
    }
    await TutorialManager.markTutorialAsCompleted();
    if (mounted) {
      widget.onDismissed?.call();
    }
  }
}