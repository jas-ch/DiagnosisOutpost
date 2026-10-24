import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:webview_flutter/webview_flutter.dart';

/// Mobile implementation of the PDB viewer using a WebView.
///
/// Loads a custom minimal Mol* viewer so the user can zoom, pan,
/// and rotate the real 3-D protein structure while hiding the State Tree,
/// Structure Tools, and other detailed menus.
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
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) {
              setState(() => _isLoading = false);
            }
          },
          onWebResourceError: (error) {
            if (mounted) {
              setState(() {
                _isLoading = false;
                _hasError = true;
              });
            }
          },
        ),
      );
    _loadViewer(widget.pdbId);
  }

  Future<void> _loadViewer(String pdbId) async {
    try {
      final html = await rootBundle.loadString('assets/html/molstar_viewer.html');
      final name = (widget.molecularName ?? '').replaceAll("'", "\\'");
      var withPdb = html.replaceFirst(
        "var pdbId = params.get('pdb');",
        "var pdbId = '${pdbId.toLowerCase()}';",
      );
      withPdb = withPdb.replaceFirst(
        "var molecularName = params.get('name') || '';",
        "var molecularName = '$name';",
      );
      await _controller.loadHtmlString(withPdb);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_isLoading)
          const Center(child: CircularProgressIndicator()),
        if (_hasError)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 12),
                Text(
                  'Could not load 3-D viewer',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Please check your internet connection.',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
