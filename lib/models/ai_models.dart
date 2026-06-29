import 'package:flutter/material.dart';

import '../providers/session_provider.dart';

// ─────────────────────────── AI Profile Optimizer ───────────────────────────

/// One actionable suggestion from the AI Profile Optimizer.
class OptimizerSuggestion {
  final String area; // Photo / Bio / Pricing / Languages / Expertise / Availability
  final IconData icon;
  final String issue;
  final String fix;
  final int impact; // 1..5 — how much this would lift the profile
  bool applied;
  OptimizerSuggestion({
    required this.area,
    required this.icon,
    required this.issue,
    required this.fix,
    required this.impact,
    this.applied = false,
  });

  /// The backend returns suggestions without icons (icons are a UI concern) —
  /// derive a sensible Material icon from the `area`.
  static IconData iconForArea(String area) {
    switch (area) {
      case 'Photo':
        return Icons.face_retouching_natural;
      case 'Bio':
        return Icons.notes_outlined;
      case 'Pricing':
        return Icons.payments_outlined;
      case 'Languages':
        return Icons.translate;
      case 'Expertise':
        return Icons.workspace_premium_outlined;
      case 'Availability':
        return Icons.schedule;
      default:
        return Icons.auto_fix_high;
    }
  }

  factory OptimizerSuggestion.fromJson(Map<String, dynamic> j) {
    final area = (j['area'] ?? '').toString();
    return OptimizerSuggestion(
      area: area,
      icon: iconForArea(area),
      issue: (j['issue'] ?? '').toString(),
      fix: (j['fix'] ?? '').toString(),
      impact: (j['impact'] as num?)?.toInt() ?? 1,
    );
  }
}

/// Result of running the optimizer: an overall score + per-area suggestions.
/// `aiBio`/`aiTips` are present only when the backend LLM produced them.
class OptimizerReport {
  final int score; // 0..100
  final String headline;
  final List<OptimizerSuggestion> suggestions;
  final String? aiBio;
  final List<String> aiTips;
  OptimizerReport({
    required this.score,
    required this.headline,
    required this.suggestions,
    this.aiBio,
    this.aiTips = const [],
  });

