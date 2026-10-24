import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../services/risk_engine.dart';

class SymptomSelection {
  final List<String> symptoms;
  final String customNote;

  const SymptomSelection({required this.symptoms, required this.customNote});
}

class SymptomsSelectorScreen extends StatefulWidget {
  final List<String> initialSymptoms;
  final String initialCustomNote;
  final DateTime? lastSavedAt;

  const SymptomsSelectorScreen({
    super.key,
    required this.initialSymptoms,
    required this.initialCustomNote,
    this.lastSavedAt,
  });

  @override
  State<SymptomsSelectorScreen> createState() => _SymptomsSelectorScreenState();
}

class _SymptomsSelectorScreenState extends State<SymptomsSelectorScreen> {
  final _speech = SpeechToText();
  late final Set<String> _selected;
  late final TextEditingController _customCtrl;
  bool _customExpanded = false;
  bool _speechAvailable = false;
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.initialSymptoms);
    _customCtrl = TextEditingController(text: widget.initialCustomNote);
    _customExpanded = widget.initialCustomNote.isNotEmpty;
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    try {
      final available = await _speech.initialize(
        onError: (_) {},
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (mounted) setState(() => _isListening = false);
          }
        },
      );
      if (mounted) setState(() => _speechAvailable = available);
    } catch (_) {
      if (mounted) setState(() => _speechAvailable = false);
    }
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      return;
    }
    if (!_speechAvailable) return;

    setState(() => _isListening = true);
    await _speech.listen(
      onResult: (result) {
        setState(() {
          _customCtrl.text = result.recognizedWords;
          _customCtrl.selection = TextSelection.fromPosition(
            TextPosition(offset: _customCtrl.text.length),
          );
        });
      },
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
      ),
    );
  }

  void _toggleCustom() {
    setState(() => _customExpanded = !_customExpanded);
  }

  void _save() {
    final symptoms = _selected.toList();
    final custom = _customCtrl.text.trim();
    if (custom.isNotEmpty) {
      symptoms.add('Custom: $custom');
    }
    Navigator.pop(
      context,
      SymptomSelection(symptoms: symptoms, customNote: custom),
    );
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    _speech.cancel();
    super.dispose();
  }

  String _formatTimestamp(DateTime dt) {
    return '${DateFormat.yMMMd().add_jm().format(dt)} (${dt.timeZoneName})';
  }

  @override
  Widget build(BuildContext context) {
    final savedAt = widget.lastSavedAt;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Symptoms'),
        leading: const BackButton(),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (savedAt != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Icon(Icons.access_time, size: 14, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text(
                      _formatTimestamp(savedAt),
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Select any symptoms you are experiencing',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  ...RiskEngine.predefinedSymptoms.map((symptom) {
                    final selected = _selected.contains(symptom);
                    return CheckboxListTile(
                      value: selected,
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            _selected.add(symptom);
                          } else {
                            _selected.remove(symptom);
                          }
                        });
                      },
                      title: Text(symptom),
                      secondary: Icon(
                        selected ? Icons.check_circle : Icons.circle_outlined,
                        color: selected ? Colors.purple : Colors.grey,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    );
                  }),
                  const Divider(height: 32),
                  ListTile(
                    leading: const Icon(Icons.edit_note, color: Colors.purple),
                    title: const Text('Custom symptom or note'),
                    trailing: Icon(
                      _customExpanded ? Icons.expand_less : Icons.expand_more,
                    ),
                    onTap: _toggleCustom,
                  ),
                  AnimatedCrossFade(
                    firstChild: const SizedBox.shrink(),
                    secondChild: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: TextField(
                        controller: _customCtrl,
                        decoration: InputDecoration(
                          hintText: 'Type or speak a symptom',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _isListening ? Icons.mic : Icons.mic_none,
                              color: _isListening ? Colors.red : Colors.purple,
                            ),
                            tooltip: _speechAvailable
                                ? 'Dictate symptom'
                                : 'Speech not available',
                            onPressed: _speechAvailable ? _toggleListening : null,
                          ),
                        ),
                        maxLines: 3,
                        textCapitalization: TextCapitalization.sentences,
                      ),
                    ),
                    crossFadeState: _customExpanded
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 200),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _save,
                  child: const Text('Done'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
