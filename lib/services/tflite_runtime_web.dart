import 'tflite_types.dart';

/// No-op TFLite runtime for web. The classifier service falls back to
/// rule-based heuristics when this runtime returns null.
class WebTfliteRuntime implements TfliteRuntime {
  @override
  Future<ClassifierInterpreter?> loadModel(List<int> buffer, {int threads = 2}) async => null;
}

TfliteRuntime createRuntime() => WebTfliteRuntime();
