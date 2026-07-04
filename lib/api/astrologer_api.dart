import 'dart:io';

import 'package:dio/dio.dart';

import '../models/ai_models.dart';
import '../models/recap_models.dart';
import 'api_client.dart';
import 'token_store.dart';

/// Result of the login-gate existence check for a phone number.
class ExistsResult {
  final bool exists;
  final String? status;
  final bool active;
  final bool takenByOtherRole;
  final String? role;

  const ExistsResult({
    required this.exists,
    this.status,
    required this.active,
    this.takenByOtherRole = false,
    this.role,
  });

  factory ExistsResult.fromJson(Map<String, dynamic> json) => ExistsResult(
        exists: json['exists'] == true,
        status: json['status'] as String?,
        active: json['active'] == true,
        takenByOtherRole: json['takenByOtherRole'] == true,
        role: json['role'] as String?,
      );
}

/// Backend calls for the astrologer auth, registration, and profile flows.
/// Holds a shared authenticated [ApiClient] + [TokenStore] so the session
/// (Bearer token) is reused across calls. Throws [ApiException] on failure.
class AstrologerApi {
  AstrologerApi(this._c, this._tokens);
  final ApiClient _c;
  final TokenStore _tokens;

  TokenStore get tokens => _tokens;

  // ── Login gate ──
  Future<ExistsResult> checkExists(String phone10) async {
    final data = await _c.get('/astrologers/exists/$phone10');
    return ExistsResult.fromJson(Map<String, dynamic>.from(data as Map));
  }

  // ── Real OTP auth (dev code stays 123456 server-side) ──
  /// Send an OTP to a raw 10-digit number (backend normalises to 91+10).
  Future<void> requestOtp(String phone10) async {
    await _c.post('/auth/request-otp', body: {'phone': phone10});
  }

  /// Verify the OTP; on success persists the token pair and returns the
  /// `{user, isNewUser}` map. The astrologer must already be an active account.
  Future<Map<String, dynamic>> verifyOtp(String phone10, String code) async {
    final data = await _c.post('/auth/verify-otp', body: {'phone': phone10, 'code': code});
    final map = Map<String, dynamic>.from(data as Map);
    await _tokens.save(
      access: map['accessToken'] as String,
      refresh: map['refreshToken'] as String,
    );
    return map;
  }

  Future<void> logout() async {
    final rt = _tokens.refreshToken;
    try {
      if (rt != null && rt.isNotEmpty) await _c.post('/auth/logout', body: {'refreshToken': rt});
    } catch (_) {/* best-effort */}
    await _tokens.clear();
  }

  // ── Push (FCM token + tap attribution) ──
  /// Register/refresh this device's push token so broadcasts reach it. The
  /// endpoint is role-agnostic (any authenticated user); mirrors the user app.
  Future<void> registerFcmToken(
    String token, {
    String platform = 'android',
    Map<String, String> device = const {},
  }) async {
    await _c.post('/auth/fcm-token', body: {'token': token, 'platform': platform, ...device});
  }

  /// Remove this device's push token (called on logout so a logged-out device
  /// stops receiving the previous astrologer's pushes).
  Future<void> removeFcmToken(String token) async {
    await _c.delete('/auth/fcm-token', body: {'token': token});
  }

  /// Attribute a notification tap to its broadcast (drives the admin "Clicks"
  /// count). Best-effort — failures are ignored by the caller.
  Future<void> recordNotificationClick(String broadcastId) async {
    await _c.post('/notifications/click', body: {'broadcastId': broadcastId});
  }

  /// Rate the app (1-5 + optional review). One rating per account
  /// (re-submitting overwrites). Same endpoint the user app uses.
  Future<void> rateApp({required int rating, String? review}) async {
    await _c.post('/feedback/rate', body: {'rating': rating, if (review != null && review.isNotEmpty) 'review': review});
  }

