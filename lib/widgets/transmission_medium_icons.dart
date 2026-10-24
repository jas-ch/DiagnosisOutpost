import 'package:flutter/material.dart';

/// Maps transmission-medium tags from the YAML to easy-to-understand
/// icons. When [showLabels] is true, the tags render as small chips;
/// otherwise they render as compact colored circles with tooltips.
class TransmissionMediumIcons extends StatelessWidget {
  final List<String> media;
  final double iconSize;
  final bool showLabels;

  const TransmissionMediumIcons({
    super.key,
    required this.media,
    this.iconSize = 20,
    this.showLabels = false,
  });

  static const _map = {
    'airborne': (Icons.air, 'Airborne', Colors.blue),
    'food': (Icons.fastfood, 'Food', Colors.orange),
    'directcontact': (Icons.front_hand, 'Direct contact', Colors.red),
    'serialcontact': (Icons.people, 'Serial contact', Colors.purple),
    'animaltohuman': (Icons.pets, 'Animal to human', Colors.brown),
    'humantohuman': (Icons.people_alt, 'Human to human', Colors.indigo),
  };

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: media.map((m) {
        final key = m.toLowerCase().replaceAll('_', '').replaceAll(' ', '');
        final entry = _map[key] ?? (Icons.help_outline, m, Colors.grey);
        final color = entry.$3;

        if (showLabels) {
          return Chip(
            avatar: Icon(entry.$1, size: iconSize, color: color),
            label: Text(entry.$2, style: const TextStyle(fontSize: 10)),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            backgroundColor: color.withValues(alpha: 0.1),
            side: BorderSide.none,
          );
        }

        return Tooltip(
          message: entry.$2,
          child: Container(
            width: iconSize + 8,
            height: iconSize + 8,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(entry.$1, size: iconSize, color: color),
          ),
        );
      }).toList(),
    );
  }
}
