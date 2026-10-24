import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/classifier_result.dart';
import '../models/diagnosis_history_entry.dart';
import '../models/diagnosis_summary.dart';
import '../models/outbreak_intel.dart';
import '../models/user_biometrics.dart';
import '../services/biometrics_service.dart';
import '../services/capture_storage_service.dart';
import '../services/classifier_service.dart';
import '../services/content_service.dart';
import '../services/diagnosis_history_service.dart';
import '../services/risk_engine.dart';
import '../services/self_diagnosis_state_service.dart';
import '../widgets/classifier_result_summary.dart';
import '../widgets/diagnosis_summary_dialog.dart';
import 'diagnosis_history_screen.dart';
import 'outbreak_intel_detail_screen.dart';
import 'self_diagnosis/camera_screen.dart';
import 'self_diagnosis/cough_recorder_screen.dart';
import 'self_diagnosis/photo_category_screen.dart';
import 'self_diagnosis/symptoms_selector_screen.dart';
import 'self_diagnosis/vitals_editor_screen.dart';

/// Self-diagnosis entry point with a live rule-based risk meter.
/// Users can enter photo, cough audio, vitals, and symptom inputs. On
/// Android/iOS the classifiers run on-device; on web the user may opt in
/// to cloud classification, where media is processed in memory and not stored.
class SelfDiagnosisScreen extends StatefulWidget {
  const SelfDiagnosisScreen({super.key});

  @override
  State<SelfDiagnosisScreen> createState() => _SelfDiagnosisScreenState();
}

