import 'dart:async';
import 'package:flutter/foundation.dart';

/// A global provider that manages the shift/break timer state
/// This provider is designed to be created ONCE and survive theme changes
/// and navigation. It now only handles the 1Hz timer tick.
/// Tab title updates are handled by TabTitleTicker which consumes
/// both WorkSessionProvider and ShiftTimerProvider.
class ShiftTimerProvider extends ChangeNotifier {
  Timer? _timer;

  // Instance tracking for debugging
  final String _instanceId = DateTime.now().millisecondsSinceEpoch.toString();

  ShiftTimerProvider() {
    debugPrint('ShiftTimerProvider[$_instanceId] CREATED');
    _startTimer();
  }

  /// Start the timer ticker - called once at app initialization
  void _startTimer() {
    // Update every second - listeners get notified on tick
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      notifyListeners();
    });
    debugPrint('ShiftTimerProvider[$_instanceId] TIMER CREATED');
  }

  /// Stop the timer ticker
  void _stopTimer() {
    debugPrint('ShiftTimerProvider[$_instanceId] TIMER CANCELLED');
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    debugPrint('ShiftTimerProvider[$_instanceId] DISPOSED');
    _stopTimer();
    super.dispose();
  }
}