library tflite_types;

/// Shared TFLite types used by both mobile and web runtime implementations.

abstract class TfliteRuntime {
  Future<ClassifierInterpreter?> loadModel(List<int> buffer, {int threads = 2});
}

abstract class ClassifierInterpreter {
  List<int> getInputShape();
  List<int> getOutputShape(int index);
  int getOutputTensorCount();
  TensorType getOutputType(int index);
  QuantParams getInputParams();
  QuantParams getOutputParams(int index);
  void run(Object input, Object output);
  void runForMultipleInputs(List<Object> inputs, Map<int, Object> outputs);
  void close();
}

enum TensorType { float32, uint8, int8, unknown }

class QuantParams {
  final double scale;
  final int zeroPoint;

  const QuantParams({required this.scale, required this.zeroPoint});
}
