import '../services/classifier_service.dart';
import '../services/content_service.dart';
import 'classifier_result.dart';
import 'user_biometrics.dart';

/// A structured summary of a self-diagnosis check for display in the live-risk
/// popup and the history detail screen.
class DiagnosisSummary {
  final String conditionId;
  final String conditionName;
  final String riskLevel;
  final int probability;
  final List<ClassifierFinding> findings;
  final List<String> interpretedFindings;
  final List<VitalReading> vitals;
  final List<String> symptoms;
  final String? customNote;
  final List<String> recommendations;
  final TongueWellness? tongueWellness;

  const DiagnosisSummary({
    required this.conditionId,
    required this.conditionName,
    required this.riskLevel,
    required this.probability,
    required this.findings,
    this.interpretedFindings = const [],
    required this.vitals,
    required this.symptoms,
    this.customNote,
    required this.recommendations,
    this.tongueWellness,
  });

  bool get hasFindings => findings.isNotEmpty;
  bool get hasInterpretedFindings => interpretedFindings.isNotEmpty;
  bool get hasVitals => vitals.any((v) => v.value != '--' && v.value != '--/--');
  bool get hasSymptoms => symptoms.isNotEmpty;
  bool get hasTongueWellness => tongueWellness != null;
}

/// A single classifier output rendered in the summary.
class ClassifierFinding {
  final String group;
  final String label;
  final String topClass;
  final double confidence;

  const ClassifierFinding({
    required this.group,
    required this.label,
    required this.topClass,
    required this.confidence,
  });
}

/// A single vital sign reading.
class VitalReading {
  final String label;
  final String value;
  final String? unit;

  const VitalReading({required this.label, required this.value, this.unit});
}

/// Builds a [DiagnosisSummary] from the raw inputs stored at check-time.
class DiagnosisSummaryBuilder {
  DiagnosisSummaryBuilder._();

  static const _groupLabels = {
    'rash': 'Rash photo',
    'wounds': 'Wound photo',
    'selfie': 'Face photo',
    'tongue': 'Tongue photo',
    'cough': 'Cough audio',
  };

  static Future<DiagnosisSummary> build({
    required String conditionId,
    required String conditionName,
    required String riskLevel,
    required int probability,
    required UserBiometrics biometrics,
    required List<String> symptoms,
    String? customNote,
    required Map<String, ClassifierResult> classifierResults,
  }) async {
    final findings = <ClassifierFinding>[];
    for (final entry in classifierResults.entries) {
      final group = entry.key.toLowerCase();
      final result = entry.value;
      if (result.topClass.isEmpty) continue;
      findings.add(ClassifierFinding(
        group: group,
        label: _groupLabels[group] ?? group,
        topClass: result.topClass.replaceAll('_', ' '),
        confidence: result.topConfidence,
      ));
    }

    final vitals = <VitalReading>[
      VitalReading(label: 'Temperature', value: biometrics.bodyTemperature, unit: '°F'),
      VitalReading(label: 'Heart rate', value: biometrics.heartRate, unit: 'bpm'),
      VitalReading(label: 'Blood pressure', value: biometrics.bloodPressure),
      VitalReading(label: 'Oxygen level', value: biometrics.oxygenLevel, unit: '%'),
      VitalReading(label: 'Weight', value: biometrics.weight, unit: 'lb'),
      VitalReading(label: 'Height', value: biometrics.height, unit: 'in'),
    ];

    final recommendations = await _loadRecommendations(conditionId);

    TongueWellness? tongueWellness;
    final tongueResult = classifierResults['tongue'];
    if (tongueResult != null && tongueResult.topClass.isNotEmpty) {
      tongueWellness = await ClassifierService.evaluateTongueWellness(
        ClassifierService.extractTongueAttributes(tongueResult),
      );
    }

    return DiagnosisSummary(
      conditionId: conditionId,
      conditionName: conditionName,
      riskLevel: riskLevel,
      probability: probability,
      findings: findings,
      interpretedFindings: _interpretVitals(biometrics),
      vitals: vitals.where((v) => v.value != '--' && v.value != '--/--').toList(),
      symptoms: symptoms,
      customNote: customNote,
      recommendations: recommendations,
      tongueWellness: tongueWellness,
    );
  }

  static List<String> _interpretVitals(UserBiometrics biometrics) {
    final findings = <String>[];

    final temp = _parseNumber(biometrics.bodyTemperature);
    if (temp != null) {
      if (temp >= 100.4) {
        findings.add('Fever is high (${temp.toStringAsFixed(1)}°F).');
      } else if (temp >= 99.0) {
        findings.add('Low-grade fever (${temp.toStringAsFixed(1)}°F).');
      } else if (temp <= 95.0) {
        findings.add('Body temperature is low (${temp.toStringAsFixed(1)}°F).');
      } else {
        findings.add('Body temperature is normal (${temp.toStringAsFixed(1)}°F).');
      }
    }

    final hr = _parseNumber(biometrics.heartRate);
    if (hr != null) {
      if (hr > 100) {
        findings.add('Heart rate is fast ($hr bpm).');
      } else if (hr < 60) {
        findings.add('Heart rate is slow ($hr bpm).');
      } else {
        findings.add('Heart rate is normal ($hr bpm).');
      }
    }

    final o2 = _parseNumber(biometrics.oxygenLevel);
    if (o2 != null) {
      if (o2 < 90) {
        findings.add('Oxygen level is very low ($o2%); possible shortage.');
      } else if (o2 < 95) {
        findings.add('Oxygen level is low ($o2%).');
      } else {
        findings.add('Oxygen level is normal ($o2%).');
      }
    }

    final bp = _parseBloodPressure(biometrics.bloodPressure);
    if (bp != null) {
      final (systolic, diastolic) = bp;
      if (systolic >= 140 || diastolic >= 90) {
        findings.add('Blood pressure is high ($systolic/$diastolic mmHg).');
      } else if (systolic < 90 || diastolic < 60) {
        findings.add('Blood pressure is low ($systolic/$diastolic mmHg).');
      } else {
        findings.add('Blood pressure is normal ($systolic/$diastolic mmHg).');
      }
    }

    return findings;
  }

  static double? _parseNumber(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^\d.]'), '');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  static (int, int)? _parseBloodPressure(String value) {
    final match = RegExp(r'(\d+)\s*/\s*(\d+)').firstMatch(value);
    if (match == null) return null;
    final sys = int.tryParse(match.group(1)!);
    final dia = int.tryParse(match.group(2)!);
    if (sys == null || dia == null) return null;
    return (sys, dia);
  }

  static Future<List<String>> _loadRecommendations(String conditionId) async {
    if (conditionId.isEmpty) return [];
    try {
      final intel = await ContentService.findById(conditionId);
      return intel?.actions ?? [];
    } catch (_) {
      return [];
    }
  }
}
