import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:diagnosis_odyssey/models/outbreak_snapshot.dart';
import 'package:diagnosis_odyssey/services/api_service.dart';

void main() {
  HttpServer? server;
  var originalBaseUrl = '';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.clearCache();

    originalBaseUrl = ApiService.baseUrl;
    server = await HttpServer.bind('127.0.0.1', 0);
    ApiService.baseUrl = 'http://127.0.0.1:${server!.port}';
  });

  tearDown(() async {
    ApiService.baseUrl = originalBaseUrl;
    await server?.close();
    await ApiService.clearCache();
  });

  test('fetchOutbreaks parses snapshots from a real HTTP response', () async {
    final snapshot = OutbreakSnapshot(
      id: 1,
      source: 'cdc_nndss',
      sourceId: 'cdc_ca_flu_2024_01',
      country: 'United States',
      state: 'California',
      conditionName: 'influenza_a',
      metricName: 'cases',
      metricValue: 1247,
      reportDate: DateTime(2024, 1, 15),
      metadataJson: {},
      updatedAt: DateTime.now(),
      createdAt: DateTime.now(),
    );

    server!.listen((request) {
      expect(request.uri.path, '/outbreaks');
      expect(request.uri.queryParameters['limit'], '100');
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode([snapshot.toJson()]))
        ..close();
    });

    final results = await ApiService.fetchOutbreaks(limit: 100);

    expect(results, hasLength(1));
    expect(results.first.source, 'cdc_nndss');
    expect(results.first.state, 'California');
    expect(results.first.metricValue, 1247);

    // A successful fetch should also have cached the result.
    expect(await ApiService.hasCache(), isTrue);
  });

  test('fetchOutbreaks falls back to cache on server error', () async {
    server!.listen((request) {
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..close();
    });

    // Seed the cache directly.
    final cached = OutbreakSnapshot(
      id: 2,
      source: 'cached',
      sourceId: 'cached_1',
      conditionName: 'covid_19',
      metricName: 'cases',
      metricValue: 99,
      reportDate: DateTime(2024, 1, 10),
      metadataJson: {},
      updatedAt: DateTime.now(),
      createdAt: DateTime.now(),
    );
    await ApiService.clearCache();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'api_cache_outbreaks',
      jsonEncode([cached.toJson()]),
    );

    final results = await ApiService.fetchOutbreaks();

    expect(results, hasLength(1));
    expect(results.first.source, 'cached');
  });
}
