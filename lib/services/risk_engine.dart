import 'dart:math' as math;

import '../models/classifier_result.dart';
import '../models/user_biometrics.dart';

/// A weighted multi-modal risk engine for the self-diagnosis flow.
///
/// It scores a fixed set of outbreak conditions from symptoms (checked + free-
/// text notes), all recorded vital signs, and every captured classifier result
/// (rash, wound, face, tongue, cough). The total weighted score is mapped to a
/// probability; the final risk level follows the thresholds:
///   <= 50% : "No obvious relation to active outbreak disease"
///   > 50% and <= 75% : low risk
///   > 75% and <= 90% : medium risk
///   > 90%            : high risk
class RiskEngine {
  RiskEngine._();

  static const predefinedSymptoms = [
    'Fever',
    'Cough',
    'Sore throat',
    'Runny nose',
    'Body aches',
    'Shortness of breath',
    'Loss of taste/smell',
    'Nausea/vomiting',
    'Diarrhea',
    'Rash',
    'Headache',
    'Fatigue',
    'Swollen lymph nodes',
    'Pain behind the eyes',
    'Joint pain',
    'Whooping cough',
    'Vomiting after coughing',
    'Wheezing',
    'Decreased appetite',
    'Strawberry tongue',
    'Mouth sores',
    'Rash on hands and feet',
    'Itchy blisters',
    'Muscle aches',
    'Loss of appetite',
  ];

  static const _conditions = [
    _Condition(
      id: 'influenza_a',
      name: 'Influenza A',
      weights: {
        'Fever': 25,
        'Cough': 25,
        'Sore throat': 10,
        'Runny nose': 5,
        'Body aches': 20,
        'Shortness of breath': 5,
        'Headache': 10,
        'Fatigue': 10,
      },
    ),
    _Condition(
      id: 'covid_19',
      name: 'COVID-19',
      weights: {
        'Fever': 15,
        'Cough': 20,
        'Sore throat': 10,
        'Runny nose': 5,
        'Body aches': 10,
        'Shortness of breath': 15,
        'Loss of taste/smell': 25,
        'Headache': 10,
        'Fatigue': 15,
      },
    ),
    _Condition(
      id: 'norovirus',
      name: 'Norovirus',
      weights: {
        'Fever': 10,
        'Body aches': 5,
        'Nausea/vomiting': 30,
        'Diarrhea': 30,
        'Headache': 5,
        'Fatigue': 10,
      },
    ),
    _Condition(
      id: 'measles',
      name: 'Measles',
      weights: {
        'Fever': 15,
        'Cough': 10,
        'Sore throat': 10,
        'Runny nose': 10,
        'Rash': 35,
        'Fatigue': 10,
      },
    ),
    _Condition(
      id: 'common_cold',
      name: 'Common Cold',
      weights: {
        'Cough': 15,
        'Sore throat': 15,
        'Runny nose': 25,
        'Headache': 5,
        'Fatigue': 5,
      },
    ),
    _Condition(
      id: 'mpox',
      name: 'Mpox',
      weights: {
        'Fever': 20,
        'Rash': 35,
        'Swollen lymph nodes': 25,
        'Headache': 10,
        'Muscle aches': 15,
        'Fatigue': 10,
      },
    ),
    _Condition(
      id: 'dengue',
      name: 'Dengue fever',
      weights: {
        'Fever': 25,
        'Headache': 25,
        'Pain behind the eyes': 25,
        'Joint pain': 20,
        'Rash': 10,
        'Fatigue': 10,
      },
    ),
    _Condition(
      id: 'pertussis',
      name: 'Pertussis',
      weights: {
        'Runny nose': 15,
        'Fever': 10,
        'Cough': 35,
        'Whooping cough': 35,
        'Vomiting after coughing': 20,
        'Fatigue': 10,
      },
    ),
    _Condition(
      id: 'rsv',
      name: 'Respiratory Syncytial Virus',
      weights: {
        'Runny nose': 20,
        'Cough': 25,
        'Wheezing': 30,
        'Fever': 15,
        'Decreased appetite': 10,
        'Fatigue': 10,
      },
    ),
    _Condition(
      id: 'scarlet_fever',
      name: 'Scarlet fever',
      weights: {
        'Fever': 20,
        'Sore throat': 25,
        'Rash': 30,
        'Strawberry tongue': 25,
        'Headache': 10,
        'Nausea/vomiting': 10,
      },
    ),
    _Condition(
      id: 'hfmd',
      name: 'Hand-foot-mouth disease',
      weights: {
        'Fever': 15,
        'Sore throat': 15,
        'Mouth sores': 30,
        'Rash on hands and feet': 30,
        'Loss of appetite': 10,
        'Fatigue': 10,
      },
    ),
    _Condition(
      id: 'chickenpox',
      name: 'Chickenpox',
      weights: {
        'Fever': 15,
        'Fatigue': 15,
        'Headache': 10,
        'Loss of appetite': 10,
        'Rash': 30,
        'Itchy blisters': 25,
      },
    ),
  ];