class _SelfDiagnosisScreenState extends State<SelfDiagnosisScreen> {
  UserBiometrics _biometrics = const UserBiometrics();
  final List<String> _predefinedSymptoms = [];
  String _customNote = '';
  String? _photoCategory;
  bool _coughRecorded = false;
  bool _loadingBiometrics = true;
  bool _initializingMl = true;
  bool? _cloudConsent;
  final Map<String, ClassifierResult> _classifierResults = {};
  List<CaptureRecord> _recentCaptures = [];
  TongueWellness? _tongueWellness;
  DateTime? _symptomsUpdatedAt;
  DateTime? _vitalsUpdatedAt;
  bool _recentInputsExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadBiometrics();
    _initializeMl();
    _loadCaptures();
    _loadSessionState();
  }

  Future<void> _loadSessionState() async {
    final state = await SelfDiagnosisStateService.load();
    if (!mounted) return;
    setState(() {
      _predefinedSymptoms
        ..clear()
        ..addAll(state.symptoms.where((s) => !s.startsWith('Custom: ')));
      _customNote = state.customNote;
      _symptomsUpdatedAt = state.symptomsUpdatedAt;
      _vitalsUpdatedAt = state.vitalsUpdatedAt;
    });
  }

  Future<void> _saveSessionState({DateTime? symptomsUpdatedAt, DateTime? vitalsUpdatedAt}) async {
    await SelfDiagnosisStateService.save(
      symptoms: _predefinedSymptoms,
      customNote: _customNote,
      symptomsUpdatedAt: symptomsUpdatedAt ?? _symptomsUpdatedAt,
      vitalsUpdatedAt: vitalsUpdatedAt ?? _vitalsUpdatedAt,
    );
  }

  Future<void> _initializeMl() async {
    await ClassifierService.initialize();
    if (kIsWeb) {
      _cloudConsent = await ClassifierService.hasCloudConsent();
    }
    if (mounted) setState(() => _initializingMl = false);
  }

  @override
  void dispose() {
    _saveSessionState();
    super.dispose();
  }

  Future<void> _loadCaptures() async {
    final records = await CaptureStorageService.loadAll();
    if (!mounted) return;
    final results = <String, ClassifierResult>{};
    for (final record in records) {
      if (record.result != null) {
        results[record.category.toLowerCase()] = record.result!;
      }
    }
    TongueWellness? wellness;
    if (results.containsKey('tongue')) {
      wellness = await ClassifierService.evaluateTongueWellness(
        ClassifierService.extractTongueAttributes(results['tongue']!),
      );
    }

    setState(() {
      _recentCaptures = records;
      _classifierResults.addAll(results);
      _tongueWellness = wellness;
      if (results.containsKey('cough')) _coughRecorded = true;
    });
  }

  Future<void> _loadBiometrics() async {
    try {
      final bio = await BiometricsService.load();
      if (mounted) {
        setState(() {
          _biometrics = bio;
          _loadingBiometrics = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingBiometrics = false);
      }
    }
  }

  List<String> get _engineSymptoms {
    final symptoms = List<String>.from(_predefinedSymptoms);
    if (_customNote.trim().isNotEmpty) {
      symptoms.add('Custom: ${_customNote.trim()}');
    }
    return symptoms;
  }

  RiskResult get _riskResult {
    return RiskEngine.compute(
      symptoms: _engineSymptoms,
      biometrics: _biometrics,
      photoCategory: _photoCategory,
      coughRecorded: _coughRecorded,
      classifierResults: _classifierResults,
    );
  }

  Future<void> _onPhoto() async {
    final result = await Navigator.push<PhotoCaptureResult>(
      context,
      MaterialPageRoute(builder: (_) => const PhotoCategoryScreen()),
    );
    if (!mounted) return;

    // Reload persisted captures so the recent-inputs panel reflects any new
    // photos taken while the photo category screen was open.
    await _loadCaptures();

    if (result == null) return;

    final category = result.category;
    setState(() {
      _photoCategory = category[0].toUpperCase() + category.substring(1);
      _classifierResults[category.toLowerCase()] =
          result.result ?? ClassifierResult.empty(category.toLowerCase());
    });

    if (category.toLowerCase() == 'tongue' && result.result != null) {
      await _showTongueWellness(result.result!);
    }
  }

  Future<void> _showTongueWellness(ClassifierResult result) async {
    final attrs = ClassifierService.extractTongueAttributes(result);
    final wellness = await ClassifierService.evaluateTongueWellness(attrs);
    if (!mounted || wellness == null) return;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tongue wellness'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              wellness.pattern,
              style: Theme.of(ctx).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            ...wellness.suggestions.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
                      Expanded(child: Text(s)),
                    ],
                  ),
                )),
            const SizedBox(height: 12),
            const Text(
              'For general wellness only; not medical advice.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _onCoughAudio() async {
    final result = await Navigator.push<ClassifierResult>(
      context,
      MaterialPageRoute(builder: (_) => const CoughRecorderScreen()),
    );
    if (!mounted) return;
    setState(() {
      _coughRecorded = result != null;
      if (result != null) _classifierResults['cough'] = result;
    });
    await _loadCaptures();
  }

  Future<void> _onVitals() async {
    final updated = await Navigator.push<UserBiometrics>(
      context,
      MaterialPageRoute(builder: (_) => VitalsEditorScreen(biometrics: _biometrics)),
    );
    if (updated == null || !mounted) return;
    await BiometricsService.save(updated);
    final now = DateTime.now();
    setState(() {
      _biometrics = updated;
      _vitalsUpdatedAt = now;
    });
    await _saveSessionState(vitalsUpdatedAt: now);
  }

  Future<void> _onSymptoms() async {
    final selection = await Navigator.push<SymptomSelection>(
      context,
      MaterialPageRoute(
        builder: (_) => SymptomsSelectorScreen(
          initialSymptoms: _predefinedSymptoms,
          initialCustomNote: _customNote,
          lastSavedAt: _symptomsUpdatedAt,
        ),
      ),
    );
    if (selection == null || !mounted) return;
    final now = DateTime.now();
    setState(() {
      _predefinedSymptoms
        ..clear()
        ..addAll(selection.symptoms.where(
          (s) => !s.startsWith('Custom: '),
        ));
      _customNote = selection.customNote;
      _symptomsUpdatedAt = now;
    });
    await _saveSessionState(symptomsUpdatedAt: now);
  }

  Future<void> _reviewRecentCapture(String category) async {
    final record = await CaptureStorageService.loadForCategory(category);
    if (!mounted || record == null) return;

    if (!kIsWeb) {
      final file = File(record.filePath);
      final exists = await file.exists();
      if (!mounted) return;
      if (!exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Capture no longer available.')),
        );
        return;
      }
    }

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Recent $category'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (category == 'cough')
                  const Center(child: Icon(Icons.audio_file, size: 64))
                else
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _buildRecentImage(record),
                  ),
                const SizedBox(height: 12),
                if (record.result != null)
                  category.toLowerCase() == 'tongue'
                      ? TongueResultSummary(result: record.result!)
                      : ClassifierResultSummary(result: record.result!, category: category),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _reviewTongueWellness() async {
    final wellness = _tongueWellness;
    if (wellness == null || !mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tongue wellness'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: SingleChildScrollView(
            child: TongueWellnessSummary(wellness: wellness),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _reviewVitals() async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recent vitals'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildVitalRow('Temperature', _biometrics.bodyTemperature, Icons.thermostat),
            _buildVitalRow('Blood pressure', _biometrics.bloodPressure, Icons.bloodtype),
            _buildVitalRow('Heart rate', _biometrics.heartRate, Icons.favorite),
            _buildVitalRow('Oxygen level', _biometrics.oxygenLevel, Icons.air),
            _buildVitalRow('Weight', _biometrics.weight, Icons.monitor_weight),
            _buildVitalRow('Height', _biometrics.height, Icons.height),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildVitalRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.blue),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }

  Future<void> _reviewSymptoms() async {
    final symptoms = List<String>.from(_predefinedSymptoms);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recent symptoms'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 300),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (symptoms.isEmpty && _customNote.isEmpty)
                  const Text('No symptoms recorded.')
                else ...[
                  if (symptoms.isNotEmpty) ...[
                    const Text('Selected:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    ...symptoms.map((s) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
                          Expanded(child: Text(s)),
                        ],
                      ),
                    )),
                  ],
                  if (_customNote.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text('Note:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(_customNote),
                  ],
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentImage(CaptureRecord record) {
    if (kIsWeb && record.webBase64 != null && record.webBase64!.isNotEmpty) {
      return Image.memory(
        base64Decode(record.webBase64!),
        height: 180,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 64),
      );
    }
    return Image.file(
      File(record.filePath),
      height: 180,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 64),
    );
  }

  Future<void> _saveCheck() async {
    final result = _riskResult;
    final summaryText = _buildSummary();

    final entry = DiagnosisHistoryEntry(
      id: 'check-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(1000)}',
      timestamp: DateTime.now(),
      riskLevel: result.riskLevel,
      symptomSummary: summaryText,
      matchedConditionId: result.conditionId,
      matchedConditionName: result.conditionName,
      notes: _customNote.isNotEmpty ? _customNote : null,
      biometrics: _biometrics,
      classifierResults: Map<String, ClassifierResult>.from(_classifierResults),
    );

    await DiagnosisHistoryService.addEntry(entry);

    final diagnosisSummary = await DiagnosisSummaryBuilder.build(
      conditionId: result.conditionId,
      conditionName: result.conditionName,
      riskLevel: result.riskLevel,
      probability: result.probability,
      biometrics: _biometrics,
      symptoms: _engineSymptoms,
      customNote: _customNote.isNotEmpty ? _customNote : null,
      classifierResults: _classifierResults,
    );

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => DiagnosisSummaryDialog(
        title: 'Risk Check Result',
        summary: diagnosisSummary,
      ),
    );
  }

  String _buildSummary() {
    final parts = <String>[
      if (_photoCategory != null) 'photo: $_photoCategory',
      if (_coughRecorded) 'cough recorded',
      if (_engineSymptoms.isNotEmpty) 'symptoms: ${_engineSymptoms.join(', ')}',
      'temp ${_biometrics.bodyTemperature}',
      'O2 ${_biometrics.oxygenLevel}',
    ];
    return parts.join('; ');
  }

  String _tileSublabel(String category) {
    final result = _classifierResults[category.toLowerCase()];
    if (result == null || result.topClass.isEmpty) {
      return switch (category) {
        'Rash' => 'rash photo',
        'Wounds' => 'wound photo',
        'Selfie' => 'face photo',
        'Tongue' => 'tongue photo',
        _ => category.toLowerCase(),
      };
    }
    final short = result.topClass.split(':').last.trim().replaceAll('_', ' ');
    return '$short • ${(result.topConfidence * 100).toStringAsFixed(0)}%';
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingBiometrics || _initializingMl) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final result = _riskResult;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Self-Diagnosis'),
        leading: const BackButton(),
        actions: [
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DiagnosisHistoryScreen()),
            ),
            child: const Text('History', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 700;
            final cardsSection = _buildCardsSection(isWide: isWide);
            final meterSection = _RiskMeterPanel(
              result: result,
              compact: !_recentInputsExpanded,
              onBuildSummary: () => DiagnosisSummaryBuilder.build(
                conditionId: result.conditionId,
                conditionName: result.conditionName,
                riskLevel: result.riskLevel,
                probability: result.probability,
                biometrics: _biometrics,
                symptoms: _engineSymptoms,
                customNote: _customNote.isNotEmpty ? _customNote : null,
                classifierResults: _classifierResults,
              ),
            );

            final bottomPadding = MediaQuery.of(context).padding.bottom;
            final bodyContent = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_recentInputsExpanded)
                  Expanded(child: SingleChildScrollView(child: cardsSection))
                else
                  cardsSection,
                const SizedBox(height: 16),
                meterSection,
                const SizedBox(height: 16),
                _buildDisclaimer(compact: !_recentInputsExpanded),
              ],
            );

            return Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomPadding),
              child: bodyContent,
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saveCheck,
        icon: const Icon(Icons.save),
        label: const Text('Save Check'),
      ),
    );
  }

  Widget _buildHeader({bool compact = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How would you like to check?',
          style: compact
              ? Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)
              : Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        SizedBox(height: compact ? 4 : 8),
        Text(
          'This tool is for educational and civic awareness only. It cannot diagnose illness.',
          style: TextStyle(color: Colors.grey.shade600, fontSize: compact ? 12 : 14),
        ),
      ],
    );
  }

  Widget _buildCardsSection({required bool isWide}) {
    final tiles = [
      _InputTileData(
        icon: Icons.camera_alt,
        label: 'Photo',
        sublabel: _photoCategory != null ? '$_photoCategory • ${_tileSublabel(_photoCategory!)}' : 'rash / tongue / wound',
        color: Colors.teal,
        onTap: _onPhoto,
        badge: _photoCategory != null,
        onRecent: _photoCategory != null ? () => _reviewRecentCapture(_photoCategory!) : null,
      ),
      _InputTileData(
        icon: Icons.mic,
        label: 'Cough Audio',
        sublabel: _coughRecorded ? _tileSublabel('cough') : 'record a cough',
        color: Colors.orange,
        onTap: _onCoughAudio,
        badge: _coughRecorded,
        onRecent: _coughRecorded ? () => _reviewRecentCapture('cough') : null,
      ),
      _InputTileData(
        icon: Icons.monitor_heart,
        label: 'Vitals',
        sublabel: 'temp • BP • heart • O2',
        color: Colors.blue,
        onTap: _onVitals,
        badge: _biometrics.bodyTemperature != '--' ||
            _biometrics.bloodPressure != '--/--' ||
            _biometrics.heartRate != '--' ||
            _biometrics.oxygenLevel != '98%',
      ),
      _InputTileData(
        icon: Icons.list_alt,
        label: 'Symptoms',
        sublabel: _predefinedSymptoms.isEmpty && _customNote.isEmpty
            ? 'check symptoms'
            : '${_predefinedSymptoms.length} selected${_customNote.isNotEmpty ? ', note' : ''}',
        color: Colors.purple,
        onTap: _onSymptoms,
        badge: _predefinedSymptoms.isNotEmpty || _customNote.isNotEmpty,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(compact: !_recentInputsExpanded),
        SizedBox(height: !_recentInputsExpanded ? 12 : 16),
        _buildRecentInputsPanel(),
        const SizedBox(height: 16),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: isWide ? 4 : 2,
          mainAxisSpacing: isWide || !_recentInputsExpanded ? 8 : 12,
          crossAxisSpacing: isWide || !_recentInputsExpanded ? 8 : 12,
          childAspectRatio: (isWide || !_recentInputsExpanded) ? 1.4 : 1.1,
          children: tiles.map((t) => _InputTile(data: t, compact: isWide || !_recentInputsExpanded)).toList(),
        ),
      ],
    );
  }

  Widget _buildDisclaimer({bool compact = false}) {
    return Container(
      padding: EdgeInsets.all(compact ? 8 : 12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(compact ? 8 : 10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'For educational and civic awareness purposes only. Not a substitute for professional medical advice.',
            style: TextStyle(fontSize: compact ? 11 : 12),
          ),
          if (kIsWeb) ...[
            SizedBox(height: compact ? 4 : 8),
            _buildCloudConsentToggle(compact: compact),
          ],
        ],
      ),
    );
  }

  Widget _buildCloudConsentToggle({bool compact = false}) {
    final consent = _cloudConsent ?? false;
    return InkWell(
      onTap: () async {
        final newValue = !consent;
        await ClassifierService.setCloudConsent(newValue);
        if (mounted) setState(() => _cloudConsent = newValue);
      },
      borderRadius: BorderRadius.circular(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            consent ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
            size: compact ? 14 : 16,
            color: Colors.grey.shade700,
          ),
          const SizedBox(width: 6),
          Text(
            consent
                ? 'Cloud classification enabled (tap to disable)'
                : 'Cloud classification disabled (tap to enable)',
            style: TextStyle(fontSize: compact ? 10 : 11, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentInputsPanel() {
    final inputs = _recentInputs;
    if (inputs.isEmpty) return const SizedBox.shrink();

    final mostRecent = inputs.map((i) => i.timestamp).reduce((a, b) => a.isAfter(b) ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _recentInputsExpanded = !_recentInputsExpanded),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Text(
                  'Recent inputs',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  _formatRecentTimestamp(mostRecent),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(width: 4),
                Icon(
                  _recentInputsExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  size: 20,
                  color: Colors.grey.shade700,
                ),
              ],
            ),
          ),
        ),
        if (_recentInputsExpanded) ...[
          const SizedBox(height: 8),
          ...inputs.map((input) {
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: InkWell(
                onTap: input.onTap,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        backgroundColor: input.color.withValues(alpha: 0.15),
                        child: Icon(input.icon, color: input.color, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              input.category,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              input.summary,
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatRecentTimestamp(input.timestamp),
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  List<_RecentInput> get _recentInputs {
    final inputs = <_RecentInput>[];
    for (final record in _recentCaptures) {
      final result = record.result;
      final summary = result == null || result.topClass.isEmpty
          ? 'Captured'
          : '${result.topClass.split(':').last.trim().replaceAll('_', ' ')} • ${(result.topConfidence * 100).toStringAsFixed(0)}%';
      inputs.add(_RecentInput(
        category: record.category[0].toUpperCase() + record.category.substring(1),
        timestamp: record.timestamp,
        icon: record.category.toLowerCase() == 'cough' ? Icons.mic : Icons.camera_alt,
        summary: summary,
        onTap: () => _reviewRecentCapture(record.category),
        color: _categoryColor(record.category),
      ));
    }
    if (_biometrics.recordedAt != null) {
      inputs.add(_RecentInput(
        category: 'Vitals',
        timestamp: _biometrics.recordedAt!,
        icon: Icons.monitor_heart,
        summary: _buildVitalsSummary(),
        onTap: _reviewVitals,
        color: Colors.blue,
      ));
    }
    if (_symptomsUpdatedAt != null && (_predefinedSymptoms.isNotEmpty || _customNote.isNotEmpty)) {
      inputs.add(_RecentInput(
        category: 'Symptoms',
        timestamp: _symptomsUpdatedAt!,
        icon: Icons.list_alt,
        summary: _buildSymptomsSummary(),
        onTap: _reviewSymptoms,
        color: Colors.purple,
      ));
    }
    final tongueRecord = _recentCaptures.cast<CaptureRecord?>().firstWhere(
      (r) => r?.category.toLowerCase() == 'tongue',
      orElse: () => null,
    );
    final wellness = _tongueWellness;
    if (tongueRecord != null && wellness != null) {
      inputs.add(_RecentInput(
        category: 'Tongue wellness',
        timestamp: tongueRecord.timestamp,
        icon: Icons.spa,
        summary: '${wellness.pattern}, suggesting ${wellness.suggestions.firstOrNull ?? 'general wellness support'}',
        onTap: _reviewTongueWellness,
        color: Colors.teal,
      ));
    }
    inputs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return inputs;
  }

  String _buildVitalsSummary() {
    final parts = <String>[
      if (_biometrics.bodyTemperature != '--') 'temp ${_biometrics.bodyTemperature}',
      if (_biometrics.oxygenLevel != '--') 'O2 ${_biometrics.oxygenLevel}',
    ];
    return parts.isEmpty ? 'Recorded' : parts.join(' • ');
  }

  String _buildSymptomsSummary() {
    if (_predefinedSymptoms.isEmpty) return 'Custom note';
    final count = _predefinedSymptoms.length;
    return '$count selected${_customNote.isNotEmpty ? ', note' : ''}';
  }

  String _formatRecentTimestamp(DateTime dt) {
    return '${DateFormat.yMMMd().add_jm().format(dt)} (${dt.timeZoneName})';
  }

  Color _categoryColor(String category) {
    return switch (category.toLowerCase()) {
      'rash' => Colors.red,
      'wounds' => Colors.orange,
      'selfie' => Colors.blue,
      'tongue' => Colors.pink,
      'cough' => Colors.orange,
      _ => Colors.teal,
    };
  }
}

class _RecentInput {
  final String category;
  final DateTime timestamp;
  final IconData icon;
  final String summary;
  final VoidCallback onTap;
  final Color color;

  const _RecentInput({
    required this.category,
    required this.timestamp,
    required this.icon,
    required this.summary,
    required this.onTap,
    required this.color,
  });
}

class _InputTileData {
  final IconData icon;
  final String label;
  final String sublabel;
  final Color color;
  final VoidCallback onTap;
  final bool badge;
  final VoidCallback? onRecent;

  const _InputTileData({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.color,
    required this.onTap,
    this.badge = false,
    this.onRecent,
  });
}

class _InputTile extends StatelessWidget {
  final _InputTileData data;
  final bool compact;

  const _InputTile({required this.data, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(compact ? 12 : 16)),
      child: InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(compact ? 12 : 16),
        child: Padding(
          padding: EdgeInsets.all(compact ? 8 : 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                alignment: Alignment.topRight,
                children: [
                  Container(
                    padding: EdgeInsets.all(compact ? 10 : 14),
                    decoration: BoxDecoration(
                      color: data.color.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(data.icon, size: compact ? 24 : 32, color: data.color),
                  ),
                  if (data.badge)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.check_circle,
                          size: compact ? 14 : 18,
                          color: Colors.green.shade600,
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(height: compact ? 8 : 12),
              Text(
                data.label,
                style: TextStyle(
                  fontSize: compact ? 13 : 15,
                  fontWeight: FontWeight.bold,
                  color: data.color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                data.sublabel,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: compact ? 10 : 11, color: Colors.grey.shade700),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (data.onRecent != null) ...[
                SizedBox(height: compact ? 4 : 6),
                InkWell(
                  onTap: data.onRecent,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: Text(
                      'Review recent',
                      style: TextStyle(fontSize: compact ? 9 : 10, color: data.color),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RiskMeterPanel extends StatelessWidget {
  final RiskResult result;
  final Future<DiagnosisSummary> Function()? onBuildSummary;
  final bool compact;

  const _RiskMeterPanel({
    required this.result,
    this.onBuildSummary,
    this.compact = false,
  });

  Color get _color {
    return switch (result.riskLevel) {
      'low' => Colors.green,
      'moderate' => Colors.amber.shade700,
      _ => Colors.red,
    };
  }

  Future<OutbreakIntel?> _loadIntel() async {
    if (result.conditionId.isEmpty) return null;
    return ContentService.findById(result.conditionId);
  }

  void _openDetail(BuildContext context, OutbreakIntel intel) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => OutbreakIntelDetailScreen(intel: intel)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasMatch = result.conditionId.isNotEmpty;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(compact ? 12 : 16)),
      child: InkWell(
        onTap: hasMatch
            ? () async {
                if (onBuildSummary != null) {
                  final summary = await onBuildSummary!();
                  if (context.mounted) {
                    await showDialog(
                      context: context,
                      builder: (ctx) => DiagnosisSummaryDialog(
                        title: 'Diagnosis Summary',
                        summary: summary,
                      ),
                    );
                  }
                  return;
                }
                final intel = await _loadIntel();
                if (intel != null && context.mounted) {
                  _openDetail(context, intel);
                }
              }
            : null,
        borderRadius: BorderRadius.circular(compact ? 12 : 16),
        child: Padding(
          padding: EdgeInsets.all(compact ? 8 : 12),
          child: FutureBuilder<OutbreakIntel?>(
            future: _loadIntel(),
            builder: (context, snapshot) {
              final intel = snapshot.data;
              final hero = intel?.heroImage ?? '';

              return Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(compact ? 8 : 12),
                    child: Container(
                      width: compact ? 44 : 56,
                      height: compact ? 44 : 56,
                      color: Colors.grey.shade200,
                      child: hero.isNotEmpty
                          ? Image.asset(
                              hero,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Icon(
                                Icons.health_and_safety,
                                size: compact ? 22 : 28,
                              ),
                            )
                          : Icon(Icons.health_and_safety, size: compact ? 22 : 28),
                    ),
                  ),
                  SizedBox(width: compact ? 8 : 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Live Risk',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Colors.grey.shade600,
                                fontSize: compact ? 10 : null,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          result.conditionName,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: compact ? 13 : null,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${result.probability}% • ${result.riskLevel.toUpperCase()}',
                          style: TextStyle(
                            fontSize: compact ? 12 : 13,
                            fontWeight: FontWeight.w600,
                            color: _color,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: result.probability / 100,
                            minHeight: compact ? 4 : 6,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: AlwaysStoppedAnimation<Color>(_color),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (hasMatch)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(
                        Icons.chevron_right,
                        color: Colors.grey.shade400,
                        size: compact ? 18 : 20,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
