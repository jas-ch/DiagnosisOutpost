import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/live_stats.dart';
import '../models/outbreak_intel.dart';
import '../widgets/pdb_viewer/pdb_viewer.dart';
import '../widgets/transmission_medium_icons.dart';

class OutbreakIntelDetailScreen extends StatelessWidget {
  final OutbreakIntel intel;
  final LiveStats? usStats;
  final LiveStats? globalStats;
  final bool isGlobalMode;

  const OutbreakIntelDetailScreen({
    super.key,
    required this.intel,
    this.usStats,
    this.globalStats,
    this.isGlobalMode = false,
  });

  Color _rarityColor(String rarity) {
    return switch (rarity.toLowerCase()) {
      'legendary' => Colors.purple,
      'epic' => Colors.deepPurple,
      'rare' => Colors.blue,
      'uncommon' => Colors.green,
      _ => Colors.teal,
    };
  }

  String _formatNumber(num n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    if (n is int) return n.toString();
    return n.toStringAsFixed(n.truncateToDouble() == n ? 0 : 2);
  }

  LiveStats? get _nationalLiveStats {
    if (usStats == null || (usStats!.source.isEmpty && usStats!.sources.isEmpty)) return null;
    return usStats;
  }

  LiveStats? get _globalLiveStats {
    if (globalStats == null || (globalStats!.source.isEmpty && globalStats!.sources.isEmpty)) return null;
    return globalStats;
  }

  Map<String, String> get _nationalFallbackStats => {
        'weeklyNewLabel': 'weekly',
        'weeklyNewValue': '—',
        'ytdLabel': 'YTD',
        'ytdValue': '—',
        'Mortality': intel.nationalStats.mortalityRate.isNotEmpty
            ? intel.nationalStats.mortalityRate
            : '—',
        'weeklyChangeLabel': 'change',
        'weeklyChangeValue': '—',
      };

  Map<String, String> get _globalFallbackStats => {
        'weeklyNewLabel': 'weekly',
        'weeklyNewValue': '—',
        'ytdLabel': 'YTD',
        'ytdValue': '—',
        'Mortality': intel.nationalStats.mortalityRate.isNotEmpty
            ? intel.nationalStats.mortalityRate
            : '—',
        'weeklyChangeLabel': 'change',
        'weeklyChangeValue': '—',
      };

