import 'dart:async';

import 'package:flutter/material.dart';

import '../models/ai_models.dart';
import '../models/astrologer.dart';

/// Kind of an incoming / historical consultation.
enum ServiceKind { chat, call, video }

extension ServiceKindX on ServiceKind {
  String get label => switch (this) {
        ServiceKind.chat => 'Chat',
        ServiceKind.call => 'Call',
        ServiceKind.video => 'Video',
      };
  IconData get icon => switch (this) {
        ServiceKind.chat => Icons.chat_bubble_outline,
        ServiceKind.call => Icons.call_outlined,
        ServiceKind.video => Icons.videocam_outlined,
      };
}

/// A historical consultation record.
class ConsultRecord {
  final String userName;
  final ServiceKind kind;
  final int minutes;
  final int earned; // ₹ astrologer share
  final String when;
  final bool completed; // false = missed/declined
  const ConsultRecord({
    required this.userName,
    required this.kind,
    required this.minutes,
    required this.earned,
    required this.when,
    this.completed = true,
  });
}

/// A wallet/earnings ledger entry.
class LedgerEntry {
  final String title;
  final int amount; // +credit / -debit, ₹
  final String when;
  final bool isWithdrawal;
  const LedgerEntry({required this.title, required this.amount, required this.when, this.isWithdrawal = false});
}

/// An in-app notification.
class AstroNotification {
  final IconData icon;
  final String title;
  final String body;
  final String when;
  bool read;
  AstroNotification({required this.icon, required this.title, required this.body, required this.when, this.read = false});
}

/// Holds the astrologer session state for the UI: profile, availability,
/// incoming requests, history, earnings ledger, notifications. All in-memory
/// (UI-only prototype — no backend wired).
class SessionProvider extends ChangeNotifier {
  Astrologer profile = Astrologer.demoPrefilled();

  // The astrologer manually controls ONLY online/offline. "Busy" is not a
  // manual choice — it is auto-derived: when online AND in an ongoing
  // consultation, status reports `busy`. It clears back to online when the
  // session ends.
  bool _isOnline = false;
  bool _inSession = false;
  // Whether the realtime socket is actually live. The astrologer is only truly
  // reachable by users when their intent is online AND the socket is connected
  // — showing "Online" with a dead socket is a lie (users would see them offline
  // because the backend derives presence from socketCount). Default true so the
  // UI doesn't flash "Connecting…" before the first socket state arrives.
  // Defaults FALSE. It used to default true "so the UI doesn't flash Connecting…",
  // but it is only ever written from DashboardShell — so every screen before the
  // dashboard mounts (and everything after it disposes) claimed a live socket that
  // might not exist. The flash is handled properly by the 2.5s disconnect grace in
  // SocketService instead of by an optimistic lie here.
  bool _socketLive = false;
  // Self-requested break end time (server-driven via my-presence). While in the
  // future the astrologer shows BUSY to seekers.
  DateTime? _breakUntil;

  bool get isOnline => _isOnline;
  bool get inSession => _inSession;
  DateTime? get breakUntil => _breakUntil;
  bool get onBreak => _breakUntil != null && _breakUntil!.isAfter(DateTime.now());

  /// Effective availability shown across the app. Reflects BOTH the astrologer's
  /// intent AND a live socket, mirroring how the backend derives presence.
  AvailabilityStatus get status {
    if (!_isOnline) return AvailabilityStatus.offline;
    // TRANSPORT TRUTH BEFORE OCCUPANCY. `busy` used to outrank `connecting`, so a
    // socket that died mid-consultation still showed "Busy in a consultation"
    // while the backend saw no socket and reported the astrologer offline — and
    // because both toggle segments are disabled while busy, the astrologer was
    // bricked and could not re-assert. Also, _inSession only clears on
    // `session-ended`, so a socket that died before that event latched busy
    // forever. Now a dead link is always visible and the toggle stays usable.
    if (!_socketLive) return AvailabilityStatus.connecting;
    if (_inSession || onBreak) return AvailabilityStatus.busy;
    return AvailabilityStatus.online;
  }

  /// Set/clear the break end time (from my-presence or an optimistic local set).
  void setBreakUntil(DateTime? until) {
    _breakUntil = (until != null && until.isAfter(DateTime.now())) ? until : null;
    notifyListeners();
  }