  /// Map the backend POST /api/ai/optimize-profile response.
  factory OptimizerReport.fromJson(Map<String, dynamic> j) => OptimizerReport(
        score: (j['score'] as num?)?.toInt() ?? 0,
        headline: (j['headline'] ?? '').toString(),
        suggestions: (j['suggestions'] as List?)
                ?.map((e) => OptimizerSuggestion.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            const [],
        aiBio: (j['improvedBio'] as String?)?.trim().isNotEmpty == true ? (j['improvedBio'] as String).trim() : null,
        aiTips: (j['aiTips'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      );
}

// ─────────────────────────── Rudra Mall + remedies ──────────────────────────

/// A product in "Rudra Mall" that can be suggested as a remedy.
class MallProduct {
  final String id;
  final String name;
  final IconData icon;
  final Color color;
  final int price; // ₹
  const MallProduct(this.id, this.name, this.icon, this.color, this.price);
}

/// Approval state for an astrologer-listed storefront product. Mirrors the
/// intended backend flow: astrologer lists → admin/super_admin approves and
/// sets a commission → it goes live in the user app's Rudra Mall.
enum ProductStatus { pending, approved, rejected }

extension ProductStatusX on ProductStatus {
  String get label => switch (this) {
        ProductStatus.pending => 'Pending approval',
        ProductStatus.approved => 'Approved',
        ProductStatus.rejected => 'Rejected',
      };
  IconData get icon => switch (this) {
        ProductStatus.pending => Icons.hourglass_top,
        ProductStatus.approved => Icons.verified,
        ProductStatus.rejected => Icons.cancel_outlined,
      };
}

/// A product the astrologer lists in their own storefront. Admin approval is
/// required, and the admin sets [commissionPercent] (platform's cut on each
/// sale) at approval time.
/// A product the astrologer can share in chat (storefront or RudraMaal). Minimal
/// fields needed for the picker + the chat card.
class CatalogueItem {
  final String id;
  final String name;
  final int price;
  final String? image;
  final String category;
  final String source; // 'storefront' | 'rudramaal'
  const CatalogueItem({required this.id, required this.name, required this.price, this.image, this.category = '', this.source = 'storefront'});

  factory CatalogueItem.fromJson(Map<String, dynamic> j) => CatalogueItem(
        id: (j['id'] ?? j['_id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        price: (j['price'] as num?)?.toInt() ?? 0,
        image: (j['image'] as String?)?.isNotEmpty == true ? j['image'] as String : null,
        category: (j['category'] ?? '').toString(),
        source: (j['source'] ?? 'storefront').toString(),
      );
}

class StoreProduct {
  String? id; // backend _id (null until created server-side)
  String name;
  String description;
  int mrp; // struck-through price ₹
  int price; // selling price ₹
  int stock;
  String category; // category name (display)
  String? categoryId; // admin Category _id (sent on create)
  String? image; // hosted image URL (first image)
  IconData icon;
  Color color;
  ProductStatus status;
  int commissionPercent; // set by admin on approval; 0 until then
  int unitsSold;
  String? adminNote; // e.g. rejection reason

  StoreProduct({
    this.id,
    required this.name,
    required this.description,
    required this.mrp,
    required this.price,
    required this.stock,
    required this.category,
    this.categoryId,
    this.image,
    this.icon = Icons.inventory_2_outlined,
    this.color = const Color(0xFFC98A5E),
    this.status = ProductStatus.pending,
    this.commissionPercent = 0,
    this.unitsSold = 0,
    this.adminNote,
  });

  /// Platform's commission rupees per sale (admin-set %).
  int get commissionPerSale => (price * commissionPercent / 100).round();

  /// What the astrologer keeps per sale after the admin commission.
  int get earnPerSale => price - commissionPerSale;

  /// Lifetime earning from this product (astrologer share).
  int get totalEarned => earnPerSale * unitsSold;

  static ProductStatus _statusFrom(String? s) => switch (s) {
        'approved' => ProductStatus.approved,
        'rejected' => ProductStatus.rejected,
        _ => ProductStatus.pending,
      };

  factory StoreProduct.fromJson(Map<String, dynamic> j) => StoreProduct(
        id: (j['_id'] ?? j['id'])?.toString(),
        name: (j['name'] ?? '').toString(),
        description: (j['description'] ?? '').toString(),
        mrp: (j['mrp'] as num?)?.toInt() ?? 0,
        price: (j['price'] as num?)?.toInt() ?? 0,
        stock: (j['stock'] as num?)?.toInt() ?? 0,
        category: (j['categoryName'] ?? '').toString(),
        image: (j['images'] is List && (j['images'] as List).isNotEmpty) ? (j['images'] as List).first.toString() : null,
        status: _statusFrom(j['status']?.toString()),
        commissionPercent: (j['commissionPercent'] as num?)?.toInt() ?? 0,
        unitsSold: (j['soldCount'] as num?)?.toInt() ?? 0,
        adminNote: j['adminNote']?.toString(),
      );

  /// Payload the astrologer create/update endpoints accept.
  Map<String, dynamic> toCreateJson() => {
        'name': name,
        'description': description,
        'mrp': mrp,
        'price': price,
        'stock': stock,
        'categoryName': category,
        if (categoryId != null && categoryId!.isNotEmpty) 'category': categoryId,
        if (image != null && image!.isNotEmpty) 'images': [image],
      };
}

/// One AI-suggested remedy tied to an optional Rudra Mall product. The
/// astrologer confirms or edits these before they surface in the user app.
class RemedySuggestion {
  String title;
  String detail;
  MallProduct? product; // null = practice/ritual with no product
  bool confirmed;
  RemedySuggestion({required this.title, required this.detail, this.product, this.confirmed = false});
}

/// AI-generated summary of a consultation + suggested remedies.
class ChatSummary {
  final String userName;
  final ServiceKind kind;
  final String when;
  final List<String> keyTopics;
  final String summary;
  final String sentiment; // e.g. "Hopeful", "Anxious about career"
  final List<RemedySuggestion> remedies;
  bool published; // pushed to the user app
  ChatSummary({
    required this.userName,
    required this.kind,
    required this.when,
    required this.keyTopics,
    required this.summary,
    required this.sentiment,
    required this.remedies,
    this.published = false,
  });
}

// ──────────────────────────────── Go Live ───────────────────────────────────

/// One message in the live chat.
class LiveChatMsg {
  final String user;
  final String text;
  final int? superchatAmount; // ₹ if this is a paid superchat highlight
  final bool isQuestion; // raised as a Q in the queue
  final bool flaggedByAi; // AI moderator hid/flagged this
  const LiveChatMsg({required this.user, required this.text, this.superchatAmount, this.isQuestion = false, this.flaggedByAi = false});
}

/// An action the AI moderator took during the live session.
class ModeratorAction {
  final IconData icon;
  final String text;
  final Color color;
  const ModeratorAction(this.icon, this.text, this.color);
}

/// A pooja the astrologer offers to perform on a seeker's behalf. Same
/// admin-approval + commission flow as [StoreProduct], with pooja-specific
/// fields (duration, availability window).
class PoojaOffering {
  String? id; // backend _id
  String name;
  String description;
  int price; // ₹
  String durationNote; // e.g. "approx 45 min"
  String availability; // e.g. "Any day", "Tue & Sat", "Amavasya only"
  DateTime? availableFrom; // optional booking-window start
  DateTime? availableTo; // optional booking-window end (== from for a single date)
  String? image; // hosted image URL
  IconData icon;
  Color color;
  ProductStatus status;
  int commissionPercent; // admin-set on approval
  int booked; // lifetime bookings
  String? adminNote;

  PoojaOffering({
    this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.durationNote,
    required this.availability,
    this.availableFrom,
    this.availableTo,
    this.image,
    this.icon = Icons.local_fire_department,
    this.color = const Color(0xFFC0392B),
    this.status = ProductStatus.pending,
    this.commissionPercent = 0,
    this.booked = 0,
    this.adminNote,
  });

  int get commissionPerBooking => (price * commissionPercent / 100).round();
  int get earnPerBooking => price - commissionPerBooking;
  int get totalEarned => earnPerBooking * booked;

  factory PoojaOffering.fromJson(Map<String, dynamic> j) => PoojaOffering(
        id: (j['_id'] ?? j['id'])?.toString(),
        name: (j['name'] ?? '').toString(),
        description: (j['description'] ?? '').toString(),
        price: (j['basePrice'] as num?)?.toInt() ?? 0,
        durationNote: (j['durationNote'] ?? '').toString(),
        availability: (j['availability'] ?? 'Any day').toString(),
        image: (j['imagePortrait'] ?? j['image'])?.toString(),
        status: StoreProduct._statusFrom(j['status']?.toString()),
        commissionPercent: (j['commissionPercent'] as num?)?.toInt() ?? 0,
        booked: (j['bookedCount'] as num?)?.toInt() ?? 0,
        adminNote: j['adminNote']?.toString(),
      );

  Map<String, dynamic> toCreateJson() => {
        'name': name,
        'description': description,
        'basePrice': price,
        'durationNote': durationNote,
        if (availableFrom != null) 'availableFrom': availableFrom!.toIso8601String(),
        if (availableTo != null) 'availableTo': availableTo!.toIso8601String(),
        // Banner photo (16:9). Sent to all artwork fields so it surfaces in both
        // the catalog card and the pooja detail header.
        if (image != null && image!.isNotEmpty) ...{
          'image': image,
          'imagePortrait': image,
          'imageLandscape': image,
        },
      };
}

/// A past live session shown on the pre-live screen.
class LiveHistory {
  final String title;
  final String when;
  final int peakViewers;
  final int questions;
  final int superchatEarnings; // ₹
  final Duration duration;
  const LiveHistory({required this.title, required this.when, required this.peakViewers, required this.questions, required this.superchatEarnings, required this.duration});
}

/// AI-generated recap shown when a live session ends.
class LiveSummary {
  final int peakViewers;
  final int totalQuestions;
  final int superchatEarnings; // ₹
  final List<String> highlights;
  final List<String> followUpProducts; // Rudra Mall items to promote next
  final String suggestedNextTopic;
  const LiveSummary({
    required this.peakViewers,
    required this.totalQuestions,
    required this.superchatEarnings,
    required this.highlights,
    required this.followUpProducts,
    required this.suggestedNextTopic,
  });
}

// ───────────────────────────── Settings presets ─────────────────────────────

/// Astrologer automation presets (saved values that drive behaviour).
class AstroPresets {
  // When the astrologer comes online…
  bool notifyFollowersOnOnline; // push to followers each time they go online
  bool dailyFollowerNotification; // a once-a-day "I'm available" broadcast
  TimeOfDay dailyNotificationTime;
  String onlineMessage; // template sent to followers

  // Auto-accept / availability cycle.
  bool autoAcceptChat;
  int breakAfterSessions; // suggest a break after N back-to-back sessions
  bool aiModeratorOnLive; // enable AI moderator in live sessions by default

  AstroPresets({
    this.notifyFollowersOnOnline = true,
    this.dailyFollowerNotification = false,
    this.dailyNotificationTime = const TimeOfDay(hour: 10, minute: 0),
    this.onlineMessage = "I'm online now — ask me anything 🙏",
    this.autoAcceptChat = false,
    this.breakAfterSessions = 5,
    this.aiModeratorOnLive = true,
  });
}
