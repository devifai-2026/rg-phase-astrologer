import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../api/content_api.dart';
import '../../i18n/strings.dart';
import '../../theme/rg_colors.dart';

/// Fetches an admin-authored legal doc (Terms/Privacy) by key and renders its
/// HTML body in a WebView, styled to the app theme. Shows an empty state if the
/// backend has no published content for that key.
class LegalScreen extends StatefulWidget {
  final String contentKey; // 'terms' | 'privacy'
  final String fallbackTitle;
  const LegalScreen({super.key, required this.contentKey, required this.fallbackTitle});

  @override
  State<LegalScreen> createState() => _LegalScreenState();
}

class _LegalScreenState extends State<LegalScreen> {
  final _api = ContentApi();
  WebViewController? _controller;
  LegalContent? _doc;
  bool _loading = true;
  bool _built = false;

  @override
  void initState() {
    super.initState();
    _api.fetch(widget.contentKey).then((doc) {
      if (mounted) setState(() { _doc = doc; _loading = false; });
    });
  }

  String _wrap(RgColors c, String html) {
    String hex(Color x) => '#${x.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
    return '''
<!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<style>
  :root { color-scheme: ${c.ground.computeLuminance() < 0.5 ? 'dark' : 'light'}; }
  body { margin:0; padding:18px 16px 32px; background:${hex(c.ground)}; color:${hex(c.ink)};
         font-family:-apple-system,Roboto,'Segoe UI',sans-serif; font-size:15px; line-height:1.65; }
  h1,h2,h3 { color:${hex(c.ink)}; line-height:1.3; margin:1.2em 0 .4em; }
  h1{font-size:20px} h2{font-size:17px} h3{font-size:15px}
  p,li { color:${hex(c.muted)}; }
  a { color:${hex(c.red)}; }
  ul,ol { padding-left:22px; }
  hr { border:none; border-top:1px solid ${hex(c.line)}; margin:18px 0; }
</style></head><body>$html</body></html>''';
  }

  void _ensure(RgColors c) {
    if (_built || _doc == null || !_doc!.hasBody) return;
    _built = true;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setBackgroundColor(c.ground)
      ..loadHtmlString(_wrap(c, _doc!.body));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    _ensure(c);
    final title = (_doc?.title.isNotEmpty ?? false) ? _doc!.title : widget.fallbackTitle;
    return Scaffold(
      backgroundColor: c.ground,
      appBar: AppBar(
        backgroundColor: c.ground,
        title: Text(title, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 17)),
        iconTheme: IconThemeData(color: c.ink),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: c.red))
          : (_controller != null
              ? WebViewWidget(controller: _controller!)
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(Strings.of(context).thisDocumentWillBeAvailableSoon,
                        textAlign: TextAlign.center, style: TextStyle(color: c.muted, fontSize: 14)),
                  ),
                )),
    );
  }
}
