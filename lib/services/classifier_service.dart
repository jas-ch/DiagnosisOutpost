import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/classifier_result.dart';
import 'api_service.dart';
// ignore: unnecessary_import
import 'tflite_types.dart';
import 'tflite_runtime.dart'
    if (dart.library.io) 'tflite_runtime_mobile.dart'
    if (dart.library.html) 'tflite_runtime_web.dart';

/// TFLite classifier service.
///
/// On Android/iOS it loads the bundled TFLite models and runs inference
/// locally. On web it normally falls back to rule-based heuristics because the
/// TFLite runtime is not available in browsers, but if the user explicitly
/// opts in it can upload photos/audio to the Diagnosis Outpost backend for
/// cloud inference. Media is processed in memory and not stored by the backend.
class ClassifierService {
  ClassifierService._();

  static final _runtime = createRuntime();
  static final Map<String, ClassifierInterpreter> _interpreters = {};
  static final Map<String, List<String>> _labels = {};
  static Map<String, dynamic>? _tongueAttributes;
  static Map<String, dynamic>? _tongueRules;

  static bool get _isWeb => kIsWeb;
  static const _cloudConsentKey = 'cloud_classification_consent';

  /// Returns whether the user has consented to uploading photos/audio to the
  /// backend for classification on web.
  static Future<bool> hasCloudConsent() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_cloudConsentKey) ?? false;
  }

  /// Persist the user's choice to allow cloud classification.
  static Future<void> setCloudConsent(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_cloudConsentKey, value);
  }

  /// Show an explicit opt-in dialog on web and return the user's choice.
  /// Returns true immediately on non-web platforms or if already consented.
  static Future<bool> requestCloudConsent(BuildContext context) async {
    if (!_isWeb) return true;
    final alreadyGranted = await hasCloudConsent();
    if (alreadyGranted) return true;

    if (!context.mounted) return false;
    final granted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Use cloud classification?'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your browser cannot run our on-device ML models. To analyze this photo or cough audio, you can send it to the Diagnosis Outpost backend for processing.',
            ),
            SizedBox(height: 12),
            Text(
              'The file is processed in memory and is not stored. You can revoke this choice at any time.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Allow'),
          ),
        ],
      ),
    );

    final value = granted == true;
    await setCloudConsent(value);
    return value;
  }

  static Future<bool> _ensureCloudConsent(BuildContext? context) async {
    if (!_isWeb) return true;
    if (await hasCloudConsent()) return true;
    if (context == null || !context.mounted) return false;
    return requestCloudConsent(context);
  }

  /// Pre-loads label files and tongue metadata. Models are loaded lazily on
  /// first inference to avoid slow startup and memory pressure.
  static Future<void> initialize() async {
    final tasks = ['rash', 'wound', 'face', 'tongue', 'cough'];
    for (final task in tasks) {
      await _loadLabels(task);
    }
    await _loadTongueMetadata();
  }

  /// Maps a UI photo category to the bundled model task name.
  static String _modelTaskFor(String uiTask) {
    return switch (uiTask.toLowerCase()) {
      'selfie' => 'face',
      'wounds' => 'wound',
      _ => uiTask.toLowerCase(),
    };
  }

  /// Run the classifier for a captured photo.
  /// [task] is the UI category (rash, wounds, selfie, tongue). It is mapped
  /// internally to the bundled model task name (rash, wound, face, tongue).
  ///
  /// On web, [context] is used to request cloud-processing consent if it has
  /// not yet been granted. If consent is denied or [context] is null, a
  /// deterministic fallback result is returned.
  ///
  /// On web [imageBytes] should be supplied because browser file paths are
  /// temporary blob URLs; on mobile it can be omitted.
  static Future<ClassifierResult> classifyPhoto(
    String task,
    String imagePath, {
    List<int>? imageBytes,
    BuildContext? context,
  }) async {
    final modelTask = _modelTaskFor(task);

    if (_isWeb) {
      final consented = await _ensureCloudConsent(context);
      if (consented) {
        try {
          final result = await ApiService.classifyImage(
            modelTask,
            imagePath,
            fileBytes: imageBytes,
          );
          // Preserve the UI category in the result so downstream storage and
          // risk fusion use the user-facing category name.
          return ClassifierResult(
            task: task,
            probabilities: result.probabilities,
            topClass: result.topClass,
            topConfidence: result.topConfidence,
            timestamp: result.timestamp,
          );
        } catch (e) {
          debugPrint('ClassifierService: backend image classification failed: $e');
        }
      }
      return _fallbackPhotoResult(task);
    }

    final interpreter = await _loadModel(modelTask);
    if (interpreter == null) {
      return ClassifierResult.empty(task);
    }

    final inputShape = interpreter.getInputShape();
    final size = inputShape.length >= 2 ? inputShape[1] : 224;

    if (modelTask == 'tongue') {
      final input = await _preprocessQuantizedImage(imagePath, size: size);
      if (input == null) return ClassifierResult.empty(task);
      return _runTongueClassifier(interpreter, input, uiTask: task);
    }

    final labels = await _loadLabels(modelTask);
    if (labels == null || labels.isEmpty) {
      return ClassifierResult.empty(task);
    }

    final input = await _preprocessFloatImage(imagePath, size: size);
    if (input == null) return ClassifierResult.empty(task);

    final output = List.generate(
      1,
      (_) => List.filled(labels.length, 0.0),
    );
    interpreter.run(input, output);

    // The bundled MobileNetV2 classifiers are trained with softmax outputs, so
    // the TFLite model already returns probabilities. Do not re-apply softmax.
    return _buildResult(task, labels, output[0]);
  }

  /// Run the cough classifier on an audio file.
  ///
  /// On the web the audio is sent to the backend only after explicit user
  /// consent. On Android/iOS we currently send the audio to the backend as well
  /// because the on-device librosa-accurate mel-spectrogram preprocessor is
  /// implemented as a native platform module (Phase 2). Until that module is
  /// active, the backend performs the identical preprocessing used during
  /// training and returns real classifier probabilities.
  ///
  /// On web [audioBytes] should be supplied because browser file paths are
  /// temporary blob URLs; on mobile it can be omitted.
  static Future<ClassifierResult> classifyCough(
    String audioPath, {
    List<int>? audioBytes,
    BuildContext? context,
  }) async {
    if (_isWeb) {
      final consented = await _ensureCloudConsent(context);
      if (!consented) return _fallbackCoughResult();
    }

    try {
      return await ApiService.classifyCough(
        audioPath,
        fileBytes: audioBytes,
      );
    } catch (e) {
      debugPrint('ClassifierService: backend cough classification failed: $e');
      return _fallbackCoughResult();
    }
  }

  /// Load a cached TFLite interpreter for [task].
  static Future<ClassifierInterpreter?> _loadModel(String task) async {
    if (_interpreters.containsKey(task)) return _interpreters[task];

    try {
      final asset = 'assets/models/classifiers/${task}_classifier.tflite';
      final byteData = await rootBundle.load(asset);
      final buffer = byteData.buffer.asUint8List();
      final interpreter = await _runtime.loadModel(buffer, threads: 2);
      if (interpreter != null) _interpreters[task] = interpreter;
      return interpreter;
    } catch (e) {
      debugPrint('ClassifierService: failed to load $task model: $e');
      return null;
    }
  }

  static Future<List<String>?> _loadLabels(String task) async {
    if (_labels.containsKey(task)) return _labels[task];
    try {
      final jsonString = await rootBundle.loadString(
        'assets/models/classifiers/${task}_labels.json',
      );
      final map = jsonDecode(jsonString) as Map<String, dynamic>;
      final classes = (map['classes'] as List<dynamic>).cast<String>();
      _labels[task] = classes;
      return classes;
    } catch (e) {
      debugPrint('ClassifierService: failed to load $task labels: $e');
      return null;
    }
  }

  static Future<void> _loadTongueMetadata() async {
    if (_tongueAttributes != null && _tongueRules != null) return;
    try {
      _tongueAttributes = jsonDecode(
        await rootBundle.loadString('assets/models/classifiers/tongue_attributes.json'),
      ) as Map<String, dynamic>;
      _tongueRules = jsonDecode(
        await rootBundle.loadString('assets/models/classifiers/tongue_evidence_rules.json'),
      ) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('ClassifierService: failed to load tongue metadata: $e');
    }
  }

  static Future<List<List<List<List<double>>>>?> _preprocessFloatImage(
    String imagePath, {
    required int size,
  }) async {
    final decoded = await _loadAndCrop(imagePath, size: size);
    if (decoded == null) return null;

    return List.generate(
      1,
      (_) => List.generate(
        size,
        (y) => List.generate(
          size,
          (x) {
            final pixel = decoded.getPixel(x, y);
            return [
              (pixel.r / 127.5) - 1.0,
              (pixel.g / 127.5) - 1.0,
              (pixel.b / 127.5) - 1.0,
            ];
          },
        ),
      ),
    );
  }

  static Future<List<List<List<List<int>>>>?> _preprocessQuantizedImage(
    String imagePath, {
    required int size,
  }) async {
    final interpreter = _interpreters['tongue'];
    if (interpreter == null) return null;
    final params = interpreter.getInputParams();
    final scale = params.scale;
    final zeroPoint = params.zeroPoint;

    final decoded = await _loadAndCrop(imagePath, size: size);
    if (decoded == null) return null;

    return List.generate(
      1,
      (_) => List.generate(
        size,
        (y) => List.generate(
          size,
          (x) {
            final pixel = decoded.getPixel(x, y);
            return [
              _quantize((pixel.r / 127.5) - 1.0, scale, zeroPoint),
              _quantize((pixel.g / 127.5) - 1.0, scale, zeroPoint),
              _quantize((pixel.b / 127.5) - 1.0, scale, zeroPoint),
            ];
          },
        ),
      ),
    );
  }

  static Future<img.Image?> _loadAndCrop(String imagePath, {required int size}) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      var decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      final minSide = math.min(decoded.width, decoded.height);
      decoded = img.copyCrop(
        decoded,
        x: (decoded.width - minSide) ~/ 2,
        y: (decoded.height - minSide) ~/ 2,
        width: minSide,
        height: minSide,
      );
      return img.copyResize(decoded, width: size, height: size);
    } catch (e) {
      debugPrint('ClassifierService: image preprocessing failed: $e');
      return null;
    }
  }

  static int _quantize(double value, double scale, int zeroPoint) {
    return ((value / scale) + zeroPoint).round().clamp(0, 255);
  }

  static ClassifierResult _buildResult(String task, List<String> labels, List<double> values) {
    final probabilities = <String, double>{};
    for (var i = 0; i < labels.length && i < values.length; i++) {
      probabilities[labels[i]] = values[i];
    }
    final top = probabilities.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return ClassifierResult(
      task: task,
      probabilities: probabilities,
      topClass: top.key,
      topConfidence: top.value,
      timestamp: DateTime.now(),
    );
  }

  static List<double> _softmax(List<double> values) {
    final maxVal = values.reduce(math.max);
    final expValues = values.map((v) => math.exp(v - maxVal)).toList();
    final sum = expValues.reduce((a, b) => a + b);
    return expValues.map((v) => v / sum).toList();
  }

  static Future<ClassifierResult> _runTongueClassifier(
    ClassifierInterpreter interpreter,
    List<List<List<List<int>>>> input, {
    String uiTask = 'tongue',
  }) async {
    await _loadTongueMetadata();
    final attr = _tongueAttributes?['attribute_groups'] as Map<String, dynamic>?;
    if (attr == null) return ClassifierResult.empty(uiTask);

    final outputCount = interpreter.getOutputTensorCount();
    final outputs = <int, List<List<int>>>{};
    for (var i = 0; i < outputCount; i++) {
      final shape = interpreter.getOutputShape(i);
      outputs[i] = List.generate(shape[0], (_) => List.filled(shape[1], 0));
    }
    interpreter.runForMultipleInputs([input], outputs);

    final groupProbs = <String, Map<String, double>>{};
    final topAttrs = <String, String>{};
    var groupIdx = 0;
    for (final entry in attr.entries) {
      final groupName = entry.key;
      final classes = (entry.value as List<dynamic>).cast<String>();
      final raw = outputs[groupIdx];
      if (raw == null) continue;
      final outParams = interpreter.getOutputParams(groupIdx);
      final values = raw[0]
          .map((q) => ((q - outParams.zeroPoint) * outParams.scale).toDouble())
          .toList();
      final probs = _softmax(values);
      final probsMap = <String, double>{};
      for (var i = 0; i < classes.length && i < probs.length; i++) {
        probsMap[classes[i]] = probs[i];
      }
      groupProbs[groupName] = probsMap;
      topAttrs[groupName] = probsMap.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
      groupIdx++;
    }

    final topClass = topAttrs.entries.map((e) => '${e.key}: ${e.value}').join('; ');
    final flatProbs = <String, double>{};
    for (final entry in groupProbs.entries) {
      for (final p in entry.value.entries) {
        flatProbs['${entry.key}.${p.key}'] = p.value;
      }
    }
    return ClassifierResult(
      task: uiTask,
      probabilities: flatProbs,
      topClass: topClass,
      topConfidence: groupProbs.values.isEmpty
          ? 0
          : groupProbs.values.map((m) => m.values.reduce(math.max)).reduce(math.max),
      timestamp: DateTime.now(),
    );
  }

  /// Extract [TongueAttributes] from a flat tongue classifier result.
  static TongueAttributes extractTongueAttributes(ClassifierResult result) {
    final groupProbs = <String, Map<String, double>>{};
    final topAttrs = <String, String>{};
    for (final entry in result.probabilities.entries) {
      final parts = entry.key.split('.');
      if (parts.length != 2) continue;
      final group = parts[0];
      final value = parts[1];
      groupProbs.putIfAbsent(group, () => {})[value] = entry.value;
    }
    for (final entry in groupProbs.entries) {
      topAttrs[entry.key] = entry.value.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    }
    return TongueAttributes(groupProbabilities: groupProbs, topAttributes: topAttrs);
  }

  /// Match tongue attributes to a wellness pattern and suggestions.
  static Future<TongueWellness?> evaluateTongueWellness(TongueAttributes attributes) async {
    await _loadTongueMetadata();
    final patterns = _tongueRules?['wellness_patterns'] as List<dynamic>?;
    if (patterns == null) return null;

    TongueWellness? best;
    var bestScore = 0;
    for (final pattern in patterns) {
      final expected = (pattern['attributes'] as Map<String, dynamic>?)?.cast<String, String>() ?? {};
      var matched = 0;
      for (final entry in expected.entries) {
        if (attributes.topAttributes[entry.key] == entry.value) matched++;
      }
      if (matched > bestScore) {
        bestScore = matched;
        best = TongueWellness(
          pattern: pattern['pattern'] as String? ?? '',
          suggestions: (pattern['suggestions'] as List<dynamic>?)?.cast<String>() ?? [],
        );
      }
    }
    return best;
  }

  // ---------------------------------------------------------------------------
  // Web / fallback heuristics
  // ---------------------------------------------------------------------------

  static ClassifierResult _fallbackPhotoResult(String task) {
    return ClassifierResult(
      task: task,
      probabilities: {'unclear': 1.0},
      topClass: 'unclear',
      topConfidence: 1.0,
      timestamp: DateTime.now(),
    );
  }

  static ClassifierResult _fallbackCoughResult() {
    return ClassifierResult(
      task: 'cough',
      probabilities: {'non_pathological_or_unclear': 1.0},
      topClass: 'non_pathological_or_unclear',
      topConfidence: 1.0,
      timestamp: DateTime.now(),
    );
  }
}
