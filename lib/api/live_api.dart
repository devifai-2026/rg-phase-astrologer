import 'api_client.dart';
import 'session_api.dart' show RtcToken;

/// Result of going live: the broadcast id + Agora broadcaster credentials.
class GoLiveResult {
  final String liveSessionId;
  final String channelName;
  final DateTime? startedAt; // broadcast start → drives the broadcaster timer
  final RtcToken token;
  const GoLiveResult({required this.liveSessionId, required this.channelName, required this.startedAt, required this.token});

  factory GoLiveResult.fromJson(Map<String, dynamic> j) {
    final ls = Map<String, dynamic>.from(j['liveSession'] as Map);
    final tok = Map<String, dynamic>.from(j['token'] as Map);
    return GoLiveResult(
      liveSessionId: (ls['_id'] ?? ls['id'] ?? '').toString(),
      channelName: (ls['channelName'] ?? tok['channelName'] ?? '').toString(),
      startedAt: ls['startedAt'] != null ? DateTime.tryParse(ls['startedAt'].toString())?.toLocal() : null,
      token: RtcToken.fromJson(tok),
    );
  }
}

/// One of the astrologer's past (or current) broadcasts, with summary stats.
class LiveHistoryItem {
  final String id;
  final String title;
  final String topic;
  final String status; // 'live' | 'ended'
  final DateTime? startedAt;
  final int durationSec;
  final int peakViewers;
  final int totalJoins;
  final int superchatTotal;
  final int giftCount;
  final int commentCount;
  final int blockedCount; // AI moderator: contact-info/link drops
  final int mutedCount; // AI moderator: abuse/spam/self-promo mutes
  final bool hasSummary;

  const LiveHistoryItem({
    required this.id,
    required this.title,
    required this.topic,
    required this.status,
    required this.startedAt,
    required this.durationSec,
    required this.peakViewers,
    this.totalJoins = 0,
    required this.superchatTotal,
    this.giftCount = 0,
    required this.commentCount,
    this.blockedCount = 0,
    this.mutedCount = 0,
    required this.hasSummary,
  });

