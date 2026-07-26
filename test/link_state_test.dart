import 'package:flutter_test/flutter_test.dart';
import 'package:rg_astrologer/net/link_state.dart';

/// The invariant these tests protect: the UI must always be able to tell the
/// difference between "working on it" and "gave up", so an unbounded spinner is
/// impossible. Previously the client tracked one `_connected` bool, so every
/// failure — no token, dead host, rejected auth, half-open socket — rendered
/// identically as "Connecting…" with no way out.
void main() {
  const host = 'https://api.example.test';

  LinkStatus s(LinkState state, {LinkFatalReason? reason}) =>
      LinkStatus(state: state, activeHost: host, fatalReason: reason);

  group('LinkStatus.reachable', () {
    test('only `connected` counts as reachable', () {
      expect(s(LinkState.connected).reachable, isTrue);
      for (final st in LinkState.values.where((v) => v != LinkState.connected)) {
        expect(s(st).reachable, isFalse, reason: '${st.name} must not be reachable');
      }
    });

    test('degraded is NOT reachable — a half-open socket cannot deliver', () {
      // socket.io can report `connected` on a zombie TCP connection; treating
      // that as reachable is what let presence lie mid-consultation.
      expect(s(LinkState.degraded).reachable, isFalse);
    });
  });

  group('transient vs actionable', () {
    test('transient states are the ones worth showing a spinner for', () {
      for (final st in [
        LinkState.connecting,
        LinkState.authenticating,
        LinkState.backoff,
        LinkState.degraded,
      ]) {
        expect(s(st).transient, isTrue, reason: st.name);
        expect(s(st).actionable, isFalse, reason: st.name);
      }
    });

    test('actionable states need a user action, never a bare spinner', () {
      for (final st in [LinkState.fatal, LinkState.offlineNoNetwork, LinkState.noAuth]) {
        expect(s(st).actionable, isTrue, reason: st.name);
        expect(s(st).transient, isFalse, reason: st.name);
      }
    });

    test('every state is exactly one of reachable / transient / actionable / stopped', () {
      for (final st in LinkState.values) {
        final v = s(st);
        final flags = [v.reachable, v.transient, v.actionable].where((f) => f).length;
        if (st == LinkState.stopped) {
          expect(flags, 0, reason: 'stopped is deliberately none of the three');
        } else {
          expect(flags, 1, reason: '${st.name} must be exactly one category');
        }
      }
    });

    test('no state is both reachable and transient (the old ambiguity)', () {
      for (final st in LinkState.values) {
        final v = s(st);
        expect(v.reachable && v.transient, isFalse, reason: st.name);
      }
    });
  });

  group('fatal reasons', () {
    test('authRejected is distinguishable from allHostsExhausted', () {
      // These need different UI: one is "sign in again", the other is "retry".
      expect(s(LinkState.fatal, reason: LinkFatalReason.authRejected).fatalReason,
          LinkFatalReason.authRejected);
      expect(s(LinkState.fatal, reason: LinkFatalReason.allHostsExhausted).fatalReason,
          LinkFatalReason.allHostsExhausted);
    });
  });

  group('copyWith', () {
    test('clearFatal drops the reason so a retry starts clean', () {
      final fatal = s(LinkState.fatal, reason: LinkFatalReason.allHostsExhausted);
      final retry = fatal.copyWith(state: LinkState.connecting, clearFatal: true);
      expect(retry.fatalReason, isNull);
      expect(retry.state, LinkState.connecting);
    });

    test('clearNextAttempt removes a stale countdown', () {
      final backoff = LinkStatus(
        state: LinkState.backoff,
        activeHost: host,
        nextAttemptAt: DateTime.now().add(const Duration(seconds: 5)),
      );
      expect(backoff.copyWith(state: LinkState.connected, clearNextAttempt: true).nextAttemptAt, isNull);
    });

    test('preserves unspecified fields', () {
      final a = LinkStatus(state: LinkState.connected, activeHost: host, socketId: 'abc', attempt: 3);
      final b = a.copyWith(state: LinkState.degraded);
      expect(b.socketId, 'abc');
      expect(b.attempt, 3);
      expect(b.activeHost, host);
    });
  });

  group('timing budget', () {
    test('our connect deadline is shorter than socket.io internal 20s timeout', () {
      // Otherwise the library wins the race and we never surface the stall.
      expect(LinkTimings.attemptTimeout.inSeconds, lessThan(20));
    });

    test('backoff is capped well above the old 3s so a dead network is not hammered', () {
      expect(LinkTimings.backoffMax.inSeconds, greaterThanOrEqualTo(10));
    });

    test('total budget exceeds per-host budget so host rotation can happen first', () {
      expect(LinkTimings.totalBudget, greaterThan(LinkTimings.hostBudget));
    });

    test('heartbeat interval leaves room for its own ack timeout', () {
      expect(LinkTimings.heartbeatAckTimeout, lessThan(LinkTimings.heartbeatInterval));
    });
  });
}
