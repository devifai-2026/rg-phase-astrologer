import 'package:flutter/foundation.dart';

/// Where the realtime link actually is. Deliberately separate from PRESENCE
/// INTENT ("I want to take consultations") — conflating the two is what let the
/// UI claim "Online" while no socket existed.
enum LinkState {
  /// No credentials. Terminal until login. The UI must show a sign-in prompt,
  /// NEVER a spinner — this is the state the old code silently sat in when
  /// `connect()` returned early on a null access token.
  noAuth,

  /// Credentials exist but the access token is missing/expired; a refresh is in
  /// flight. Bounded by [LinkTimings.refreshTimeout].
  authenticating,

  /// A connect attempt is in flight. Bounded by [LinkTimings.attemptTimeout],
  /// which is deliberately shorter than socket.io's own 20s so we surface a
  /// stalled handshake instead of waiting on the library.
  connecting,

  /// Handshake complete.
  connected,

  /// Socket reports connected but heartbeat acks are being missed — a half-open
  /// TCP connection, the classic mobile-NAT zombie. Treated as NOT reachable,
  /// because it isn't.
  degraded,

  /// A connect attempt failed; waiting out the backoff before retrying.
  backoff,

  /// The device has no network at all. We don't burn retries here; we wait for a
  /// connectivity change. Distinct from [backoff] because the user-facing advice
  /// differs ("check your internet", not "retrying…").
  offlineNoNetwork,

  /// Retry budget exhausted on every host, or the server rejected our identity.
  /// Requires an explicit user or lifecycle action to leave.
  ///
  /// THIS is the state that makes "Connecting… forever" impossible: every path
  /// out of [backoff] either retries or lands here, and here the UI shows an
  /// actionable error with a Retry button.
  fatal,

  /// Deliberately down: logged out, or backgrounded past the grace window.
  stopped,
}

enum LinkFatalReason { authRejected, allHostsExhausted, unknown }

/// Timing budget for the state machine. Every transient state is bounded by one
/// of these, which is what guarantees the machine cannot stall.
class LinkTimings {
  /// Shorter than socket.io's internal 20s connect timeout on purpose: we want to
  /// own the retry decision rather than wait for the library.
  static const attemptTimeout = Duration(seconds: 8);
  static const refreshTimeout = Duration(seconds: 10);

  /// Exponential backoff with full jitter. The old 500ms→3s cap hammered the
  /// radio ~20x/minute forever on a dead network — a real battery complaint and a
  /// self-inflicted flood during an outage.
  static const backoffBase = Duration(milliseconds: 800);
  static const backoffMax = Duration(seconds: 20);
  static const backoffJitter = 0.3;

  /// Attempts on one host before rotating to the next candidate.
  static const hostBudget = 4;

  /// Total attempts before giving up and going [LinkState.fatal].
  static const totalBudget = 12;

  /// Suppress the UI flap for a brief drop; socket.io usually reconnects inside
  /// this window. Note this only delays the BADGE — the state machine starts
  /// reconnecting immediately.
  static const disconnectGrace = Duration(milliseconds: 2500);

  /// How long the app may be backgrounded before we close the socket cleanly.
  static const backgroundGrace = Duration(seconds: 20);

  static const heartbeatInterval = Duration(seconds: 25);
  static const heartbeatAckTimeout = Duration(seconds: 10);
}

/// Immutable snapshot the UI renders. A value type rather than a bool, so the
/// UI can be specific ("Retrying in 4s", "Not connected — Retry") instead of
/// showing one indeterminate spinner for every different failure.
@immutable
class LinkStatus {
  const LinkStatus({
    required this.state,
    required this.activeHost,
    this.attempt = 0,
    this.nextAttemptAt,
    this.connectedSince,
    this.lastAckAt,
    this.fatalReason,
    this.lastErrorCode,
    this.socketId,
  });

  final LinkState state;
  final String activeHost;
  final int attempt;
  final DateTime? nextAttemptAt;
  final DateTime? connectedSince;
  final DateTime? lastAckAt;
  final LinkFatalReason? fatalReason;

  /// Normalized: 'timeout' | 'dns' | 'refused' | 'auth' | 'network' | …
  final String? lastErrorCode;
  final String? socketId;

  /// The ONE question the rest of the app should ask. Everything else is display.
  bool get reachable => state == LinkState.connected;

  /// Working on it — show a calm "reconnecting" affordance, not an error.
  bool get transient =>
      state == LinkState.connecting ||
      state == LinkState.authenticating ||
      state == LinkState.backoff ||
      state == LinkState.degraded;

  /// The user must do something. Show an error WITH an action.
  bool get actionable =>
      state == LinkState.fatal ||
      state == LinkState.offlineNoNetwork ||
      state == LinkState.noAuth;

  LinkStatus copyWith({
    LinkState? state,
    String? activeHost,
    int? attempt,
    DateTime? nextAttemptAt,
    DateTime? connectedSince,
    DateTime? lastAckAt,
    LinkFatalReason? fatalReason,
    String? lastErrorCode,
    String? socketId,
    bool clearNextAttempt = false,
    bool clearFatal = false,
  }) {
    return LinkStatus(
      state: state ?? this.state,
      activeHost: activeHost ?? this.activeHost,
      attempt: attempt ?? this.attempt,
      nextAttemptAt: clearNextAttempt ? null : (nextAttemptAt ?? this.nextAttemptAt),
      connectedSince: connectedSince ?? this.connectedSince,
      lastAckAt: lastAckAt ?? this.lastAckAt,
      fatalReason: clearFatal ? null : (fatalReason ?? this.fatalReason),
      lastErrorCode: lastErrorCode ?? this.lastErrorCode,
      socketId: socketId ?? this.socketId,
    );
  }

  /// One-line summary for the diagnostics sheet + telemetry.
  @override
  String toString() =>
      'LinkStatus(${state.name} host=$activeHost attempt=$attempt '
      'err=${lastErrorCode ?? '-'} fatal=${fatalReason?.name ?? '-'})';
}