  /// Fed from the SocketService connect/disconnect state so the displayed status
  /// can't claim "Online" while the socket is dead.
  Timer? _socketLiveDebounce;

  void setSocketLive(bool live) {
    _socketLiveDebounce?.cancel();
    if (live == _socketLive) return;
    // Going live is applied IMMEDIATELY — the astrologer should see "Online" the
    // instant the link is up. Going dark is debounced, because a reconnect
    // usually completes within a second and flashing "Connecting…" for every
    // blip is what made the status feel unreliable. (This replaces the dead grace
    // timer that used to live in SocketService.onDisconnect.)
    if (live) {
      _socketLive = true;
      notifyListeners();
      return;
    }
    _socketLiveDebounce = Timer(const Duration(milliseconds: 2500), () {
      if (_socketLive) {
        _socketLive = false;
        notifyListeners();
      }
    });
  }

  bool _profileCompleted = false;
  bool get profileCompleted => _profileCompleted;

  /// Manual online/offline toggle (the only thing the astrologer controls).
  void setOnline(bool online) {
    _isOnline = online;
    notifyListeners();
  }

  /// System sets this when a consultation starts/ends; drives the auto "busy".
  void setInSession(bool busy) {
    _inSession = busy;
    notifyListeners();
  }

  /// Mirror the SERVER's authoritative presence. Called on profile load, socket
  /// reconnect, and the live `my-presence` event so the toggle always matches
  /// the backend in every scenario. The astrologer's intent is
  /// `availabilityPreference`; `currentCallStatus` carries the auto-busy flag.
  void syncPresence({bool? availabilityPreference, bool? isOnline, String? currentCallStatus}) {
    // Prefer the saved intent (survives reconnect blips); fall back to isOnline.
    final online = availabilityPreference ?? isOnline ?? _isOnline;
    final busy = currentCallStatus == 'busy';
    if (online == _isOnline && busy == _inSession) return; // no-op, avoid rebuilds
    _isOnline = online;
    _inSession = busy;
    notifyListeners();
  }

  void markProfileCompleted() {
    _profileCompleted = true;
    notifyListeners();
  }

  /// Persist the chosen storefront theme locally (backend save happens in the UI).
  void setStoreTheme(String key) {
    profile.storeTheme = key;
    notifyListeners();
  }

  // ── Automation presets ──
  final AstroPresets presets = AstroPresets();
  void savePresets() => notifyListeners();

  // ── Storefront (astrologer-listed products) ──
  // Seeded with a couple already-reviewed items so the approval states + the
  // admin-set commission are visible immediately.
  final List<StoreProduct> storeProducts = [
    StoreProduct(
      name: 'Energised 5-Mukhi Rudraksha', description: 'Hand-picked, energised on a Saturday. Comes with a thread.',
      mrp: 1199, price: 899, stock: 24, category: 'Rudraksha', icon: Icons.spa, color: const Color(0xFFC98A5E),
      status: ProductStatus.approved, commissionPercent: 15, unitsSold: 38,
    ),
    StoreProduct(
      name: 'Hand-drawn Janam Kundli (PDF)', description: 'Personalised 20-page birth chart report, delivered in 48h.',
      mrp: 999, price: 699, stock: 999, category: 'Reports', icon: Icons.menu_book_outlined, color: const Color(0xFF6D4B9E),
      status: ProductStatus.approved, commissionPercent: 10, unitsSold: 64,
    ),
    StoreProduct(
      name: 'Shri Yantra (Brass, energised)', description: 'For wealth & focus. Place in the north-east.',
      mrp: 1799, price: 1299, stock: 12, category: 'Yantra', icon: Icons.auto_awesome, color: const Color(0xFFC0392B),
      status: ProductStatus.pending,
    ),
    StoreProduct(
      name: 'Lucky charm bracelet', description: 'Mixed beads bracelet.',
      mrp: 499, price: 399, stock: 40, category: 'Accessories', icon: Icons.brightness_1, color: const Color(0xFFE0584A),
      status: ProductStatus.rejected, adminNote: 'Needs clearer product photos and material details.',
    ),
  ];

