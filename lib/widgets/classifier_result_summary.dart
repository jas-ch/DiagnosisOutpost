import 'package:flutter/material.dart';

import '../models/classifier_result.dart';
import '../services/classifier_service.dart';

/// Reusable rendering of a classifier result: top finding plus the full sorted
/// probability list. For tongue results it can also display the matched TCM
/// wellness pattern and suggestions.
class ClassifierResultSummary extends StatelessWidget {
  final ClassifierResult result;
  final String? category;
  final bool compact;

  const ClassifierResultSummary({
    super.key,
    required this.result,
    this.category,
    this.compact = false,
  });

  static const _groupIcons = {
    'rash': Icons.texture,
    'wounds': Icons.healing,
    'selfie': Icons.face,
    'tongue': Icons.circle,
    'cough': Icons.mic,
  };

  String get _displayCategory => category ?? result.task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sorted = result.probabilities.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (result.topClass.isNotEmpty) _buildTopFinding(theme),
        if (sorted.isNotEmpty && !compact) ...[
          const SizedBox(height: 12),
          Text(
            'All predictions',
            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          ...sorted.map((e) => _buildProbabilityRow(e.key, e.value)),
        ],
      ],
    );
  }

  Widget _buildTopFinding(ThemeData theme) {
    final accent = theme.colorScheme.primary;
    final displayClass = result.topClass.replaceAll('_', ' ');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_groupIcons[_displayCategory.toLowerCase()] ?? Icons.analytics,
              color: accent, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Top finding',
                  style: TextStyle(fontSize: 11, color: accent),
                ),
                const SizedBox(height: 2),
                Text(
                  displayClass,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: accent,
                  ),
                ),
                Text(
                  '${(result.topConfidence * 100).toStringAsFixed(0)}% confidence',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProbabilityRow(String label, double probability) {
    return buildProbabilityRow(label, probability);
  }
}

Widget buildProbabilityRow(String label, double probability) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label.replaceAll('_', ' '),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        SizedBox(
          width: 56,
          child: Stack(
            alignment: Alignment.centerRight,
            children: [
              Container(
                height: 6,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              FractionallySizedBox(
                widthFactor: probability.clamp(0, 1),
                alignment: Alignment.centerRight,
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: Colors.teal,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 44,
          child: Text(
            '${(probability * 100).toStringAsFixed(1)}%',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    ),
  );
}

/// Displays a matched tongue wellness pattern and its suggestions.
class TongueWellnessSummary extends StatelessWidget {
  final TongueWellness wellness;
  final bool compact;

  const TongueWellnessSummary({
    super.key,
    required this.wellness,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${wellness.pattern}, suggesting',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.teal.shade700,
          ),
        ),
        const SizedBox(height: 8),
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
        const SizedBox(height: 8),
        const Text(
          'General wellness only; not medical advice.',
          style: TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ],
    );
  }
}

/// Convenience async builder that loads the wellness match for a tongue result
/// and renders both the classifier summary and the wellness summary.
class TongueResultSummary extends StatelessWidget {
  final ClassifierResult result;
  final bool compact;

  const TongueResultSummary({
    super.key,
    required this.result,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final attrs = ClassifierService.extractTongueAttributes(result);
    return FutureBuilder<TongueWellness?>(
      future: ClassifierService.evaluateTongueWellness(attrs),
      builder: (context, snapshot) {
        final wellness = snapshot.data;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClassifierResultSummary(
              result: result,
              category: 'tongue',
              compact: compact,
            ),
            if (wellness != null && !compact) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TongueWellnessSummary(wellness: wellness),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Detailed tongue result view for the photo category screen: top finding,
/// collapsible "All predictions" list, and a labeled tongue wellness section.
class TonguePhotoDetail extends StatefulWidget {
  final ClassifierResult result;

  const TonguePhotoDetail({super.key, required this.result});

  @override
  State<TonguePhotoDetail> createState() => _TonguePhotoDetailState();
}

class _TonguePhotoDetailState extends State<TonguePhotoDetail> {
  bool _predictionsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sorted = widget.result.probabilities.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return FutureBuilder<TongueWellness?>(
      future: ClassifierService.evaluateTongueWellness(
        ClassifierService.extractTongueAttributes(widget.result),
      ),
      builder: (context, snapshot) {
        final wellness = snapshot.data;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClassifierResultSummary(
              result: widget.result,
              category: 'tongue',
              compact: true,
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () => setState(() => _predictionsExpanded = !_predictionsExpanded),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Text(
                      'All predictions',
                      style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    Icon(
                      _predictionsExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      size: 20,
                      color: Colors.grey.shade700,
                    ),
                  ],
                ),
              ),
            ),
            if (_predictionsExpanded) ...[
              const SizedBox(height: 6),
              ...sorted.map((e) => buildProbabilityRow(e.key, e.value)),
            ],
            const SizedBox(height: 16),
            Text(
              'Tongue wellness',
              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (wellness != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TongueWellnessSummary(wellness: wellness),
              )
            else
              const Text('Loading wellness suggestion…'),
          ],
        );
      },
    );
  }
}
