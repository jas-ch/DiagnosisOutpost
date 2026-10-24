import 'dart:typed_data';

import 'package:tflite_flutter/tflite_flutter.dart' as tflite;

import 'tflite_types.dart';

class MobileTfliteRuntime implements TfliteRuntime {
  @override
  Future<ClassifierInterpreter?> loadModel(List<int> buffer, {int threads = 2}) async {
    try {
      final options = tflite.InterpreterOptions()..threads = threads;
      final interpreter = tflite.Interpreter.fromBuffer(
        Uint8List.fromList(buffer),
        options: options,
      );
      return MobileClassifierInterpreter(interpreter);
    } catch (e) {
      return null;
    }
  }
}

class MobileClassifierInterpreter implements ClassifierInterpreter {
  final tflite.Interpreter _interpreter;

  MobileClassifierInterpreter(this._interpreter);

  @override
  List<int> getInputShape() => List<int>.from(_interpreter.getInputTensor(0).shape);

  @override
  List<int> getOutputShape(int index) => List<int>.from(_interpreter.getOutputTensor(index).shape);

  @override
  int getOutputTensorCount() => _interpreter.getOutputTensors().length;

  @override
  TensorType getOutputType(int index) {
    return switch (_interpreter.getOutputTensor(index).type) {
      tflite.TensorType.float32 => TensorType.float32,
      tflite.TensorType.uint8 => TensorType.uint8,
      tflite.TensorType.int8 => TensorType.int8,
      _ => TensorType.unknown,
    };
  }

  @override
  QuantParams getInputParams() {
    final p = _interpreter.getInputTensor(0).params;
    return QuantParams(scale: p.scale, zeroPoint: p.zeroPoint);
  }

  @override
  QuantParams getOutputParams(int index) {
    final p = _interpreter.getOutputTensor(index).params;
    return QuantParams(scale: p.scale, zeroPoint: p.zeroPoint);
  }

  @override
  void run(Object input, Object output) => _interpreter.run(input, output);

  @override
  void runForMultipleInputs(List<Object> inputs, Map<int, Object> outputs) {
    _interpreter.runForMultipleInputs(inputs, outputs);
  }

  @override
  void close() => _interpreter.close();
}

TfliteRuntime createRuntime() => MobileTfliteRuntime();
