/// A normalized outbreak snapshot returned by the backend `/outbreaks` endpoint.
class OutbreakSnapshot {
  final int id;
  final String source;
  final String sourceId;

  final String? country;
  final String? state;
  final String? county;
  final String? city;
  final String? site;

  final String? regionType;
  final String? regionCode;
  final String? region;

  final String? conditionName;
  final int? caseCount;
  final String? metricName;
  final double? metricValue;
  final String? metricValueText;

  final DateTime? reportDate;
  final Map<String, dynamic>? metadataJson;

  final DateTime updatedAt;
  final DateTime createdAt;

  const OutbreakSnapshot({
    required this.id,
    required this.source,
    required this.sourceId,
    this.country,
    this.state,
    this.county,
    this.city,
    this.site,
    this.regionType,
    this.regionCode,
    this.region,
    this.conditionName,
    this.caseCount,
    this.metricName,
    this.metricValue,
    this.metricValueText,
    this.reportDate,
    this.metadataJson,
    required this.updatedAt,
    required this.createdAt,
  });

  factory OutbreakSnapshot.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic value) {
      final s = value?.toString();
      if (s == null || s.isEmpty) return null;
      return DateTime.tryParse(s);
    }

    double? parseDouble(dynamic value) {
      if (value == null) return null;
      if (value is double) return value;
      if (value is int) return value.toDouble();
      return double.tryParse(value.toString());
    }

    int? parseInt(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is double) return value.toInt();
      return int.tryParse(value.toString());
    }

    return OutbreakSnapshot(
      id: parseInt(json['id']) ?? 0,
      source: json['source']?.toString() ?? '',
      sourceId: json['source_id']?.toString() ?? '',
      country: json['country']?.toString(),
      state: json['state']?.toString(),
      county: json['county']?.toString(),
      city: json['city']?.toString(),
      site: json['site']?.toString(),
      regionType: json['region_type']?.toString(),
      regionCode: json['region_code']?.toString(),
      region: json['region']?.toString(),
      conditionName: json['condition_name']?.toString(),
      caseCount: parseInt(json['case_count']),
      metricName: json['metric_name']?.toString(),
      metricValue: parseDouble(json['metric_value']),
      metricValueText: json['metric_value_text']?.toString(),
      reportDate: parseDate(json['report_date']),
      metadataJson: json['metadata_json'] is Map<String, dynamic>
          ? json['metadata_json'] as Map<String, dynamic>
          : null,
      updatedAt: parseDate(json['updated_at']) ?? DateTime.now(),
      createdAt: parseDate(json['created_at']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'source': source,
      'source_id': sourceId,
      'country': country,
      'state': state,
      'county': county,
      'city': city,
      'site': site,
      'region_type': regionType,
      'region_code': regionCode,
      'region': region,
      'condition_name': conditionName,
      'case_count': caseCount,
      'metric_name': metricName,
      'metric_value': metricValue,
      'metric_value_text': metricValueText,
      'report_date': reportDate?.toIso8601String(),
      'metadata_json': metadataJson,
      'updated_at': updatedAt.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Best display label for the geographic region covered by this snapshot.
  String get displayLocation {
    return city ?? county ?? state ?? region ?? country ?? 'Unknown';
  }

  /// Best numeric value to show for this snapshot.
  String get displayValue {
    if (metricValue != null) {
      return metricValueText ?? metricValue!.toStringAsFixed(1);
    }
    if (caseCount != null) return caseCount.toString();
    if (metricValueText != null && metricValueText!.isNotEmpty) {
      return metricValueText!;
    }
    return '—';
  }
}
