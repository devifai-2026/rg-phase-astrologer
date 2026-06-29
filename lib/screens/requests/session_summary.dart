import 'package:flutter/material.dart';

import '../../i18n/strings.dart';
import '../../theme/rg_colors.dart';
import '../feedback/service_feedback_sheet.dart';

/// Astrologer end-of-session summary popup: duration + earnings for THIS
/// session. Shown when a consultation ends (by either side), after which the
/// astrologer is returned to the dashboard. Premium card with a close (X).
/// Once the card is dismissed, the multi-dimension feedback sheet is offered
/// (skippable) for this session so admins get post-service feedback.
Future<void> showAstroSessionSummary(BuildContext context, Map<String, dynamic> summary) async {
  final durationSec = (summary['durationSec'] as num?)?.toInt() ?? 0;
  final billedMinutes = (summary['billedMinutes'] as num?)?.toInt() ?? 0;
  final earning = (summary['astrologerEarning'] as num?)?.toInt() ?? 0;
  final m = durationSec ~/ 60, s = durationSec % 60;
  final durLabel = s == 0 ? '${m}m' : '${m}m ${s}s';
  final sessionId = (summary['sessionId'] ?? '').toString();
  final type = (summary['type'] ?? 'chat').toString();

  await showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Session complete',
    barrierColor: Colors.black.withValues(alpha: 0.62),
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (ctx, a, b) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, secondary, child) {
      final c = ctx.rg;
      final curved = Curves.easeOutBack.transform(anim.value.clamp(0.0, 1.0));
      return Opacity(
        opacity: anim.value.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: 0.92 + 0.08 * curved,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Material(
                color: Colors.transparent,
                child: _SummaryCard(
                  c: c,
                  durLabel: durLabel,
                  billedMinutes: billedMinutes,
                  earning: earning,
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  // After the summary card is dismissed, offer the skippable feedback sheet for
  // this delivered service. Guard context validity (the dialog may have popped
  // the route on its way out).
  if (sessionId.isNotEmpty && context.mounted) {
    await ServiceFeedbackSheet.show(context, kind: 'session', sourceId: sessionId, serviceType: type);
  }
}

class _SummaryCard extends StatelessWidget {
  final RgColors c;
  final String durLabel;
  final int billedMinutes;
  final int earning;
  const _SummaryCard({required this.c, required this.durLabel, required this.billedMinutes, required this.earning});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [c.ground2, c.ground],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: c.line),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 36, offset: const Offset(0, 18)),
        ],
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Success crest.
                Container(
                  height: 76, width: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [c.green.withValues(alpha: 0.28), c.green.withValues(alpha: 0.06)]),
                    border: Border.all(color: c.green.withValues(alpha: 0.55), width: 1.4),
                  ),
                  child: Icon(Icons.check_rounded, color: c.green, size: 40),
                ),
                const SizedBox(height: 16),
                Text(Strings.of(context).sessionComplete, style: TextStyle(color: c.ink, fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 5),
                Text(Strings.of(context).yourConsultationHasEnded, style: TextStyle(color: c.muted, fontSize: 13.5)),
                const SizedBox(height: 20),

                // Stat row in a glassy panel.
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  decoration: BoxDecoration(
                    color: c.ground.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: c.line),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _stat(c, Icons.timer_outlined, durLabel, Strings.of(context).duration),
                      _divider(c),
                      _stat(c, Icons.confirmation_number_outlined, '$billedMinutes', Strings.of(context).billedMin),
                      _divider(c),
                      _stat(c, Icons.account_balance_wallet_outlined, '₹$earning', Strings.of(context).earned, highlight: true),
                    ],
                  ),
                ),
                const SizedBox(height: 22),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(Strings.of(context).backToDashboard, style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),

          // Close (X).
          Positioned(
            top: 10, right: 10,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: Icon(Icons.close_rounded, color: c.muted, size: 22),
              tooltip: Strings.of(context).close,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider(RgColors c) => Container(width: 1, height: 34, color: c.line);

  Widget _stat(RgColors c, IconData icon, String value, String label, {bool highlight = false}) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: highlight ? c.gold : c.muted, size: 22),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(color: highlight ? c.gold : c.ink, fontWeight: FontWeight.w800, fontSize: 16.5)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: c.muted, fontSize: 10.5)),
        ],
      );
}
