// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:ui_web' as ui;

import 'package:flutter/material.dart';

/// Web implementation of the PDB viewer using an embedded iframe.
class PdbViewer extends StatefulWidget {
  final String pdbId;
  final String? molecularName;

  const PdbViewer({
    super.key,
    required this.pdbId,
    this.molecularName,
  });

  @override
  State<PdbViewer> createState() => _PdbViewerState();
}

class _PdbViewerState extends State<PdbViewer> {
  static int _counter = 0;
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType = 'pdb-viewer-${widget.pdbId}-${_counter++}';

    // ignore: undefined_prefixed_name
    ui.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final url = 'https://www.rcsb.org/3d-view/${widget.pdbId}';
      final iframe = html.IFrameElement()
        ..src = url
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.border = 'none';
      return iframe;
    });
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