  // ── Registration (lead) ──
  Future<String> register({
    required String name,
    required String phone10,
    String? email,
    List<String> expertise = const [],
    List<String> languages = const [],
    int experienceYears = 0,
    String? note,
    String? fcmToken,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'phone': phone10,
      if (email != null && email.isNotEmpty) 'email': email,
      if (expertise.isNotEmpty) 'expertise': expertise,
      if (languages.isNotEmpty) 'languages': languages,
      'experienceYears': experienceYears,
      if (note != null && note.isNotEmpty) 'note': note,
      if (fcmToken != null && fcmToken.isNotEmpty) 'fcmToken': fcmToken,
    };
    final data = await _c.post('/astrologers/apply', body: body);
    return (data is Map && data['applicationId'] != null) ? data['applicationId'].toString() : '';
  }

  /// Shared expertise catalog (public). The app shows these as chip options so
  /// they always match the admin's list, including admin-created expertise.
  Future<List<String>> listExpertise() async {
    final data = await _c.get('/astrologers/expertise');
    return (data is List) ? data.map((e) => e.toString()).toList() : <String>[];
  }

  /// Set the astrologer's online/offline availability (durable; the socket
  /// `set-online` event is the realtime fast path). POST /astrologers/me/online.
  Future<void> setOnline(bool online) async {
    await _c.post('/astrologers/me/online', body: {'online': online});
  }

  /// Wallet balance for the logged-in astrologer. GET /wallet/balance.
  /// Returns `{balance, lockedBalance, available}`.
  Future<Map<String, dynamic>> walletBalance() async {
    final data = await _c.get('/wallet/balance');
    return Map<String, dynamic>.from(data as Map);
  }

  // ── Payout (bank / UPI) details ──
  /// Saved payout details: { accountNumber, ifsc, beneficiaryName, upi } (any null).
  Future<Map<String, dynamic>> getPayoutDetails() async {
    final data = await _c.get('/astrologers/me/payout-details');
    return Map<String, dynamic>.from((data as Map?) ?? const {});
  }

  /// Add/edit bank account or UPI (saved instantly, admin notified).
  Future<Map<String, dynamic>> savePayoutDetails({String? accountNumber, String? ifsc, String? beneficiaryName, String? upi}) async {
    final data = await _c.put('/astrologers/me/payout-details', body: {
      if (accountNumber != null) 'accountNumber': accountNumber,
      if (ifsc != null) 'ifsc': ifsc,
      if (beneficiaryName != null) 'beneficiaryName': beneficiaryName,
      if (upi != null) 'upi': upi,
    });
    return Map<String, dynamic>.from((data as Map?) ?? const {});
  }

  // ── Withdrawals ──
  /// Request a withdrawal of [amountRupees] to the saved payout details.
  Future<void> requestWithdrawal({required int amountRupees}) async {
    await _c.post('/withdrawals', body: {'amountRupees': amountRupees});
  }