  /// Lightweight keyword map for free-text symptom notes. Each matched keyword
  /// adds a small evidence score to the associated condition.
  static const _noteKeywords = {
    'influenza_a': ['flu', 'influenza', 'fever', 'cough', 'body ache', 'bodyache', 'chills', 'achy', 'aches'],
    'covid_19': ['covid', 'coronavirus', 'loss of taste', 'loss of smell', 'taste', 'smell', 'shortness of breath', 'sob'],
    'norovirus': ['vomit', 'vomiting', 'diarrhea', 'nausea', 'stomach bug', 'stomach flu', 'gastro'],
    'measles': ['measles', 'koplik', 'conjunctivitis', 'red eyes'],
    'common_cold': ['cold', 'runny nose', 'congestion', 'sneezing', 'stuffy nose'],
    'mpox': ['mpox', 'monkeypox', 'pox', 'lesion', 'vesicular', 'swollen lymph', 'lymph node'],
    'dengue': ['dengue', 'breakbone', 'joint pain', 'pain behind eyes', 'mosquito', 'bone pain'],
    'pertussis': ['pertussis', 'whooping cough', 'whooping', 'coughing fits', 'paroxysmal cough'],
    'rsv': ['rsv', 'wheezing', 'breathing difficulty', 'infant', 'bronchiolitis'],
    'scarlet_fever': ['scarlet fever', 'strawberry tongue', 'sore throat', 'sandpaper rash', 'strep'],
    'hfmd': ['hand foot mouth', 'hfmd', 'mouth sores', 'foot sores', 'hand sores'],
    'chickenpox': ['chickenpox', 'varicella', 'itchy blisters', 'blisters', 'itchy spots'],
  };

  /// Returns true when the user has provided enough inputs for the risk score
  /// to be meaningful.
  static bool hasSufficientInputs({
    required List<String> symptoms,
    required UserBiometrics biometrics,
    String? photoCategory,
    bool coughRecorded = false,
    Map<String, ClassifierResult> classifierResults = const {},
  }) {
    if (symptoms.any((s) => s.trim().isNotEmpty)) return true;
    if (photoCategory != null && photoCategory.trim().isNotEmpty) return true;
    if (coughRecorded) return true;
    if (classifierResults.isNotEmpty) return true;
    if (biometrics.bodyTemperature != '--' &&
        _firstNumber(biometrics.bodyTemperature) != null) {
      return true;
    }
    if (biometrics.oxygenLevel != '98%' &&
        _firstNumber(biometrics.oxygenLevel) != null) {
      return true;
    }
    if (biometrics.heartRate != '--' &&
        _firstNumber(biometrics.heartRate) != null) {
      return true;
    }
    if (biometrics.bloodPressure != '--/--' &&
        _firstNumber(biometrics.bloodPressure) != null) {
      return true;
    }
    return false;
  }

