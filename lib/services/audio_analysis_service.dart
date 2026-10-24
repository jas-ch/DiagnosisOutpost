import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Lightweight audio analysis for the cough recorder UI.
///
/// Parses 16-bit mono WAV files and computes a time-domain waveform for
/// visualization. Classifier inference is performed by the backend so we do
/// not risk accuracy drift from reimplementing the training preprocessing.
class AudioAnalysisService {
  /// Decode a 16-bit mono WAV file and return PCM samples normalized to
  /// [-1.0, 1.0]. Returns null if the file is not a supported WAV.
  static Future<List<double>?> decodeWav(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    return _parseWavPcm(bytes);
  }

  /// Parse WAV bytes. Supports 16-bit PCM mono only.
  static List<double>? _parseWavPcm(Uint8List bytes) {
    if (bytes.length < 44) return null;

    // RIFF header
    if (!_match(bytes, 0, 'RIFF')) return null;
    if (!_match(bytes, 8, 'WAVE')) return null;

    int pos = 12;
    int? fmtPos;
    int? dataPos;
    int? dataSize;

    while (pos + 8 <= bytes.length) {
      final chunkId = String.fromCharCodes(bytes.sublist(pos, pos + 4));
      final chunkSize = _readUint32(bytes, pos + 4);
      if (chunkId == 'fmt ') {
        fmtPos = pos;
      } else if (chunkId == 'data') {
        dataPos = pos + 8;
        dataSize = chunkSize;
      }
      pos += 8 + chunkSize + (chunkSize.isOdd ? 1 : 0);
    }

    if (fmtPos == null || dataPos == null || dataSize == null) return null;

    final fmtOffset = fmtPos;
    final dataOffset = dataPos;
    final dataLen = dataSize;

    final audioFormat = _readUint16(bytes, fmtOffset + 8);
    final numChannels = _readUint16(bytes, fmtOffset + 10);
    final sampleRate = _readUint32(bytes, fmtOffset + 12);
    final bitsPerSample = _readUint16(bytes, fmtOffset + 22);

    if (audioFormat != 1 || numChannels != 1 || bitsPerSample != 16) {
      return null;
    }

    final sampleCount = math.min(dataLen ~/ 2, (bytes.length - dataOffset) ~/ 2);
    final samples = List<double>.generate(sampleCount, (i) {
      final byteIdx = dataOffset + i * 2;
      final value = bytes[byteIdx] | (bytes[byteIdx + 1] << 8);
      return (value > 32767 ? value - 65536 : value).toDouble() / 32768.0;
    });

    return _resampleIfNeeded(samples, sampleRate, 16000);
  }

  static bool _match(Uint8List bytes, int pos, String s) {
    final codes = s.codeUnits;
    for (var i = 0; i < codes.length; i++) {
      if (pos + i >= bytes.length || bytes[pos + i] != codes[i]) return false;
    }
    return true;
  }

  static int _readUint16(Uint8List bytes, int pos) {
    return bytes[pos] | (bytes[pos + 1] << 8);
  }

  static int _readUint32(Uint8List bytes, int pos) {
    return bytes[pos] |
        (bytes[pos + 1] << 8) |
        (bytes[pos + 2] << 16) |
        (bytes[pos + 3] << 24);
  }

  /// Simple linear resample to target sample rate.
  static List<double> _resampleIfNeeded(
    List<double> samples,
    int sourceRate,
    int targetRate,
  ) {
    if (sourceRate == targetRate) return samples;
    final ratio = sourceRate / targetRate;
    final outLen = (samples.length / ratio).floor();
    return List<double>.generate(outLen, (i) {
      final srcIdx = i * ratio;
      final idx0 = srcIdx.floor();
      final idx1 = math.min(idx0 + 1, samples.length - 1);
      final frac = srcIdx - idx0;
      return samples[idx0] * (1 - frac) + samples[idx1] * frac;
    });
  }

  /// Compute a time-domain waveform with [barCount] bars in [0, 1].
  ///
  /// Each bar is the RMS amplitude of its time slice, converted to dB
  /// relative to the loudest slice in the clip.
  static List<double> computeWaveform(
    List<double> samples, {
    int barCount = 64,
  }) {
    if (samples.isEmpty) return List.filled(barCount, 0.0);

    final sliceSize = samples.length / barCount;
    final rmsValues = List<double>.generate(barCount, (i) {
      final start = (i * sliceSize).floor();
      final end = ((i + 1) * sliceSize).floor().clamp(0, samples.length);
      if (end <= start) return 0.0;
      var sumSq = 0.0;
      for (var j = start; j < end; j++) {
        final v = samples[j];
        sumSq += v * v;
      }
      return math.sqrt(sumSq / (end - start));
    });

    final maxRms = rmsValues.reduce(math.max);
    if (maxRms <= 0) return List.filled(barCount, 0.0);

    return rmsValues.map((rms) {
      final db = 20 * math.log(rms / maxRms) / math.ln10;
      // Map -80 dB .. 0 dB to 0 .. 1.
      return ((db + 80) / 80).clamp(0.0, 1.0);
    }).toList();
  }

  /// Convenience wrapper that decodes a WAV file and returns its waveform.
  static Future<List<double>> waveformFromFile(
    String path, {
    int barCount = 64,
  }) async {
    final samples = await decodeWav(path);
    if (samples == null || samples.isEmpty) {
      return List.filled(barCount, 0.0);
    }
    return computeWaveform(samples, barCount: barCount);
  }

  /// Decode WAV bytes directly (used on web where file paths are blob URLs).
  static Future<List<double>> waveformFromBytes(
    List<int> bytes, {
    int barCount = 64,
  }) async {
    final samples = _parseWavPcm(Uint8List.fromList(bytes));
    if (samples == null || samples.isEmpty) {
      return List.filled(barCount, 0.0);
    }
    return computeWaveform(samples, barCount: barCount);
  }
}
