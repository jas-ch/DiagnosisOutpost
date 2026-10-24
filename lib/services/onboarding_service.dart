import 'package:shared_preferences/shared_preferences.dart';

/// Tracks whether the user has completed the onboarding flow.
class OnboardingService {
  static const _key = 'onboarding_complete';

  static Future<bool> isComplete() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  static Future<void> markComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
  }

  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
