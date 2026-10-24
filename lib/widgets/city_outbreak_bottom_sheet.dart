import 'package:flutter/material.dart';

import '../models/outbreak_intel.dart';

/// Bottom sheet shown when a user taps a map balloon.
/// Displays exact city-level active infectants and recovered numbers.
class CityOutbreakBottomSheet extends StatelessWidget {
  final OutbreakIntel intel;
  final CityOutbreak city;

  const CityOutbreakBottomSheet({
    super.key,
    required this.intel,
    required this.city,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.teal.shade50,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: intel.heroImage.isNotEmpty
                      ? Image.asset(
                          intel.heroImage,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(Icons.bug_report),
                        )
                      : const Icon(Icons.bug_report),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      intel.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      city.city,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _statCard(
                  context,
                  label: 'Active infectants',
                  value: city.activeInfectants.toString(),
                  icon: Icons.coronavirus,
                  color: Colors.red.shade700,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _statCard(
                  context,
                  label: 'Recovered',
                  value: city.recovered.toString(),
                  icon: Icons.health_and_safety,
                  color: Colors.green.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'For educational and civic awareness only. Not a substitute for professional medical advice.',
              style: TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }
}
