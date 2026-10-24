import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

class PlatformModelViewer extends StatelessWidget {
  final String src;
  final String alt;
  final bool ar;
  final bool autoRotate;
  final bool cameraControls;
  final Color? backgroundColor;

  const PlatformModelViewer({
    super.key,
    required this.src,
    required this.alt,
    this.ar = true,
    this.autoRotate = true,
    this.cameraControls = true,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    if (src.isEmpty) {
      return Container(
        color: backgroundColor ?? Colors.grey.shade200,
        child: const Center(child: Text('No model available')),
      );
    }

    return ModelViewer(
      src: src,
      alt: alt,
      ar: ar,
      autoRotate: autoRotate,
      cameraControls: cameraControls,
      backgroundColor: backgroundColor ?? Colors.grey.shade200,
    );
  }
}
