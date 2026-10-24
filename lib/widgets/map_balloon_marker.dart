import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/outbreak_intel.dart';

/// A map marker that renders as a "balloon" icon with a heat ring.
/// Tapping the balloon calls [onTap] with the associated city outbreak.
class MapBalloonMarker extends Marker {
  MapBalloonMarker({
    required OutbreakIntel intel,
    required CityOutbreak city,
    required VoidCallback onTap,
    super.key,
  }) : super(
          point: LatLng(city.lat, city.lng),
          width: 64,
          height: 64,
          child: _BalloonIcon(
            intel: intel,
            city: city,
            onTap: onTap,
          ),
        );
}

class _BalloonIcon extends StatelessWidget {
  final OutbreakIntel intel;
  final CityOutbreak city;
  final VoidCallback onTap;

  const _BalloonIcon({
    required this.intel,
    required this.city,
    required this.onTap,
  });

  Color _heatColor(int active) {
    if (active >= 1000) return Colors.red;
    if (active >= 300) return Colors.orange;
    if (active >= 50) return Colors.amber;
    return Colors.yellow;
  }

  double _heatRadius(int active) {
    if (active >= 1000) return 28;
    if (active >= 300) return 22;
    if (active >= 50) return 18;
    return 14;
  }

  @override
  Widget build(BuildContext context) {
    final heatColor = _heatColor(city.activeInfectants);
    final heatRadius = _heatRadius(city.activeInfectants);

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Heat ring
          Container(
            width: heatRadius * 2,
            height: heatRadius * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: heatColor.withValues(alpha: 0.25),
              border: Border.all(color: heatColor.withValues(alpha: 0.6), width: 1.5),
            ),
          ),
          // Balloon icon
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: heatColor, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipOval(
              child: intel.heroImage.isNotEmpty
                  ? Image.asset(
                      intel.heroImage,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(Icons.bug_report, size: 16, color: heatColor),
                    )
                  : Icon(Icons.bug_report, size: 16, color: heatColor),
            ),
          ),
        ],
      ),
    );
  }
}
