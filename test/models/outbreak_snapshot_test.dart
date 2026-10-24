import 'package:flutter_test/flutter_test.dart';

import 'package:diagnosis_odyssey/models/outbreak_snapshot.dart';

void main() {
  group('OutbreakSnapshot.fromJson', () {
    test('parses a full backend snapshot', () {
      final json = {
        'id': 42,
        'source': 'cdc_wastewater',
        'source_id': 'cdc_wastewater:CA:Alameda:ID_1:SARS-CoV-2:2026-09-01:2026-09-22',
        'country': 'United States',
        'state': 'California',
        'county': 'Alameda',
        'city': null,
        'site': 'ID:1',
        'region_type': 'site',
        'region_code': null,
        'region': 'ID:1',
        'condition_name': 'SARS-CoV-2',
        'case_count': null,
        'metric_name': 'wastewater_level',
        'metric_value': 7.5,
        'metric_value_text': 'Moderate',
        'report_date': '2026-09-22T00:00:00',
        'metadata_json': {'foo': 'bar'},
        'updated_at': '2026-09-22T10:00:00.000',
        'created_at': '2026-09-22T09:00:00.000',
      };

      final snapshot = OutbreakSnapshot.fromJson(json);

      expect(snapshot.id, 42);
      expect(snapshot.source, 'cdc_wastewater');
      expect(snapshot.state, 'California');
      expect(snapshot.metricValue, 7.5);
      expect(snapshot.metricValueText, 'Moderate');
      expect(snapshot.reportDate, DateTime(2026, 9, 22));
      expect(snapshot.displayLocation, 'Alameda');
      expect(snapshot.displayValue, 'Moderate');
    });

    test('handles null fields safely', () {
      final json = {
        'id': 1,
        'source': 'test',
        'source_id': 'test:1',
      };

      final snapshot = OutbreakSnapshot.fromJson(json);

      expect(snapshot.conditionName, isNull);
      expect(snapshot.metricValue, isNull);
      expect(snapshot.reportDate, isNull);
      expect(snapshot.displayLocation, 'Unknown');
      expect(snapshot.displayValue, '—');
    });

    test('round-trips through toJson', () {
      final snapshot = OutbreakSnapshot(
        id: 1,
        source: 'test',
        sourceId: 'test:1',
        conditionName: 'Influenza A',
        metricValue: 12.3,
        updatedAt: DateTime(2026, 9, 22),
        createdAt: DateTime(2026, 9, 22),
      );

      final json = snapshot.toJson();
      expect(json['source'], 'test');
      expect(json['source_id'], 'test:1');
      expect(json['condition_name'], 'Influenza A');
      expect(json['metric_value'], 12.3);
    });
  });
}
