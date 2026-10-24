import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/diagnosis_history_entry.dart';
import '../services/diagnosis_history_service.dart';
import 'diagnosis_history_detail_screen.dart';

/// Shows the user's past self-diagnosis checks with timestamps,
/// risk levels, and matched conditions.
class DiagnosisHistoryScreen extends StatefulWidget {
  const DiagnosisHistoryScreen({super.key});

  @override
  State<DiagnosisHistoryScreen> createState() => _DiagnosisHistoryScreenState();
}

class _DiagnosisHistoryScreenState extends State<DiagnosisHistoryScreen> {
  List<DiagnosisHistoryEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await DiagnosisHistoryService.load();
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text('This will remove all saved diagnosis history.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
        ],
      ),
    );
    if (confirmed == true) {
      await DiagnosisHistoryService.clear();
      await _load();
    }
  }

  Color _riskColor(String risk) {
    return switch (risk.toLowerCase()) {
      'high' => Colors.red,
      'moderate' => Colors.orange,
      'low' => Colors.green,
      _ => Colors.grey,
    };
  }

  String _formatTimestamp(DateTime dt) {
    return '${DateFormat.yMMMd().add_jm().format(dt)} (${dt.timeZoneName})';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
        ),
        title: const Text('Diagnosis History'),
        actions: [
          if (_entries.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _clear,
              tooltip: 'Clear history',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? const Center(child: Text('No diagnosis history yet.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _entries.length,
                  itemBuilder: (context, index) {
                    final entry = _entries[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DiagnosisHistoryDetailScreen(entry: entry),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _formatTimestamp(entry.timestamp),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  Chip(
                                    backgroundColor: _riskColor(entry.riskLevel).withValues(alpha: 0.15),
                                    label: Text(
                                      entry.riskLevel.toUpperCase(),
                                      style: TextStyle(
                                        color: _riskColor(entry.riskLevel),
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    padding: EdgeInsets.zero,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                entry.matchedConditionName ?? 'No condition match',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Symptoms / input: ${entry.symptomSummary}',
                                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                              ),
                              if (entry.notes != null && entry.notes!.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    entry.notes!,
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
