import 'dart:async';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

/// Manages an anonymized session token and periodic heartbeat so the app can
/// display a real-time online-user count without collecting any PII.
class OnlineUsersService {
  static const _tokenKey = 'online_session_token';
  static Timer? _heartbeatTimer;

  /// Generate or load a random session token stored only on the device.
  static Future<String> _getOrCreateToken() async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString(_tokenKey);
    if (token == null || token.isEmpty) {
      token = _generateToken();
      await prefs.setString(_tokenKey, token);
    }
    return token;
  }

  static String _generateToken() {
    final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Start sending a heartbeat every [interval]. Safe to call multiple times.
  static Future<void> startHeartbeat({Duration interval = const Duration(seconds: 60)}) async {
    _heartbeatTimer?.cancel();
    final token = await _getOrCreateToken();
    await ApiService.sendHeartbeat(token);
    _heartbeatTimer = Timer.periodic(interval, (_) async {
      await ApiService.sendHeartbeat(await _getOrCreateToken());
    });
  }

  /// Stop the periodic heartbeat.
  static void stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Fetch the current approximate online-user count from the backend.
  static Future<int> fetchCount() => ApiService.fetchOnlineCount();
}
