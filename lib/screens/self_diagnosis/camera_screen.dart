import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../models/classifier_result.dart';
import '../../services/capture_storage_service.dart';
import '../../services/classifier_service.dart';
import '../../widgets/classifier_result_summary.dart';

class PhotoCaptureResult {
  final String category;
  final String filePath;
  final ClassifierResult? result;

  PhotoCaptureResult({
    required this.category,
    required this.filePath,
    this.result,
  });
}

class CameraScreen extends StatefulWidget {
  final bool useRearCamera;
  final String title;
  final String category;

  const CameraScreen({
    super.key,
    required this.useRearCamera,
    required this.title,
    required this.category,
  });

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  bool _isReady = false;
  bool _permissionDenied = false;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final status = await Permission.camera.request();
    if (status != PermissionStatus.granted && status != PermissionStatus.limited) {
      if (mounted) {
        setState(() => _permissionDenied = true);
      }
      return;
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() => _permissionDenied = true);
        }
        return;
      }

      final lens = widget.useRearCamera
          ? CameraLensDirection.back
          : CameraLensDirection.front;
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == lens,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        camera,
        kIsWeb ? ResolutionPreset.low : ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();

      if (mounted) {
        setState(() {
          _controller = controller;
          _isReady = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _permissionDenied = true);
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      setState(() => _isProcessing = true);
      final file = await controller.takePicture();
      if (!mounted) return;

      // On web, file paths are temporary blob URLs. Read the bytes once and
      // use them for classification, review, and persistence.
      String persistentPath;
      List<int>? imageBytes;
      String? webBase64;
      if (kIsWeb) {
        try {
          imageBytes = await file.readAsBytes();
          webBase64 = base64Encode(imageBytes);
        } catch (e) {
          debugPrint('CameraScreen: could not read web image bytes: $e');
        }
        persistentPath = file.path;
      } else {
        persistentPath = await CaptureStorageService.persistentPath(
          file.path,
          widget.category,
        );
      }

      if (!mounted) return;

      ClassifierResult? result;
      try {
        result = await ClassifierService.classifyPhoto(
          widget.category.toLowerCase(),
          persistentPath,
          imageBytes: imageBytes,
          context: context,
        );
      } catch (e) {
        debugPrint('CameraScreen: classification failed: $e');
      }

      if (!mounted) return;
      final confirmed = await _showReviewDialog(
        persistentPath,
        result,
        webBase64: webBase64,
      );
      if (!mounted) return;

      if (confirmed == true) {
        try {
          await CaptureStorageService.save(CaptureRecord(
            category: widget.category,
            filePath: persistentPath,
            timestamp: DateTime.now(),
            result: result,
            webBase64: webBase64,
          ));
        } catch (e, st) {
          debugPrint('CameraScreen: save failed: $e\n$st');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not save photo: $e')),
            );
          }
          return;
        }
        if (!mounted) return;
        Navigator.pop(
          context,
          PhotoCaptureResult(
            category: widget.category,
            filePath: persistentPath,
            result: result,
          ),
        );
      }
    } catch (e, st) {
      debugPrint('CameraScreen: capture failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not capture photo: $e')),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<bool?> _showReviewDialog(
    String filePath,
    ClassifierResult? result, {
    String? webBase64,
  }) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _CaptureReviewDialog(
        filePath: filePath,
        category: widget.category,
        result: result,
        webBase64: webBase64,
      ),
    );
  }

  void _toggleLens() {
    final controller = _controller;
    if (controller == null) return;
    final cameras = controller.description;
    final newLens = cameras.lensDirection == CameraLensDirection.back
        ? CameraLensDirection.front
        : CameraLensDirection.back;
    controller.dispose().then((_) {
      if (mounted) {
        setState(() {
          _controller = null;
          _isReady = false;
        });
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => CameraScreen(
              useRearCamera: newLens == CameraLensDirection.back,
              title: widget.title,
              category: widget.category,
            ),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title),
      ),
      body: _permissionDenied
          ? _buildNoCamera()
          : !_isReady
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : Stack(
                  children: [
                    Column(
                      children: [
                        Expanded(
                          child: ClipRect(
                            child: OverflowBox(
                              alignment: Alignment.center,
                              child: CameraPreview(_controller!),
                            ),
                          ),
                        ),
                        Container(
                          color: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                          child: SafeArea(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.flip_camera_ios, color: Colors.white),
                                  onPressed: _toggleLens,
                                  tooltip: 'Switch camera',
                                ),
                                FloatingActionButton(
                                  backgroundColor: Colors.white,
                                  onPressed: _isProcessing ? null : _capture,
                                  child: const Icon(Icons.camera, color: Colors.black),
                                ),
                                const SizedBox(width: 48),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_isProcessing)
                      Container(
                        color: Colors.black54,
                        child: const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(color: Colors.white),
                              SizedBox(height: 12),
                              Text('Analyzing…', style: TextStyle(color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }

  Widget _buildNoCamera() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off, size: 64, color: Colors.white54),
            const SizedBox(height: 16),
            const Text(
              'Camera permission is required to take a photo.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => openAppSettings(),
              child: const Text('Open settings'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CaptureReviewDialog extends StatelessWidget {
  final String filePath;
  final String category;
  final ClassifierResult? result;
  final String? webBase64;

  const _CaptureReviewDialog({
    required this.filePath,
    required this.category,
    this.result,
    this.webBase64,
  });

  Widget _buildImage() {
    if (kIsWeb && webBase64 != null && webBase64!.isNotEmpty) {
      return Image.memory(
        base64Decode(webBase64!),
        height: 180,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 64),
      );
    }
    return Image.file(
      File(filePath),
      height: 180,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 64),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('$category review'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _buildImage(),
              ),
              const SizedBox(height: 16),
              if (result == null || result!.topClass.isEmpty)
                Text(
                  'Could not analyze the image.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleSmall,
                )
              else if (category.toLowerCase() == 'tongue')
                TongueResultSummary(result: result!)
              else
                ClassifierResultSummary(result: result!, category: category),
              const SizedBox(height: 8),
              const Text(
                'This is an estimate, not a diagnosis.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Retake'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Use this photo'),
        ),
      ],
    );
  }
}
