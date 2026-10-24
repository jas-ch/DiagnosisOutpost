import 'package:flutter_test/flutter_test.dart';

import 'package:diagnosis_odyssey/models/classifier_result.dart';
import 'package:diagnosis_odyssey/models/user_biometrics.dart';
import 'package:diagnosis_odyssey/services/risk_engine.dart';

ClassifierResult _result(String task, Map<String, double> probs) {
  final top = probs.entries.reduce((a, b) => a.value >= b.value ? a : b);
  return ClassifierResult(
    task: task,
    probabilities: probs,
    topClass: top.key,
    topConfidence: top.value,
    timestamp: DateTime.now(),
  );
}

void main() {
  group('RiskEngine symptom-only scoring', () {
    test('no inputs returns zero probability', () {
      final result = RiskEngine.compute(
        symptoms: const [],
        biometrics: const UserBiometrics(),
      );
      expect(result.probability, 0);
      expect(result.conditionId, '');
    });

    test('fever alone is conservative and reports no obvious relation', () {
      final result = RiskEngine.compute(
        symptoms: const [],
        biometrics: const UserBiometrics(bodyTemperature: '101°F'),
      );
      expect(result.probability, 0);
      expect(result.conditionId, '');
      expect(result.conditionName, 'No obvious relation to active outbreak disease');
    });

    test('measles symptoms select measles', () {
      final result = RiskEngine.compute(
        symptoms: const ['Fever', 'Cough', 'Runny nose', 'Rash'],
        biometrics: const UserBiometrics(),
      );
      expect(result.conditionId, 'measles');
      expect(result.probability, greaterThan(50));
    });
  });

  group('RiskEngine classifier fusion', () {
    test('rash measles_like selects measles', () {
      final result = RiskEngine.compute(
        symptoms: const [],
        biometrics: const UserBiometrics(),
        classifierResults: {
          'rash': _result('rash', {'measles_like': 0.95}),
        },
      );
      expect(result.conditionId, 'measles');
      expect(result.probability, greaterThan(60));
    });

    test('rash chickenpox_like selects chickenpox', () {
      final result = RiskEngine.compute(
        symptoms: const [],
        biometrics: const UserBiometrics(),
        classifierResults: {
          'rash': _result('rash', {'chickenpox_like': 0.95}),
        },
      );
      expect(result.conditionId, 'chickenpox');
      expect(result.probability, greaterThan(60));
    });

    test('rash monkeypox_like selects mpox', () {
      final result = RiskEngine.compute(
        symptoms: const [],
        biometrics: const UserBiometrics(),
        classifierResults: {
          'rash': _result('rash', {'monkeypox_like': 0.95}),
        },
      );
      expect(result.conditionId, 'mpox');
      expect(result.probability, greaterThan(60));
    });

    test('rash scarlet_fever_like selects scarlet_fever', () {
      final result = RiskEngine.compute(
        symptoms: const [],
        biometrics: const UserBiometrics(),
        classifierResults: {
          'rash': _result('rash', {'scarlet_fever_like': 0.95}),
        },
      );
      expect(result.conditionId, 'scarlet_fever');
      expect(result.probability, greaterThan(60));
    });

    test('cough whooping selects pertussis', () {
      final result = RiskEngine.compute(
        symptoms: const [],
        biometrics: const UserBiometrics(),
        coughRecorded: true,
        classifierResults: {
          'cough': _result('cough', {'whooping': 0.95}),
        },
      );
      expect(result.conditionId, 'pertussis');
      expect(result.probability, greaterThan(60));
    });

    test('tongue strawberry tongue selects scarlet_fever when confident', () {
      final result = RiskEngine.compute(
        symptoms: const [],
        biometrics: const UserBiometrics(),
        classifierResults: {
          'tongue': _result('tongue', {'shape_features.red_dots_strawberry': 0.95}),
        },
      );
      expect(result.conditionId, 'scarlet_fever');
      expect(result.probability, greaterThan(50));
    });

    test('combined modalities increase confidence', () {
      final withRash = RiskEngine.compute(
        symptoms: const ['Fever', 'Cough', 'Runny nose'],
        biometrics: const UserBiometrics(),
        classifierResults: {
          'rash': _result('rash', {'measles_like': 0.8}),
        },
      );
      final withoutRash = RiskEngine.compute(
        symptoms: const ['Fever', 'Cough', 'Runny nose'],
        biometrics: const UserBiometrics(),
      );
      expect(withRash.probability, greaterThan(withoutRash.probability));
    });
  });
}
