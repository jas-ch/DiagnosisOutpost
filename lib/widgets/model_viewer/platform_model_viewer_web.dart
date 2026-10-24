// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;
import 'dart:ui_web' as ui;

import 'package:flutter/material.dart';

class PlatformModelViewer extends StatefulWidget {
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
  State<PlatformModelViewer> createState() => _PlatformModelViewerState();
}

class _PlatformModelViewerState extends State<PlatformModelViewer> {
  static int _counter = 0;
  late final String _viewType;

  String get _resolvedSrc {
    // Flutter web serves assets under /assets/<asset-key>. Local asset keys
    // start with "assets/", so they must be prefixed to load correctly in the
    // browser. Remote URLs and bundled model-viewer placeholders are left as-is.
    final src = widget.src;
    if (src.startsWith('assets/') && !src.startsWith('assets/assets/')) {
      return 'assets/assets/${src.substring('assets/'.length)}';
    }
    return src;
  }

  @override
  void initState() {
    super.initState();
    _viewType = 'model-viewer-${widget.src}-${_counter++}';

    // ignore: undefined_prefixed_name
    ui.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final element = html.Element.tag('model-viewer')
        ..setAttribute('src', _resolvedSrc)
        ..setAttribute('alt', widget.alt)
        ..setAttribute('auto-rotate', '')
        ..setAttribute('camera-controls', '')
        ..setAttribute('ar', '')
        ..setAttribute('shadow-intensity', '1')
        ..style.width = '100%'
        ..style.height = '100%';

      final bg = widget.backgroundColor;
      if (bg != null) {
        element.style.backgroundColor =
            '#${(bg.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
      }

      return element;
    });
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
