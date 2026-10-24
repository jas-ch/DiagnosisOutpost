import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/classifier_result.dart';
import '../models/diagnosis_history_entry.dart';
import '../models/diagnosis_summary.dart';
import '../models/user_biometrics.dart';
import '../services/content_service.dart';
import '../widgets/classifier_result_summary.dart';
import 'outbreak_intel_detail_screen.dart';

/// Detail view for a single diagnosis history entry.
///
/// Shows the diagnosis summary and recommendations in a scrollable body, with
/// a sticky bottom chooser that expands a classifier-analysis panel above it.
class DiagnosisHistoryDetailScreen extends StatefulWidget {
  final DiagnosisHistoryEntry entry;

  const DiagnosisHistoryDetailScreen({super.key, required this.entry});

  @override
  State<DiagnosisHistoryDetailScreen> createState() => _DiagnosisHistoryDetailScreenState();
}

class _DiagnosisHistoryDetailScreenState extends State<DiagnosisHistoryDetailScreen> {
  DiagnosisSummary? _summary;

  // No icon selected by default.
  String _selectedGroup = '';

  // Light teal accent for the popup/chooser so it is distinct from the main
  // Diagnosis Record screen. Darker teal is used for selected highlights.
  static final _lightCanvas = Colors.teal.shade50;
  static final _darkAccent = Colors.teal.shade700;

  static const _groupOrder = ['rash', 'wounds', 'selfie', 'tongue', 'cough'];
  static const _groupLabels = {
    'rash': 'Rash',
    'wounds': 'Wounds',
    'selfie': 'Selfie',
    'tongue': 'Tongue',
    'cough': 'Cough',
  };
  static const _groupIcons = {
    'rash': Icons.texture,
    'wounds': Icons.healing,
    'selfie': Icons.face,
    'tongue': Icons.circle,
    'cough': Icons.mic,
  };

  @override
  void initState() {
    super.initState();
    _buildSummary();
  }

  Future<void> _buildSummary() async {
    final biometrics = widget.entry.biometrics ?? _parseBiometrics(widget.entry.symptomSummary);
    final summary = await DiagnosisSummaryBuilder.build(
      conditionId: widget.entry.matchedConditionId ?? '',
      conditionName: widget.entry.matchedConditionName ?? 'No condition match',
      riskLevel: widget.entry.riskLevel,
      probability: _parseProbability(widget.entry.symptomSummary),
      biometrics: biometrics,
      symptoms: _parseSymptoms(widget.entry.symptomSummary),
      customNote: widget.entry.notes,
      classifierResults: widget.entry.classifierResults,
    );
    if (mounted) setState(() => _summary = summary);
  }

  UserBiometrics _parseBiometrics(String symptomSummary) {
    String extract(String prefix, String fallback) {
      final regex = RegExp('$prefix ([\\d./]+)');
      final match = regex.firstMatch(symptomSummary);
      return match?.group(1) ?? fallback;
    }

    return UserBiometrics(
      bodyTemperature: extract('temp', '--'),
      bloodPressure: extract('BP', '--/--'),
      heartRate: extract('HR', '--'),
      oxygenLevel: extract('O2', '98%'),
      weight: extract('weight', '--'),
      height: extract('height', '--'),
    );
  }

  List<String> _parseSymptoms(String symptomSummary) {
    final match = RegExp(r'symptoms: (.+?)(;|$)').firstMatch(symptomSummary);
    if (match == null) return [];
    return match.group(1)!.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }

  int _parseProbability(String symptomSummary) {
    return 50;
  }

  String _formatTimestamp(DateTime dt) {
    return '${DateFormat.yMMMd().add_jm().format(dt)} (${dt.timeZoneName})';
  }

