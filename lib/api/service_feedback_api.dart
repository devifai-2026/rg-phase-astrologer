import 'api_client.dart';

/// Astrologer-authored feedback after a delivered service or live ends.
/// Multi-dimension (overall / connection quality / seeker behaviour) + a note.
/// All ratings optional so the form stays skippable. POST /service-feedback.
class ServiceFeedbackApi {
  final ApiClient _c;
  ServiceFeedbackApi(this._c);

  /// Submit feedback for a session (kind:'session') or live (kind:'live').
  /// [sourceId] is the Session id or LiveSession id. Pass only the ratings the
  /// astrologer set (1–5); omit/null skips that dimension.
  Future<void> submit({
    required String kind, // 'session' | 'live'
    required String sourceId,
    int? overall,
    int? connectionQuality,
    int? seekerBehaviour,
    String comment = '',
  }) async {
    await _c.post('/service-feedback', body: {
      'kind': kind,
      'sourceId': sourceId,
      if (overall != null) 'overall': overall,
      if (connectionQuality != null) 'connectionQuality': connectionQuality,
      if (seekerBehaviour != null) 'seekerBehaviour': seekerBehaviour,
      'comment': comment,
    });
  }
}
