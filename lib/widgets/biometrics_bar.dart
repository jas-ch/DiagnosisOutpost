import 'package:flutter/material.dart';

import '../models/user_biometrics.dart';

/// Top bar that shows the user's latest biometrics at a glance.
/// Tapping it opens a simple editor to update values.
class BiometricsBar extends StatelessWidget {
  final UserBiometrics biometrics;
  final ValueChanged<UserBiometrics>? onEdit;

  const BiometricsBar({
    super.key,
    required this.biometrics,
    this.onEdit,
  });

  Widget _chip(IconData icon, String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.teal.shade700),
        const SizedBox(width: 4),
        Text(
          '$label $value',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onEdit != null ? () => _showEditDialog(context) : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.teal.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.teal.shade100),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _chip(Icons.thermostat, 'T', biometrics.bodyTemperature),
              const SizedBox(width: 10),
              _chip(Icons.favorite, 'HR', biometrics.heartRate),
              const SizedBox(width: 10),
              _chip(Icons.bloodtype, 'BP', biometrics.bloodPressure),
              const SizedBox(width: 10),
              _chip(Icons.air, 'O₂', biometrics.oxygenLevel),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showEditDialog(BuildContext context) async {
    final tempCtrl = TextEditingController(text: biometrics.bodyTemperature);
    final bpCtrl = TextEditingController(text: biometrics.bloodPressure);
    final hrCtrl = TextEditingController(text: biometrics.heartRate);
    final o2Ctrl = TextEditingController(text: biometrics.oxygenLevel);
    final weightCtrl = TextEditingController(text: biometrics.weight);
    final heightCtrl = TextEditingController(text: biometrics.height);

    final result = await showDialog<UserBiometrics>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update Biometrics'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: tempCtrl,
                decoration: const InputDecoration(labelText: 'Body temperature'),
                keyboardType: TextInputType.text,
              ),
              TextField(
                controller: bpCtrl,
                decoration: const InputDecoration(labelText: 'Blood pressure'),
                keyboardType: TextInputType.text,
              ),
              TextField(
                controller: hrCtrl,
                decoration: const InputDecoration(labelText: 'Heart rate'),
                keyboardType: TextInputType.text,
              ),
              TextField(
                controller: o2Ctrl,
                decoration: const InputDecoration(labelText: 'Oxygen level'),
                keyboardType: TextInputType.text,
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: weightCtrl,
                      decoration: const InputDecoration(labelText: 'Weight'),
                      keyboardType: TextInputType.text,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: heightCtrl,
                      decoration: const InputDecoration(labelText: 'Height'),
                      keyboardType: TextInputType.text,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(
                ctx,
                UserBiometrics(
                  bodyTemperature: tempCtrl.text,
                  bloodPressure: bpCtrl.text,
                  heartRate: hrCtrl.text,
                  oxygenLevel: o2Ctrl.text,
                  weight: weightCtrl.text,
                  height: heightCtrl.text,
                  recordedAt: DateTime.now(),
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && onEdit != null) {
      onEdit!(result);
    }
  }
}
