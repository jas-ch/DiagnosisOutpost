import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:diagnosis_odyssey/screens/home_screen.dart';
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

  testWidgets('HomeScreen renders map, carousel, and check button',
      (tester) async {
    server!.listen((request) {
      final path = request.uri.path;
      if (path == '/outbreaks/recent') {
        request.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode([
            {
              'source': 'cdc_measles',
              'source_id': 'cdc_measles:1',
              'condition_name': 'Measles',
              'country': 'United States',
              'state': 'California',
              'region_type': 'state',
              'case_count': 10,
              'report_date': DateTime.now().toIso8601String(),
            },
            {
              'source': 'who_covid_cases',
              'source_id': 'who_covid_cases:1',
              'condition_name': 'COVID-19',
              'country': 'United States',
              'region_type': 'country',
              'metric_name': 'new_cases',
              'metric_value': 100,
              'report_date': DateTime.now().toIso8601String(),
            },
          ]))
          ..close();
      } else if (path == '/outbreaks/aggregate') {
        request.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({
            'aggregated_at': DateTime.now().toIso8601String(),
            'diseases': {
              'Measles': {
                'us': {
                  'weekly_new': 224,
                  'weekly_new_label': 'weekly',
                  'ytd': 4076,
                  'ytd_label': 'YTD',
                  'weekly_change': 84,
                  'weekly_change_label': 'change',
                  'source': 'cdc_measles',
                  'sources': ['cdc_measles'],
                  'report_date': DateTime.now().toIso8601String(),
                },
              },
              'COVID-19': {
                'us': {
                  'weekly_new': 1200,
                  'weekly_new_label': 'weekly',
                  'ytd': 50000,
                  'ytd_label': 'YTD',
                  'weekly_change': -252,
                  'weekly_change_label': 'change',
                  'source': 'who_covid_cases',
                  'sources': ['who_covid_cases'],
                  'report_date': DateTime.now().toIso8601String(),
                },
              },
            },
          }))
          ..close();
      } else {
        request.response
          ..statusCode = HttpStatus.notFound
          ..close();
      }
    });

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

    // Allow local YAML and mock backend fetches to complete.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Outbreak Intel'), findsOneWidget);
    expect(find.text('Check'), findsOneWidget);
    expect(find.byType(FlutterMap), findsOneWidget);

    // Carousel should show live-data-driven disease cards.
    expect(find.text('US'), findsOneWidget);
    expect(find.text('Global'), findsOneWidget);

    // Open the drawer and verify menu items.
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.text('Self-Diagnosis'), findsOneWidget);
    expect(find.text('Diagnosis History'), findsOneWidget);
    expect(find.text('Privacy First'), findsOneWidget);
  });
}
