// Real (backend-backed) chat-recap models for Feature 1 — distinct from the
// demo shapes in ai_models.dart (ChatSummary/MockAi). These map the JSON
// returned by GET /api/ai/recaps and /api/ai/recaps/:id.

/// A product the AI suggested, tied to a real catalogue Product (populated).
class RecapSuggestion {
  final String id; // the suggestion sub-document _id (used to keep/drop on approve)
  final String productId;
  final String productName;
  final int price;
  final int mrp;
  final String? image;
  final String title; // short remedy headline
  final String? reason; // why the AI tied it to this chat
  String status; // pending | approved | rejected
  bool keep; // local UI toggle (whether it ships to the user on approve)

  RecapSuggestion({
    required this.id,
    required this.productId,
    required this.productName,
    required this.price,
    this.mrp = 0,
    this.image,
    required this.title,
    this.reason,
    this.status = 'pending',
    this.keep = true,
  });

  factory RecapSuggestion.fromJson(Map<String, dynamic> j) {
    // `product` is populated (an object) or, defensively, a bare id string.
    final prod = j['product'];
    final pm = prod is Map ? Map<String, dynamic>.from(prod) : <String, dynamic>{};
    final images = (pm['images'] as List?)?.map((e) => e.toString()).toList() ?? const [];
    return RecapSuggestion(
      id: (j['_id'] ?? j['id'] ?? '').toString(),
      productId: (pm['_id'] ?? pm['id'] ?? (prod is String ? prod : '')).toString(),
      productName: (pm['name'] ?? '').toString(),
      price: (pm['price'] as num?)?.toInt() ?? 0,
      mrp: (pm['mrp'] as num?)?.toInt() ?? 0,
      image: images.isNotEmpty ? images.first : null,
      title: (j['title'] ?? 'Suggested item').toString(),
      reason: j['reason']?.toString(),
      status: (j['status'] ?? 'pending').toString(),
      keep: (j['status'] ?? 'pending').toString() != 'rejected',
    );
  }
}

/// A follow-up reminder the AI proposed from the chat. Two kinds:
///  - `mantra`: a recurring daily reminder (a 14-day course), fired 5 min before
///    [timeOfDay] ("HH:MM").
///  - `event`: a one-off reminder on [date] ("YYYY-MM-DD").
/// The astrologer edits these inline and toggles [keep] to drop one without
/// deleting it; on approve the backend schedules the kept reminders.
class RecapReminder {
  final String id; // the reminder sub-document _id (may be empty for new ones)
  String type; // mantra | event
  String title;
  String reason;
  String? timeOfDay; // "HH:MM" — mantra only
  String? date; // "YYYY-MM-DD" — event only
  bool keep; // local UI toggle (whether it gets scheduled on approve)

  RecapReminder({
    required this.id,
    required this.type,
    required this.title,
    required this.reason,
    this.timeOfDay,
    this.date,
    this.keep = true,
  });

  bool get isMantra => type == 'mantra';
  bool get isEvent => type == 'event';

  factory RecapReminder.fromJson(Map<String, dynamic> j) => RecapReminder(
        id: (j['_id'] ?? j['id'] ?? '').toString(),
        type: (j['type'] ?? 'event').toString(),
        title: (j['title'] ?? '').toString(),
        reason: (j['reason'] ?? '').toString(),
        timeOfDay: j['timeOfDay']?.toString(),
        date: j['date']?.toString(),
        keep: j['keep'] != false,
      );

  /// Serialised for the PATCH body — only the fields the backend accepts.
  Map<String, dynamic> toJson() => {
        'type': type,
        'title': title,
        'reason': reason,
        if (timeOfDay != null) 'timeOfDay': timeOfDay,
        if (date != null) 'date': date,
        'keep': keep,
      };
}

/// The full recap the astrologer reviews before publishing.
class Recap {
  final String id;
  final String sessionId;
  final String status; // pending | approved | rejected | sent
  String summary;
  String sentiment;
  List<String> keyTopics;
  final List<RecapSuggestion> suggestions;
  final List<RecapReminder> reminders;
  final bool generatedByMock;
  final DateTime? createdAt;

  Recap({
    required this.id,
    required this.sessionId,
    required this.status,
    required this.summary,
    required this.sentiment,
    required this.keyTopics,
    required this.suggestions,
    this.reminders = const [],
    this.generatedByMock = false,
    this.createdAt,
  });

  bool get isPending => status == 'pending';
  bool get isSent => status == 'sent';

  factory Recap.fromJson(Map<String, dynamic> j) => Recap(
        id: (j['_id'] ?? j['id'] ?? '').toString(),
        sessionId: (j['sessionId'] ?? '').toString(),
        status: (j['status'] ?? 'pending').toString(),
        summary: (j['summary'] ?? '').toString(),
        sentiment: (j['sentiment'] ?? '').toString(),
        keyTopics: (j['keyTopics'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        suggestions: (j['suggestions'] as List?)
                ?.map((e) => RecapSuggestion.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            const [],
        reminders: (j['reminders'] as List?)
                ?.map((e) => RecapReminder.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            const [],
        generatedByMock: j['generatedByMock'] == true,
        createdAt: DateTime.tryParse((j['createdAt'] ?? '').toString()),
      );
}
