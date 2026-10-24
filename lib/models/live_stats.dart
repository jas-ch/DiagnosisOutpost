/// Live aggregated statistics for a single outbreak disease.
class LiveStats {
  final num? weeklyNew;
  final String weeklyNewLabel;
  final num? ytd;
  final String ytdLabel;
  final num? weeklyChange;
  final String weeklyChangeLabel;
  final bool isAdmissions;
  final String source;
  final List<String> sources;
  final String? reportDate;

  const LiveStats({
    this.weeklyNew,
    required this.weeklyNewLabel,
    this.ytd,
    required this.ytdLabel,
    this.weeklyChange,
    required this.weeklyChangeLabel,
    this.isAdmissions = false,
    required this.source,
    this.sources = const [],
    this.reportDate,
  });

  factory LiveStats.fromJson(Map<String, dynamic> json) {
    return LiveStats(
      weeklyNew: _toOptionalNum(json['weekly_new']),
      weeklyNewLabel: json['weekly_new_label']?.toString() ?? 'weekly',
      ytd: _toOptionalNum(json['ytd']),
      ytdLabel: json['ytd_label']?.toString() ?? 'YTD',
      weeklyChange: _toOptionalNum(json['weekly_change']),
      weeklyChangeLabel: json['weekly_change_label']?.toString() ?? 'change',
      isAdmissions: json['is_admissions'] == true,
      source: json['source']?.toString() ?? '',
      sources: _toStringList(json['sources']),
      reportDate: json['report_date']?.toString(),
    );
  }

  static List<String> _toStringList(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return [];
  }

  static num? _toOptionalNum(dynamic value) {
    if (value == null) return null;
    if (value is num) return value;
    return num.tryParse(value.toString());
  }
}

/// Backend response from GET /outbreaks/aggregate.
class OutbreakAggregate {
  final Map<String, LiveStats?> us;
  final Map<String, LiveStats?> global;

  const OutbreakAggregate({
    this.us = const {},
    this.global = const {},
  });

  factory OutbreakAggregate.fromJson(Map<String, dynamic> json) {
    final diseases = json['diseases'] as Map<String, dynamic>? ?? {};
    final us = <String, LiveStats?>{};
    final global = <String, LiveStats?>{};

    diseases.forEach((condition, value) {
      if (value is! Map<String, dynamic>) return;
      if (value['us'] is Map<String, dynamic>) {
        us[condition] = LiveStats.fromJson(value['us'] as Map<String, dynamic>);
      }
      if (value['global'] is Map<String, dynamic>) {
        global[condition] =
            LiveStats.fromJson(value['global'] as Map<String, dynamic>);
      }
    });

    return OutbreakAggregate(us: us, global: global);
  }
}
