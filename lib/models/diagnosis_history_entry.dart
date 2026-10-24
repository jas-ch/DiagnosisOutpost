import 'classifier_result.dart';
import 'user_biometrics.dart';

/// A single entry in the user's self-diagnosis history.
class DiagnosisHistoryEntry {
  final String id;
  final DateTime timestamp;
  final String riskLevel;
  final String symptomSummary;
  final String? matchedConditionId;
  final String? matchedConditionName;
  final String? notes;
  final UserBiometrics? biometrics;
  final Map<String, ClassifierResult> classifierResults;

  const DiagnosisHistoryEntry({
    required this.id,
    required this.timestamp,
    required this.riskLevel,
    required this.symptomSummary,
    this.matchedConditionId,
    this.matchedConditionName,
    this.notes,
    this.biometrics,
    this.classifierResults = const {},
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'riskLevel': riskLevel,
      'symptomSummary': symptomSummary,
      'matchedConditionId': matchedConditionId,
      'matchedConditionName': matchedConditionName,
      'notes': notes,
      'biometrics': biometrics?.toMap(),
      'classifierResults': classifierResults.map(
        (k, v) => MapEntry(k, v.toMap()),
      ),
    };
  }

  factory DiagnosisHistoryEntry.fromMap(Map<dynamic, dynamic> map) {
    final rawResults = map['classifierResults'] as Map<dynamic, dynamic>?;
    final rawBiometrics = map['biometrics'] as Map<dynamic, dynamic>?;
    return DiagnosisHistoryEntry(
      id: map['id']?.toString() ?? '',
      timestamp: DateTime.tryParse(map['timestamp']?.toString() ?? '') ?? DateTime.now(),
      riskLevel: map['riskLevel']?.toString() ?? 'unknown',
      symptomSummary: map['symptomSummary']?.toString() ?? '',
      matchedConditionId: map['matchedConditionId']?.toString(),
      matchedConditionName: map['matchedConditionName']?.toString(),
      notes: map['notes']?.toString(),
      biometrics: rawBiometrics != null ? UserBiometrics.fromMap(rawBiometrics) : null,
      classifierResults: rawResults?.map(
            (k, v) => MapEntry(
              k.toString(),
              ClassifierResult.fromMap(v as Map<String, dynamic>),
            ),
          ) ??
          {},
    );
  }
}
