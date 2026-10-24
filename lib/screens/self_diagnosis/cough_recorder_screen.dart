import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../../models/classifier_result.dart';
import '../../services/audio_analysis_service.dart';
import '../../services/capture_storage_service.dart';
import '../../services/classifier_service.dart';
import '../../widgets/classifier_result_summary.dart';

class CoughRecorderScreen extends StatefulWidget {
  const CoughRecorderScreen({super.key});

  @override
  State<CoughRecorderScreen> createState() => _CoughRecorderScreenState();
}

class _CoughRecorderScreenState extends State<CoughRecorderScreen> {
  final _recorder = AudioRecorder();
  final _livePlayer = AudioPlayer();
  final _recentPlayer = AudioPlayer();

  bool _hasPermission = false;
  bool _isRecording = false;
  bool _isLivePlaying = false;
  bool _isRecentPlaying = false;
  bool _isProcessing = false;
  String? _recordedPath;
  Timer? _timer;
  Duration _duration = Duration.zero;
  DateTime? _recordingStartedAt;
  CaptureRecord? _recentRecord;
  ClassifierResult? _liveResult;
  List<double> _recentWaveform = [];
  List<double> _liveWaveform = [];
  Duration _livePosition = Duration.zero;
  Duration _liveDuration = Duration.zero;
  Duration _recentPosition = Duration.zero;
  Duration _recentDuration = Duration.zero;
  StreamSubscription? _livePositionSub;
  StreamSubscription? _recentPositionSub;
  StreamSubscription? _amplitudeSub;
  double _currentDb = -160;

