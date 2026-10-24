import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_biometrics.dart';

class BiometricsService {
  static const _key = 'user_biometrics';

  static Future<UserBiometrics> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) {
      // Return a sensible default so first-time users see sample values.
      return const UserBiometrics(
        bodyTemperature: '98.6°F',
        bloodPressure: '120/80',
        heartRate: '72',
        oxygenLevel: '98%',
        weight: '70 kg',
        height: '175 cm',
      );
    }
    return UserBiometrics.fromMap(jsonDecode(raw));
  }

  static Future<void> save(UserBiometrics biometrics) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(biometrics.toMap()));
  }
}
