import 'package:flutter/material.dart';

import 'pdb_viewer_stub.dart'
    if (dart.library.html) 'pdb_viewer_web.dart' as platform;

/// Embeds an interactive RCSB PDB or Molstar 3-D protein structure viewer.
class PdbViewer extends StatelessWidget {
  final String pdbId;
  final String? molecularName;

  const PdbViewer({
    super.key,
    required this.pdbId,
    this.molecularName,
  });

  @override
  Widget build(BuildContext context) {
    return platform.PdbViewer(
      pdbId: pdbId,
      molecularName: molecularName,
    );
  }
}
