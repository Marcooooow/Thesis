import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TutorialManager {
  static const String _tutorialCompletedKey = 'tutorial_completed';
  static const String _tutorialSkippedKey = 'tutorial_skipped';
  static const String _currentStepKey = 'tutorial_current_step';

  /// Returns the user-specific key prefix, or null if no user is signed in.
  static String? _getUserKeyPrefix() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      return 'tutorial_${user.uid}';
    }
    return null;
  }

  /// Returns the full key for the given [suffix], using user-specific prefix if available.
  static String _getKey(String suffix) {
    final prefix = _getUserKeyPrefix();
    if (prefix != null) {
      return '${prefix}_$suffix';
    }
    // Fallback to global keys (backward compatibility)
    return suffix;
  }

  static Future<bool> shouldShowTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    // First check user-specific state
    final completed = prefs.getBool(_getKey(_tutorialCompletedKey)) ?? false;
    final skipped = prefs.getBool(_getKey(_tutorialSkippedKey)) ?? false;
    if (completed || skipped) {
      // User-specific state exists; use it.
      return !completed && !skipped;
    }

    // No user-specific state; fall back to global keys for backward compatibility.
    final globalCompleted = prefs.getBool(_tutorialCompletedKey) ?? false;
    final globalSkipped = prefs.getBool(_tutorialSkippedKey) ?? false;
    if (globalCompleted || globalSkipped) {
      // Migrate the global state to user-specific for this user.
      await _migrateGlobalStateToUserIfNeeded(globalCompleted, globalSkipped);
      // After migration, the user-specific state will be set, so we can recurse.
      return shouldShowTutorial();
    }

    // Neither user-specific nor global state exists -> show tutorial.
    return true;
  }

  static Future<void> _migrateGlobalStateToUserIfNeeded(bool globalCompleted, bool globalSkipped) async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = _getUserKeyPrefix();
    if (prefix == null) {
      // Cannot migrate without user ID; abort.
      return;
    }
    // Only migrate if the user-specific state is not already set.
    final userCompleted = prefs.getBool('${prefix}_$_tutorialCompletedKey') ?? false;
    final userSkipped = prefs.getBool('${prefix}_$_tutorialSkippedKey') ?? false;
    if (!userCompleted && !userSkipped) {
      if (globalCompleted) {
        await prefs.setBool('${prefix}_$_tutorialCompletedKey', true);
      }
      if (globalSkipped) {
        await prefs.setBool('${prefix}_$_tutorialSkippedKey', true);
      }
      // Clear the global state to avoid future confusion.
      await prefs.remove(_tutorialCompletedKey);
      await prefs.remove(_tutorialSkippedKey);
      await prefs.remove(_currentStepKey);
    }
  }

  static Future<void> markTutorialAsCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_getKey(_tutorialCompletedKey), true);
    await prefs.remove(_getKey(_currentStepKey));
  }

  static Future<void> markTutorialAsSkipped() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_getKey(_tutorialSkippedKey), true);
    await prefs.remove(_getKey(_currentStepKey));
  }

  static Future<void> resetTutorialState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_getKey(_tutorialCompletedKey));
    await prefs.remove(_getKey(_tutorialSkippedKey));
    await prefs.remove(_getKey(_currentStepKey));
  }

  static Future<int> getCurrentStep() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_getKey(_currentStepKey)) ?? -1;
  }

  static Future<void> setCurrentStep(int step) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_getKey(_currentStepKey), step);
  }

  static Future<void> advanceToNextStep() async {
    final currentStep = await getCurrentStep();
    await setCurrentStep(currentStep + 1);
  }

  static Future<void> goToPreviousStep() async {
    final currentStep = await getCurrentStep();
    if (currentStep > 0) {
      await setCurrentStep(currentStep - 1);
    }
  }

  static Future<void> goToStep(int step) async {
    await setCurrentStep(step);
  }
}

enum TutorialStep {
  workSession('Work Session'),
  tasks('Tasks'),
  startTask('Start a Task'),
  breaks('Breaks'),
  focusRate('Focus Rate'),
  finish('Finish');

  final String title;

  const TutorialStep(this.title);

  static TutorialStep fromIndex(int index) {
    return TutorialStep.values.firstWhere(
      (step) => step.index == index,
      orElse: () => TutorialStep.workSession,
    );
  }

  int getStepCount() => TutorialStep.finish.index + 1;
}