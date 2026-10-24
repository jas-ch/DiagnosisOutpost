import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/diagnosis_history_entry.dart';

class DiagnosisHistoryService {
  static const _key = 'diagnosis_history';
  static const _clearedFlagKey = 'history_was_cleared_v1';

  static Future<List<DiagnosisHistoryEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final wasCleared = prefs.getBool(_clearedFlagKey) ?? false;
    if (wasCleared) return [];
    final raw = prefs.getString(_key);
    if (raw == null) return _sampleHistory();
    final List<dynamic> decoded = jsonDecode(raw);
    return decoded.map((e) => DiagnosisHistoryEntry.fromMap(e)).toList();
  }

  static Future<void> save(List<DiagnosisHistoryEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(entries.map((e) => e.toMap()).toList());
    await prefs.setString(_key, encoded);
    await prefs.remove(_clearedFlagKey);
  }

  static Future<void> addEntry(DiagnosisHistoryEntry entry) async {
    final entries = await load();
    entries.insert(0, entry);
    await save(entries);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    await prefs.setBool(_clearedFlagKey, true);
  }

  /// Provide a few sample entries so first-time users understand the screen.
  static List<DiagnosisHistoryEntry> _sampleHistory() {
    return [
      DiagnosisHistoryEntry(
        id: 'sample-1',
        timestamp: DateTime.now().subtract(const Duration(days: 2)),
        riskLevel: 'low',
        symptomSummary: 'mild cough, no fever',
        matchedConditionId: null,
        matchedConditionName: 'No strong outbreak match',
        notes: 'Sample entry',
      ),
      DiagnosisHistoryEntry(
        id: 'sample-2',
        timestamp: DateTime.now().subtract(const Duration(days: 5)),
        riskLevel: 'moderate',
        symptomSummary: 'fever, sore throat, body aches',
        matchedConditionId: 'influenza_a',
        matchedConditionName: 'Influenza A',
        notes: 'Sample entry',
      ),
    ];
  }
}
