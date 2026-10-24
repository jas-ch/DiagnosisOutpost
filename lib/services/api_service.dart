import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/classifier_result.dart';
import '../models/live_stats.dart';
import '../models/outbreak_snapshot.dart';

/// Service for calling the Diagnosis Outpost backend API.
///
/// Fetches outbreak snapshots and keeps a lightweight offline cache in
/// SharedPreferences so the map still works when the device is offline.
///
/// Uses the cross-platform `http` package so the same code runs on Android,
/// iOS, and Web.
class ApiService {
  /// Base URL for the Diagnosis Outpost backend.
  ///
  /// Release builds default to the production Cloud Run service so a missing
  /// `--dart-define` cannot silently break the deployed app. Local debug builds
  /// and tests still default to `http://localhost:8000`; pass
  /// `--dart-define=API_BASE_URL=...` to override either case.
  static String baseUrl = const String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: kReleaseMode
        ? 'https://diagnosis-odyssey-backend-707085896717.us-central1.run.app'
        : 'http://localhost:8000',
  );
  static const _cacheKey = 'api_cache_outbreaks';
  static const _cacheTimestampKey = 'api_cache_outbreaks_ts';

  /// Fetch outbreaks from the backend. Returns cached data on network failure.
  ///
  /// [client] is used only by tests to inject a mock `http.Client`.
  static Future<List<OutbreakSnapshot>> fetchOutbreaks({
    String? region,
    String? country,
    String? state,
    String? county,
    String? city,
    String? conditionName,
    String? source,
    int limit = 500,
    http.Client? client,
  }) async {
    final query = <String, String>{
      if (region != null) 'region': region,
      if (country != null) 'country': country,
      if (state != null) 'state': state,
      if (county != null) 'county': county,
      if (city != null) 'city': city,
      if (conditionName != null) 'condition_name': conditionName,
      if (source != null) 'source': source,
      'limit': limit.toString(),
    };

    final uri = Uri.parse('$baseUrl/outbreaks').replace(queryParameters: query);

    try {
      final httpClient = client ?? http.Client();
      final response = await httpClient
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final List<dynamic> decoded = jsonDecode(response.body) as List<dynamic>;
      final snapshots = decoded
          .map((e) => OutbreakSnapshot.fromJson(e as Map<String, dynamic>))
          .toList();

      await _cacheSnapshots(snapshots);
      return snapshots;
    } catch (_) {
      return _loadCachedOutbreaks();
    }
  }

  /// Fetch recent snapshots across all sources in a single request.
  /// This is the mobile-friendly replacement for firing one request per source.
  static Future<List<OutbreakSnapshot>> fetchRecentOutbreaks({
    int days = 90,
    int limit = 1000,
    http.Client? client,
  }) async {
    final uri = Uri.parse('$baseUrl/outbreaks/recent').replace(
      queryParameters: {
        'days': days.toString(),
        'limit': limit.toString(),
      },
    );

    try {
      final httpClient = client ?? http.Client();
      final response = await httpClient
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final List<dynamic> decoded = jsonDecode(response.body) as List<dynamic>;
      final snapshots = decoded
          .map((e) => OutbreakSnapshot.fromJson(e as Map<String, dynamic>))
          .toList();

      await _cacheSnapshots(snapshots);
      return snapshots;
    } catch (_) {
      return _loadCachedOutbreaks();
    }
  }

  static const _cacheKeyAggregate = 'api_cache_aggregate';
  static const _cacheTimestampKeyAggregate = 'api_cache_aggregate_ts';

  /// Fetch pre-aggregated US/global stats for all tracked diseases.
  static Future<OutbreakAggregate> fetchAggregate({http.Client? client}) async {
    final uri = Uri.parse('$baseUrl/outbreaks/aggregate');

    try {
      final httpClient = client ?? http.Client();
      final response = await httpClient
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final aggregate = OutbreakAggregate.fromJson(decoded);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKeyAggregate, response.body);
      await prefs.setInt(
        _cacheTimestampKeyAggregate,
        DateTime.now().millisecondsSinceEpoch,
      );

      return aggregate;
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKeyAggregate);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        return OutbreakAggregate.fromJson(decoded);
      }
      return const OutbreakAggregate();
    }
  }

  /// Classify an image on the backend (used by web where TFLite is unavailable).
  /// Media is processed in memory and not persisted by the backend.
  ///
  /// On web [fileBytes] should be provided because browser file paths are
  /// temporary blob URLs and `MultipartFile.fromPath` does not work.
  static Future<ClassifierResult> classifyImage(
    String task,
    String filePath, {
    List<int>? fileBytes,
    http.Client? client,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/classify/$task'),
    );
    final filename = filePath.split('/').last;
    if (fileBytes != null) {
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        fileBytes,
        filename: filename,
      ));
    } else {
      final file = File(filePath);
      request.files.add(await http.MultipartFile.fromPath(
        'file',
        file.path,
        filename: filename,
      ));
    }

    final httpClient = client ?? http.Client();
    final streamedResponse = await httpClient.send(request).timeout(const Duration(seconds: 30));
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw Exception('Classification failed: HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final result = decoded['result'] as Map<String, dynamic>;
    return _parseClassifierResult(task, result);
  }

  /// Classify a cough audio file on the backend (used by web).
  ///
  /// On web [fileBytes] should be provided because browser file paths are
  /// temporary blob URLs and `MultipartFile.fromPath` does not work.
  static Future<ClassifierResult> classifyCough(
    String filePath, {
    List<int>? fileBytes,
    http.Client? client,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/classify/cough'),
    );
    final filename = filePath.split('/').last;
    if (fileBytes != null) {
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        fileBytes,
        filename: filename,
      ));
    } else {
      final file = File(filePath);
      request.files.add(await http.MultipartFile.fromPath(
        'file',
        file.path,
        filename: filename,
      ));
    }

    final httpClient = client ?? http.Client();
    final streamedResponse = await httpClient.send(request).timeout(const Duration(seconds: 30));
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw Exception('Classification failed: HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final result = decoded['result'] as Map<String, dynamic>;
    return _parseClassifierResult('cough', result);
  }

  static ClassifierResult _parseClassifierResult(String task, Map<String, dynamic> result) {
    final probs = (result['probabilities'] as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, (v as num).toDouble()));
    return ClassifierResult(
      task: task,
      probabilities: probs,
      topClass: result['topClass']?.toString() ?? '',
      topConfidence: (result['topConfidence'] as num?)?.toDouble() ?? 0,
      timestamp: DateTime.now(),
    );
  }

  /// Fetch raw outbreak snapshots without model conversion.
  static Future<List<Map<String, dynamic>>> fetchOutbreaksRaw({
    String? region,
    String? country,
    String? state,
    String? county,
    String? city,
    String? conditionName,
    String? source,
    int limit = 500,
  }) async {
    final snapshots = await fetchOutbreaks(
      region: region,
      country: country,
      state: state,
      county: county,
      city: city,
      conditionName: conditionName,
      source: source,
      limit: limit,
    );
    return snapshots.map((s) => s.toJson()).toList();
  }

  static Future<void> _cacheSnapshots(List<OutbreakSnapshot> snapshots) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(snapshots.map((s) => s.toJson()).toList());
    await prefs.setString(_cacheKey, encoded);
    await prefs.setInt(_cacheTimestampKey, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<List<OutbreakSnapshot>> _loadCachedOutbreaks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => OutbreakSnapshot.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Returns true if a non-empty cache exists.
  static Future<bool> hasCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    return raw != null && raw.isNotEmpty && raw != '[]';
  }

  /// Age of the current cache, or null if no cache exists.
  static Future<Duration?> cacheAge() async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getInt(_cacheTimestampKey);
    if (ts == null) return null;
    return DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(ts),
    );
  }

  /// Clear the outbreak cache.
  static Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
    await prefs.remove(_cacheTimestampKey);
  }

  /// Post an anonymized heartbeat for the given session token.
  /// Failures are silently ignored so the UI never blocks on this.
  static Future<void> sendHeartbeat(String token, {http.Client? client}) async {
    try {
      final httpClient = client ?? http.Client();
      await httpClient
          .post(
            Uri.parse('$baseUrl/heartbeat'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'token': token}),
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Best-effort: do not surface heartbeat errors to the user.
    }
  }

  /// Fetch the approximate number of active users in the backend window.
  /// Returns 0 on any failure so the UI degrades gracefully.
  static Future<int> fetchOnlineCount({http.Client? client}) async {
    try {
      final httpClient = client ?? http.Client();
      final response = await httpClient
          .get(Uri.parse('$baseUrl/online'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return 0;
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return (decoded['count'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }
}
