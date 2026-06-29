import 'package:flutter/material.dart';

/// Astrologer availability state. Mirrors `currentCallStatus` on the backend
/// AstrologerProfile (available | busy | offline), with `isOnline` folded in.
enum AvailabilityStatus { online, busy, offline, connecting }

extension AvailabilityStatusX on AvailabilityStatus {
  String get label => switch (this) {
        AvailabilityStatus.online => 'Online',
        AvailabilityStatus.busy => 'Busy',
        AvailabilityStatus.offline => 'Offline',
        // Intent is online but the socket isn't live yet — we're not actually
        // reachable by users, so show this honestly instead of a false "Online".
        AvailabilityStatus.connecting => 'Connecting…',
      };
}

/// One per-service rate (call/chat/video). Rates + the admin cut are absolute
/// rupees/min; the astrologer earns (ratePerMin - adminCutPerMin) per minute.
@immutable
class ServiceRate {
  final bool enabled;
  final int ratePerMin; // what the user pays, ₹/min
  final int adminCutPerMin; // platform's cut, ₹/min
  const ServiceRate({this.enabled = false, this.ratePerMin = 0, this.adminCutPerMin = 0});

  int get earnPerMin => (ratePerMin - adminCutPerMin).clamp(0, ratePerMin);
}

/// A gift entry in the admin-seeded "gifts received" display. Uses a Material
/// icon + tint (not a unicode emoji) so it renders consistently on every
/// device — older Android system fonts don't include newer emoji glyphs.
@immutable
class GiftItem {
  final String name;
  final IconData icon;
  final Color color;
  final int count;
  const GiftItem(this.name, this.icon, this.color, this.count);
}

/// A review left on the astrologer's profile (read-only in this app).
@immutable
class ReviewItem {
  final String userName;
  final int rating; // 1..5
  final String comment;
  final String timeAgo;
  const ReviewItem(this.userName, this.rating, this.comment, this.timeAgo);
}

/// Per-service consultation tallies (segregated by chat/call/video).
@immutable
class ServiceStats {
  final int sessions;
  final int minutes;
  final int earnings; // ₹ astrologer share
  const ServiceStats({this.sessions = 0, this.minutes = 0, this.earnings = 0});
}

/// The astrologer's own profile. Editable: avatar, coverPhoto, bio,
/// displayName, expertise, languages, experienceYears.
/// Read-only (admin/seeker-driven): reviews, gifts, followers, rates, stats.
class Astrologer {
  String displayName;
  String bio;
  String? avatar; // network url OR local file path
  String? coverPhoto; // network url OR local file path
  String storeTheme; // link-in-bio storefront template key
  List<String> expertise;
  List<String> languages;
  int experienceYears;

  // Read-only display values.
  final int followers;
  final double rating;
  final int reviewCount;
  final int giftCount;
  final List<GiftItem> gifts;
  final List<ReviewItem> reviews;

  // Per-service rates (set by admin).
  final ServiceRate callRate;
  final ServiceRate chatRate;
  final ServiceRate videoRate;

  // Lifetime stats, segregated by service.
  final ServiceStats chatStats;
  final ServiceStats callStats;
  final ServiceStats videoStats;

  Astrologer({
    required this.displayName,
    required this.bio,
    this.avatar,
    this.coverPhoto,
    this.storeTheme = 'rudraksh',
    required this.expertise,
    required this.languages,
    required this.experienceYears,
    required this.followers,
    required this.rating,
    required this.reviewCount,
    required this.giftCount,
    required this.gifts,
    required this.reviews,
    required this.callRate,
    required this.chatRate,
    required this.videoRate,
    required this.chatStats,
    required this.callStats,
    required this.videoStats,
  });

  int get totalSessions => chatStats.sessions + callStats.sessions + videoStats.sessions;
  int get totalMinutes => chatStats.minutes + callStats.minutes + videoStats.minutes;
  int get totalEarnings => chatStats.earnings + callStats.earnings + videoStats.earnings;

