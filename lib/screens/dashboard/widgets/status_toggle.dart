import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../api/astrologer_api.dart';
import '../../../api/socket_service.dart';
import '../../../i18n/strings.dart';
import '../../../models/astrologer.dart';
import '../../../providers/session_provider.dart';
import '../../../services/analytics.dart';
import '../../../theme/rg_colors.dart';

/// Availability control. The astrologer manually toggles only Online ⟷ Offline.
/// "Busy" is NOT a manual option — it is auto-set by the system while a
/// consultation is in progress, shown here as a read-only badge.
class StatusToggle extends StatelessWidget {
  const StatusToggle({super.key});

  /// Flip local state immediately (snappy UI), then push to the backend: the
  /// socket `set-online` event is the fast path (the server flips presence +
  /// broadcasts to users), with POST /me/online as a durable fallback.
  void _setOnline(BuildContext context, bool online) {
    context.read<SessionProvider>().setOnline(online);
    context.read<SocketService>().setOnline(online);
    context.read<AstrologerApi>().setOnline(online).catchError((_) {/* socket already handled it */});
    Analytics.instance.setAvailability(online); // GA event
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final session = context.watch<SessionProvider>();
    final online = session.isOnline;
    final busy = session.status == AvailabilityStatus.busy;
    // Intent is online but the realtime socket isn't live yet → not reachable.
    final connecting = session.status == AvailabilityStatus.connecting;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Online / Offline segmented switch.
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
          child: Row(
            children: [
              _seg(context, label: Strings.of(context).online, tint: c.green, selected: online, onTap: () => _setOnline(context, true)),
              _seg(context, label: Strings.of(context).offline, tint: c.muted, selected: !online, onTap: () => _setOnline(context, false)),
            ],
          ),
        ),
        // Reconnecting badge — online intent but socket not live (not reachable).
        if (connecting) ...[
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

  Widget _seg(BuildContext context, {required String label, required Color tint, required bool selected, required VoidCallback onTap}) {
    final c = context.rg;
    return Expanded(
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
    );
  }
}
