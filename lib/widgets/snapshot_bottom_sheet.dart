import 'package:flutter/material.dart';

import '../models/outbreak_snapshot.dart';

/// Bottom sheet shown when a user taps a live snapshot map marker.
class SnapshotBottomSheet extends StatelessWidget {
  final OutbreakSnapshot snapshot;

  const SnapshotBottomSheet({
    super.key,
    required this.snapshot,
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
                child: const Icon(Icons.coronavirus),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      snapshot.conditionName ?? 'Unknown condition',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      snapshot.displayLocation,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    Text(
                      'Source: ${snapshot.source}',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
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
                  label: snapshot.metricName ?? 'Value',
                  value: snapshot.displayValue,
                  icon: Icons.show_chart,
                  color: Colors.blue.shade700,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _statCard(
                  context,
                  label: 'Report date',
                  value: snapshot.reportDate != null
                      ? '${snapshot.reportDate!.month}/${snapshot.reportDate!.day}/${snapshot.reportDate!.year}'
                      : '—',
                  icon: Icons.calendar_today,
                  color: Colors.purple.shade700,
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
              'Live public-health data for educational and civic awareness only. Not a substitute for professional medical advice.',
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