  Widget _buildSnapshotCard(
    BuildContext context, {
    required String title,
    required LiveStats? stats,
    required Map<String, String> fallback,
  }) {
    final values = stats != null ? _statsFromLiveStats(stats) : fallback;
    final sourceLine = stats != null && stats.reportDate != null
        ? '${_formatSources(stats)} · ${_formatDate(stats.reportDate)}'
        : null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _statColumn(
                  values['weeklyNewLabel']!,
                  values['weeklyNewValue']!,
                  Colors.red,
                ),
              ),
              Expanded(
                child: _statColumn(
                  values['ytdLabel']!,
                  values['ytdValue']!,
                  Colors.purple,
                ),
              ),
              Expanded(
                child: _statColumn(
                  'Mortality',
                  values['Mortality']!,
                  Colors.orange,
                ),
              ),
              Expanded(
                child: _statColumn(
                  values['weeklyChangeLabel']!,
                  values['weeklyChangeValue']!,
                  Colors.blue,
                ),
              ),
            ],
          ),
          if (sourceLine != null) ...[
            const SizedBox(height: 8),
            Text(
              sourceLine,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
            ),
          ],
        ],
      ),
    );
  }

  Map<String, String> _statsFromLiveStats(LiveStats stats) {
    final weeklyNewValue = stats.weeklyNew != null ? _formatNumber(stats.weeklyNew!) : '—';
    final ytdValue = stats.ytd != null ? _formatNumber(stats.ytd!) : '—';
    final changeValue = stats.weeklyChange != null
        ? (stats.weeklyChange! > 0
            ? '+${_formatNumber(stats.weeklyChange!)}'
            : _formatNumber(stats.weeklyChange!))
        : '—';
    final admissionsSuffix = stats.isAdmissions ? ' admissions' : '';
    return {
      'weeklyNewLabel': 'weekly$admissionsSuffix',
      'weeklyNewValue': weeklyNewValue,
      'ytdLabel': 'YTD$admissionsSuffix',
      'ytdValue': ytdValue,
      'Mortality': intel.nationalStats.mortalityRate.isNotEmpty
          ? intel.nationalStats.mortalityRate
          : '—',
      'weeklyChangeLabel': 'change',
      'weeklyChangeValue': changeValue,
    };
  }

  String _shortSource(String source) {
    return switch (source) {
      'cdc_nndss' => 'CDC',
      'cdc_measles' => 'CDC',
      'cdc_dengue' => 'CDC',
      'cdc_resp_naat' => 'CDC',
      'cdc_nssp_ed_resp' => 'CDC NSSP',
      'cdc_wastewater' => 'CDC',
      'cdc_ari_activity' => 'CDC',
      'cdc_hosp_resp' => 'CDC',
      'cdc_mpox' => 'CDC',
      'who_covid_cases' => 'WHO',
      'who_flunet' => 'WHO',
      'who_measles_monthly' => 'WHO',
      'who_mpox' => 'WHO',
      'who_don' => 'WHO DON',
      'paho_dengue' => 'PAHO',
      'ecdc_respiratory' => 'ECDC',
      _ => source.toUpperCase(),
    };
  }

  String _formatSources(LiveStats stats) {
    final sources = stats.sources.isNotEmpty
        ? stats.sources
        : (stats.source.isNotEmpty ? [stats.source] : <String>[]);
    if (sources.isEmpty) return '';
    final primary = _shortSource(sources.first);
    if (sources.length == 1) return primary;
    return '$primary (+${sources.length - 1})';
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso);
      return '${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final rarityColor = _rarityColor(intel.rarity);

    return Scaffold(
      appBar: AppBar(
        title: Text(intel.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Sharing coming soon')),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Hero image with rarity badge
            Stack(
              alignment: Alignment.topRight,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.asset(
                    intel.heroImage,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: Colors.grey.shade800,
                      child: const Center(child: Icon(Icons.image_not_supported)),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Chip(
                    backgroundColor: rarityColor,
                    label: Text(
                      intel.rarity.toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + MediaQuery.of(context).padding.bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name and description
                  Text(
                    intel.commonName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(intel.description),
                  const SizedBox(height: 20),

                  // Live national + global stats
                  _sectionTitle(context, 'Live Snapshot'),
                  const SizedBox(height: 10),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth > 500;
                      final usCard = Expanded(
                        child: _buildSnapshotCard(
                          context,
                          title: 'United States',
                          stats: _nationalLiveStats,
                          fallback: _nationalFallbackStats,
                        ),
                      );
                      final globalCard = Expanded(
                        child: _buildSnapshotCard(
                          context,
                          title: 'Global',
                          stats: _globalLiveStats,
                          fallback: _globalFallbackStats,
                        ),
                      );
                      final gap = SizedBox(width: isWide ? 12 : 0, height: isWide ? 0 : 12);
                      final ordered = isGlobalMode
                          ? [globalCard, gap, usCard]
                          : [usCard, gap, globalCard];
                      return isWide
                          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: ordered)
                          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: ordered);
                    },
                  ),
                  const SizedBox(height: 20),

                  // Transmission medium
                  _sectionTitle(context, 'Transmission'),
                  const SizedBox(height: 8),
                  TransmissionMediumIcons(
                    media: intel.transmissionMedia,
                    iconSize: 22,
                    showLabels: true,
                  ),
                  const SizedBox(height: 20),

                  // Clinical profile
                  _sectionTitle(context, 'Clinical Profile'),
                  const SizedBox(height: 10),
                  _infoCard(
                    rows: [
                      _infoRow('Hidden period before symptoms', intel.clinicalProfile.hiddenPeriodDays),
                      _infoRow('Variants', intel.clinicalProfile.variants),
                      _infoRow('Severity', intel.clinicalProfile.severity),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Epidemiological stats
                  _sectionTitle(context, 'Epidemiology'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      _statChip('R0', intel.stats.r0),
                      _statChip('Incubation', intel.stats.incubationDays),
                      _statChip('Spread', intel.stats.transmissionRoute),
                      _statChip('Vaccine', intel.stats.vaccineAvailable ? 'Yes' : 'No'),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // 3D / AR model (when a local GLB or PDB ID is available)
                  if (intel.model3d.isNotEmpty || intel.pdbId.isNotEmpty) ...[
                    _sectionTitle(context, '3D Protein Structure'),
                    const SizedBox(height: 10),
                    _buildModelPreviewCard(context),
                    const SizedBox(height: 20),
                  ],

                  // Symptoms
                  _sectionTitle(context, 'Symptoms'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: intel.symptoms.map((s) => Chip(label: Text(s))).toList(),
                  ),
                  const SizedBox(height: 20),

                  // Recommended actions
                  _sectionTitle(context, 'Recommended Actions'),
                  const SizedBox(height: 10),
                  ...intel.actions.map(
                    (a) => ListTile(
                      leading: const Icon(Icons.check_circle_outline),
                      title: Text(a),
                      dense: true,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Sources
                  _sectionTitle(context, 'Sources'),
                  const SizedBox(height: 10),
                  ...intel.citations.map(
                    (c) => ListTile(
                      leading: const Icon(Icons.link),
                      title: Text(c.text),
                      dense: true,
                      onTap: () async {
                        final uri = Uri.parse(c.url);
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Disclaimer
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'For educational and civic awareness purposes only. Not a substitute for professional medical advice.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
    );
  }

  Widget _statColumn(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: color,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _statChip(String label, String value) {
    return Chip(
      avatar: CircleAvatar(
        backgroundColor: Colors.teal.shade700,
        child: Text(label[0], style: const TextStyle(color: Colors.white, fontSize: 10)),
      ),
      label: Text('$label: $value'),
    );
  }

  Widget _infoCard({required List<Widget> rows}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows,
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelPreviewCard(BuildContext context) {
    final formula = intel.molecularFormula.isNotEmpty
        ? intel.molecularFormula
        : intel.name;
    final source = intel.model3dSource.isNotEmpty
        ? intel.model3dSource
        : (intel.pdbId.isNotEmpty ? 'RCSB PDB ${intel.pdbId}' : '');
    final imagePath = intel.molecularImage;
    final rarityColor = _rarityColor(intel.rarity);

    return GestureDetector(
      onTap: () => _showMoleculeImageDialog(context),
      child: Container(
        height: 270,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: Text(
                  formula,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                child: imagePath.isNotEmpty
                    ? Image.asset(
                        imagePath,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => _moleculePlaceholder(formula),
                      )
                    : _moleculePlaceholder(formula),
              ),
              if (source.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                  child: Text(
                    source,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    textAlign: TextAlign.center,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: rarityColor.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.threed_rotation, size: 14, color: Colors.white),
                      SizedBox(width: 6),
                      Text(
                        'Tap the image for interactive 3D structure',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _moleculePlaceholder(String label) {
    return Container(
      color: Colors.grey.shade200,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.image_not_supported, size: 48, color: Colors.grey),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 4),
            Text(
              'Structure image unavailable',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  void _showMoleculeImageDialog(BuildContext context) {
    final formula = intel.molecularFormula.isNotEmpty
        ? intel.molecularFormula
        : intel.name;
    final source = intel.model3dSource.isNotEmpty
        ? intel.model3dSource
        : (intel.pdbId.isNotEmpty ? 'RCSB PDB ${intel.pdbId}' : '');

    showDialog(
      context: context,
      builder: (_) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
              tooltip: 'Back',
            ),
            title: Text(formula),
            actions: [
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
                tooltip: 'Close',
              ),
            ],
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (source.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    source,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: intel.pdbId.isNotEmpty
                      ? PdbViewer(pdbId: intel.pdbId, molecularName: formula)
                      : InteractiveViewer(
                          boundaryMargin: const EdgeInsets.all(24),
                          minScale: 0.5,
                          maxScale: 5.0,
                          child: intel.molecularImage.isNotEmpty
                              ? Image.asset(intel.molecularImage, fit: BoxFit.contain)
                              : _moleculePlaceholder(formula),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
