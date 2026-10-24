import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:diagnosis_odyssey/models/outbreak_snapshot.dart';
import 'package:diagnosis_odyssey/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ApiService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('hasCache returns false when no cache exists', () async {
      final hasCache = await ApiService.hasCache();
      expect(hasCache, isFalse);
    });

    test('fetchOutbreaks returns empty list on network failure with no cache', () async {
      final snapshots = await ApiService.fetchOutbreaks(limit: 5);
      expect(snapshots, isEmpty);
    });

    test('fetchOutbreaks falls back to cached snapshots on network failure', () async {
      final prefs = await SharedPreferences.getInstance();
      final cached = [
        OutbreakSnapshot(
          id: 1,
          source: 'test',
          sourceId: 'test:1',
          conditionName: 'Influenza A',
          state: 'California',
          updatedAt: DateTime(2026, 9, 22),
          createdAt: DateTime(2026, 9, 22),
        ).toJson(),
      ];
      await prefs.setString('api_cache_outbreaks', jsonEncode(cached));
      await prefs.setInt('api_cache_outbreaks_ts', DateTime.now().millisecondsSinceEpoch);

      final snapshots = await ApiService.fetchOutbreaks(limit: 5);
      expect(snapshots, hasLength(1));
      expect(snapshots.first.conditionName, 'Influenza A');
    });

    test('clearCache removes cached data', () async {
      final prefs = await SharedPreferences.getInstance();
      final cached = [
        OutbreakSnapshot(
          id: 1,
          source: 'test',
          sourceId: 'test:1',
          conditionName: 'Influenza A',
          updatedAt: DateTime(2026, 9, 22),
          createdAt: DateTime(2026, 9, 22),
        ).toJson(),
      ];
      await prefs.setString('api_cache_outbreaks', jsonEncode(cached));
      await prefs.setInt('api_cache_outbreaks_ts', DateTime.now().millisecondsSinceEpoch);

      expect(await ApiService.hasCache(), isTrue);
      await ApiService.clearCache();
      expect(await ApiService.hasCache(), isFalse);
    });

    test('fetchOutbreaks parses snapshots via injected http client', () async {
      final snapshot = OutbreakSnapshot(
        id: 1,
        source: 'test',
        sourceId: 'test:1',
        conditionName: 'Influenza A',
        state: 'California',
        updatedAt: DateTime(2026, 9, 22),
        createdAt: DateTime(2026, 9, 22),
      );

      final client = MockClient((request) async {
        expect(request.url.path, '/outbreaks');
        return http.Response(
          jsonEncode([snapshot.toJson()]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final snapshots = await ApiService.fetchOutbreaks(
        limit: 5,
        client: client,
      );

      expect(snapshots, hasLength(1));
      expect(snapshots.first.conditionName, 'Influenza A');
      expect(await ApiService.hasCache(), isTrue);
    });
  });
}
