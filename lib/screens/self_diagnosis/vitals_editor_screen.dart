import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/user_biometrics.dart';

class VitalsEditorScreen extends StatefulWidget {
  final UserBiometrics biometrics;

  const VitalsEditorScreen({super.key, required this.biometrics});

  @override
  State<VitalsEditorScreen> createState() => _VitalsEditorScreenState();
}

class _VitalsEditorScreenState extends State<VitalsEditorScreen> {
  late final TextEditingController _tempCtrl;
  late final TextEditingController _bpCtrl;
  late final TextEditingController _hrCtrl;
  late final TextEditingController _o2Ctrl;
  late final TextEditingController _weightCtrl;
  late final TextEditingController _heightCtrl;

  @override
  void initState() {
    super.initState();
    _tempCtrl = TextEditingController(text: widget.biometrics.bodyTemperature);
    _bpCtrl = TextEditingController(text: widget.biometrics.bloodPressure);
    _hrCtrl = TextEditingController(text: widget.biometrics.heartRate);
    _o2Ctrl = TextEditingController(text: widget.biometrics.oxygenLevel);
    _weightCtrl = TextEditingController(text: widget.biometrics.weight);
    _heightCtrl = TextEditingController(text: widget.biometrics.height);
  }

  @override
  void dispose() {
    _tempCtrl.dispose();
    _bpCtrl.dispose();
    _hrCtrl.dispose();
    _o2Ctrl.dispose();
    _weightCtrl.dispose();
    _heightCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final updated = UserBiometrics(
      bodyTemperature: _tempCtrl.text.trim(),
      bloodPressure: _bpCtrl.text.trim(),
      heartRate: _hrCtrl.text.trim(),
      oxygenLevel: _o2Ctrl.text.trim(),
      weight: _weightCtrl.text.trim(),
      height: _heightCtrl.text.trim(),
      recordedAt: DateTime.now(),
    );
    Navigator.pop(context, updated);
  }

  String _formatTimestamp(DateTime dt) {
    return '${DateFormat.yMMMd().add_jm().format(dt)} (${dt.timeZoneName})';
  }

  @override
  Widget build(BuildContext context) {
    final savedAt = widget.biometrics.recordedAt;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Vitals'),
        leading: const BackButton(),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(Icons.access_time, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    savedAt != null
                        ? 'Last updated ${_formatTimestamp(savedAt)}'
                        : 'No vitals recorded yet',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    _buildField(
                      controller: _tempCtrl,
                      label: 'Body temperature',
                      hint: 'e.g. 98.6°F or 37.0°C',
                      icon: Icons.thermostat,
                    ),
                    const SizedBox(height: 16),
                    _buildField(
                      controller: _bpCtrl,
                      label: 'Blood pressure',
                      hint: 'e.g. 120/80',
                      icon: Icons.bloodtype,
                    ),
                    const SizedBox(height: 16),
                    _buildField(
                      controller: _hrCtrl,
                      label: 'Heart rate',
                      hint: 'e.g. 72',
                      icon: Icons.favorite,
                    ),
                    const SizedBox(height: 16),
                    _buildField(
                      controller: _o2Ctrl,
                      label: 'Oxygen level',
                      hint: 'e.g. 98%',
                      icon: Icons.air,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildField(
                            controller: _weightCtrl,
                            label: 'Weight',
                            hint: 'e.g. 70 kg',
                            icon: Icons.monitor_weight,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildField(
                            controller: _heightCtrl,
                            label: 'Height',
                            hint: 'e.g. 175 cm',
                            icon: Icons.height,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _save,
                        child: const Text('Save Vitals'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      ),
      keyboardType: TextInputType.text,
    );
  }
}
