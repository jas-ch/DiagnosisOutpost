import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/capture_storage_service.dart';
import '../../widgets/classifier_result_summary.dart';
import 'camera_screen.dart';

class PhotoCategoryScreen extends StatefulWidget {
  const PhotoCategoryScreen({super.key});

  @override
  State<PhotoCategoryScreen> createState() => _PhotoCategoryScreenState();
}

class _PhotoCategoryScreenState extends State<PhotoCategoryScreen> {
  final List<_Category> _categories = const [
    _Category('Rash', Icons.texture, Colors.red, true),
    _Category('Wounds', Icons.healing, Colors.orange, true),
    _Category('Selfie', Icons.face, Colors.blue, false),
    _Category('Tongue', Icons.circle, Colors.pink, false),
  ];
  int _selectedIndex = 0;
  final Map<String, CaptureRecord> _records = {};
  PhotoCaptureResult? _lastCaptureResult;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    final records = await CaptureStorageService.loadAll();
    if (!mounted) return;
    final map = <String, CaptureRecord>{};
    for (final r in records) {
      map[r.category.toLowerCase()] = r;
    }
    setState(() => _records.addAll(map));
  }

  Future<void> _takePhoto(_Category category) async {
    final result = await Navigator.push<PhotoCaptureResult>(
      context,
      MaterialPageRoute(
        builder: (_) => CameraScreen(
          useRearCamera: category.useRearCamera,
          title: category.name,
          category: category.name.toLowerCase(),
        ),
      ),
    );
    if (!mounted) return;
    if (result != null) {
      _lastCaptureResult = result;
      await _loadRecords();
      // Keep the user on this screen so they can review the updated capture.
      setState(() {});
    }
  }

  Future<void> _reviewRecent(_Category category) async {
    final record = _records[category.name.toLowerCase()];
    if (record == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PhotoReviewScreen(record: record, category: category.name),
      ),
    );
  }

  Future<void> _deleteRecent(_Category category) async {
    final key = category.name.toLowerCase();
    final record = _records[key];
    if (record == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear recent capture?'),
        content: Text('Remove the most recent ${category.name.toLowerCase()} photo and its analysis.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await CaptureStorageService.deleteForCategory(key);
    setState(() => _records.remove(key));
  }

  Widget _buildImage(CaptureRecord record, {double? height, BoxFit fit = BoxFit.cover}) {
    if (kIsWeb && record.webBase64 != null && record.webBase64!.isNotEmpty) {
      return Image.memory(
        base64Decode(record.webBase64!),
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 64),
      );
    }
    return Image.file(
      File(record.filePath),
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 64),
    );
  }

  String _formatTimestamp(DateTime dt) {
    return '${DateFormat.yMMMd().add_jm().format(dt)} (${dt.timeZoneName})';
  }

  @override
  Widget build(BuildContext context) {
    final category = _categories[_selectedIndex];
    final record = _records[category.name.toLowerCase()];
    final result = record?.result;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose photo type'),
        leading: BackButton(
          onPressed: () => Navigator.pop(context, _lastCaptureResult),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Category selector
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: _categories.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final cat = entry.value;
                  final selected = idx == _selectedIndex;
                  return InkWell(
                    onTap: () => setState(() => _selectedIndex = idx),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: 72,
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                      decoration: BoxDecoration(
                        color: selected ? cat.color.withValues(alpha: 0.15) : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: selected ? cat.color : Colors.grey.shade300,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(cat.icon, color: cat.color, size: 32),
                          const SizedBox(height: 6),
                          Text(
                            cat.name,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                              color: selected ? cat.color : Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              // Description
              Text(
                _descriptionFor(category.name),
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              ),
              const SizedBox(height: 20),
              // Most recent capture
              if (record != null) ...[
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Most recent ${category.name}',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              _formatTimestamp(record.timestamp),
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: _buildImage(record, height: 180),
                        ),
                        const SizedBox(height: 12),
                        if (result != null && result.topClass.isNotEmpty)
                          category.name.toLowerCase() == 'tongue'
                              ? TonguePhotoDetail(result: result)
                              : ClassifierResultSummary(result: result, category: category.name.toLowerCase())
                        else
                          const Text('No analysis available for this capture.'),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _reviewRecent(category),
                                icon: const Icon(Icons.zoom_in),
                                label: const Text('View recent photo'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: () => _deleteRecent(category),
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'Clear recent ${category.name}',
                              color: Colors.red.shade400,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              // Take photo button
              FilledButton.icon(
                onPressed: () => _takePhoto(category),
                icon: const Icon(Icons.camera_alt),
                label: Text(record == null ? 'Take ${category.name} photo' : 'Take new ${category.name} photo'),
                style: FilledButton.styleFrom(
                  backgroundColor: category.color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _descriptionFor(String name) {
    return switch (name) {
      'Rash' => 'Capture a rash photo to check for measles-like, chickenpox-like, or other outbreak-related patterns.',
      'Wounds' => 'Capture a wound or skin break to check for infection risk.',
      'Selfie' => 'Capture a face photo to check for eye discharge or other facial signs.',
      'Tongue' => 'Capture a tongue photo for tongue attribute analysis and wellness suggestions.',
      _ => '',
    };
  }
}

class _PhotoReviewScreen extends StatelessWidget {
  final CaptureRecord record;
  final String category;

  const _PhotoReviewScreen({required this.record, required this.category});

  Widget _buildImage(BuildContext context) {
    if (kIsWeb && record.webBase64 != null && record.webBase64!.isNotEmpty) {
      return InteractiveViewer(
        minScale: 0.5,
        maxScale: 5.0,
        child: Image.memory(
          base64Decode(record.webBase64!),
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 64),
        ),
      );
    }
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 5.0,
      child: Image.file(
        File(record.filePath),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 64),
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    return '${DateFormat.yMMMd().add_jm().format(dt)} (${dt.timeZoneName})';
  }

  @override
  Widget build(BuildContext context) {
    final result = record.result;
    return Scaffold(
      appBar: AppBar(
        title: Text('Recent $category'),
        leading: const BackButton(),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _buildImage(context),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatTimestamp(record.timestamp),
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (result != null && result.topClass.isNotEmpty)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: SingleChildScrollView(
                        child: category.toLowerCase() == 'tongue'
                            ? TonguePhotoDetail(result: result)
                            : ClassifierResultSummary(result: result, category: category.toLowerCase()),
                      ),
                    )
                  else
                    const Text('No analysis available.'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Category {
  final String name;
  final IconData icon;
  final Color color;
  final bool useRearCamera;

  const _Category(this.name, this.icon, this.color, this.useRearCamera);
}