  factory LiveHistoryItem.fromJson(Map<String, dynamic> j) => LiveHistoryItem(
        id: (j['id'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        topic: (j['topic'] ?? '').toString(),
        status: (j['status'] ?? 'ended').toString(),
        startedAt: j['startedAt'] != null ? DateTime.tryParse(j['startedAt'].toString()) : null,
        durationSec: (j['durationSec'] as num?)?.toInt() ?? 0,
        peakViewers: (j['peakViewers'] as num?)?.toInt() ?? 0,
        totalJoins: (j['totalJoins'] as num?)?.toInt() ?? 0,
        superchatTotal: (j['superchatTotal'] as num?)?.toInt() ?? 0,
        giftCount: (j['giftCount'] as num?)?.toInt() ?? 0,
        commentCount: (j['commentCount'] as num?)?.toInt() ?? 0,
        blockedCount: (j['blockedCount'] as num?)?.toInt() ?? 0,
        mutedCount: (j['mutedCount'] as num?)?.toInt() ?? 0,
        hasSummary: j['hasSummary'] == true,
      );
}

/// One poll from a past broadcast, with its final vote tallies.
class LivePollResult {
  final int no; // running order (1,2,3…)
  final String question;
  final String source; // 'ai' | 'manual'
  final int totalVotes;
  final List<LivePollOption> options;
  const LivePollResult({required this.no, required this.question, required this.source, required this.totalVotes, required this.options});

  factory LivePollResult.fromJson(Map<String, dynamic> j) => LivePollResult(
        no: (j['no'] as num?)?.toInt() ?? 0,
        question: (j['question'] ?? '').toString(),
        source: (j['source'] ?? 'ai').toString(),
        totalVotes: (j['totalVotes'] as num?)?.toInt() ?? 0,
        options: ((j['options'] as List?) ?? const [])
            .map((o) => LivePollOption.fromJson(Map<String, dynamic>.from(o as Map)))
            .toList(),
      );
}

class LivePollOption {
  final String text;
  final int votes;
  final int pct; // 0–100 share of total votes (server-computed)
  const LivePollOption({required this.text, required this.votes, required this.pct});
  factory LivePollOption.fromJson(Map<String, dynamic> j) => LivePollOption(
        text: (j['text'] ?? '').toString(),
        votes: (j['votes'] as num?)?.toInt() ?? 0,
        pct: (j['pct'] as num?)?.toInt() ?? 0,
      );
}

/// Full recap analytics for one broadcast: audience metrics, the AI-moderator
/// scorecard, and every poll with its vote tallies. Powers the recap screen.
class LiveDetail {
  final String id;
  final String title;
  final String topic;
  final String status;
  final int durationSec;
  final int peakViewers;
  final int totalJoins;
  final int commentCount;
  final int superchatTotal;
  final int giftCount;
  // AI moderator scorecard.
  final int blockedCount; // contact info / links removed
  final int mutedCount; // abuse / spam / self-promo muted
  final int shownCount; // comments that passed moderation
  final String moderationNote;
  final List<LivePollResult> polls;
  final String aiSummary;
  final List<Map<String, dynamic>> aiTopQuestions; // [{question, count}]

  const LiveDetail({
    required this.id,
    required this.title,
    required this.topic,
    required this.status,
    required this.durationSec,
    required this.peakViewers,
    required this.totalJoins,
    required this.commentCount,
    required this.superchatTotal,
    required this.giftCount,
    required this.blockedCount,
    required this.mutedCount,
    required this.shownCount,
    required this.moderationNote,
    required this.polls,
    required this.aiSummary,
    required this.aiTopQuestions,
  });

  factory LiveDetail.fromJson(Map<String, dynamic> j) {
    final mod = (j['moderation'] is Map) ? Map<String, dynamic>.from(j['moderation']) : <String, dynamic>{};
    return LiveDetail(
      id: (j['id'] ?? '').toString(),
      title: (j['title'] ?? '').toString(),
      topic: (j['topic'] ?? '').toString(),
      status: (j['status'] ?? 'ended').toString(),
      durationSec: (j['durationSec'] as num?)?.toInt() ?? 0,
      peakViewers: (j['peakViewers'] as num?)?.toInt() ?? 0,
      totalJoins: (j['totalJoins'] as num?)?.toInt() ?? 0,
      commentCount: (j['commentCount'] as num?)?.toInt() ?? 0,
      superchatTotal: (j['superchatTotal'] as num?)?.toInt() ?? 0,
      giftCount: (j['giftCount'] as num?)?.toInt() ?? 0,
      blockedCount: (mod['blockedCount'] as num?)?.toInt() ?? 0,
      mutedCount: (mod['mutedCount'] as num?)?.toInt() ?? 0,
      shownCount: (mod['shownCount'] as num?)?.toInt() ?? 0,
      moderationNote: (mod['note'] ?? '').toString(),
      polls: ((j['polls'] as List?) ?? const [])
          .map((p) => LivePollResult.fromJson(Map<String, dynamic>.from(p as Map)))
          .toList(),
      aiSummary: (j['aiSummary'] ?? '').toString(),
      aiTopQuestions: ((j['aiTopQuestions'] as List?) ?? const [])
          .map((q) => Map<String, dynamic>.from(q as Map))
          .toList(),
    );
  }
}

/// REST surface for the astrologer's live broadcast: go live, end, trigger an
/// AI poll, list past lives, fetch a recap. Comments/gifts/poll-tallies arrive
/// over the socket while live.
class LiveApi {
  final ApiClient _c;
  LiveApi(this._c);

  Future<GoLiveResult> goLive({required String title, required String topic}) async {
    final data = await _c.post('/live/go-live', body: {'title': title, 'topic': topic});
    return GoLiveResult.fromJson(Map<String, dynamic>.from(data as Map));
  }

  /// End the broadcast. [reason] labels why ('manual' tap End, or 'minimize'
  /// when auto-ended after the app was backgrounded past the grace window). The
  /// backend only accepts these two client reasons; it has its own server-side
  /// reasons (disconnect/stale) for drops the client can't report.
  Future<Map<String, dynamic>> end(String liveSessionId, {String reason = 'manual'}) async {
    final data = await _c.post('/live/$liveSessionId/end', body: {'reason': reason});
    return Map<String, dynamic>.from(data as Map);
  }

  /// Ask the backend to auto-generate (AI) and broadcast a poll to the room.
  Future<Map<String, dynamic>> createPoll(String liveSessionId) async {
    final data = await _c.post('/live/$liveSessionId/poll');
    return Map<String, dynamic>.from(data as Map);
  }

  /// The astrologer's own past/current broadcasts (newest first).
  Future<List<LiveHistoryItem>> mine() async {
    final data = await _c.get('/live/mine');
    final raw = (data as List?) ?? const [];
    return raw.map((e) => LiveHistoryItem.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  /// AI recap of a broadcast — generated once on the server and cached in DB.
  Future<String> summary(String liveSessionId) async {
    final data = await _c.get('/live/$liveSessionId/summary');
    final m = Map<String, dynamic>.from(data as Map);
    return (m['summary'] ?? '').toString();
  }

  /// Full recap analytics: AI-moderator scorecard + every poll with vote tallies
  /// + audience metrics. Drives the recap screen (end-of-live + past-card tap).
  Future<LiveDetail> detail(String liveSessionId) async {
    final data = await _c.get('/live/$liveSessionId/detail');
    return LiveDetail.fromJson(Map<String, dynamic>.from(data as Map));
  }
}