  static RiskResult compute({
    required List<String> symptoms,
    required UserBiometrics biometrics,
    String? photoCategory,
    bool coughRecorded = false,
    Map<String, ClassifierResult> classifierResults = const {},
  }) {
    if (!hasSufficientInputs(
      symptoms: symptoms,
      biometrics: biometrics,
      photoCategory: photoCategory,
      coughRecorded: coughRecorded,
      classifierResults: classifierResults,
    )) {
      return const RiskResult(
        conditionId: '',
        conditionName: 'No obvious relation to active outbreak disease',
        probability: 0,
        riskLevel: 'low',
        allScores: {},
      );
    }

    final selected = _selectedSymptoms(symptoms);
    final customNote = _extractCustomNote(symptoms);
    final hasFever = _hasFever(biometrics.bodyTemperature);
    final lowOxygen = _isLowOxygen(biometrics.oxygenLevel);
    final heartStatus = _heartRateStatus(biometrics.heartRate);
    final bpStatus = _bloodPressureStatus(biometrics.bloodPressure);

    final scores = <String, double>{};
    for (final condition in _conditions) {
      var score = 0.0;

      // Checked symptoms.
      for (final symptom in selected) {
        score += condition.weights[symptom] ?? 0;
      }

      // Free-text note keyword matching.
      score += _noteScore(condition.id, customNote);

      // Body temperature.
      if (hasFever) {
        score += switch (condition.id) {
          'influenza_a' => 15.0,
          'covid_19' => 15.0,
          'norovirus' => 10.0,
          'measles' => 15.0,
          'mpox' => 15.0,
          'dengue' => 20.0,
          'pertussis' => 10.0,
          'rsv' => 15.0,
          'scarlet_fever' => 15.0,
          'hfmd' => 10.0,
          'chickenpox' => 15.0,
          _ => 5.0,
        };
      }

      // Oxygen saturation.
      if (lowOxygen) {
        score += switch (condition.id) {
          'covid_19' => 15.0,
          'influenza_a' => 10.0,
          'rsv' => 10.0,
          'pertussis' => 5.0,
          _ => 0.0,
        };
      }

      // Heart rate.
      if (heartStatus == _HeartRate.tachycardia) {
        score += switch (condition.id) {
          'influenza_a' => 10.0,
          'covid_19' => 10.0,
          'rsv' => 10.0,
          'pertussis' => 10.0,
          'dengue' => 5.0,
          _ => 0.0,
        };
      } else if (heartStatus == _HeartRate.bradycardia) {
        score += 5.0;
      }

      // Blood pressure.
      if (bpStatus == _BpStatus.hypertension) {
        score += 5.0;
      } else if (bpStatus == _BpStatus.hypotension) {
        score += switch (condition.id) {
          'dengue' => 15.0,
          'norovirus' => 10.0,
          'covid_19' => 10.0,
          _ => 5.0,
        };
      }

      // Cough recorded (audio modality present).
      if (coughRecorded) {
        score += switch (condition.id) {
          'influenza_a' => 15.0,
          'covid_19' => 15.0,
          'measles' => 10.0,
          'common_cold' => 5.0,
          'pertussis' => 25.0,
          'rsv' => 15.0,
          _ => 0.0,
        };
      }

      // Most recent photo category selected.
      score += _photoCategoryScore(condition.id, photoCategory);

      // All captured classifier results (multi-modal fusion).
      score += _classifierScore(condition.id, classifierResults);

      scores[condition.id] = score;
    }

    final top = _conditions.reduce(
      (a, b) => (scores[a.id] ?? 0) >= (scores[b.id] ?? 0) ? a : b,
    );
    final topScore = scores[top.id] ?? 0;
    final probability = _toProbability(topScore);

    if (probability <= 50) {
      return RiskResult(
        conditionId: '',
        conditionName: 'No obvious relation to active outbreak disease',
        probability: 0,
        riskLevel: 'low',
        allScores: scores,
      );
    }

    final riskLevel = probability <= 75
        ? 'low'
        : probability <= 90
            ? 'moderate'
            : 'high';

    return RiskResult(
      conditionId: top.id,
      conditionName: top.name,
      probability: probability,
      riskLevel: riskLevel,
      allScores: scores,
    );
  }