  void addStoreProduct(StoreProduct p) {
    storeProducts.insert(0, p);
    notifyListeners();
  }

  void updateStoreProducts() => notifyListeners();

  int get storeLifetimeEarnings => storeProducts.fold(0, (s, p) => s + p.totalEarned);

  // ── Pooja offerings (astrologer-listed) ──
  final List<PoojaOffering> poojaOfferings = [
    PoojaOffering(
      name: 'Maha Mrityunjaya Jaap (1,25,000)', description: 'Full anushthan for health & longevity, performed on your behalf with sankalp.',
      price: 5100, durationNote: 'approx 3 days', availability: 'Mon, Wed, Sat', icon: Icons.local_fire_department, color: const Color(0xFFC0392B),
      status: ProductStatus.approved, commissionPercent: 12, booked: 41,
    ),
    PoojaOffering(
      name: 'Navagraha Shanti Puja', description: 'Pacifies all nine planets. Includes havan and prasad dispatch.',
      price: 2100, durationNote: 'approx 90 min', availability: 'Any day', icon: Icons.brightness_7, color: const Color(0xFFD4A24E),
      status: ProductStatus.approved, commissionPercent: 10, booked: 73,
    ),
    PoojaOffering(
      name: 'Lakshmi Puja (Amavasya special)', description: 'For wealth & prosperity, performed on Amavasya night.',
      price: 1500, durationNote: 'approx 60 min', availability: 'Amavasya only', icon: Icons.auto_awesome, color: const Color(0xFF6D4B9E),
      status: ProductStatus.pending,
    ),
    PoojaOffering(
      name: 'Quick blessing call', description: '10-min blessing.',
      price: 300, durationNote: '10 min', availability: 'Any day', icon: Icons.volunteer_activism, color: const Color(0xFFE0584A),
      status: ProductStatus.rejected, adminNote: 'Too similar to a paid call — list under consultations instead.',
    ),
  ];

  void addPoojaOffering(PoojaOffering p) {
    poojaOfferings.insert(0, p);
    notifyListeners();
  }

  int get poojaLifetimeEarnings => poojaOfferings.fold(0, (s, p) => s + p.totalEarned);

  // ── Live session history ──
  final List<LiveHistory> liveHistory = const [
    LiveHistory(title: 'Evening Q&A — Career & Marriage', when: 'Yesterday, 8:00 PM', peakViewers: 412, questions: 11, superchatEarnings: 1850, duration: Duration(minutes: 42)),
    LiveHistory(title: 'Saturn transit special', when: '3 days ago', peakViewers: 286, questions: 9, superchatEarnings: 920, duration: Duration(minutes: 33)),
    LiveHistory(title: 'Daily horoscope live', when: 'Last week', peakViewers: 198, questions: 6, superchatEarnings: 540, duration: Duration(minutes: 25)),
  ];

  /// Replace the profile with the one loaded from the backend
  /// (GET /astrologers/me/profile). Called after login so the dashboard +
  /// complete-profile screen show the admin-created record, not demo data.
  void applyServerProfile(Map<String, dynamic> json) {
    profile = Astrologer.fromServerJson(json);
    // Mirror the server's authoritative presence so the Online/Offline/Busy
    // toggle reflects the real saved state (not the local default) on load.
    syncPresence(
      availabilityPreference: json['availabilityPreference'] as bool?,
      isOnline: json['isOnline'] as bool?,
      currentCallStatus: json['currentCallStatus'] as String?,
    );
    notifyListeners();
  }

  /// Apply edits from the profile form (only editable fields).
  void updateEditable({
    String? displayName,
    String? bio,
    String? avatar,
    String? coverPhoto,
    List<String>? expertise,
    List<String>? languages,
    int? experienceYears,
  }) {
    if (displayName != null) profile.displayName = displayName;
    if (bio != null) profile.bio = bio;
    if (avatar != null) profile.avatar = avatar;
    if (coverPhoto != null) profile.coverPhoto = coverPhoto;
    if (expertise != null) profile.expertise = expertise;
    if (languages != null) profile.languages = languages;
    if (experienceYears != null) profile.experienceYears = experienceYears;
    notifyListeners();
  }

