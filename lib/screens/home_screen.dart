import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/app_info.dart';
import '../data/country_coordinates.dart';
import '../data/state_coordinates.dart';
import '../models/diagnosis_history_entry.dart';
import '../models/live_stats.dart';
import '../models/outbreak_intel.dart';
import '../models/outbreak_snapshot.dart';
import '../models/user_biometrics.dart';
import '../services/api_service.dart';
import '../services/biometrics_service.dart';
import '../services/content_service.dart';
import '../services/diagnosis_history_service.dart';
import '../services/online_users_service.dart';
import '../widgets/biometrics_bar.dart';
import '../widgets/outbreak_intel_compact_card.dart';
import '../widgets/snapshot_bottom_sheet.dart';
import '../widgets/snapshot_map_marker.dart';
import 'diagnosis_history_screen.dart';
import 'outbreak_intel_detail_screen.dart';
import 'self_diagnosis_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<OutbreakIntel> _intelList = [];
  List<OutbreakIntel> _predefinedIntelList = [];
  List<OutbreakSnapshot> _snapshots = [];
  UserBiometrics _biometrics = const UserBiometrics();
  DiagnosisHistoryEntry? _latestHistoryEntry;
  bool _loading = true;
  int _selectedIndex = 0;
  int _onlineCount = 0;
  Timer? _onlineCountTimer;
  Timer? _snapshotRefreshTimer;
  Set<String> _selectedDiseaseIds = {};
  bool _globalMode = false;
  OutbreakAggregate _aggregate = const OutbreakAggregate();
  final MapController _mapController = MapController();
  StreamSubscription? _mapEventSub;
  Timer? _mapEventDebounce;
  double _mapZoom = 4.0;

  // Regression guard: never let the carousel hide most diseases because of a
  // data-source naming mismatch. If fewer than this many predefined diseases
  // are flagged active, fall back to showing all predefined diseases.
  static const _minActivePredefinedDiseases = 3;

  // Sample facility locations around San Diego for the MVP.
  final List<Map<String, dynamic>> _hospitals = const [
    {'name': 'UCSD Medical Center', 'lat': 32.7555, 'lng': -117.0842},
    {'name': 'Scripps Mercy', 'lat': 32.7246, 'lng': -117.1605},
    {'name': 'Sharp Grossmont', 'lat': 32.7795, 'lng': -117.0172},
  ];

  final List<Map<String, dynamic>> _pharmacies = const [
    {'name': 'CVS Pharmacy', 'lat': 32.7157, 'lng': -117.1500},
    {'name': 'Walgreens', 'lat': 32.7057, 'lng': -117.1700},
    {'name': 'Rite Aid', 'lat': 32.7257, 'lng': -117.1400},
  ];

  @override
  void initState() {
    super.initState();
    _load();
    OnlineUsersService.startHeartbeat();
    _refreshOnlineCount();
    _onlineCountTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _refreshOnlineCount(),
    );
    // Refresh outbreak snapshots periodically so the live map stays current
    // without a manual refresh button.
    _snapshotRefreshTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _loadSnapshots(),
    );
    // Debounce map camera updates so panning/zooming does not rebuild all
    // markers on every frame.
    _mapEventSub = _mapController.mapEventStream.listen((_) {
      _mapEventDebounce?.cancel();
      _mapEventDebounce = Timer(const Duration(milliseconds: 150), () {
        final zoom = _mapController.camera.zoom;
        if (zoom != _mapZoom && mounted) {
          setState(() => _mapZoom = zoom);
        }
      });
    });
  }

  @override
  void dispose() {
    _onlineCountTimer?.cancel();
    _snapshotRefreshTimer?.cancel();
    _mapEventDebounce?.cancel();
    _mapEventSub?.cancel();
    OnlineUsersService.stopHeartbeat();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _refreshOnlineCount() async {
    final count = await OnlineUsersService.fetchCount();
    if (mounted) setState(() => _onlineCount = count);
  }

  Future<void> _load() async {
    final list = await ContentService.loadOutbreakIntel();
    final bio = await BiometricsService.load();
    final history = await DiagnosisHistoryService.load();
    // Load snapshots and aggregate stats in parallel. A single backend call
    // replaces the previous 12 parallel per-source requests that timed out on
    // mobile networks and caused the carousel to collapse to one disease.
    final results = await Future.wait([
      _fetchSnapshots(),
      _fetchAggregate(),
    ]);
    final snapshots = results[0] as List<OutbreakSnapshot>;
    final aggregate = results[1] as OutbreakAggregate;
    final unified = _buildUnifiedIntelList(list, snapshots);

    if (mounted) {
      setState(() {
        _predefinedIntelList = list;
        _intelList = unified;
        _snapshots = snapshots;
        _aggregate = aggregate;
        // Default every outbreak disease to selected on first load so the map
        // shows all real-time data and every displayed carousel card is checked.
        // The carousel itself still filters to diseases with current snapshots.
        _selectedDiseaseIds = _intelList.map((i) => i.id).toSet();
        _biometrics = bio;
        _latestHistoryEntry = history.isNotEmpty ? history.first : null;
        _loading = false;
      });
      // On web the map sometimes does not fetch tiles until the camera moves.
      // Nudge it after the first frame so initial tiles paint without user
      // interaction.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _mapController.move(
            const LatLng(39.8283, -98.5795),
            4,
          );
        }
      });
    }
  }

  Future<List<OutbreakSnapshot>> _fetchSnapshots() async {
    try {
      return await ApiService.fetchRecentOutbreaks(days: 90, limit: 1000);
    } catch (e) {
      // Return the existing snapshots (or empty list) on error; the map still
      // shows static Outbreak Intel markers as a fallback.
      return _snapshots;
    }
  }

  Future<OutbreakAggregate> _fetchAggregate() async {
    try {
      return await ApiService.fetchAggregate();
    } catch (e) {
      return _aggregate;
    }
  }

  Future<void> _loadSnapshots() async {
    final results = await Future.wait([
      _fetchSnapshots(),
      _fetchAggregate(),
    ]);
    final snapshots = results[0] as List<OutbreakSnapshot>;
    final aggregate = results[1] as OutbreakAggregate;
    final unified = _buildUnifiedIntelList(_predefinedIntelList, snapshots);

    if (mounted) {
      setState(() {
        _snapshots = snapshots;
        _intelList = unified;
        _aggregate = aggregate;
        // Preserve user filter choices for diseases that are still tracked, and
        // default any newly discovered disease to checked.
        final allIds = _intelList.map((i) => i.id).toSet();
        _selectedDiseaseIds = _selectedDiseaseIds.intersection(allIds);
        _selectedDiseaseIds.addAll(allIds.difference(_selectedDiseaseIds));
      });
    }
  }

  /// Creates a stable URL-safe ID from a disease condition name.
  String _slugify(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  /// Creates a minimal OutbreakIntel for a condition reported by real-time
  /// sources that is not covered by the predefined YAML content.
  OutbreakIntel _createDynamicIntel(String id, String conditionName, int totalCases) {
    return OutbreakIntel(
      id: id,
      name: conditionName,
      commonName: conditionName,
      rarity: 'common',
      category: 'other',
      heroImage: '',
      model3d: '',
      molecularFormula: '',
      model3dSource: '',
      pdbId: '',
      molecularStructure: '',
      molecularImage: '',
      description: 'Real-time outbreak surveillance data for $conditionName.',
      stats: const OutbreakIntelStats(
        r0: 'Unknown',
        incubationDays: 'Unknown',
        severity: 'Unknown',
        transmissionRoute: 'Unknown',
        vaccineAvailable: false,
      ),
      nationalStats: NationalStats(
        infectants: totalCases,
        mortalityRate: '—',
        infectionRate: '—',
        recovered: 0,
      ),
      clinicalProfile: const ClinicalProfile(
        hiddenPeriodDays: 'Unknown',
        variants: 'Unknown',
        severity: 'Unknown',
      ),
      transmissionMedia: const [],
      cityOutbreaks: const [],
      symptoms: const [],
      actions: const [],
      citations: const [],
      unlockCondition: '',
    );
  }

  /// Merges predefined outbreak intel with dynamically discovered diseases
  /// from the real-time snapshots so the carousel and map stay in sync.
  List<OutbreakIntel> _buildUnifiedIntelList(
    List<OutbreakIntel> predefined,
    List<OutbreakSnapshot> snapshots,
  ) {
    // Group snapshots by condition name.
    final byCondition = <String, List<OutbreakSnapshot>>{};
    for (final snapshot in snapshots) {
      final condition = snapshot.conditionName;
      if (condition == null || condition.isEmpty) continue;
      byCondition.putIfAbsent(condition, () => []).add(snapshot);
    }

    // Create dynamic intel for conditions not covered by predefined entries.
    final dynamicList = <OutbreakIntel>[];
    for (final entry in byCondition.entries) {
      final condition = entry.key;
      final snaps = entry.value;
      if (predefined.any((i) => _conditionMatches(condition, i))) continue;
      final id = 'dynamic_${_slugify(condition)}';
      final totalCases = snaps.fold<int>(0, (sum, s) => sum + (s.caseCount ?? 0));
      dynamicList.add(_createDynamicIntel(id, condition, totalCases));
    }

    return [...predefined, ...dynamicList];
  }

  Future<void> _updateBiometrics(UserBiometrics updated) async {
    await BiometricsService.save(updated);
    setState(() => _biometrics = updated);
  }

  void _onCardSelected(int index) {
    setState(() => _selectedIndex = index);
  }

  void _toggleDiseaseFilter(String id) {
    setState(() {
      if (_selectedDiseaseIds.contains(id)) {
        _selectedDiseaseIds.remove(id);
      } else {
        _selectedDiseaseIds.add(id);
      }
    });
  }

  void _openDetail(OutbreakIntel intel) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OutbreakIntelDetailScreen(
          intel: intel,
          isGlobalMode: _globalMode,
          usStats: _bestStatsFor(_aggregate.us, intel),
          globalStats: _bestStatsFor(_aggregate.global, intel),
        ),
      ),
    );
  }

  Future<void> _openSelfDiagnosis() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SelfDiagnosisScreen()),
    );
    // Refresh the latest history entry so the risk-alert chip updates
    // after the user completes a self-diagnosis check.
    if (mounted) {
      final history = await DiagnosisHistoryService.load();
      setState(() {
        _latestHistoryEntry = history.isNotEmpty ? history.first : null;
      });
    }
  }

  void _openHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DiagnosisHistoryScreen()),
    );
  }

  void _showSnapshotSheet(OutbreakSnapshot snapshot) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SnapshotBottomSheet(snapshot: snapshot),
    );
  }

  /// Build a city name -> coordinate lookup from the static content.
  Map<String, LatLng> _cityCoordinateIndex() {
    final index = <String, LatLng>{};
    for (final intel in _intelList) {
      for (final city in intel.cityOutbreaks) {
        index[city.city.toLowerCase()] = LatLng(city.lat, city.lng);
      }
    }
    return index;
  }

  List<Marker> _snapshotMarkers() {
    final candidates = <(OutbreakSnapshot, Marker)>[];
    final cityCoords = _cityCoordinateIndex();
    final seen = <String>{};

    for (final snapshot in _snapshots) {
      try {
        final city = snapshot.city?.trim();
        final state = snapshot.state?.trim();
        final country = snapshot.country?.trim();
        // One marker per (country/state, condition) so the map does not get
        // overcrowded when multiple sources report the same condition.
        final dedupeKey = '${state ?? country ?? city ?? snapshot.region}_${snapshot.conditionName}';
        if (seen.contains(dedupeKey)) continue;
        seen.add(dedupeKey);

        LatLng? point;
        if (city != null && cityCoords.containsKey(city.toLowerCase())) {
          point = cityCoords[city.toLowerCase()];
        } else if (state != null) {
          final lowerState = state.toLowerCase();
          final stateKey = usStateCenters.keys.cast<String?>().firstWhere(
            (k) => k?.toLowerCase() == lowerState,
            orElse: () => null,
          );
          if (stateKey != null) point = usStateCenters[stateKey];
        } else if (country != null) {
          final lowerCountry = country.toLowerCase();
          final countryKey = countryCenters.keys.cast<String?>().firstWhere(
            (k) => k?.toLowerCase() == lowerCountry,
            orElse: () => null,
          );
          if (countryKey != null) point = countryCenters[countryKey];
        }
        if (point == null) continue;
        if (!_snapshotMatchesSelection(snapshot)) continue;

        final intel = _intelForSnapshot(snapshot);
        candidates.add((
          snapshot,
          SnapshotMapMarker(
            snapshot: snapshot,
            intel: intel,
            point: point,
            onTap: () => _showSnapshotSheet(snapshot),
          ),
        ));
      } catch (e, st) {
        debugPrint('HomeScreen: marker build failed: $e\n$st');
      }
    }

    // Limit rendered markers when zoomed far out to keep pan/zoom smooth.
    final zoom = _mapZoom;
    final maxMarkers = zoom >= 5 ? 300 : (zoom >= 3 ? 200 : 120);
    if (candidates.length > maxMarkers) {
      candidates.sort((a, b) {
        final av = a.$1.metricValue ?? 0;
        final bv = b.$1.metricValue ?? 0;
        return bv.compareTo(av);
      });
      return candidates.take(maxMarkers).map((c) => c.$2).toList();
    }
    return candidates.map((c) => c.$2).toList();
  }

  /// Pragmatic aliases for common source naming variations.
  static const _conditionAliases = <String, List<String>>{
    'influenza_a': ['influenza', 'flu', 'influenza a virus'],
    'covid_19': ['covid-19', 'covid', 'sars-cov-2', 'sars cov 2', 'coronavirus'],
    'measles': ['measles'],
    'norovirus': ['norovirus'],
    'mpox': ['mpox', 'monkeypox'],
    'dengue': ['dengue'],
    'pertussis': ['pertussis', 'whooping cough'],
    'rsv': ['rsv', 'respiratory syncytial virus'],
    'scarlet_fever': ['scarlet fever', 'group a strep', 'group a streptococcus'],
    'hfmd': ['hand foot mouth', 'hand-foot-mouth', 'coxsackievirus', 'enterovirus'],
    'chickenpox': ['chickenpox', 'varicella', 'varicella-zoster'],
    'acute_respiratory_infection': ['acute respiratory infection', 'ari'],
    'ari': ['ari', 'acute respiratory infection'],
  };

  /// Returns true when a raw condition name matches a specific disease.
  bool _conditionMatches(String condition, OutbreakIntel intel) {
    final c = condition.toLowerCase().trim();
    if (c.isEmpty) return false;

    final names = {intel.name, intel.commonName}
        .map((s) => s.toLowerCase())
        .where((s) => s.isNotEmpty);
    for (final name in names) {
      if (c.contains(name) || name.contains(c)) return true;
    }
    for (final alias in _conditionAliases[intel.id] ?? []) {
      if (c.contains(alias)) return true;
    }
    return false;
  }

  /// Returns the predefined [OutbreakIntel] whose aliases match the snapshot's
  /// condition name, or null when the snapshot is from a dynamic disease.
  OutbreakIntel? _intelForSnapshot(OutbreakSnapshot snapshot) {
    final condition = snapshot.conditionName;
    if (condition == null || condition.isEmpty) return null;
    for (final intel in _intelList) {
      if (_conditionMatches(condition, intel)) return intel;
    }
    return null;
  }

  /// Returns true when the snapshot's condition matches a specific disease.
  bool _snapshotMatchesIntel(OutbreakSnapshot snapshot, OutbreakIntel intel) {
    final condition = snapshot.conditionName;
    if (condition == null || condition.isEmpty) return false;
    return _conditionMatches(condition, intel);
  }

  /// Returns true when the snapshot's condition matches at least one selected
  /// outbreak disease. The matching is fuzzy because public-health sources use
  /// varying names (e.g., "Influenza A virus", "SARS-CoV-2", "COVID-19").
  bool _snapshotMatchesSelection(OutbreakSnapshot snapshot) {
    for (final id in _selectedDiseaseIds) {
      final intel = _intelList.firstWhere(
        (i) => i.id == id,
        orElse: () => _intelList.first,
      );
      if (_snapshotMatchesIntel(snapshot, intel)) return true;
    }
    return false;
  }

  /// Disease IDs that currently have real-time tracking data. A disease is
  /// active when it has either a recent snapshot within the freshness window
  /// or a non-null aggregate stat from /outbreaks/aggregate. The aggregate
  /// covers all tracked diseases, including sources such as cdc_dengue that
  /// can fall outside the limited /outbreaks/recent row window.
  static const _activeWindowDays = 90;

  Set<String> _activeDiseaseIds(List<OutbreakSnapshot> snapshots) {
    if ((snapshots.isEmpty && _aggregate.us.isEmpty && _aggregate.global.isEmpty) ||
        _intelList.isEmpty) {
      return _intelList.map((i) => i.id).toSet();
    }
    final cutoff = DateTime.now().subtract(const Duration(days: _activeWindowDays));
    final active = <String>{};

    // Activate from recent snapshots.
    for (final snapshot in snapshots) {
      final reportDate = snapshot.reportDate;
      if (reportDate == null || reportDate.isBefore(cutoff)) continue;
      for (final intel in _intelList) {
        if (_snapshotMatchesIntel(snapshot, intel) ||
            _sourceMatchesIntel(snapshot.source, intel)) {
          active.add(intel.id);
        }
      }
    }

    // Also activate any disease the backend aggregate is already tracking,
    // since the aggregate has no row limit and may include diseases that the
    // limited snapshot response dropped (e.g., Dengue fever).
    for (final intel in _intelList) {
      if (_bestStatsFor(_aggregate.us, intel) != null ||
          _bestStatsFor(_aggregate.global, intel) != null) {
        active.add(intel.id);
      }
    }

    // Safety net: if matching produced very few diseases but we have data,
    // something likely went wrong with condition naming or the network request
    // returned only a partial cache. Show all predefined diseases so the
    // carousel never collapses to a single card.
    if (active.length < _minActivePredefinedDiseases &&
        _intelList.length >= _minActivePredefinedDiseases) {
      return _intelList.map((i) => i.id).toSet();
    }
    return active;
  }

  bool _sourceMatchesIntel(String source, OutbreakIntel intel) {
    final s = source.toLowerCase();
    final names = {intel.name, intel.commonName}
        .map((x) => x.toLowerCase())
        .where((x) => x.isNotEmpty);
    for (final name in names) {
      if (s.contains(name)) return true;
    }
    for (final alias in _conditionAliases[intel.id] ?? []) {
      if (s.contains(alias)) return true;
    }
    return false;
  }

  /// Diseases currently showing real-time outbreak signals. Falls back to the
  /// full list when no real-time data is available. The carousel is data-driven:
  /// unchecking a card only affects the map filter, not the card list.
  List<OutbreakIntel> get _activeIntelList {
    final activeIds = _activeDiseaseIds(_snapshots);
    return _intelList.where((i) => activeIds.contains(i.id)).toList();
  }

  /// Looks up live stats for a disease card, respecting the current US/Global
  /// switch. Prefers an exact condition-name match; if multiple bucket keys
  /// match (e.g., "Influenza A" vs "Influenza A virus"), picks the one with
  /// the highest total so the card shows the most representative real-time
  /// aggregate instead of a minor sub-category.
  LiveStats? _liveStatsFor(OutbreakIntel intel) {
    final bucket = _globalMode ? _aggregate.global : _aggregate.us;
    return _bestStatsFor(bucket, intel);
  }

  /// Resolve the best matching [LiveStats] from an aggregate bucket.
  ///
  /// Some diseases have multiple condition-name variants in the backend
  /// (e.g. "RSV" vs "Respiratory Syncytial Virus", "ARI" vs
  /// "Acute Respiratory Infection"). To avoid showing a minor sub-category,
  /// all matching buckets are considered and the one with the largest total
  /// is returned. Exact-name matches are included in this scan so stale
  /// duplicate buckets never shadow the representative aggregate.
  LiveStats? _bestStatsFor(Map<String, LiveStats?> bucket, OutbreakIntel intel) {
    if (bucket.isEmpty) return null;

    final names = {intel.name, intel.commonName}
        .map((s) => s.toLowerCase())
        .where((s) => s.isNotEmpty)
        .toSet();

    LiveStats? best;
    for (final entry in bucket.entries) {
      final stats = entry.value;
      if (stats == null) continue;

      final keyLower = entry.key.toLowerCase().trim();
      final isExact = names.contains(keyLower);
      final isFuzzy = _conditionMatches(entry.key, intel);

      if (isExact || isFuzzy) {
        final score = (stats.weeklyNew ?? 0) + (stats.ytd ?? 0);
        final bestScore = (best?.weeklyNew ?? 0) + (best?.ytd ?? 0);
        if (best == null || score > bestScore) {
          best = stats;
        }
      }
    }
    return best;
  }

  List<Marker> _facilityMarkers() {
    final markers = <Marker>[];
    for (final h in _hospitals) {
      markers.add(Marker(
        point: LatLng(h['lat'] as double, h['lng'] as double),
        width: 32,
        height: 32,
        child: Tooltip(
          message: h['name'] as String,
          child: const Icon(Icons.local_hospital, color: Colors.red, size: 24),
        ),
      ));
    }
    for (final p in _pharmacies) {
      markers.add(Marker(
        point: LatLng(p['lat'] as double, p['lng'] as double),
        width: 32,
        height: 32,
        child: Tooltip(
          message: p['name'] as String,
          child: Icon(Icons.local_pharmacy, color: Colors.green.shade700, size: 24),
        ),
      ));
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: _buildDrawer(),
      body: SafeArea(
        child: Column(
          children: [
            // Top bar: menu + biometrics + online count — compact
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Builder(
                    builder: (ctx) => IconButton(
                      icon: const Icon(Icons.menu),
                      onPressed: () => Scaffold.of(ctx).openDrawer(),
                    ),
                  ),
                  Expanded(
                    child: BiometricsBar(
                      biometrics: _biometrics,
                      onEdit: _updateBiometrics,
                    ),
                  ),
                ],
              ),
            ),
            // Main content: loading or map + carousel
            _loading
                ? const Expanded(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text(
                            'Loading live map data, please wait...',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : Expanded(
                    flex: 3,
                    child: FlutterMap(
                      options: MapOptions(
                        initialCenter: const LatLng(39.8283, -98.5795),
                        initialZoom: 4,
                        minZoom: 2.5,
                        maxZoom: 18.0,
                        interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                        ),
                        onMapReady: () {
                          // Ensure the first frame with real data is painted.
                          if (mounted) setState(() {});
                        },
                      ),
                      mapController: _mapController,
                      // ignore: prefer_const_literals_to_create_immutables
                      children: [
                        // ignore: prefer_const_constructors
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.jasinteractive.diagnosisodyssey',
                        ),
                        MarkerLayer(
                          key: ValueKey(
                            'markers_${_snapshots.length}_${_selectedDiseaseIds.toList()..sort()}',
                          ),
                          markers: [
                            // Only real-time snapshot markers and sample facility
                            // markers are shown. Static cityOutbreaks entries from
                            // the YAML are intentionally omitted so the map reflects
                            // live surveillance data rather than sample data.
                            ..._snapshotMarkers(),
                            ..._facilityMarkers(),
                          ],
                        ),
                      ],
                    ),
                  ),
            // Online count + Outbreak Intel carousel
            _loading
                ? const SizedBox.shrink()
                : Container(
                    color: Colors.grey.shade50,
                    padding: const EdgeInsets.fromLTRB(12, 6, 0, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildOnlineCountRow(),
                            _buildRiskAlertChip(),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Outbreak Intel',
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            _buildCarouselFilterButtons(),
                          ],
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 160,
                          child: _activeIntelList.isEmpty
                              ? Center(
                                  child: Text(
                                    'No active outbreaks reported currently',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _activeIntelList.length,
                                  itemBuilder: (context, index) {
                                    final intel = _activeIntelList[index];
                                    return OutbreakIntelCompactCard(
                                      intel: intel,
                                      liveStats: _liveStatsFor(intel),
                                      isGlobalMode: _globalMode,
                                      isSelected: index == _selectedIndex,
                                      isChecked: _selectedDiseaseIds.contains(intel.id),
                                      onToggle: (_) => _toggleDiseaseFilter(intel.id),
                                      onTap: () {
                                        _onCardSelected(index);
                                        _openDetail(intel);
                                      },
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openSelfDiagnosis,
        icon: const Icon(Icons.camera_alt),
        label: const Text('Check'),
      ),
    );
  }

  Widget _buildOnlineCountRow() {
    return Row(
      children: [
        Icon(Icons.people_outline, size: 14, color: Colors.grey.shade600),
        const SizedBox(width: 4),
        Text(
          '$_onlineCount user${_onlineCount == 1 ? '' : 's'} online now',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildRiskAlertChip() {
    final entry = _latestHistoryEntry;
    final risk = entry?.riskLevel;
    final isAlert = risk == 'moderate' || risk == 'high';

    if (!isAlert) {
      return _buildAlertContainer(
        color: Colors.green.shade600,
        icon: Icons.check_circle,
        text: 'No outbreak infection indicated',
        textColor: Colors.white,
      );
    }

    final color = risk == 'high' ? Colors.red.shade700 : Colors.amber.shade700;
    final condition = entry!.matchedConditionName ?? 'possible illness';
    return Tooltip(
      message:
          'Risk alert: your recent check suggests $condition. This is not a medical diagnosis. Consult a healthcare provider if you feel unwell.',
      child: _buildAlertContainer(
        color: color,
        icon: Icons.warning_amber_rounded,
        text: 'Risk alert: $condition',
        textColor: color,
      ),
    );
  }

  Widget _buildAlertContainer({
    required Color color,
    required IconData icon,
    required String text,
    required Color textColor,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Container(
        margin: const EdgeInsets.only(left: 12),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: color == Colors.green.shade600 ? color : color.withValues(alpha: 0.12),
          border: color == Colors.green.shade600
              ? null
              : Border.all(color: color.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: textColor),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 11,
                  color: textColor,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCarouselFilterButtons() {
    final primaryColor = Theme.of(context).colorScheme.primary;
    Widget pill(String label, bool selected, VoidCallback onTap) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: selected ? primaryColor : Colors.transparent,
            border: Border.all(color: selected ? primaryColor : Colors.grey.shade400),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : Colors.grey.shade700,
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        pill('US', !_globalMode, () => setState(() => _globalMode = false)),
        const SizedBox(width: 4),
        pill('Global', _globalMode, () => setState(() => _globalMode = true)),
        const SizedBox(width: 8),
        TextButton(
          onPressed: _selectAllDiseases,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Select all', style: TextStyle(fontSize: 11)),
        ),
        TextButton(
          onPressed: _unselectAllDiseases,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Unselect all', style: TextStyle(fontSize: 11)),
        ),
      ],
    );
  }

  void _selectAllDiseases() {
    setState(() {
      _selectedDiseaseIds = _activeIntelList.map((i) => i.id).toSet();
    });
  }

  void _unselectAllDiseases() {
    setState(() => _selectedDiseaseIds = {});
  }

  Widget _buildDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'Diagnosis Outpost',
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 4),
                Text(
                  'Community Outbreak Sentinel',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.home),
            title: const Text('Home'),
            onTap: () => Navigator.pop(context),
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt),
            title: const Text('Self-Diagnosis'),
            onTap: () {
              Navigator.pop(context);
              _openSelfDiagnosis();
            },
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Diagnosis History'),
            onTap: () {
              Navigator.pop(context);
              _openHistory();
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy First'),
            onTap: () {
              Navigator.pop(context);
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Privacy First'),
                  content: const Text(
                    'Diagnosis Outpost is for educational and civic awareness only. '
                    'We do not collect personal data. On Android and iOS, audio and photos stay on your device. '
                    'On the web, you may opt in to send a photo or cough audio to our backend for analysis; it is processed in memory and not stored.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About'),
            onTap: () {
              Navigator.pop(context);
              _showAboutDialog();
            },
          ),
        ],
      ),
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About ${AppInfo.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Version: ${AppInfo.version}'),
            const SizedBox(height: 8),
            Text('Created by ${AppInfo.author}'),
            const SizedBox(height: 8),
            Text(AppInfo.copyright),
            const SizedBox(height: 16),
            const Text('More info:'),
            InkWell(
              onTap: () async {
                final uri = Uri.parse(AppInfo.website);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              child: Text(
                AppInfo.website,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