  /// Build from the backend `GET /astrologers/me/profile` shape. Editable fields
  /// come straight through; read-only display values (rates, followers, gifts,
  /// reviews, stats) map from the admin-configured record. Tolerant of missing
  /// fields (a freshly-activated profile may have rates at 0 and no reviews yet).
  factory Astrologer.fromServerJson(Map<String, dynamic> j) {
    final user = (j['user'] is Map) ? Map<String, dynamic>.from(j['user']) : const {};
    final rates = (j['rates'] is Map) ? Map<String, dynamic>.from(j['rates']) : const {};
    ServiceRate rate(String k) {
      final r = (rates[k] is Map) ? Map<String, dynamic>.from(rates[k]) : const {};
      return ServiceRate(
        enabled: r['enabled'] == true,
        ratePerMin: (r['ratePerMin'] as num?)?.toInt() ?? 0,
        adminCutPerMin: (r['adminCutPerMin'] as num?)?.toInt() ?? 0,
      );
    }

    List<String> strList(dynamic v) =>
        (v is List) ? v.map((e) => e.toString()).toList() : <String>[];

    final giftDisplay = (j['giftDisplay'] is Map) ? Map<String, dynamic>.from(j['giftDisplay']) : const {};

    return Astrologer(
      displayName: (j['displayName'] ?? user['name'] ?? '').toString(),
      bio: (j['bio'] ?? '').toString(),
      avatar: (j['avatar'] as String?)?.isNotEmpty == true ? j['avatar'] as String : null,
      coverPhoto: (j['coverPhoto'] as String?)?.isNotEmpty == true ? j['coverPhoto'] as String : null,
      storeTheme: (j['storeTheme'] as String?)?.isNotEmpty == true ? j['storeTheme'] as String : 'rudraksh',
      expertise: strList(j['expertise']),
      languages: strList(j['languages']),
      experienceYears: (j['experienceYears'] as num?)?.toInt() ?? 0,
      // `followers`/`giftCount` are the LIVE totals computed by GET /me/profile
      // (seed + real active follows; seed + real gifts received). Fall back to the
      // raw seed fields for older payloads so the count is never blank.
      followers: (j['followers'] as num?)?.toInt() ?? (j['followerSeed'] as num?)?.toInt() ?? 0,
      rating: (j['rating'] as num?)?.toDouble() ?? 0,
      reviewCount: (j['reviewCount'] as num?)?.toInt() ?? 0,
      giftCount: (j['giftCount'] as num?)?.toInt() ?? (giftDisplay['count'] as num?)?.toInt() ?? 0,
      gifts: const [], // gift breakdown icons are display-only; omitted from server load
      reviews: const [],
      callRate: rate('call'),
      chatRate: rate('chat'),
      videoRate: rate('video'),
      // Per-service consultation stats come from /me/stats (set via withStats);
      // start empty so totals are 0 until that loads.
      chatStats: const ServiceStats(),
      callStats: const ServiceStats(),
      videoStats: const ServiceStats(),
    );
  }

  /// Return a copy with per-service stats applied (from /me/stats). Reputation,
  /// rates and editable fields are preserved.
  Astrologer withStats({ServiceStats? chat, ServiceStats? call, ServiceStats? video}) {
    return Astrologer(
      displayName: displayName, bio: bio, avatar: avatar, coverPhoto: coverPhoto, storeTheme: storeTheme,
      expertise: expertise, languages: languages, experienceYears: experienceYears,
      followers: followers, rating: rating, reviewCount: reviewCount, giftCount: giftCount,
      gifts: gifts, reviews: reviews,
      callRate: callRate, chatRate: chatRate, videoRate: videoRate,
      chatStats: chat ?? chatStats, callStats: call ?? callStats, videoStats: video ?? videoStats,
    );
  }

  /// A demo profile resembling one the admin would have pre-filled, so the
  /// "complete profile" form opens with data already populated and editable.
  factory Astrologer.demoPrefilled() => Astrologer(
        displayName: 'Acharya Vikram Sharma',
        bio:
            'Vedic astrologer with deep roots in Parashari and KP systems. I read birth charts, '
            'guide on career, marriage and remedies, and believe in honest, compassionate counsel.',
        avatar: null,
        coverPhoto: null,
        expertise: const ['Vedic', 'Numerology', 'Vastu', 'Tarot'],
        languages: const ['Hindi', 'English', 'Punjabi'],
        experienceYears: 12,
        followers: 2487,
        rating: 4.8,
        reviewCount: 312,
        giftCount: 156,
        gifts: const [
          GiftItem('Rose', Icons.local_florist, Color(0xFFE0584A), 64),
          GiftItem('Diya', Icons.local_fire_department, Color(0xFFC98A5E), 41),
          GiftItem('Lotus', Icons.spa, Color(0xFF6D4B9E), 28),
          GiftItem('Crown', Icons.workspace_premium, Color(0xFFD4A24E), 14),
          GiftItem('Star', Icons.star, Color(0xFF2E9E6B), 9),
        ],
        reviews: const [
          ReviewItem('Priya M.', 5, 'Spot on about my career change. Very calm and clear.', '2d ago'),
          ReviewItem('Rahul K.', 5, 'Detailed kundli reading, gave practical remedies.', '5d ago'),
          ReviewItem('Anjali S.', 4, 'Helpful session, would consult again.', '1w ago'),
          ReviewItem('Dev P.', 5, 'Best astrologer on the app. Highly recommend.', '2w ago'),
        ],
        callRate: const ServiceRate(enabled: true, ratePerMin: 35, adminCutPerMin: 12),
        chatRate: const ServiceRate(enabled: true, ratePerMin: 25, adminCutPerMin: 9),
        videoRate: const ServiceRate(enabled: true, ratePerMin: 50, adminCutPerMin: 18),
        chatStats: const ServiceStats(sessions: 540, minutes: 7820, earnings: 124800),
        callStats: const ServiceStats(sessions: 318, minutes: 5260, earnings: 121000),
        videoStats: const ServiceStats(sessions: 96, minutes: 1840, earnings: 58900),
      );
}