  // ── Earnings (loaded from the backend via loadDashboard) ──
  int _availableBalance = 0;
  int _pendingBalance = 0;
  int _thisMonthEarnings = 0;
  bool _dashboardLoaded = false;

  int get availableBalance => _availableBalance;
  int get pendingBalance => _pendingBalance;
  int get lifetimeEarnings => profile.totalEarnings; // from /me/profile
  int get thisMonthEarnings => _thisMonthEarnings;
  bool get dashboardLoaded => _dashboardLoaded;

  /// Apply wallet balance from GET /wallet/balance.
  void applyBalance({required int available, required int locked}) {
    _availableBalance = available;
    _pendingBalance = locked;
    notifyListeners();
  }

  /// Apply the per-service consultation stats + this-month earnings from
  /// GET /astrologers/me/stats onto the profile.
  void applyStats(Map<String, dynamic> data) {
    final s = (data['stats'] is Map) ? Map<String, dynamic>.from(data['stats']) : const {};
    ServiceStats parse(String k) {
      final m = (s[k] is Map) ? Map<String, dynamic>.from(s[k]) : const {};
      return ServiceStats(
        sessions: (m['sessions'] as num?)?.toInt() ?? 0,
        minutes: (m['minutes'] as num?)?.toInt() ?? 0,
        earnings: (m['earnings'] as num?)?.toInt() ?? 0,
      );
    }

    profile = profile.withStats(chat: parse('chat'), call: parse('call'), video: parse('video'));
    _thisMonthEarnings = (data['thisMonthEarnings'] as num?)?.toInt() ?? 0;
    _dashboardLoaded = true;
    notifyListeners();
  }

  // ── Notifications ──
  final List<AstroNotification> notifications = [
    AstroNotification(icon: Icons.card_giftcard, title: 'New gift received', body: 'Priya sent you a Lotus', when: '5m ago'),
    AstroNotification(icon: Icons.star, title: 'New 5★ review', body: '"Spot on about my career change."', when: '1h ago'),
    AstroNotification(icon: Icons.payments_outlined, title: 'Withdrawal processed', body: '₹10,000 credited to your bank', when: '1d ago', read: true),
    AstroNotification(icon: Icons.favorite, title: 'New follower', body: 'Rahul K. started following you', when: '2d ago', read: true),
  ];

  int get unreadCount => notifications.where((n) => !n.read).length;

  void markAllRead() {
    for (final n in notifications) {
      n.read = true;
    }
    notifyListeners();
  }

  // ── Incoming request (live, from the socket `incoming-request` event) ──
  ServiceKind? incomingKind;
  String? incomingSessionId;
  String incomingUser = 'Seeker'; // anonymous alias — never the real name/phone
  int incomingRatePerMin = 0;
  int incomingExpiresInSec = 60;

  /// Populate an incoming request from the socket/push payload.
  void setIncoming({required String sessionId, required ServiceKind kind, required String alias, int ratePerMin = 0, int expiresInSec = 60}) {
    incomingSessionId = sessionId;
    incomingKind = kind;
    incomingUser = alias;
    incomingRatePerMin = ratePerMin;
    incomingExpiresInSec = expiresInSec;
    notifyListeners();
  }

  /// Demo trigger retained for manual testing (no real session).
  void simulateIncoming(ServiceKind kind) {
    incomingKind = kind;
    incomingUser = 'Cosmic Seeker';
    notifyListeners();
  }

  void clearIncoming() {
    incomingKind = null;
    incomingSessionId = null;
    notifyListeners();
  }

  // ── Live session (after accept) ──
  String? activeSessionId;
  ServiceKind? activeKind;
  String activeAlias = 'Seeker';
  final List<Map<String, dynamic>> liveMessages = []; // {id,kind,sender,message,mediaUrl,timestamp}

  // Shared server start time → identical clock on both apps (no drift). Null
  // until both parties have joined and the server emits 'session-started'.
  DateTime? sessionStartedAt;
  bool get sessionStarted => sessionStartedAt != null;

  // Elapsed whole seconds since the server-stamped start. Driven by a 1-second
  // ticker in THIS provider (not by each screen's own Timer) so EVERY surface
  // that watches the provider — the active session screen AND the minimized
  // "Resume" pill on the dashboard — advances smoothly and stays in lock-step
  // with the user app (both compute from the same server startedAt). 0 before
  // both parties join. Mirrors the user app's model exactly.
  Timer? _ticker;
  int _elapsedSec = 0;
  int get elapsedSec => _elapsedSec;

