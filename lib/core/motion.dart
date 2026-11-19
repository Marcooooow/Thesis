import 'package:flutter/material.dart';

/// Slide direction for fade slide transitions.
enum SlideDirection {
  topToBottom,
  bottomToTop,
  leftToRight,
  rightToLeft,
}

/// Motion durations for the IntelliBreak application.
class MotionDurations {
  /// Micro interactions: 100–150ms
  static const Duration micro = Duration(milliseconds: 125);

  /// Small state transitions: 150–200ms
  static const Duration smallState = Duration(milliseconds: 175);

  /// Component transitions: 200–300ms
  static const Duration component = Duration(milliseconds: 250);

  /// Page transitions: 250–350ms
  static const Duration page = Duration(milliseconds: 300);

  /// Modal/dialog transitions: 200–300ms
  static const Duration modal = Duration(milliseconds: 250);

  /// Data transitions: 300–400ms
  static const Duration dataTransition = Duration(milliseconds: 350);

  /// Stagger delay between elements: 40–70ms
  static const Duration stagger = Duration(milliseconds: 55);
}

/// Motion curves for the IntelliBreak application.
class MotionCurves {
  /// Primary ease-out cubic curve
  static const Curve easeOutCubic = Curves.easeOutCubic;

  /// Primary ease-in-out curve
  static const Curve easeInOut = Curves.easeInOut;
}

/// Global animation control — respects reduced-motion preferences.
class GlobalMotionController {
  static bool areEnabled(BuildContext context) => !MediaQuery.of(context).disableAnimations;
}

/// Subtle button scale (0.97–0.99) for interactive feedback.
class SubtleButtonScale extends StatefulWidget {
  final Widget child;
  const SubtleButtonScale({super.key, required this.child});

  @override
  State<SubtleButtonScale> createState() => _SubtleButtonScaleState();
}

class _SubtleButtonScaleState extends State<SubtleButtonScale> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(duration: MotionDurations.micro, vsync: this);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!GlobalMotionController.areEnabled(context)) return widget.child;
    return ScaleTransition(
      scale: Tween<double>(begin: 0.98, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: MotionCurves.easeOutCubic)),
      child: widget.child,
    );
  }
}

/// A reusable fade and slide transition widget.
class FadeSlideTransition extends StatelessWidget {
  const FadeSlideTransition({
    super.key,
    required this.animation,
    this.slideDirection = SlideDirection.topToBottom,
    this.isFade = true,
    this.isSlide = true,
    required this.child,
  });

  /// The animation driving this transition.
  final Animation<double> animation;

  /// The direction of the slide.
  final SlideDirection slideDirection;

  /// Whether to fade the child.
  final bool isFade;

  /// Whether to slide the child.
  final bool isSlide;

  /// The child widget to animate.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bool areAnimationsEnabled = !MediaQuery.of(context).disableAnimations;
    if (!areAnimationsEnabled) {
      return child;
    }

    // Use easeOutCubic for a natural, calming motion
    final Animation<double> curvedAnimation =
        CurvedAnimation(parent: animation, curve: MotionCurves.easeOutCubic);

    // Calculate fade value (0.0 to 1.0)
    final double fadeValue = isFade ? curvedAnimation.value : 1.0;

    // Calculate slide offset
    Offset slideOffset = Offset.zero;
    if (isSlide) {
      final double slideAmount = 12.0; // 8-12px slide, using 12px as per requirements
      switch (slideDirection) {
        case SlideDirection.topToBottom:
          slideOffset = Offset(0, -slideAmount * (1.0 - curvedAnimation.value));
          break;
        case SlideDirection.bottomToTop:
          slideOffset = Offset(0, slideAmount * (1.0 - curvedAnimation.value));
          break;
        case SlideDirection.leftToRight:
          slideOffset = Offset(-slideAmount * (1.0 - curvedAnimation.value), 0);
          break;
        case SlideDirection.rightToLeft:
          slideOffset = Offset(slideAmount * (1.0 - curvedAnimation.value), 0);
          break;
      }
    }

