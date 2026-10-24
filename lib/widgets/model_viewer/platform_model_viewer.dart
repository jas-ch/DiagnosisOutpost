import 'package:flutter/material.dart';

import 'platform_model_viewer_stub.dart'
    if (dart.library.html) 'platform_model_viewer_web.dart' as platform;

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
    return platform.PlatformModelViewer(
      src: src,
      alt: alt,
      ar: ar,
      autoRotate: autoRotate,
      cameraControls: cameraControls,
      backgroundColor: backgroundColor,
    );
  }
}
