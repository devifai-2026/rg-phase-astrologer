import 'api_client.dart';
import 'token_store.dart';

/// One CMS/legal document from the backend (Terms, Privacy…).
class LegalContent {
  final String key;
  final String title;
  final String body; // HTML
  const LegalContent({required this.key, required this.title, required this.body});

  bool get hasBody => body.trim().isNotEmpty;

  factory LegalContent.fromJson(Map<String, dynamic> j) => LegalContent(
        key: (j['key'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        body: (j['body'] ?? '').toString(),
      );
}

/// Public site-content reads (GET /content/:key). Used for Terms & Privacy on
/// the auth screen.
class ContentApi {
  // Public reads need no auth; an empty TokenStore just omits the Bearer header.
  ContentApi([ApiClient? client]) : _c = client ?? ApiClient(TokenStore());
  final ApiClient _c;

  /// Fetch a published doc by key, or null if missing/unpublished/unreachable.
  Future<LegalContent?> fetch(String key) async {
    try {
      final data = await _c.get('/content/$key');
      final doc = LegalContent.fromJson(data as Map<String, dynamic>);
      return doc.hasBody ? doc : null;
    } catch (_) {
      return null;
    }
  }
}