  static Set<String> _selectedSymptoms(List<String> symptoms) {
    return symptoms
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && !s.startsWith('Custom:'))
        .toSet();
  }

  static String _extractCustomNote(List<String> symptoms) {
    for (final s in symptoms) {
      final trimmed = s.trim();
      if (trimmed.startsWith('Custom:')) {
        return trimmed.substring('Custom:'.length).trim();
      }
    }
    return '';
  }

  static double _noteScore(String conditionId, String note) {
    if (note.isEmpty) return 0.0;
    final lowered = note.toLowerCase();
    final keywords = _noteKeywords[conditionId] ?? [];
    var hits = 0;
    for (final keyword in keywords) {
      if (lowered.contains(keyword.toLowerCase())) hits++;
    }
    // 5 points per matched keyword, capped at 25 to avoid overweighting notes.
    return (hits * 5.0).clamp(0.0, 25.0);
  }

  static double _photoCategoryScore(String conditionId, String? photoCategory) {
    final cat = photoCategory?.toLowerCase() ?? '';
    if (cat == 'rash') {
      return switch (conditionId) {
        'measles' => 25.0,
        'mpox' => 30.0,
        'dengue' => 10.0,
        'scarlet_fever' => 25.0,
        'hfmd' => 20.0,
        'chickenpox' => 30.0,
        _ => 0.0,
      };
    }
    if (cat == 'wounds') {
      return switch (conditionId) {
        'mpox' => 15.0,
        'scarlet_fever' => 10.0,
        _ => 0.0,
      };
    }
    if (cat == 'selfie') {
      return switch (conditionId) {
        'measles' => 10.0,
        'hfmd' => 10.0,
        'mpox' => 10.0,
        'rsv' => 5.0,
        _ => 0.0,
      };
    }
    if (cat == 'tongue') {
      return switch (conditionId) {
        'scarlet_fever' => 15.0,
        'covid_19' => 5.0,
        _ => 0.0,
      };
    }
    return 0.0;
  }

  static double _classifierScore(String conditionId, Map<String, ClassifierResult> results) {
    var score = 0.0;

    // Rash classifier mapping.
    final rash = results['rash'];
    if (rash != null) {
      final probs = rash.probabilities;
      score += (probs['measles_like'] ?? 0) * (conditionId == 'measles' ? 55.0 : 0);
      score += (probs['chickenpox_like'] ?? 0) * (conditionId == 'chickenpox' ? 55.0 : 0);
      score += (probs['hfmd_like'] ?? 0) * (conditionId == 'hfmd' ? 55.0 : 0);
      score += (probs['monkeypox_like'] ?? 0) * (conditionId == 'mpox' ? 55.0 : 0);
      score += (probs['scarlet_fever_like'] ?? 0) * (conditionId == 'scarlet_fever' ? 55.0 : 0);
    }

    // Wound classifier mapping.
    final wound = results['wounds'];
    if (wound != null) {
      final infected = wound.probabilities['infected'] ?? 0;
      if (conditionId == 'mpox' || conditionId == 'scarlet_fever') {
        score += infected * 25.0;
      }
    }

    // Face / selfie classifier mapping.
    final face = results['selfie'];
    if (face != null) {
      final probs = face.probabilities;
      score += (probs['conjunctivitis_eye_discharge'] ?? 0) * (conditionId == 'measles' ? 30.0 : 0);
      score += (probs['oral_perioral_lesions'] ?? 0) * (conditionId == 'hfmd' ? 30.0 : 0);
      score += (probs['vesicular_pustular_lesions'] ?? 0) * (conditionId == 'mpox' ? 30.0 : 0);
      score += (probs['nasal_discharge'] ?? 0) * (conditionId == 'rsv' ? 20.0 : 0);
    }

    // Tongue attribute mapping.
    final tongue = results['tongue'];
    if (tongue != null) {
      final probs = tongue.probabilities;
      final strawberry = probs['shape_features.red_dots_strawberry'] ?? 0;
      final redBody = probs['body_color.red'] ?? 0;
      final yellowCoating = probs['coating_color.yellow'] ?? 0;
      if (conditionId == 'scarlet_fever') {
        score += strawberry * 50.0;
        score += (redBody * yellowCoating) * 35.0;
      }
    }

    // Cough classifier mapping.
    final cough = results['cough'];
    if (cough != null) {
      final probs = cough.probabilities;
      score += (probs['whooping'] ?? 0) * (conditionId == 'pertussis' ? 55.0 : 0);
      score += (probs['wheeze_present'] ?? 0) * (conditionId == 'rsv' ? 35.0 : 0);
      score += (probs['dry_respiratory'] ?? 0) *
          ((conditionId == 'influenza_a' || conditionId == 'covid_19') ? 25.0 : 0);
    }

    return score;
  }

  static int _toProbability(double score) {
    final p = 100.0 / (1.0 + math.exp(-0.07 * (score - 45)));
    return p.round().clamp(0, 100);
  }

  static bool _hasFever(String temperature) {
    final value = _firstNumber(temperature);
    if (value == null) return false;
    if (temperature.toLowerCase().contains('f')) return value > 99.5;
    if (temperature.toLowerCase().contains('c')) return value > 37.5;
    return value > 99.5;
  }

  static bool _isLowOxygen(String oxygen) {
    final value = _firstNumber(oxygen);
    if (value == null) return false;
    return value < 92;
  }

  static _HeartRate _heartRateStatus(String heartRate) {
    final value = _firstNumber(heartRate);
    if (value == null) return _HeartRate.normal;
    if (value > 100) return _HeartRate.tachycardia;
    if (value < 60) return _HeartRate.bradycardia;
    return _HeartRate.normal;
  }

  static _BpStatus _bloodPressureStatus(String bloodPressure) {
    final match = RegExp(r'(\d+)\s*/\s*(\d+)').firstMatch(bloodPressure);
    if (match == null) return _BpStatus.normal;
    final sys = int.tryParse(match.group(1)!);
    final dia = int.tryParse(match.group(2)!);
    if (sys == null || dia == null) return _BpStatus.normal;
    if (sys >= 140 || dia >= 90) return _BpStatus.hypertension;
    if (sys < 90 || dia < 60) return _BpStatus.hypotension;
    return _BpStatus.normal;
  }

  static double? _firstNumber(String text) {
    final match = RegExp(r'\d+(\.\d+)?').firstMatch(text);
    if (match == null) return null;
    return double.tryParse(match.group(0)!);
  }
}

enum _HeartRate { normal, tachycardia, bradycardia }

enum _BpStatus { normal, hypertension, hypotension }

class RiskResult {
  final String conditionId;
  final String conditionName;
  final int probability;
  final String riskLevel;
  final Map<String, double> allScores;

  const RiskResult({
    required this.conditionId,
    required this.conditionName,
    required this.probability,
    required this.riskLevel,
    required this.allScores,
  });
}

class _Condition {
  final String id;
  final String name;
  final Map<String, int> weights;

  const _Condition({
    required this.id,
    required this.name,
    required this.weights,
  });
}
