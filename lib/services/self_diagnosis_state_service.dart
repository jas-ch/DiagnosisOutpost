import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persisted self-diagnosis session state so symptoms and custom notes
/// survive the back button and app restarts. Vitals are persisted separately
/// by [BiometricsService] so the latest reading is always shared across screens.
class SelfDiagnosisStateService {
  static const _key = 'self_diagnosis_state_v2';

  static Future<void> save({
    required List<String> symptoms,
    required String customNote,
    DateTime? symptomsUpdatedAt,
    DateTime? vitalsUpdatedAt,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = {
      'symptoms': symptoms,
      'customNote': customNote,
      if (symptomsUpdatedAt != null)
        'symptomsUpdatedAt': symptomsUpdatedAt.toIso8601String(),
      if (vitalsUpdatedAt != null)
        'vitalsUpdatedAt': vitalsUpdatedAt.toIso8601String(),
    };
    await prefs.setString(_key, jsonEncode(payload));
  }

  static Future<SelfDiagnosisState> load() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_key);
    if (jsonString == null || jsonString.isEmpty) {
      return const SelfDiagnosisState();
    }
    try {
      final map = jsonDecode(jsonString) as Map<String, dynamic>;
      return SelfDiagnosisState(
        symptoms: _toStringList(map['symptoms']),
        customNote: map['customNote']?.toString() ?? '',
        symptomsUpdatedAt: _parseDateTime(map['symptomsUpdatedAt']),
        vitalsUpdatedAt: _parseDateTime(map['vitalsUpdatedAt']),
      );
    } catch (_) {
      return const SelfDiagnosisState();
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  static List<String> _toStringList(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return [];
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}

class SelfDiagnosisState {
  final List<String> symptoms;
  final String customNote;
  final DateTime? symptomsUpdatedAt;
  final DateTime? vitalsUpdatedAt;

  const SelfDiagnosisState({
    this.symptoms = const [],
    this.customNote = '',
    this.symptomsUpdatedAt,
    this.vitalsUpdatedAt,
  });
}