  // Device↔server clock offset (serverNow − deviceNow), captured whenever the
  // server hands us a timestamp pair. Corrects device clock skew so the timer
  // shows the server's elapsed time exactly (and matches the user app).
  Duration _clockOffset = Duration.zero;

  /// Adopt a server "now" (ISO). [rtt] — the request round-trip, when known —
  /// centers the sample so network latency doesn't bias the offset.
  void _adoptServerNow(String? iso, {Duration rtt = Duration.zero}) {
    final serverNow = iso != null ? DateTime.tryParse(iso)?.toLocal() : null;
    if (serverNow == null) return;
    _clockOffset = serverNow.difference(DateTime.now()) + Duration(milliseconds: rtt.inMilliseconds ~/ 2);
  }

  /// Server-corrected wall clock.
  DateTime get _nowCorrected => DateTime.now().add(_clockOffset);

  void _startTicker() {
    sessionStartedAt ??= _nowCorrected;
    _ticker?.cancel();
    _tick();
    _scheduleNextTick();
  }

  // Self-scheduling ticks aligned to the session's second boundary, so the
  // displayed second flips exactly when the server's does (no ±1s jitter from
  // an arbitrary Timer.periodic phase).
  void _scheduleNextTick() {
    _ticker?.cancel();
    if (sessionStartedAt == null) return;
    final elapsedMs = _nowCorrected.difference(sessionStartedAt!).inMilliseconds;
    final msToBoundary = 1000 - (elapsedMs % 1000);
    _ticker = Timer(Duration(milliseconds: msToBoundary.clamp(1, 1000)), () {
      _tick();
      _scheduleNextTick();
    });
  }