  void _onGroupTap(String group) {
    setState(() {
      if (_selectedGroup == group) {
        _selectedGroup = '';
      } else {
        _selectedGroup = group;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final summary = _summary;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    const bottomBarHeight = 72.0;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
        ),
        title: const Text('Diagnosis Record'),
        actions: [
          if (entry.matchedConditionId != null && entry.matchedConditionId!.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.open_in_new),
              tooltip: 'Scientific details',
              onPressed: _openDetail,
            ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomBarHeight + bottomPadding),
            child: _buildSummaryPanel(summary, entry),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomBar(entry),
          ),
          if (_selectedGroup.isNotEmpty) ...[
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _selectedGroup = ''),
                child: Container(color: Colors.black.withValues(alpha: 0.2)),
              ),
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: bottomBarHeight + bottomPadding + 8,
              child: _buildExpandedPanel(entry),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryPanel(DiagnosisSummary? summary, DiagnosisHistoryEntry entry) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _formatTimestamp(entry.timestamp),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            Text(
              entry.matchedConditionName ?? 'No condition match',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            _buildRiskChip(entry.riskLevel),
            const Divider(height: 24),
            if (summary != null) ...[
              if (summary.hasVitals) ...[
                _buildSectionTitle('Vitals'),
                _buildVitalsChips(summary.vitals),
                const SizedBox(height: 16),
              ],
              if (summary.hasFindings || summary.hasInterpretedFindings) ...[
                _buildSectionTitle('Findings'),
                ...summary.findings.map(_buildFinding),
                ...summary.interpretedFindings.map(_buildInterpretedFinding),
                const SizedBox(height: 16),
              ],
              if (summary.hasSymptoms) ...[
                _buildSectionTitle('Symptoms'),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: summary.symptoms.map((s) => Chip(
                    label: Text(s, style: const TextStyle(fontSize: 11)),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  )).toList(),
                ),
                const SizedBox(height: 16),
              ],
              if (summary.hasTongueWellness) ...[
                _buildSectionTitle('Tongue wellness'),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TongueWellnessSummary(wellness: summary.tongueWellness!),
                ),
                const SizedBox(height: 16),
              ],
              if (summary.recommendations.isNotEmpty) ...[
                _buildSectionTitle('Recommended actions'),
                ...summary.recommendations.map(_buildRecommendation),
              ],
            ] else ...[
              const Center(child: CircularProgressIndicator()),
            ],
            const SizedBox(height: 12),
            const Text(
              'Not a medical diagnosis. Consult a healthcare provider if you feel unwell.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVitalsChips(List<VitalReading> vitals) {
    final chips = [
      _VitalIconChip(
        icon: Icons.thermostat,
        label: 'T',
        value: _findVital(vitals, 'Temperature'),
      ),
      _VitalIconChip(
        icon: Icons.favorite,
        label: 'HR',
        value: _findVital(vitals, 'Heart rate'),
      ),
      _VitalIconChip(
        icon: Icons.bloodtype,
        label: 'BP',
        value: _findVital(vitals, 'Blood pressure'),
      ),
      _VitalIconChip(
        icon: Icons.air,
        label: 'O₂',
        value: _findVital(vitals, 'Oxygen level'),
      ),
      _VitalIconChip(
        icon: Icons.monitor_weight,
        label: 'WT',
        value: _findVital(vitals, 'Weight'),
      ),
      _VitalIconChip(
        icon: Icons.height,
        label: 'HT',
        value: _findVital(vitals, 'Height'),
      ),
    ].where((c) => c.value != null && c.value!.isNotEmpty && c.value != '--' && c.value != '--/--').toList();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: chips,
    );
  }

  String? _findVital(List<VitalReading> vitals, String label) {
    for (final v in vitals) {
      if (v.label == label) {
        final text = '${v.value}${v.unit != null ? ' ${v.unit}' : ''}';
        return text;
      }
    }
    return null;
  }

  Widget _buildFinding(ClassifierFinding finding) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              finding.label,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              '${finding.topClass} • ${(finding.confidence * 100).toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInterpretedFinding(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendation(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(DiagnosisHistoryEntry entry) {
    return Container(
      color: _lightCanvas,
      child: SafeArea(
        top: false,
        child: Container(
          height: 72,
          decoration: BoxDecoration(
            color: _lightCanvas,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: _groupOrder.map((group) {
              final isSelected = _selectedGroup.toLowerCase() == group;
              final hasResult = entry.classifierResults.containsKey(group);
              final label = _groupLabels[group] ?? group;
              final icon = _groupIcons[group] ?? Icons.analytics;

              return Expanded(
                child: InkWell(
                  onTap: () => _onGroupTap(group),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? _darkAccent.withValues(alpha: 0.12) : Colors.transparent,
                      border: Border(
                        top: BorderSide(
                          color: isSelected ? _darkAccent : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          alignment: Alignment.topRight,
                          children: [
                            Icon(
                              icon,
                              size: 22,
                              color: isSelected
                                  ? _darkAccent
                                  : hasResult
                                      ? Colors.black87
                                      : Colors.grey.shade600,
                            ),
                            Icon(
                              isSelected ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                              size: 14,
                              color: isSelected ? _darkAccent : Colors.grey.shade600,
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected
                                ? _darkAccent
                                : hasResult
                                    ? Colors.black87
                                    : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedPanel(DiagnosisHistoryEntry entry) {
    final result = entry.classifierResults[_selectedGroup.toLowerCase()];
    final label = _groupLabels[_selectedGroup.toLowerCase()] ?? _selectedGroup;

    return Card(
      elevation: 8,
      color: _lightCanvas,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.45,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              dense: true,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _selectedGroup = ''),
              ),
              title: Text(
                '$label analysis',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _selectedGroup = ''),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: result == null
                    ? Text(
                        'No $label analysis recorded for this visit.',
                        style: TextStyle(color: Colors.grey.shade700),
                      )
                    : _buildGroupContent(_selectedGroup, result),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupContent(String group, ClassifierResult result) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (group.toLowerCase() == 'tongue')
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.3,
            ),
            child: SingleChildScrollView(
              child: TongueResultSummary(result: result),
            ),
          )
        else
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.3,
            ),
            child: SingleChildScrollView(
              child: ClassifierResultSummary(result: result, category: group),
            ),
          ),
        const SizedBox(height: 16),
        const Text(
          'Past images or audio are not stored in history yet.',
          style: TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildRiskChip(String risk) {
    final color = switch (risk.toLowerCase()) {
      'high' => Colors.red,
      'moderate' => Colors.orange,
      _ => Colors.green,
    };
    return Chip(
      backgroundColor: color.withValues(alpha: 0.15),
      label: Text(
        risk.toUpperCase(),
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
      ),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildSectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
    );
  }

  void _openDetail() async {
    final id = widget.entry.matchedConditionId;
    if (id == null || id.isEmpty) return;
    final intel = await ContentService.findById(id);
    if (intel != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => OutbreakIntelDetailScreen(intel: intel)),
      );
    }
  }
}

class _VitalIconChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;

  const _VitalIconChip({
    required this.icon,
    required this.label,
    this.value,
  });

  @override
  Widget build(BuildContext context) {
    if (value == null) return const SizedBox.shrink();
    return Chip(
      avatar: Icon(icon, size: 16, color: Colors.teal.shade700),
      label: Text(
        '$label $value',
        style: const TextStyle(fontSize: 11),
      ),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }
}