  @override
  void initState() {
    super.initState();
    _checkPermission();
    _loadRecent();

    _livePlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _isLivePlaying = false);
    });
    _livePositionSub = _livePlayer.onPositionChanged.listen((pos) {
      if (mounted) setState(() => _livePosition = pos);
    });
    _livePlayer.onDurationChanged.listen((dur) {
      if (mounted) setState(() => _liveDuration = dur);
    });

    _recentPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _isRecentPlaying = false);
    });
    _recentPositionSub = _recentPlayer.onPositionChanged.listen((pos) {
      if (mounted) setState(() => _recentPosition = pos);
    });
    _recentPlayer.onDurationChanged.listen((dur) {
      if (mounted) setState(() => _recentDuration = dur);
    });
  }

  Future<void> _loadRecent() async {
    final record = await CaptureStorageService.loadForCategory('cough');
    if (!mounted) return;
    setState(() => _recentRecord = record);
    if (record != null) {
      final bytes = await _readAudioBytes(record.filePath);
      if (bytes != null) {
        _recentWaveform = await AudioAnalysisService.waveformFromBytes(bytes);
      }
      await _updatePlayerDuration(_recentPlayer, record.filePath);
      if (mounted) setState(() {});
    }
  }

  Future<void> _checkPermission() async {
    // permission_handler does not reliably request microphone access on web;
    // the record package will ask the browser when start() is called.
    if (kIsWeb) {
      setState(() => _hasPermission = true);
      return;
    }
    final status = await Permission.microphone.request();
    setState(() => _hasPermission = status.isGranted || status.isLimited);
  }

  Future<void> _toggleRecord() async {
    if (_isRecording) {
      await _stopRecording();
      return;
    }
    if (!_hasPermission) {
      await _checkPermission();
      if (!_hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission is required.')),
          );
        }
        return;
      }
    }

    // Stop any playback so recording starts from a clean state.
    await _livePlayer.stop();
    await _recentPlayer.stop();
    if (mounted) {
      setState(() {
        _isLivePlaying = false;
        _isRecentPlaying = false;
        _recordedPath = null;
        _liveResult = null;
        _liveWaveform = [];
        _livePosition = Duration.zero;
        _liveDuration = Duration.zero;
      });
    }

    final filePath = kIsWeb
        ? 'cough_${DateTime.now().millisecondsSinceEpoch}.wav'
        : path.join(
            Directory.systemTemp.path,
            'cough_${DateTime.now().millisecondsSinceEpoch}.wav',
          );

    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: filePath,
      );
      _recordingStartedAt = DateTime.now();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateRecordingDuration());
      _amplitudeSub = _recorder.onAmplitudeChanged(const Duration(milliseconds: 100)).listen(
        (amp) {
          if (mounted) setState(() => _currentDb = amp.current);
        },
        onError: (_) {},
      );
      setState(() {
        _isRecording = true;
        _duration = Duration.zero;
        _currentDb = -160;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start recording: $e')),
        );
      }
    }
  }

  void _updateRecordingDuration() {
    if (_recordingStartedAt == null) return;
    setState(() {
      _duration = DateTime.now().difference(_recordingStartedAt!);
    });
  }

  Future<void> _stopRecording() async {
    try {
      final filePath = await _recorder.stop();
      _timer?.cancel();
      _timer = null;
      await _amplitudeSub?.cancel();
      _amplitudeSub = null;
      if (!mounted) return;

      setState(() {
        _isRecording = false;
        _recordedPath = filePath;
        _currentDb = -160;
      });

      if (filePath != null && filePath.isNotEmpty) {
        await _analyzeLiveRecording(filePath);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not stop recording: $e')),
        );
      }
    }
  }

  Future<List<int>?> _readAudioBytes(String filePath) async {
    if (kIsWeb) {
      try {
        return await http.readBytes(Uri.parse(filePath));
      } catch (e) {
        debugPrint('CoughRecorderScreen: could not read web audio bytes: $e');
        return null;
      }
    }
    try {
      return await File(filePath).readAsBytes();
    } catch (e) {
      debugPrint('CoughRecorderScreen: could not read audio bytes: $e');
      return null;
    }
  }

  Future<void> _analyzeLiveRecording(String filePath) async {
    setState(() => _isProcessing = true);
    try {
      final bytes = await _readAudioBytes(filePath);
      if (!mounted) return;
      if (bytes == null) {
        setState(() {
          _liveWaveform = List.filled(64, 0.0);
          _liveResult = null;
        });
        return;
      }

      // Decode the WAV and classify in parallel; the backend still performs
      // the librosa-accurate mel-spectrogram preprocessing.
      final waveformFuture = AudioAnalysisService.waveformFromBytes(bytes);
      final resultFuture = ClassifierService.classifyCough(
        filePath,
        audioBytes: bytes,
        context: context,
      );
      final results = await Future.wait([waveformFuture, resultFuture]);
      final waveform = results[0] as List<double>;
      final result = results[1] as ClassifierResult?;

      if (!mounted) return;
      setState(() {
        _liveWaveform = waveform;
        _liveResult = result;
      });
      await _updatePlayerDuration(_livePlayer, filePath);
    } catch (e, st) {
      debugPrint('CoughRecorderScreen: analysis failed: $e\n$st');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Source _audioSource(String filePath) {
    return kIsWeb ? UrlSource(filePath) : DeviceFileSource(filePath);
  }

  Future<void> _updatePlayerDuration(AudioPlayer player, String filePath) async {
    try {
      await player.setSource(_audioSource(filePath));
      final dur = await player.getDuration() ?? Duration.zero;
      if (mounted) {
        if (player == _livePlayer) {
          _liveDuration = dur;
        } else {
          _recentDuration = dur;
        }
      }
    } catch (e) {
      debugPrint('CoughRecorderScreen: could not get duration: $e');
    }
  }

  Future<void> _toggleLivePlayback() async {
    final file = _recordedPath;
    if (file == null) return;
    if (_isLivePlaying) {
      await _livePlayer.stop();
      setState(() => _isLivePlaying = false);
      return;
    }
    try {
      setState(() => _isLivePlaying = true);
      await _livePlayer.play(_audioSource(file));
    } catch (e) {
      setState(() => _isLivePlaying = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not play recording: $e')),
        );
      }
    }
  }

  Future<void> _toggleRecentPlayback() async {
    final file = _recentRecord?.filePath;
    if (file == null) return;
    if (_isRecentPlaying) {
      await _recentPlayer.stop();
      setState(() => _isRecentPlaying = false);
      return;
    }
    try {
      setState(() => _isRecentPlaying = true);
      await _recentPlayer.play(_audioSource(file));
    } catch (e) {
      setState(() => _isRecentPlaying = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not play recording: $e')),
        );
      }
    }
  }

  Future<void> _deleteRecent() async {
    final recent = _recentRecord;
    if (recent == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear recent cough audio?'),
        content: const Text('Remove the most recent cough recording and its analysis.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await CaptureStorageService.deleteForCategory('cough');
    setState(() {
      _recentRecord = null;
      _recentWaveform = [];
      _recentPosition = Duration.zero;
      _recentDuration = Duration.zero;
    });
  }

  Future<void> _onSave() async {
    final filePath = _recordedPath;
    if (filePath == null || filePath.isEmpty) return;

    setState(() => _isProcessing = true);
    try {
      final persistentPath = kIsWeb
          ? filePath
          : await CaptureStorageService.persistentPath(filePath, 'cough');

      String? webBase64;
      if (kIsWeb) {
        try {
          final bytes = await _readAudioBytes(persistentPath);
          if (bytes != null) webBase64 = base64Encode(bytes);
        } catch (e) {
          debugPrint('CoughRecorderScreen: could not encode web audio: $e');
        }
      }

      final result = _liveResult;
      final now = DateTime.now();

      final saved = CaptureRecord(
        category: 'cough',
        filePath: persistentPath,
        timestamp: now,
        result: result,
        webBase64: webBase64,
      );

      await CaptureStorageService.save(saved);

      if (!mounted) return;
      setState(() {
        _recentRecord = saved;
        _recentWaveform = List<double>.from(_liveWaveform);
        _recordedPath = null;
        _liveResult = null;
        _liveWaveform = [];
        _livePosition = Duration.zero;
        _liveDuration = Duration.zero;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cough audio saved')),
      );
    } catch (e, st) {
      debugPrint('CoughRecorderScreen: save failed: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save cough recording: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Widget _buildRecordButtonChild() {
    final label = _isRecording
        ? 'Stop'
        : (_recordedPath != null ? 'Re-record' : 'Record');
    final isReRecord = label == 'Re-record';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isReRecord) ...[
          const Icon(Icons.refresh, size: 18),
          const SizedBox(width: 4),
        ],
        Text(label),
        const SizedBox(width: 4),
        Icon(_isRecording ? Icons.stop : Icons.mic, size: 18),
      ],
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _formatTimestamp(DateTime dt) {
    return '${DateFormat.yMMMd().add_jm().format(dt)} (${dt.timeZoneName})';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _livePositionSub?.cancel();
    _recentPositionSub?.cancel();
    _amplitudeSub?.cancel();
    _recorder.dispose();
    _livePlayer.dispose();
    _recentPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recent = _recentRecord;
    final hasRecent = recent != null;
    final hasNewRecording = _recordedPath != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cough Audio'),
        leading: const BackButton(),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            20 + MediaQuery.of(context).padding.bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasRecent) ...[
                _buildRecentCard(recent),
                const SizedBox(height: 20),
              ],
              if (_isRecording) ...[
                Center(
                  child: Column(
                    children: [
                      _RecordingMic(db: _currentDb),
                      const SizedBox(height: 16),
                      Text(
                        'Recording...',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _formatDuration(_duration),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _stopRecording,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                        icon: const Icon(Icons.stop),
                        label: const Text('Complete Recording'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
              if (!_isRecording) _buildLivePreviewCard(hasNewRecording),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentCard(CaptureRecord record) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Most recent cough audio',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              _formatTimestamp(record.timestamp),
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            _WaveformVisualizer(
              waveform: _recentWaveform,
              progress: _recentDuration.inMilliseconds > 0
                  ? _recentPosition.inMilliseconds / _recentDuration.inMilliseconds
                  : 0,
            ),
            const SizedBox(height: 8),
            Text(
              '${_formatDuration(_recentPosition)} / ${_formatDuration(_recentDuration)}',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 8),
            if (record.result != null && record.result!.topClass.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: SingleChildScrollView(
                  child: ClassifierResultSummary(result: record.result!, category: 'cough'),
                ),
              )
            else
              const Text('No analysis available.'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _toggleRecentPlayback,
                    icon: Icon(_isRecentPlaying ? Icons.stop : Icons.play_arrow),
                    label: Text(_isRecentPlaying ? 'Stop recent' : 'Play recent'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _deleteRecent,
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Clear recent cough audio',
                  color: Colors.red.shade400,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLivePreviewCard(bool hasNewRecording) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Live preview',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Stack(
              alignment: Alignment.center,
              children: [
                _WaveformVisualizer(
                  waveform: _liveWaveform,
                  progress: _liveDuration.inMilliseconds > 0
                      ? _livePosition.inMilliseconds / _liveDuration.inMilliseconds
                      : 0,
                ),
                if (_isProcessing && _liveWaveform.isEmpty)
                  const CircularProgressIndicator(),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${_formatDuration(_livePosition)} / ${_formatDuration(_liveDuration)}',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 8),
            if (hasNewRecording && _liveResult != null && _liveResult!.topClass.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: SingleChildScrollView(
                  child: ClassifierResultSummary(result: _liveResult!, category: 'cough'),
                ),
              )
            else
              const Text(
                'No live recording yet',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: hasNewRecording && !_isProcessing && _liveWaveform.isNotEmpty
                        ? _toggleLivePlayback
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: hasNewRecording && !_isProcessing && _liveWaveform.isNotEmpty
                          ? Colors.green
                          : Colors.grey,
                    ),
                    icon: Icon(_isLivePlaying ? Icons.stop : Icons.play_arrow),
                    label: Text(_isLivePlaying ? 'Stop' : 'Play'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _isProcessing ? null : _toggleRecord,
                    style: FilledButton.styleFrom(
                      backgroundColor: _isRecording ? Colors.red : Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                    child: _buildRecordButtonChild(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isProcessing || !hasNewRecording ? null : _onSave,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                icon: _isProcessing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save),
                label: const Text('Save Cough Audio'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WaveformVisualizer extends StatelessWidget {
  final List<double> waveform;
  final double progress;

  const _WaveformVisualizer({
    required this.waveform,
    this.progress = 0,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(double.infinity, 64),
      painter: _WaveformPainter(
        waveform: waveform,
        progress: progress.clamp(0, 1),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> waveform;
  final double progress;

  _WaveformPainter({required this.waveform, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    const barCount = 64;
    final bars = waveform.isEmpty ? List.filled(barCount, 0.0) : waveform;
    final paint = Paint()
      ..color = Colors.teal.withAlpha(180)
      ..strokeCap = StrokeCap.round;

    const spacing = 2.0;
    const totalSpacing = spacing * (barCount + 1);
    final barWidth = (size.width - totalSpacing) / barCount;
    final maxBarHeight = size.height * 0.9;

    for (var i = 0; i < barCount; i++) {
      final value = i < bars.length ? bars[i] : 0.0;
      final h = 2.0 + value * maxBarHeight;
      final left = spacing + i * (barWidth + spacing);
      final top = (size.height - h) / 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, barWidth, h),
        const Radius.circular(2),
      );
      canvas.drawRRect(rect, paint);
    }

    // Red playback-position line.
    final lineX = progress * size.width;
    final linePaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(lineX, 0),
      Offset(lineX, size.height),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.waveform != waveform || oldDelegate.progress != progress;
  }
}

/// Red circular microphone with animated white amplitude bars inside it.
class _RecordingMic extends StatelessWidget {
  final double db;

  const _RecordingMic({required this.db});

  double get _intensity {
    // Map dBFS to a 0..1 intensity using a sensible speech range.
    // Silence is at or below -60 dB; very loud input nears -10 dB.
    const minDb = -60.0;
    const maxDb = -10.0;
    final clampedDb = db.clamp(-160.0, maxDb);
    return ((clampedDb - minDb) / (maxDb - minDb)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    const size = 120.0;
    const barCount = 5;
    final intensity = _intensity;
    final visibleCount = (intensity * barCount).round().clamp(0, barCount);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size,
            height: size,
            decoration: const BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
            ),
          ),
          const Icon(
            Icons.mic,
            size: 56,
            color: Colors.white,
          ),
          Positioned(
            bottom: 18,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(barCount, (index) {
                final active = index < visibleCount;
                final height = active ? 4.0 + intensity * 16.0 : 0.0;
                return Container(
                  width: 5,
                  height: height,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: active ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}