  void _tick() {
    if (sessionStartedAt == null) return;
    final s = _nowCorrected.difference(sessionStartedAt!).inSeconds;
    _elapsedSec = s < 0 ? 0 : s;
    notifyListeners();
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  // Astrologer's NET earning per minute for the active session (rate − platform
  // cut), from the 'session-started' event. Billing rounds UP to whole minutes.
  int activePerMin = 0;

  /// Live running earning = perMin × billed minutes (ceil of elapsed seconds).
  int get liveEarning {
    if (sessionStartedAt == null || activePerMin <= 0) return 0;
    final billedMinutes = (elapsedSec / 60).ceil().clamp(1, 1 << 30);
    return activePerMin * billedMinutes;
  }

  void startActive({required String sessionId, required ServiceKind kind, required String alias}) {
    activeSessionId = sessionId;
    activeKind = kind;
    activeAlias = alias;
    activePerMin = 0; // set when 'session-started' arrives
    liveMessages.clear();
    _stopTicker();
    _elapsedSec = 0;
    sessionStartedAt = null; // timer waits for session-started
    endSummary = null; // clear any prior session's summary so the new screen
                       // doesn't immediately auto-end on a stale endSummary
    _inSession = true;
    notifyListeners();
  }

  /// Server says both joined → adopt the shared start time. Lenient match: if
  /// this arrives in the tiny window before startActive() set activeSessionId,
  /// adopt it anyway (the only session we could be starting).
  void onSessionStarted(Map<String, dynamic> d) {
    if (activeSessionId != null && d['sessionId'] != null && d['sessionId'] != activeSessionId) return;
    // serverNow pairs with startedAt → clock-offset correction (exact timer).
    _adoptServerNow(d['serverNow']?.toString());
    final started = d['startedAt']?.toString();
    sessionStartedAt = started != null ? DateTime.tryParse(started)?.toLocal() : _nowCorrected;
    // Astrologer's net per-minute earning for this session (from the server).
    final perMin = (d['astrologerPerMin'] as num?)?.toInt();
    if (perMin != null && perMin > 0) activePerMin = perMin;
    _startTicker(); // clock ticks from the server startedAt (identical to user)
    notifyListeners();
  }

  /// Re-pull the authoritative startedAt from the backend. Covers the race where
  /// the live 'session-started' event fired before this client subscribed (FCM
  /// cold-start tap), AND re-anchors the clock to server truth whenever a
  /// (possibly minimized/backgrounded) session is reopened — so the astrologer's
  /// timer always matches the user app exactly, no drift. Safe to call repeatedly.
  /// [api] is the astrologer SessionApi.
  Future<void> syncStartedAt(dynamic api) async {
    final id = activeSessionId;
    if (id == null) return;
    try {
      final t0 = DateTime.now();
      final detail = await api.detail(id);
      // Clock-offset sample: serverNow centered on the request midpoint.
      _adoptServerNow(detail['serverNow']?.toString(), rtt: DateTime.now().difference(t0));
      // Fallback for the per-min earning if the live event was missed: derive
      // the astrologer's net (ratePerMin − adminCutPerMin) from the detail.
      if (activePerMin <= 0) {
        final rate = (detail['ratePerMin'] as num?)?.toInt() ?? 0;
        final cut = (detail['adminCutPerMin'] as num?)?.toInt() ?? 0;
        final net = rate - cut;
        if (net > 0) activePerMin = net;
      }
      final started = detail['startedAt']?.toString();
      if (started != null && started.isNotEmpty) {
        // Adopt the SERVER start time (authoritative) even if we had a local
        // one — this corrects any drift from a DateTime.now() fallback.
        sessionStartedAt = DateTime.tryParse(started)?.toLocal();
        if (_ticker == null) { _startTicker(); } else { _tick(); _scheduleNextTick(); }
        notifyListeners();
      }
    } catch (_) {/* keep waiting for the live event */}
  }

  void addLiveMessage(Map<String, dynamic> m) {
    if (m['sessionId'] != null && m['sessionId'] != activeSessionId) return;
    liveMessages.add(m);
    notifyListeners();
  }

  /// COLD START: ask the server whether this astrologer is still mid-session
  /// and, if so, re-enter it. Without this the app came up on the dashboard
  /// after being killed / swiped out of RAM, silently abandoning a chat the
  /// seeker is still being billed for.
  ///
  /// [api] is the astrologer SessionApi; [socket] rejoins the room so live
  /// events resume. Safe to call repeatedly — no-ops once a session is active.
  Future<bool> resumeFromActive(dynamic api, dynamic socket) async {
    if (_inSession) return true;
    try {
      final res = await api.active();
      if (res == null) return false;
      final s = Map<String, dynamic>.from(res.session as Map);
      final sid = s['sessionId']?.toString();
      if (sid == null) return false;

      final typeStr = (s['type'] ?? 'chat').toString();
      final kind = typeStr == 'call'
          ? ServiceKind.call
          : typeStr == 'video'
              ? ServiceKind.video
              : ServiceKind.chat;

      startActive(sessionId: sid, kind: kind, alias: (s['seekerAlias'] ?? 'Seeker').toString());
      try { socket.joinSession(sid); } catch (_) {/* socket connects shortly after */}

      // Re-anchor the timer to the server's start time.
      final startedAt = s['startedAt'];
      if (startedAt != null) onSessionStarted({'sessionId': sid, 'startedAt': startedAt});

      if (kind == ServiceKind.chat) await loadMessages(api);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Rehydrate the transcript from the server (GET /sessions/:id/messages) —
  /// called on open/resume of an ongoing session so history survives an app
  /// kill or background gap. Clear-then-fill keeps repeated calls idempotent.
  /// [api] is the astrologer SessionApi.
  Future<void> loadMessages(dynamic api) async {
    final id = activeSessionId;
    if (id == null) return;
    try {
      final prior = await api.messagesRaw(id) as List<Map<String, dynamic>>;
      final mapped = prior.map((m) => <String, dynamic>{
            'id': (m['id'] ?? m['_id'])?.toString(),
            'sessionId': id,
            'kind': (m['kind'] ?? 'user').toString(),
            // The pane aligns bubbles by sender=='me'; the server marks `mine`
            // relative to this requester.
            'sender': m['mine'] == true ? 'me' : m['sender']?.toString(),
            'message': m['message'],
            'mediaUrl': m['mediaUrl'],
            'mediaType': m['mediaType'],
            'product': m['product'] is Map ? Map<String, dynamic>.from(m['product'] as Map) : null,
            'timestamp': m['timestamp']?.toString(),
          }).toList();
      liveMessages
        ..clear()
        ..addAll(mapped);
      notifyListeners();
    } catch (_) {/* keep whatever arrived live; history may be unavailable */}
  }

  // Terminal summary from the server's session-ended event (duration + earnings)
  // — drives the astrologer's end-of-session popup. Cleared when consumed.
  Map<String, dynamic>? endSummary;

  /// Session ids we have already torn down. The backend emits `session-ended`
  /// TWICE — once to the session room (`emit.toSession`) and once to the
  /// astrologer's personal room (`emit.toUser`) — so this handler always runs
  /// twice for one real end. Without this latch the second delivery re-set
  /// `endSummary` AFTER the screen had consumed it, and because the screen's own
  /// `_endHandled` flag was already true it refused to act again: the astrologer
  /// sat on the chat screen while the seeker had already left.
  final Set<String> _endedSessionIds = {};

  /// Server says the session ended (by either side). Capture the summary so the
  /// active screen can show it, then clear the live state.
  void onSessionEnded(Map<String, dynamic> d) {
    if (activeSessionId != null && d['sessionId'] != null && d['sessionId'] != activeSessionId) return;
    // Ignore the duplicate delivery of an end we have already processed.
    final endedId = d['sessionId']?.toString();
    if (endedId != null && endedId.isNotEmpty) {
      if (!_endedSessionIds.add(endedId)) return;
      // Keep the set from growing without bound over a long-lived session.
      if (_endedSessionIds.length > 20) {
        _endedSessionIds.remove(_endedSessionIds.first);
      }
    }
    endSummary = Map<String, dynamic>.from(d);
    activeSessionId = null;
    activeKind = null;
    _stopTicker();
    _elapsedSec = 0;
    sessionStartedAt = null;
    liveMessages.clear();
    _inSession = false;
    notifyListeners();
  }

  void consumeEndSummary() { endSummary = null; }

  void endActive() {
    activeSessionId = null;
    activeKind = null;
    _stopTicker();
    _elapsedSec = 0;
    sessionStartedAt = null;
    liveMessages.clear();
    _inSession = false;
    notifyListeners();
  }

  // ── History (mock) ──
  final List<ConsultRecord> history = const [
    ConsultRecord(userName: 'Meera Joshi', kind: ServiceKind.call, minutes: 18, earned: 414, when: 'Today, 2:14 PM'),
    ConsultRecord(userName: 'Sandeep R.', kind: ServiceKind.chat, minutes: 24, earned: 384, when: 'Today, 11:40 AM'),
    ConsultRecord(userName: 'Kavya N.', kind: ServiceKind.video, minutes: 12, earned: 384, when: 'Yesterday, 7:02 PM'),
    ConsultRecord(userName: 'Unknown', kind: ServiceKind.call, minutes: 0, earned: 0, when: 'Yesterday, 5:50 PM', completed: false),
    ConsultRecord(userName: 'Arjun T.', kind: ServiceKind.chat, minutes: 31, earned: 496, when: 'Yesterday, 3:18 PM'),
    ConsultRecord(userName: 'Pooja D.', kind: ServiceKind.call, minutes: 9, earned: 207, when: '2 days ago'),
    ConsultRecord(userName: 'Ritu S.', kind: ServiceKind.video, minutes: 22, earned: 704, when: '3 days ago'),
  ];

  // ── Ledger (mock) ──
  final List<LedgerEntry> ledger = const [
    LedgerEntry(title: 'Call with Meera Joshi', amount: 414, when: 'Today, 2:32 PM'),
    LedgerEntry(title: 'Chat with Sandeep R.', amount: 384, when: 'Today, 12:04 PM'),
    LedgerEntry(title: 'Withdrawal to HDFC ••4521', amount: -10000, when: 'Yesterday', isWithdrawal: true),
    LedgerEntry(title: 'Video with Kavya N.', amount: 384, when: 'Yesterday, 7:14 PM'),
    LedgerEntry(title: 'Chat with Arjun T.', amount: 496, when: 'Yesterday, 3:49 PM'),
    LedgerEntry(title: 'Withdrawal to HDFC ••4521', amount: -8000, when: 'Last week', isWithdrawal: true),
  ];
}
