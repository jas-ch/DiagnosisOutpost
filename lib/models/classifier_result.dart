/// Result of running a single classifier (on-device or cloud).
class ClassifierResult {
  final String task;
  final Map<String, double> probabilities;
  final String topClass;
  final double topConfidence;
  final DateTime timestamp;

  const ClassifierResult({
    required this.task,
    required this.probabilities,
    required this.topClass,
    required this.topConfidence,
    required this.timestamp,
  });

  factory ClassifierResult.empty(String task) => ClassifierResult(
        task: task,
        probabilities: const {},
        topClass: '',
        topConfidence: 0,
        timestamp: DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'task': task,
        'probabilities': probabilities,
        'topClass': topClass,
        'topConfidence': topConfidence,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ClassifierResult.fromMap(Map<String, dynamic> map) => ClassifierResult(
        task: map['task']?.toString() ?? '',
        probabilities: (map['probabilities'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, (v as num).toDouble())) ??
            {},
        topClass: map['topClass']?.toString() ?? '',
        topConfidence: (map['topConfidence'] as num?)?.toDouble() ?? 0,
        timestamp: DateTime.tryParse(map['timestamp']?.toString() ?? '') ?? DateTime.now(),
      );
}

/// Multi-task attribute prediction for the tongue classifier.
class TongueAttributes {
  final Map<String, Map<String, double>> groupProbabilities;
  final Map<String, String> topAttributes;

  const TongueAttributes({
    required this.groupProbabilities,
    required this.topAttributes,
  });

  factory TongueAttributes.empty() => const TongueAttributes(
        groupProbabilities: {},
        topAttributes: {},
      );
}

/// Wellness pattern matched from tongue attributes.
class TongueWellness {
  final String pattern;
  final List<String> suggestions;

  const TongueWellness({required this.pattern, required this.suggestions});
}
