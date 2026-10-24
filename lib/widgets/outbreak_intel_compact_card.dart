import 'package:flutter/material.dart';

import '../models/live_stats.dart';
import '../models/outbreak_intel.dart';
import 'transmission_medium_icons.dart';

/// Compact Outbreak Intel card used in the bottom carousel on the home screen.
/// Shows live US or global stats when available, falling back to static YAML
/// data only when the backend has not yet reported numbers for a disease.
class OutbreakIntelCompactCard extends StatelessWidget {
  final OutbreakIntel intel;
  final LiveStats? liveStats;
  final bool isGlobalMode;
  final VoidCallback? onTap;
  final bool isSelected;
  final bool isChecked;
  final ValueChanged<bool>? onToggle;

  const OutbreakIntelCompactCard({
    super.key,
    required this.intel,
    this.liveStats,
    this.isGlobalMode = false,
    this.onTap,
    this.isSelected = false,
    this.isChecked = true,
    this.onToggle,
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
    return n.toInt().toString();
  }

  String _formatValue(num? value) {
    if (value == null) return '—';
    return _formatNumber(value);
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

  @override
  Widget build(BuildContext context) {
    final rarityColor = _rarityColor(intel.rarity);
    final stats = liveStats;

    final hasLiveStats = stats != null;
    final weeklyValue = hasLiveStats ? _formatValue(stats.weeklyNew) : '—';
    final ytdValue = hasLiveStats ? _formatValue(stats.ytd) : '—';
    final changeValue = hasLiveStats ? _formatValue(stats.weeklyChange) : '—';
    final changeIsPositive = hasLiveStats && (stats.weeklyChange ?? 0) > 0;
    final sourceLine = hasLiveStats && stats.reportDate != null
        ? '${_formatSources(stats)} · ${_formatDate(stats.reportDate)}'
        : '';

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 160,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? rarityColor : Colors.grey.shade200,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: rarityColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: intel.heroImage.isNotEmpty
                        ? Image.asset(
                            intel.heroImage,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(Icons.bug_report, size: 18, color: rarityColor),
                          )
                        : Icon(Icons.bug_report, size: 18, color: rarityColor),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        intel.name,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        intel.commonName,
                        style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 28,
                  height: 28,
                  child: Checkbox(
                    value: isChecked,
                    onChanged: onToggle != null ? (v) => onToggle!(v ?? false) : null,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  weeklyValue,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 4),
                Text(
                  'weekly',
                  style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        ytdValue,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'YTD',
                        style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(child: _statColumn('Mortality', intel.nationalStats.mortalityRate)),
                Expanded(
                  child: _statColumn(
                    'change',
                    hasLiveStats && stats.weeklyChange != null
                        ? (changeIsPositive ? '+$changeValue' : changeValue)
                        : '—',
                  ),
                ),
              ],
            ),
            if (sourceLine.isNotEmpty)
              Text(
                sourceLine,
                style: TextStyle(fontSize: 8, color: Colors.grey.shade500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            if (hasLiveStats && stats.isAdmissions)
              Text(
                'by # of hospital admissions',
                style: TextStyle(fontSize: 8, color: rarityColor),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            TransmissionMediumIcons(
              media: intel.transmissionMedia,
              iconSize: 10,
            ),
          ],
        ),
      ),
    );
  }

  Widget _statColumn(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
