import 'tflite_types.dart';

export 'tflite_types.dart';

/// Default factory for the TFLite runtime. Swapped by conditional imports:
/// - mobile (dart:io) uses tflite_runtime_mobile.dart
/// - web (dart:html) uses tflite_runtime_web.dart
TfliteRuntime createRuntime() {
  throw UnsupportedError('TFLite runtime not implemented for this platform.');
}