  /// My withdrawal history (newest first). GET /withdrawals.
  Future<List<Map<String, dynamic>>> myWithdrawals() async {
    final data = await _c.get('/withdrawals');
    final raw = (data is Map ? (data['items'] as List?) : (data as List?)) ?? const [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Dashboard consultation stats (per-service sessions/minutes/earnings +
  /// this-month earnings). GET /astrologers/me/stats.
  Future<Map<String, dynamic>> myStats() async {
    final data = await _c.get('/astrologers/me/stats');
    return Map<String, dynamic>.from(data as Map);
  }

  /// My followers (name, avatar, since), newest first. GET /astrologers/me/followers.
  Future<List<Follower>> myFollowers({int page = 1, int limit = 30}) async {
    final data = await _c.get('/astrologers/me/followers', query: {'page': page, 'limit': limit});
    final raw = (data is Map ? (data['items'] as List?) : (data as List?)) ?? const [];
    return raw.map((e) => Follower.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  // ── Storefront (theme + my products/poojas) ──
  /// Admin-managed product categories (GET /categories) — astrologers pick from
  /// these when listing a product; they can't create new categories.
  Future<List<StoreCategory>> categories() async {
    final data = await _c.get('/categories');
    final raw = (data as List?) ?? const [];
    return raw.map((e) => StoreCategory.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  /// Persist the chosen storefront template. PUT /astrologers/me/store-theme.
  Future<void> setStoreTheme(String theme) async {
    await _c.put('/astrologers/me/store-theme', body: {'theme': theme});
  }

  // ── AI storefront designs ("Let the Stars design your storefront") ──

  /// Lifetime usage: { used, limit, remaining }.
  Future<({int used, int limit, int remaining})> storefrontDesignUsage() async {
    final data = await _c.get('/astrologers/me/storefront-design/usage');
    final m = Map<String, dynamic>.from(data as Map);
    return (used: (m['used'] as num?)?.toInt() ?? 0, limit: (m['limit'] as num?)?.toInt() ?? 3, remaining: (m['remaining'] as num?)?.toInt() ?? 0);
  }

  /// All generated layouts (newest first); each carries spec + active flag.
  Future<List<Map<String, dynamic>>> listStorefrontDesigns() async {
    final data = await _c.get('/astrologers/me/storefront-design');
    return ((data as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Generate a new layout (consumes one lifetime credit). Returns { layout, usage }.
  Future<Map<String, dynamic>> generateStorefrontDesign() async {
    final data = await _c.post('/astrologers/me/storefront-design/generate');
    return Map<String, dynamic>.from(data as Map);
  }

  /// Make a saved layout the active one for the public storefront.
  Future<void> setActiveStorefrontDesign(String layoutId) async {
    await _c.put('/astrologers/me/storefront-design/active', body: {'layoutId': layoutId});
  }

  /// My storefront products (all statuses, for the manage tab).
  Future<List<StoreProduct>> myProducts() async {
    final data = await _c.get('/astrologers/me/products');
    final raw = (data as List?) ?? const [];
    return raw.map((e) => StoreProduct.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<StoreProduct> createProduct(StoreProduct p) async {
    final data = await _c.post('/astrologers/me/products', body: p.toCreateJson());
    return StoreProduct.fromJson(Map<String, dynamic>.from(data as Map));
  }

  /// Shareable catalogue (own storefront + RudraMaal) for the in-chat product
  /// picker. Optional name search. GET /astrologers/me/catalogue?q=
  Future<List<CatalogueItem>> catalogue({String? q}) async {
    final data = await _c.get('/astrologers/me/catalogue', query: {if (q != null && q.isNotEmpty) 'q': q});
    final raw = (data as List?) ?? const [];
    return raw.map((e) => CatalogueItem.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<StoreProduct> updateProduct(String id, StoreProduct p) async {
    final data = await _c.put('/astrologers/me/products/$id', body: p.toCreateJson());
    return StoreProduct.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<void> deleteProduct(String id) async {
    await _c.delete('/astrologers/me/products/$id');
  }

  /// My storefront poojas (all statuses).
  Future<List<PoojaOffering>> myPoojas() async {
    final data = await _c.get('/astrologers/me/poojas');
    final raw = (data as List?) ?? const [];
    return raw.map((e) => PoojaOffering.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<PoojaOffering> createPooja(PoojaOffering p) async {
    final data = await _c.post('/astrologers/me/poojas', body: p.toCreateJson());
    return PoojaOffering.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<PoojaOffering> updatePooja(String id, PoojaOffering p) async {
    final data = await _c.put('/astrologers/me/poojas/$id', body: p.toCreateJson());
    return PoojaOffering.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<void> deletePooja(String id) async {
    await _c.delete('/astrologers/me/poojas/$id');
  }

  // ── Storefront orders + pooja bookings (read-only) ──
  Future<List<StoreOrder>> myStoreOrders() async {
    final data = await _c.get('/astrologers/me/store-orders');
    final raw = (data as List?) ?? const [];
    return raw.map((e) => StoreOrder.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  /// Flag an order's item(s) as handed to the admin/fulfillment team.
  Future<void> markOrderSent(String orderId) async {
    await _c.post('/astrologers/me/store-orders/$orderId/sent');
  }

  Future<List<StoreBooking>> myPoojaBookings() async {
    final data = await _c.get('/astrologers/me/pooja-bookings');
    final raw = (data as List?) ?? const [];
    return raw.map((e) => StoreBooking.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  // ── Self-service profile (authenticated) ──
  /// The astrologer's own profile (the admin-created record). Includes the
  /// populated `user` (name/phone/email/language).
  Future<Map<String, dynamic>> myProfile() async {
    final data = await _c.get('/astrologers/me/profile');
    return Map<String, dynamic>.from(data as Map);
  }

  /// Save the editable subset + UI language. Send only the changed fields.
  Future<Map<String, dynamic>> updateMyProfile(Map<String, dynamic> body) async {
    final data = await _c.put('/astrologers/me/profile', body: body);
    return Map<String, dynamic>.from(data as Map);
  }

  /// Persist the chosen UI language to the DB (User.language). Used by the
  /// language picker right after login.
  Future<void> saveLanguage(String code) async {
    await updateMyProfile({'language': code});
  }

  /// Persist the granted runtime permissions to the User (PUT /auth/me — the
  /// endpoint is role-agnostic). Used by the post-auth permissions screen.
  Future<void> savePermissions(Map<String, bool> permissions) async {
    await _c.put('/auth/me', body: {'permissions': permissions});
  }

  /// Upload a local image; returns the hosted URL. Reuses the user upload
  /// endpoint (multipart field "image", ImageBB-hosted). Requires a session.
  Future<String> uploadImage(File file) async {
    final filename = file.path.split(Platform.pathSeparator).last;
    final form = FormData.fromMap({
      'image': await MultipartFile.fromFile(file.path, filename: filename),
    });
    final data = await _c.post('/users/upload', body: form);
    if (data is Map && (data['url'] != null || data['image'] != null)) {
      return (data['url'] ?? data['image']).toString();
    }
    if (data is String) return data;
    throw ApiException('Upload failed');
  }

  // ── AI chat-end recaps (Feature 1) ──

  /// The astrologer's recap review queue. `status` defaults to 'pending'.
  Future<List<Recap>> listRecaps({String status = 'pending', int page = 1, int limit = 20}) async {
    final data = await _c.get('/ai/recaps', query: {'status': status, 'page': page, 'limit': limit});
    final raw = (data is Map ? (data['items'] as List?) : (data as List?)) ?? const [];
    return raw.map((e) => Recap.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  /// Count of recaps in a given status (default 'pending') — for the home badge.
  Future<int> recapCount({String status = 'pending'}) async {
    final data = await _c.get('/ai/recaps', query: {'status': status, 'page': 1, 'limit': 1});
    if (data is Map && data['total'] is num) return (data['total'] as num).toInt();
    return 0;
  }

  /// A single recap by id (populated suggestions).
  Future<Recap> getRecap(String recapId) async {
    final data = await _c.get('/ai/recaps/$recapId');
    return Recap.fromJson(Map<String, dynamic>.from(data as Map));
  }

  /// Edit the recap text / sentiment / topics / reminders before approving.
  /// When [reminders] is given each item is serialised to a
  /// {type, title, reason, timeOfDay?, date?, keep} map for the backend.
  Future<Recap> editRecap(
    String recapId, {
    String? summary,
    String? sentiment,
    List<String>? keyTopics,
    List<RecapReminder>? reminders,
  }) async {
    final body = <String, dynamic>{};
    if (summary != null) body['summary'] = summary;
    if (sentiment != null) body['sentiment'] = sentiment;
    if (keyTopics != null) body['keyTopics'] = keyTopics;
    if (reminders != null) body['reminders'] = reminders.map((r) => r.toJson()).toList();
    final data = await _c.patch('/ai/recaps/$recapId', body: body);
    return Recap.fromJson(Map<String, dynamic>.from(data as Map));
  }

  /// Approve → publish to the user. `keepSuggestionIds` limits which suggestions
  /// ship (omit to keep all).
  Future<Recap> approveRecap(String recapId, {List<String>? keepSuggestionIds}) async {
    final body = <String, dynamic>{};
    if (keepSuggestionIds != null) body['keepSuggestionIds'] = keepSuggestionIds;
    final data = await _c.post('/ai/recaps/$recapId/approve', body: body);
    return Recap.fromJson(Map<String, dynamic>.from(data as Map));
  }

  /// Reject (discard) — never reaches the user.
  Future<void> rejectRecap(String recapId) async {
    await _c.post('/ai/recaps/$recapId/reject');
  }

  // ── Profile Optimizer (Feature 3) ──

  /// Score this astrologer's profile server-side and (when the LLM is available)
  /// return an AI-rewritten bio + tips. Returns the raw map so the screen can map
  /// it onto its OptimizerReport (deriving per-area icons on the client).
  Future<Map<String, dynamic>> optimizeProfile() async {
    final data = await _c.post('/ai/optimize-profile');
    return Map<String, dynamic>.from(data as Map);
  }

  /// Monthly optimizer quota { used, limit, remaining } — drives the "N left
  /// this month" badge on the home-tab CTA.
  Future<({int used, int limit, int remaining})> optimizerUsage() async {
    final data = await _c.get('/ai/optimize-profile/usage');
    final m = Map<String, dynamic>.from(data as Map);
    return (
      used: (m['used'] as num?)?.toInt() ?? 0,
      limit: (m['limit'] as num?)?.toInt() ?? 2,
      remaining: (m['remaining'] as num?)?.toInt() ?? 0,
    );
  }
}

/// An admin-managed product category the astrologer can pick from.
class StoreCategory {
  final String id;
  final String name;
  const StoreCategory({required this.id, required this.name});
  factory StoreCategory.fromJson(Map<String, dynamic> j) => StoreCategory(
        id: (j['_id'] ?? j['id']).toString(),
        name: (j['name'] ?? '').toString(),
      );
}

/// A user who follows this astrologer (for the Followers page).
class Follower {
  final String name;
  final String? avatar;
  final DateTime? since;
  const Follower({required this.name, this.avatar, this.since});
  factory Follower.fromJson(Map<String, dynamic> j) => Follower(
        name: (j['name'] ?? 'Seeker').toString(),
        avatar: j['avatar']?.toString(),
        since: j['since'] != null ? DateTime.tryParse(j['since'].toString()) : null,
      );
}

/// One of the astrologer's line items within a storefront order.
class StoreOrderItem {
  final String name;
  final int qty;
  final int price;
  const StoreOrderItem({required this.name, required this.qty, required this.price});
  factory StoreOrderItem.fromJson(Map<String, dynamic> j) => StoreOrderItem(
        name: (j['name'] ?? '').toString(),
        qty: (j['qty'] as num?)?.toInt() ?? 1,
        price: (j['price'] as num?)?.toInt() ?? 0,
      );
}

/// A storefront order the astrologer can view (their items + admin status).
class StoreOrder {
  final String id;
  final String shortId;
  final String status; // admin-controlled fulfillment status
  final bool sentToAdmin;
  final DateTime? createdAt;
  final List<StoreOrderItem> items;
  const StoreOrder({required this.id, required this.shortId, required this.status, required this.sentToAdmin, this.createdAt, this.items = const []});
  factory StoreOrder.fromJson(Map<String, dynamic> j) => StoreOrder(
        id: (j['id'] ?? '').toString(),
        shortId: (j['shortId'] ?? '').toString(),
        status: (j['status'] ?? '').toString(),
        sentToAdmin: j['sentToAdmin'] == true,
        createdAt: j['createdAt'] != null ? DateTime.tryParse(j['createdAt'].toString()) : null,
        items: ((j['items'] as List?) ?? const []).map((e) => StoreOrderItem.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      );
  int get total => items.fold(0, (s, it) => s + it.price * it.qty);
}

/// A pooja booking the astrologer can view (admin-controlled status).
class StoreBooking {
  final String id;
  final String poojaType;
  final String status;
  final int price;
  final String contactName;
  final DateTime? preferredDate;
  const StoreBooking({required this.id, required this.poojaType, required this.status, required this.price, this.contactName = '', this.preferredDate});
  factory StoreBooking.fromJson(Map<String, dynamic> j) => StoreBooking(
        id: (j['id'] ?? '').toString(),
        poojaType: (j['poojaType'] ?? '').toString(),
        status: (j['status'] ?? '').toString(),
        price: (j['price'] as num?)?.toInt() ?? 0,
        contactName: (j['contactName'] ?? '').toString(),
        preferredDate: j['preferredDate'] != null ? DateTime.tryParse(j['preferredDate'].toString()) : null,
      );
}
