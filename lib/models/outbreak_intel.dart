int _toInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is double) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}

double _toDouble(dynamic value) {
  if (value == null) return 0.0;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0.0;
}

List<String> _toStringList(dynamic value) {
  if (value is List) {
    return value.map((e) => e.toString()).toList();
  }
  return [];
}

class OutbreakIntelStats {
  final String r0;
  final String incubationDays;
  final String severity;
  final String transmissionRoute;
  final bool vaccineAvailable;

  const OutbreakIntelStats({
    required this.r0,
    required this.incubationDays,
    required this.severity,
    required this.transmissionRoute,
    required this.vaccineAvailable,
  });

  factory OutbreakIntelStats.fromMap(Map<dynamic, dynamic> map) {
    return OutbreakIntelStats(
      r0: map['r0']?.toString() ?? '',
      incubationDays: map['incubationDays']?.toString() ?? '',
      severity: map['severity']?.toString() ?? '',
      transmissionRoute: map['transmissionRoute']?.toString() ?? '',
      vaccineAvailable: map['vaccineAvailable'] == true,
    );
  }
}

class Citation {
  final String text;
  final String url;

  const Citation({required this.text, required this.url});

  factory Citation.fromMap(Map<dynamic, dynamic> map) {
    return Citation(
      text: map['text']?.toString() ?? '',
      url: map['url']?.toString() ?? '',
    );
  }
}

/// Snapshot of national-level numbers shown on compact cards and dashboards.
class NationalStats {
  final int infectants;
  final String mortalityRate;
  final String infectionRate;
  final int recovered;

  const NationalStats({
    required this.infectants,
    required this.mortalityRate,
    required this.infectionRate,
    required this.recovered,
  });

  factory NationalStats.fromMap(Map<dynamic, dynamic> map) {
    return NationalStats(
      infectants: _toInt(map['infectants']),
      mortalityRate: map['mortalityRate']?.toString() ?? '',
      infectionRate: map['infectionRate']?.toString() ?? '',
      recovered: _toInt(map['recovered']),
    );
  }
}

/// Clinical details shown on the Outbreak Intel detail screen.
class ClinicalProfile {
  final String hiddenPeriodDays;
  final String variants;
  final String severity;

  const ClinicalProfile({
    required this.hiddenPeriodDays,
    required this.variants,
    required this.severity,
  });

  factory ClinicalProfile.fromMap(Map<dynamic, dynamic> map) {
    return ClinicalProfile(
      hiddenPeriodDays: map['hiddenPeriodDays']?.toString() ?? '',
      variants: map['variants']?.toString() ?? '',
      severity: map['severity']?.toString() ?? '',
    );
  }
}

/// A city-level outbreak used to render map balloons and heat layers.
class CityOutbreak {
  final String city;
  final double lat;
  final double lng;
  final int activeInfectants;
  final int recovered;

  const CityOutbreak({
    required this.city,
    required this.lat,
    required this.lng,
    required this.activeInfectants,
    required this.recovered,
  });

  factory CityOutbreak.fromMap(Map<dynamic, dynamic> map) {
    return CityOutbreak(
      city: map['city']?.toString() ?? '',
      lat: _toDouble(map['lat']),
      lng: _toDouble(map['lng']),
      activeInfectants: _toInt(map['activeInfectants']),
      recovered: _toInt(map['recovered']),
    );
  }
}

class OutbreakIntel {
  final String id;
  final String name;
  final String commonName;
  final String rarity;
  final String category;
  final String heroImage;
  final String model3d;
  final String molecularFormula;
  final String model3dSource;
  final String pdbId;
  final String molecularStructure;
  final String molecularImage;
  final String description;
  final OutbreakIntelStats stats;
  final NationalStats nationalStats;
  final ClinicalProfile clinicalProfile;
  final List<String> transmissionMedia;
  final List<CityOutbreak> cityOutbreaks;
  final List<String> symptoms;
  final List<String> actions;
  final List<Citation> citations;
  final String unlockCondition;

  const OutbreakIntel({
    required this.id,
    required this.name,
    required this.commonName,
    required this.rarity,
    required this.category,
    required this.heroImage,
    required this.model3d,
    required this.molecularFormula,
    required this.model3dSource,
    required this.pdbId,
    required this.molecularStructure,
    required this.molecularImage,
    required this.description,
    required this.stats,
    required this.nationalStats,
    required this.clinicalProfile,
    required this.transmissionMedia,
    required this.cityOutbreaks,
    required this.symptoms,
    required this.actions,
    required this.citations,
    required this.unlockCondition,
  });

  factory OutbreakIntel.fromMap(Map<dynamic, dynamic> map) {
    return OutbreakIntel(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      commonName: map['commonName']?.toString() ?? '',
      rarity: map['rarity']?.toString() ?? 'common',
      category: map['category']?.toString() ?? '',
      heroImage: map['heroImage']?.toString() ?? '',
      model3d: map['model3d']?.toString() ?? '',
      molecularFormula: map['molecularFormula']?.toString() ?? '',
      model3dSource: map['model3dSource']?.toString() ?? '',
      pdbId: map['pdbId']?.toString() ?? '',
      molecularStructure: map['molecularStructure']?.toString() ?? '',
      molecularImage: map['molecularImage']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      stats: OutbreakIntelStats.fromMap(map['stats'] ?? {}),
      nationalStats: NationalStats.fromMap(map['nationalStats'] ?? {}),
      clinicalProfile: ClinicalProfile.fromMap(map['clinicalProfile'] ?? {}),
      transmissionMedia: _toStringList(map['transmissionMedia']),
      cityOutbreaks: (map['cityOutbreaks'] as List<dynamic>? ?? [])
          .map((e) => CityOutbreak.fromMap(e as Map<dynamic, dynamic>))
          .toList(),
      symptoms: _toStringList(map['symptoms']),
      actions: _toStringList(map['actions']),
      citations: (map['citations'] as List<dynamic>? ?? [])
          .map((e) => Citation.fromMap(e as Map<dynamic, dynamic>))
          .toList(),
      unlockCondition: map['unlockCondition']?.toString() ?? '',
    );
  }
}
