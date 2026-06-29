import 'api_client.dart';

/// One row of the astrologer's session history (GET /sessions). The seeker is
/// ALWAYS anonymous on the astrologer side — the backend exposes only an alias
/// (`seeker.alias`), never the real user. `astrologerEarning` is the
/// astrologer's share for the session, in whole rupees.
class SessionItem {
  final String sessionId;
  final String type; // chat | call | video
  final String status; // completed | missed | rejected | cancelled | ...
  final int durationSec;
  final int billedMinutes;
  final int totalAmount; // total charged to the seeker (coins/₹)
  final int astrologerEarning; // the astrologer's share, whole rupees
  final String seekerAlias; // anonymous seeker name (never the real user)
  final bool canViewChat; // completed chat still within retention
  final DateTime? startedAt;
  final DateTime? endedAt;
  final DateTime? createdAt;

  const SessionItem({
    required this.sessionId,
    required this.type,
    required this.status,
    this.durationSec = 0,
    this.billedMinutes = 0,
    this.totalAmount = 0,
    this.astrologerEarning = 0,
    this.seekerAlias = 'Seeker',
    this.canViewChat = false,
    this.startedAt,
    this.endedAt,
    this.createdAt,
  });

  /// A completed (billed) consultation the astrologer earned from.
  bool get isCompleted => status == 'completed';

  /// Whole minutes for display (rounds the raw seconds up to at least the
  /// billed minutes when present).
  int get minutes => billedMinutes > 0 ? billedMinutes : (durationSec / 60).round();

  static DateTime? _date(dynamic v) =>
      v != null ? DateTime.tryParse(v.toString())?.toLocal() : null;

  factory SessionItem.fromJson(Map<String, dynamic> j) {
    // For astrologer viewers the backend strips the real user and exposes
    // `seeker: { alias }`. Fall back to a flat `seekerAlias` if present.
    final seeker = j['seeker'];
    final alias = (seeker is Map ? seeker['alias'] : null) ?? j['seekerAlias'] ?? 'Seeker';
    return SessionItem(
      sessionId: (j['sessionId'] ?? j['id'] ?? j['_id'] ?? '').toString(),
      type: (j['type'] ?? 'chat').toString(),
      status: (j['status'] ?? '').toString(),
      durationSec: (j['durationSec'] as num?)?.toInt() ?? 0,
      billedMinutes: (j['billedMinutes'] as num?)?.toInt() ?? 0,
      totalAmount: (j['totalAmount'] as num?)?.toInt() ?? 0,
      astrologerEarning: (j['astrologerEarning'] as num?)?.toInt() ?? 0,
      seekerAlias: alias.toString(),
      canViewChat: j['canViewChat'] == true,
      startedAt: _date(j['startedAt']),
      endedAt: _date(j['endedAt']),
      createdAt: _date(j['createdAt']),
    );
  }
}

/// A chat message in a session (user or system; text or image). Mirrors the
/// backend ChatMessage. On the astrologer side the seeker is anonymous.
class ChatMsg {
  final String id;
  final String sessionId;
  final String kind; // user | system
  final String? sender; // null for system
  final String? message;
  final String? mediaUrl;
  final String? mediaType;
  final DateTime timestamp;

  const ChatMsg({
    required this.id,
    required this.sessionId,
    this.kind = 'user',
    this.sender,
    this.message,
    this.mediaUrl,
    this.mediaType,
    required this.timestamp,
  });

  bool get isSystem => kind == 'system';
  bool get hasImage => mediaUrl != null && mediaUrl!.isNotEmpty;

  factory ChatMsg.fromJson(Map<String, dynamic> j) => ChatMsg(
        id: (j['id'] ?? j['_id'] ?? '').toString(),
        sessionId: (j['sessionId'] ?? '').toString(),
        kind: (j['kind'] ?? 'user').toString(),
        sender: j['sender']?.toString(),
        message: j['message']?.toString(),
        mediaUrl: j['mediaUrl']?.toString(),
        mediaType: j['mediaType']?.toString(),
        timestamp: DateTime.tryParse((j['timestamp'] ?? '').toString())?.toLocal() ?? DateTime.now(),
      );
}

/// Agora join credentials for a media (call/video) session.
class RtcToken {
  final String appId;
  final String token;
  final String channelName;
  final int uid;
  const RtcToken({required this.appId, required this.token, required this.channelName, required this.uid});
  factory RtcToken.fromJson(Map<String, dynamic> j) => RtcToken(
        appId: (j['appId'] ?? '').toString(),
        token: (j['token'] ?? '').toString(),
        channelName: (j['channelName'] ?? '').toString(),
        uid: (j['uid'] as num?)?.toInt() ?? 0,
      );
}

/// REST surface for the astrologer's side of a consultation. Accept/reject/end
/// also have socket equivalents; these are the HTTP path (used from a push tap
/// where the socket may not be connected yet) + history loading.
class SessionApi {
  final ApiClient _c;
  SessionApi(this._c);

  /// Accept an incoming request. For call/video this returns the Agora token.
  Future<RtcToken?> accept(String sessionId) async {
    final data = await _c.post('/sessions/$sessionId/accept');
    final tok = (data is Map) ? data['token'] : null;
    return tok is Map ? RtcToken.fromJson(Map<String, dynamic>.from(tok)) : null;
  }

  Future<void> reject(String sessionId) => _c.post('/sessions/$sessionId/reject');
  Future<void> end(String sessionId) => _c.post('/sessions/$sessionId/end');

  /// Agora token for a media session (if not returned by accept).
  Future<RtcToken> token(String sessionId) async {
    final data = await _c.get('/sessions/$sessionId/token');
    return RtcToken.fromJson(Map<String, dynamic>.from(data as Map));
  }

  /// A session's detail (used from a push tap to recover the alias + type).
  Future<Map<String, dynamic>> detail(String sessionId) async {
    final data = await _c.get('/sessions/$sessionId');
    return Map<String, dynamic>.from(data as Map);
  }

  /// The astrologer's currently-LIVE session (status accepted|ongoing) to RESUME
  /// after an app kill, or null if none. Returns the session map (aliased seeker)
  /// + a fresh media token. Best-effort; null on any failure.
  Future<({Map<String, dynamic> session, RtcToken? token})?> active() async {
    try {
      final data = await _c.get('/sessions/me/active');
      if (data == null || data is! Map || data['session'] == null) return null;
      final session = Map<String, dynamic>.from(data['session'] as Map);
      final tok = data['token'];
      final token = tok is Map ? RtcToken.fromJson(Map<String, dynamic>.from(tok)) : null;
      return (session: session, token: token);
    } catch (_) {
      return null;
    }
  }

  Future<List<ChatMsg>> messages(String sessionId, {int page = 1, int limit = 50}) async {
    final data = await _c.get('/sessions/$sessionId/messages', query: {'page': page, 'limit': limit});
    final raw = (data is Map ? (data['items'] as List?) : (data as List?)) ?? [];
    return raw.map((e) => ChatMsg.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  /// The astrologer's session history (GET /sessions), newest first. Each item
  /// carries the anonymous seeker alias, duration, and the astrologer's earning.
  /// Pass [type] (chat|call|video) to filter to a single service.
  Future<List<SessionItem>> history({int page = 1, int limit = 30, String? type}) async {
    final data = await _c.get('/sessions', query: {
      'page': page,
      'limit': limit,
      'type': ?type,
    });
    final raw = (data is Map ? (data['items'] as List?) : (data as List?)) ?? [];
    return raw.map((e) => SessionItem.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }
}
