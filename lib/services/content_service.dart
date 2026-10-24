import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';

import '../models/outbreak_intel.dart';

class ContentService {
  static List<OutbreakIntel>? _cache;

  static Future<List<OutbreakIntel>> loadOutbreakIntel() async {
    if (_cache != null) return _cache!;

    final raw = await rootBundle.loadString('assets/content/outbreak_intel.yaml');
    final yaml = loadYaml(raw) as Map<dynamic, dynamic>;
    final list = yaml['outbreak_intel'] as List<dynamic>;

    _cache = list
        .map((item) => OutbreakIntel.fromMap(item as Map<dynamic, dynamic>))
        .toList();

    return _cache!;
  }

  static Future<OutbreakIntel?> findById(String id) async {
    final all = await loadOutbreakIntel();
    try {
      return all.firstWhere((item) => item.id == id);
    } catch (_) {
      return null;
    }
  }
}
