import 'package:shared_preferences/shared_preferences.dart';

class TutorialSettings {
  static const String _replayTutorialKey = 'tutorial_replay_enabled';

  static Future<bool> getReplayTutorialEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_replayTutorialKey) ?? false;
  }

  static Future<void> setReplayTutorialEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_replayTutorialKey, value);
  }

  static Future<void> resetTutorialState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('tutorial_completed');
    await prefs.remove('tutorial_skipped');
    await prefs.remove('tutorial_current_step');
  }
}