    return FadeTransition(
      opacity: AlwaysStoppedAnimation<double>(fadeValue),
      child: SlideTransition(
        position: AlwaysStoppedAnimation<Offset>(slideOffset),
        child: child,
      ),
    );
  }
}

/// A reusable container that applies a fade slide transition when shown or hidden.
class AnimatedSection extends StatelessWidget {
  const AnimatedSection({
    super.key,
    required this.visible,
    this.duration = MotionDurations.component,
    this.slideDirection = SlideDirection.topToBottom,
    required this.child,
  });

  /// Whether the section is visible.
  final bool visible;

  /// The child widget to animate.
  final Widget child;

  /// The duration of the animation.
  final Duration duration;

  /// The direction of the slide when appearing.
  final SlideDirection slideDirection;

  @override
  Widget build(BuildContext context) {
    final bool areAnimationsEnabled = !MediaQuery.of(context).disableAnimations;
    if (!visible) {
      return const SizedBox.shrink();
    }
    if (!areAnimationsEnabled) {
      return child;
    }
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: MotionCurves.easeOutCubic,
      switchOutCurve: MotionCurves.easeInOut,
      child: FadeSlideTransition(
        key: ValueKey<bool>(visible),
        animation: AlwaysStoppedAnimation<double>(1.0),
        slideDirection: slideDirection,
        child: child,
      ),
    );
  }
}

/// A reusable switcher for animating between different states.
class AnimatedStateSwitcher extends StatelessWidget {
  const AnimatedStateSwitcher({
    super.key,
    required this.currentState,
    required this.stateBuilder,
    this.duration = MotionDurations.smallState,
  });

  /// The current state value.
  final Object currentState;

  /// Builder that returns the widget for a given state.
  final Widget Function(Object state) stateBuilder;

  /// The duration of the animation.
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: MotionCurves.easeOutCubic,
      switchOutCurve: MotionCurves.easeInOut,
      child: stateBuilder(currentState),
    );
  }
}

/// A widget that delays showing its child by a specified duration, then applies an animated section.
class DelayedAnimatedSection extends StatefulWidget {
  const DelayedAnimatedSection({
    super.key,
    required this.visible,
    required this.child,
    this.duration = MotionDurations.component,
    this.slideDirection = SlideDirection.topToBottom,
    this.delay = Duration.zero,
  });

  /// Whether the section should be visible (after delay).
  final bool visible;

  /// The child widget to animate.
  final Widget child;

  /// The duration of the animation.
  final Duration duration;

  /// The direction of the slide when appearing.
  final SlideDirection slideDirection;

  /// The delay before starting the animation.
  final Duration delay;

  @override
  State<DelayedAnimatedSection> createState() => _DelayedAnimatedSectionState();
}

class _DelayedAnimatedSectionState extends State<DelayedAnimatedSection> {
  bool _showChild = false;

  @override
  void initState() {
    super.initState();
    if (widget.visible) {
      // Start with delay if initially visible
      Future.delayed(widget.delay, () {
        if (mounted) {
          setState(() {
            _showChild = true;
          });
        }
      });
    } else {
      _showChild = false;
    }
  }

  @override
  void didUpdateWidget(covariant DelayedAnimatedSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) {
      // Widget became visible, start the delay
      Future.delayed(widget.delay, () {
        if (mounted) {
          setState(() {
            _showChild = true;
          });
        }
      });
    } else if (!widget.visible) {
      // Widget became invisible, hide immediately
      _showChild = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool areAnimationsEnabled = !MediaQuery.of(context).disableAnimations;

    if (!widget.visible) {
      return const SizedBox.shrink();
    }

    if (!areAnimationsEnabled) {
      return widget.child;
    }

    return AnimatedSection(
      visible: _showChild,
      duration: widget.duration,
      slideDirection: widget.slideDirection,
      child: widget.child,
    );
  }
}