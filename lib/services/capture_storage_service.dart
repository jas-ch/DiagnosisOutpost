import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/classifier_result.dart';

/// A persisted user capture (photo or audio) with its classifier result.
class CaptureRecord {
  final String category;
  final String filePath;
  final DateTime timestamp;
  final ClassifierResult? result;

  /// Base64-encoded file bytes, used on web where path_provider file storage
  /// is not available. Empty on mobile.
  final String? webBase64;

  CaptureRecord({
    required this.category,
    required this.filePath,
    required this.timestamp,
    this.result,
    this.webBase64,
  });

  Map<String, dynamic> toMap() {
    return {
      'category': category,
      'filePath': filePath,
      'timestamp': timestamp.toIso8601String(),
      'result': result?.toMap(),
      'webBase64': webBase64,
    };
  }

  factory CaptureRecord.fromMap(Map<String, dynamic> map) {
    return CaptureRecord(
      category: map['category']?.toString() ?? '',
      filePath: map['filePath']?.toString() ?? '',
      timestamp: DateTime.tryParse(map['timestamp']?.toString() ?? '') ?? DateTime.now(),
      result: map['result'] != null
          ? ClassifierResult.fromMap(map['result'] as Map<String, dynamic>)
          : null,
      webBase64: map['webBase64']?.toString(),
    );
  }
}

/// Local persistence for the most recent capture per category.
class CaptureStorageService {
  static const _key = 'capture_records_v1';

  static Future<List<CaptureRecord>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_key);
    if (jsonString == null || jsonString.isEmpty) return [];
    try {
      final list = jsonDecode(jsonString) as List<dynamic>;
      return list
          .map((e) => CaptureRecord.fromMap(e as Map<String, dynamic>))
          .where((r) => kIsWeb || r.webBase64 != null || File(r.filePath).existsSync())
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<CaptureRecord?> loadForCategory(String category) async {
    final all = await loadAll();
    try {
      return all.lastWhere((r) => r.category == category);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(CaptureRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await loadAll();
    all.removeWhere((r) => r.category == record.category);
    all.add(record);
    // Keep only the latest entry per category to avoid unbounded growth.
    final latestByCategory = <String, CaptureRecord>{};
    for (final r in all) {
      latestByCategory[r.category] = r;
    }
    final encoded = jsonEncode(latestByCategory.values.map((r) => r.toMap()).toList());
    await prefs.setString(_key, encoded);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// Delete the most recent capture for [category] and remove its persisted
  /// file (on mobile). Returns true if a record was removed.
  static Future<bool> deleteForCategory(String category) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await loadAll();
    final before = all.length;
    CaptureRecord? removedRecord;
    all.removeWhere((r) {
      final match = r.category.toLowerCase() == category.toLowerCase();
      if (match) removedRecord = r;
      return match;
    });
    final removed = before > all.length;
    if (removed) {
      final encoded = jsonEncode(all.map((r) => r.toMap()).toList());
      await prefs.setString(_key, encoded);
      if (!kIsWeb && removedRecord != null) {
        try {
          final file = File(removedRecord!.filePath);
          if (await file.exists()) await file.delete();
        } catch (e, st) {
          debugPrint('CaptureStorageService: could not delete file: $e\n$st');
        }
      }
    }
    return removed;
  }

  /// Returns a stable local path for mobile, or the original path for web.
  /// On web the caller should store base64 bytes separately if persistence is
  /// needed, because browser file paths are temporary.
  static Future<String> persistentPath(String originalPath, String category) async {
    if (kIsWeb) return originalPath;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}/captures/$category');
      await folder.create(recursive: true);
      final segments = originalPath.split('.');
      final ext = segments.length > 1 ? segments.last : 'bin';
      final name = '${DateTime.now().millisecondsSinceEpoch}.$ext';
      final dest = '${folder.path}/$name';
      final source = File(originalPath);
      if (await source.exists()) {
        await source.copy(dest);
        return dest;
      }
    } catch (e, st) {
      debugPrint('CaptureStorageService: could not persist file: $e\n$st');
    }
    // Fallback: return the original path so the UI can still use it.
    return originalPath;
  }

  /// Read a file and return base64-encoded bytes for web persistence.
  static Future<String> fileToBase64(String path) async {
    final bytes = await File(path).readAsBytes();
    return base64Encode(bytes);
  }
}
