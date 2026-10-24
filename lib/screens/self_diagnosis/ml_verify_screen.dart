import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/classifier_result.dart';
import '../../models/user_biometrics.dart';
import '../../services/classifier_service.dart';
import '../../services/risk_engine.dart';

/// Debug screen to verify classifiers and risk fusion in real time.
///
/// - Load status for each bundled TFLite model (mobile) or cloud inference
///   readiness (web).
/// - Run real inference on a picked photo or recorded cough.
/// - Simulate classifier outputs + vitals + symptoms and inspect RiskEngine scores.
class MlVerifyScreen extends StatefulWidget {
  const MlVerifyScreen({super.key});

  @override
  State<MlVerifyScreen> createState() => _MlVerifyScreenState();
}

class _MlVerifyScreenState extends State<MlVerifyScreen> {
  final Map<String, bool> _modelLoaded = {
    'rash': false,
    'wound': false,
    'face': false,
    'tongue': false,
    'cough': false,
  };
  final Map<String, String> _modelStatus = {};
  final Map<String, ClassifierResult> _realResults = {};
  final Map<String, ClassifierResult> _simulatedResults = {};
  final List<String> _simulatedSymptoms = [];
  final UserBiometrics _simulatedBiometrics = const UserBiometrics();

  @override
  void initState() {
    super.initState();
    _checkModels();
  }

  Future<void> _checkModels() async {
    for (final task in _modelLoaded.keys) {
      if (kIsWeb) {
        setState(() {
          _modelLoaded[task] = true;
          _modelStatus[task] = 'cloud inference available';
        });
        continue;
      }
      try {
        // Trigger lazy load by classifying a non-existent path; it will fail
        // at preprocessing but the model will be loaded into memory.
        await ClassifierService.classifyPhoto(task, '');
        setState(() {
          _modelLoaded[task] = true;
          _modelStatus[task] = 'loaded';
        });
      } catch (e) {
        setState(() {
          _modelLoaded[task] = false;
          _modelStatus[task] = 'error: $e';
        });
      }
    }
  }

  Future<void> _runImageClassifier(String task) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;

    setState(() => _modelStatus[task] = 'running...');
    try {
      final result = await ClassifierService.classifyPhoto(
        task,
        picked.path,
        context: context,
      );
      if (!mounted) return;
      setState(() {
        _realResults[task] = result;
        _modelStatus[task] = 'loaded';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _modelStatus[task] = 'run failed: $e');
    }
  }

