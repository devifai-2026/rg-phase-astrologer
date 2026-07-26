import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../api/astrologer_api.dart';
import '../../../api/socket_service.dart';
import '../../../i18n/strings.dart';
import '../../../net/link_state.dart';
import '../../../models/astrologer.dart';
import '../../../providers/session_provider.dart';
import '../../../services/analytics.dart';
import '../../../theme/rg_colors.dart';

/// Availability control. The astrologer manually toggles only Online ⟷ Offline.
/// "Busy" is NOT a manual option — it is auto-set by the system while a
/// consultation is in progress, shown here as a read-only badge.
class StatusToggle extends StatelessWidget {
  const StatusToggle({super.key});

  /// Flip local state immediately (snappy UI), then push to the backend and
  /// VERIFY it landed — reverting the optimistic flip if it didn't.
  ///
  /// This used to fire three unawaited calls and swallow the REST failure with
  /// `.catchError((_) {})`, so if both the socket emit and the REST write failed
  /// the UI kept asserting a state the server never accepted: the astrologer
  /// believed they were online while seekers saw them offline.
  Future<void> _setOnline(BuildContext context, bool online) async {
    final session = context.read<SessionProvider>();
    final socket = context.read<SocketService>();
    final api = context.read<AstrologerApi>();
    final messenger = ScaffoldMessenger.of(context);
    final t = Strings.of(context);

    final previous = session.isOnline;
    session.setOnline(online); // optimistic
    Analytics.instance.setAvailability(online);

    // Fast path: the socket event flips presence server-side and broadcasts it.
    socket.setOnline(online);

    // Durable path: the REST write is the source of truth for the saved
    // preference, so it must succeed even when the socket is down.
    try {
      await api.setOnline(online);
    } catch (_) {
      // If the socket is live the server already has it; only revert when BOTH
      // paths are unavailable, otherwise a slow REST call would undo a good flip.
      if (!socket.status.reachable) {
        session.setOnline(previous);
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(t.couldNotUpdateStatusCheck),
            behavior: SnackBarBehavior.floating,
          ));
      }
    }
  }

  /// Diagnostics sheet (long-press the toggle). You cannot debug what the client
  /// won't tell you — this turns "it says connecting forever" into a report with
  /// the state, host, last error and socket id.
  void _showDiagnostics(BuildContext context) {
    final c = context.rg;
    final s = context.read<SocketService>().status;
    final rows = <List<String>>[
      ['State', s.state.name],
      ['Host', s.activeHost],
      ['Attempt', '${s.attempt}'],
      ['Last error', s.lastErrorCode ?? '—'],
      ['Fatal reason', s.fatalReason?.name ?? '—'],
      ['Socket id', s.socketId ?? '—'],
      ['Connected since', s.connectedSince?.toIso8601String() ?? '—'],
      ['Last ack', s.lastAckAt?.toIso8601String() ?? '—'],
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: c.ground2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Connection diagnostics', style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 12),
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  SizedBox(width: 130, child: Text(r[0], style: TextStyle(color: c.muted, fontSize: 12.5))),
                  Expanded(child: Text(r[1], style: TextStyle(color: c.ink, fontSize: 12.5, fontWeight: FontWeight.w600))),
                ]),
              ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(Strings.of(context).retry),
                onPressed: () {
                  context.read<SocketService>().nudge();
                  Navigator.of(ctx).pop();
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final session = context.watch<SessionProvider>();
    final link = context.watch<SocketService>().status;
    final online = session.isOnline;
    final busy = session.status == AvailabilityStatus.busy;
    // Intent is online but the realtime socket isn't live yet → not reachable.
    final connecting = session.status == AvailabilityStatus.connecting;
    // The link has GIVEN UP (budget exhausted / auth rejected / no network).
    // This is the state that used to be an eternal spinner; it now needs an
    // explicit, actionable banner.
    final dead = link.actionable && link.state != LinkState.noAuth;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Online / Offline segmented switch. Long-press for diagnostics.
        GestureDetector(
          onLongPress: () => _showDiagnostics(context),
          child: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
            child: Row(
              children: [
                // Locked while BUSY (can't go offline on a billing seeker) — but
                // only when the link is actually LIVE. With a dead link `busy` may
                // be stale (it clears on `session-ended`, which can't arrive), and
                // locking both segments then bricks the astrologer entirely.
                _seg(context, label: Strings.of(context).online, tint: c.green, selected: online,
                    onTap: (busy && link.reachable) ? null : () => _setOnline(context, true)),
                _seg(context, label: Strings.of(context).offline, tint: c.muted, selected: !online,
                    onTap: (busy && link.reachable) ? null : () => _setOnline(context, false)),
              ],
            ),
          ),
        ),
        // Link gave up → red, explicit, with a Retry button.
        if (dead) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: c.red.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.red),
            ),
            child: Row(children: [
              Icon(link.state == LinkState.offlineNoNetwork ? Icons.wifi_off : Icons.error_outline,
                  size: 16, color: c.red),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  link.state == LinkState.offlineNoNetwork
                      ? Strings.of(context).noInternetConnection
                      : Strings.of(context).notConnectedYouWillNot,
                  style: TextStyle(color: c.red, fontWeight: FontWeight.w700, fontSize: 12.5),
                ),
              ),
              const SizedBox(width: 6),
              TextButton(
                onPressed: () => context.read<SocketService>().nudge(),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10), minimumSize: const Size(0, 32)),
                child: Text(Strings.of(context).retry, style: TextStyle(color: c.red, fontWeight: FontWeight.w800)),
              ),
            ]),
          ),
        ],
        // Reconnecting badge — online intent but socket not live (not reachable).
        if (connecting && !dead) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(color: c.gold.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12), border: Border.all(color: c.gold)),
            child: Row(children: [
              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: c.gold)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(Strings.of(context).connectingYouReNotVisibleTo,
                    style: TextStyle(color: c.gold, fontWeight: FontWeight.w700, fontSize: 12.5)),
              ),
            ]),
          ),
        ],
        // Auto "busy" badge (read-only) while in a consultation.
        if (busy) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(color: c.gold.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12), border: Border.all(color: c.gold)),
            child: Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: c.gold, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Icon(Icons.lock_clock, size: 16, color: c.gold),
              const SizedBox(width: 6),
              Expanded(
                child: Text(Strings.of(context).busyInAConsultationSetAutomatically,
                    style: TextStyle(color: c.gold, fontWeight: FontWeight.w700, fontSize: 12.5)),
              ),
            ]),
          ),
        ],
      ],
    );
  }

  Widget _seg(BuildContext context, {required String label, required Color tint, required bool selected, required VoidCallback? onTap}) {
    final c = context.rg;
    final disabled = onTap == null;
    return Expanded(
      child: Opacity(
        opacity: disabled && !selected ? 0.45 : 1, // dim the unavailable option
        child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected ? tint.withValues(alpha: 0.16) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? tint : Colors.transparent, width: 1.3),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: tint, shape: BoxShape.circle)),
              const SizedBox(width: 7),
              Text(label, style: TextStyle(color: selected ? tint : c.muted, fontWeight: selected ? FontWeight.w800 : FontWeight.w600, fontSize: 13.5)),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
