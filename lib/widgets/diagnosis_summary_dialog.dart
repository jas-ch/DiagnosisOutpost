import 'package:flutter/material.dart';

import '../models/diagnosis_summary.dart';
import '../models/outbreak_intel.dart';
import '../screens/outbreak_intel_detail_screen.dart';
import '../services/content_service.dart';
import 'classifier_result_summary.dart';

/// Reusable dialog that shows a diagnosis summary, recommendations, and a
/// button to open the matched disease's scientific detail page.
class DiagnosisSummaryDialog extends StatelessWidget {
  final DiagnosisSummary summary;
  final String title;

  const DiagnosisSummaryDialog({
    super.key,
    required this.summary,
    this.title = 'Diagnosis Summary',
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(),
              const Divider(height: 24),
              if (summary.hasFindings || summary.hasInterpretedFindings) ...[
                _buildSectionTitle('Findings'),
                ...summary.findings.map(_buildFinding),
                ...summary.interpretedFindings.map(_buildInterpretedFinding),
                const SizedBox(height: 12),
              ],
              if (summary.hasSymptoms) ...[
                _buildSectionTitle('Symptoms'),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: summary.symptoms.map(_buildSymptomChip).toList(),
                ),
                const SizedBox(height: 12),
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
                const SizedBox(height: 12),
              ],
              if (summary.customNote != null && summary.customNote!.isNotEmpty) ...[
                _buildSectionTitle('Notes'),
                Text(summary.customNote!, style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 12),
              ],
              if (summary.recommendations.isNotEmpty) ...[
                _buildSectionTitle('Recommended actions'),
                ...summary.recommendations.map(_buildRecommendation),
              ],
              const SizedBox(height: 8),
              const Text(
                'This is not a medical diagnosis. Consult a healthcare provider if you feel unwell.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        if (summary.conditionId.isNotEmpty)
          FilledButton(
            onPressed: () => _openDetail(context),
            child: const Text('Scientific details'),
          ),
      ],
    );
  }

  Widget _buildHeader() {
    final color = switch (summary.riskLevel.toLowerCase()) {
      'low' => Colors.green,
      'moderate' => Colors.amber.shade700,
      _ => Colors.red,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          summary.conditionName,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
              '${summary.probability}% match',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                summary.riskLevel.toUpperCase(),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
      ),
    );
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

  Widget _buildSymptomChip(String symptom) {
    return Chip(
      label: Text(symptom, style: const TextStyle(fontSize: 11)),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
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

  void _openDetail(BuildContext context) async {
    final intel = await _loadIntel();
    if (intel != null && context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => OutbreakIntelDetailScreen(intel: intel)),
      );
    }
  }

  Future<OutbreakIntel?> _loadIntel() async {
    if (summary.conditionId.isEmpty) return null;
    return ContentService.findById(summary.conditionId);
  }
}
