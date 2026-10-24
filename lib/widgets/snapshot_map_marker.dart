import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'dart:math' show log;

import '../models/outbreak_intel.dart';
import '../models/outbreak_snapshot.dart';

/// A circular map marker that renders a live outbreak snapshot using the
/// matched disease's hero image. The marker diameter scales with the
/// snapshot's severity/case count, and a colored rarity circle is used as a
/// fallback when the image is missing or fails to load.
class SnapshotMapMarker extends Marker {
  final OutbreakSnapshot snapshot;
  final OutbreakIntel? intel;

  SnapshotMapMarker({
    required this.snapshot,
    required this.intel,
    required super.point,
    required VoidCallback onTap,
    super.key,
  }) : super(
          width: _markerSize(snapshot),
          height: _markerSize(snapshot),
          child: _SnapshotDot(
            snapshot: snapshot,
            intel: intel,
            onTap: onTap,
          ),
        );

  static double _markerSize(OutbreakSnapshot snapshot) {
    final value = snapshot.metricValue ?? snapshot.caseCount ?? 0;
    if (value <= 0) return 24.0;
    final t = log(1 + value) / log(100001);
    return (24.0 + 48.0 * t).clamp(24.0, 72.0);
  }
}

class _SnapshotDot extends StatelessWidget {
  final OutbreakSnapshot snapshot;
  final OutbreakIntel? intel;
  final VoidCallback onTap;

  const _SnapshotDot({
    required this.snapshot,
    required this.intel,
    required this.onTap,
  });

  Color get _fallbackColor {
    final rarity = intel?.rarity.toLowerCase() ?? 'common';
    return switch (rarity) {
      'legendary' => Colors.purple,
      'epic' => Colors.deepPurple,
      'rare' => Colors.blue,
      'uncommon' => Colors.green,
      _ => Colors.teal,
    };
  }

  String? get _heroImage {
    final path = intel?.heroImage;
    return path != null && path.isNotEmpty ? path : null;
  }

  @override
  Widget build(BuildContext context) {
    final imagePath = _heroImage;
    final fallbackColor = _fallbackColor;
    final size = SnapshotMapMarker._markerSize(snapshot);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: fallbackColor,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: imagePath != null
            ? Image.asset(
                imagePath,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallbackIcon(fallbackColor, size),
              )
            : _fallbackIcon(fallbackColor, size),
      ),
    );
  }

  Widget _fallbackIcon(Color color, double size) {
    return Center(
      child: Icon(
        Icons.bug_report,
        color: Colors.white,
        size: size * 0.45,
      ),
    );
  }
}