  Future<void> _runCoughClassifier() async {
    final files = await FilePicker.pickFiles(type: FileType.audio);
    if (files.isEmpty || !mounted) return;
    final path = files.single.path;
    if (path == null) return;

    setState(() => _modelStatus['cough'] = 'running...');
    try {
      final classifierResult = await ClassifierService.classifyCough(
        path,
        context: context,
      );
      if (!mounted) return;
      setState(() {
        _realResults['cough'] = classifierResult;
        _modelStatus['cough'] = 'loaded';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _modelStatus['cough'] = 'run failed: $e');
    }
  }

  void _setSimulatedResult(String task, String topClass, double confidence) {
    setState(() {
      _simulatedResults[task] = ClassifierResult(
        task: task,
        probabilities: {topClass: confidence},
        topClass: topClass,
        topConfidence: confidence,
        timestamp: DateTime.now(),
      );
    });
  }

  RiskResult get _simulatedRiskResult {
    return RiskEngine.compute(
      symptoms: _simulatedSymptoms,
      biometrics: _simulatedBiometrics,
      coughRecorded: _simulatedResults.containsKey('cough'),
      classifierResults: _simulatedResults,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify ML & Risk Fusion')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                kIsWeb ? 'Classifier status' : 'Model load status',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ..._modelLoaded.entries.map((e) => ListTile(
                    dense: true,
                    leading: Icon(
                      e.value ? Icons.check_circle : Icons.error,
                      color: e.value ? Colors.green : Colors.red,
                    ),
                    title: Text(e.key[0].toUpperCase() + e.key.substring(1)),
                    subtitle: Text(_modelStatus[e.key] ?? 'unknown'),
                    trailing: e.key == 'cough'
                        ? TextButton(
                            onPressed: _runCoughClassifier,
                            child: const Text('Run'),
                          )
                        : TextButton(
                            onPressed: () => _runImageClassifier(e.key),
                            child: const Text('Run'),
                          ),
                  )),
              const Divider(height: 32),
              Text(
                'Real inference results',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (_realResults.isEmpty)
                const Text('Tap "Run" next to a model above to classify a real sample.',
                    style: TextStyle(color: Colors.grey))
              else
                ..._realResults.entries.map((e) => _ResultCard(
                      title: e.key,
                      result: e.value,
                    )),
              const Divider(height: 32),
              Text(
                'Simulate inputs & view risk fusion',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Pick simulated classifier outputs and symptoms, then see the computed outbreak scores.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _SimButton('Rash: measles', () => _setSimulatedResult('rash', 'measles_like', 0.9)),
                  _SimButton('Rash: chickenpox', () => _setSimulatedResult('rash', 'chickenpox_like', 0.9)),
                  _SimButton('Rash: mpox', () => _setSimulatedResult('rash', 'monkeypox_like', 0.9)),
                  _SimButton('Tongue: strawberry', () => _setSimulatedResult('tongue', 'shape_features.red_dots_strawberry', 0.85)),
                  _SimButton('Face: eye discharge', () => _setSimulatedResult('face', 'conjunctivitis_eye_discharge', 0.8)),
                  _SimButton('Cough: whooping', () => _setSimulatedResult('cough', 'whooping', 0.9)),
                  _SimButton('Wound: infected', () => _setSimulatedResult('wound', 'infected', 0.8)),
                  _SimButton('Clear', () => setState(_simulatedResults.clear)),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: RiskEngine.predefinedSymptoms.map((s) {
                  final selected = _simulatedSymptoms.contains(s);
                  return FilterChip(
                    label: Text(s),
                    selected: selected,
                    onSelected: (_) {
                      setState(() {
                        if (selected) {
                          _simulatedSymptoms.remove(s);
                        } else {
                          _simulatedSymptoms.add(s);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Computed risk',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Text('Top match: ${_simulatedRiskResult.conditionName}'),
                      Text('Probability: ${_simulatedRiskResult.probability}%'),
                      Text('Level: ${_simulatedRiskResult.riskLevel.toUpperCase()}'),
                      const SizedBox(height: 8),
                      const Text('All scores:', style: TextStyle(fontWeight: FontWeight.bold)),
                      ...(_simulatedRiskResult.allScores.entries.toList()
                            ..sort((a, b) => b.value.compareTo(a.value)))
                          .map((e) => Text(
                                '  ${e.key}: ${e.value.toStringAsFixed(1)}',
                                style: const TextStyle(fontSize: 12),
                              )),
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
}

class _ResultCard extends StatelessWidget {
  final String title;
  final ClassifierResult result;

  const _ResultCard({required this.title, required this.result});

  @override
  Widget build(BuildContext context) {
    final sorted = result.probabilities.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title[0].toUpperCase() + title.substring(1),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text('Top: ${result.topClass.replaceAll('_', ' ')} (${(result.topConfidence * 100).toStringAsFixed(1)}%)'),
            const SizedBox(height: 4),
            ...sorted.take(5).map((e) => Text(
                  '  ${e.key.replaceAll('_', ' ')}: ${(e.value * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(fontSize: 12),
                )),
          ],
        ),
      ),
    );
  }
}

class _SimButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SimButton(this.label, this.onTap);

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        textStyle: const TextStyle(fontSize: 12),
      ),
      child: Text(label),
    );
  }
}
