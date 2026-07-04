import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../api/socket_service.dart';
import '../../i18n/strings.dart';
import '../../models/ai_models.dart';
import '../../providers/session_provider.dart';
import '../../theme/rg_colors.dart';
import '../storefront/storefront_screen.dart';

/// Astrologer settings & presets. Take-a-break control (shows busy to seekers),
/// storefront theme, share-the-app referral, and the Live AI-moderator default.
class AstroSettingsScreen extends StatefulWidget {
  const AstroSettingsScreen({super.key});

  @override
  State<AstroSettingsScreen> createState() => _AstroSettingsScreenState();
}

class _AstroSettingsScreenState extends State<AstroSettingsScreen> {
  late final AstroPresets p = context.read<SessionProvider>().presets;
  Timer? _tick; // 1s repaint for the break countdown

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && context.read<SessionProvider>().onBreak) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _save() {
    context.read<SessionProvider>().savePresets();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Strings.of(context).settingsSaved)));
  }

  // ── Break ──
  void _startBreak(int minutes) {
    final s = context.read<SessionProvider>();
    final messenger = ScaffoldMessenger.of(context);
    // Can't break mid-consultation.
    if (s.inSession) {
      messenger.showSnackBar(SnackBar(content: Text(Strings.of(context).youReInAConsultationFinish)));
      return;
    }
    if (!s.isOnline) {
      messenger.showSnackBar(SnackBar(content: Text(Strings.of(context).goOnlineFirstToTakeA)));
      return;
    }
    // Optimistic: show busy immediately; server confirms via ack/my-presence.
    s.setBreakUntil(DateTime.now().add(Duration(minutes: minutes)));
    context.read<SocketService>().setBreak(minutes, ack: (resp) {
      if (!mounted) return;
      if (resp['ok'] != true) {
        s.setBreakUntil(null); // roll back
        final reason = resp['reason'] == 'in_consultation'
            ? Strings.of(context).youReInAConsultationCan
            : Strings.of(context).couldNotStartTheBreakPlease;
        messenger.showSnackBar(SnackBar(content: Text(reason)));
      } else {
        final bu = resp['breakUntil'];
        s.setBreakUntil(bu == null ? null : DateTime.tryParse(bu.toString())?.toLocal());
      }
    });
  }

  void _endBreak() {
    final s = context.read<SessionProvider>();
    s.setBreakUntil(null); // optimistic
    context.read<SocketService>().setBreak(0);
  }

  String _fmtRemaining(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  // ── Share the app (refer an astrologer) ──
  void _shareApp() {
    final msg =
        '${Strings.of(context).joinMeOnRudragangaAsAn}${Strings.of(context).audioVideoAndEarnOnYour}https://astroapp.example/astrologer';
    Share.share(msg, subject: Strings.of(context).becomeAnAstrologerOnRudraganga);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final s = context.watch<SessionProvider>();

    return Scaffold(
      backgroundColor: c.ground,
      appBar: AppBar(
        title: Text(Strings.of(context).settingsPresets, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800)),
        actions: [TextButton(onPressed: _save, child: Text(Strings.of(context).save2, style: TextStyle(color: c.red, fontWeight: FontWeight.w700)))],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // ── Take a break ──
          _section(c, Strings.of(context).takeABreak),
          _breakCard(c, s),

          // ── Storefront theme ──
          _section(c, Strings.of(context).storefront),
          _navTile(c,
              icon: Icons.palette_outlined,
              title: Strings.of(context).chooseTheme,
              sub: Strings.of(context).pickTheLookOfYourPublic,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StorefrontScreen()))),

          // ── Refer ──
          _section(c, Strings.of(context).growTheCommunity),
          _navTile(c,
              icon: Icons.ios_share,
              title: Strings.of(context).shareTheApp,
              sub: Strings.of(context).inviteOthersToJoinRudragangaAs,
              onTap: _shareApp),

          // ── Live ──
          _section(c, 'Live'),
          _switchTile(c,
              icon: Icons.smart_toy_outlined,
              title: Strings.of(context).aiModeratorOnByDefault,
              sub: Strings.of(context).enableTheAiLiveModeratorWhenever,
              value: p.aiModeratorOnLive,
              onChanged: (v) { setState(() => p.aiModeratorOnLive = v); }),

          const SizedBox(height: 16),
          ElevatedButton.icon(icon: const Icon(Icons.save_outlined), label: Text(Strings.of(context).saveSettings), onPressed: _save),
        ],
      ),
    );
  }

  Widget _breakCard(RgColors c, SessionProvider s) {
    final onBreak = s.onBreak;
    if (onBreak) {
      final remaining = s.breakUntil!.difference(DateTime.now());
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: c.gold.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(16), border: Border.all(color: c.gold)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.self_improvement, color: c.gold, size: 22),
            const SizedBox(width: 10),
            Expanded(child: Text(Strings.of(context).onABreak, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 15))),
            Text(_fmtRemaining(remaining.isNegative ? Duration.zero : remaining),
                style: TextStyle(color: c.gold, fontWeight: FontWeight.w800, fontSize: 20, fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
          const SizedBox(height: 6),
          Text(Strings.of(context).seekersSeeYouAsBusyWe,
              style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.3)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _endBreak,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(Strings.of(context).endBreakNow),
              style: OutlinedButton.styleFrom(foregroundColor: c.red, side: BorderSide(color: c.red)),
            ),
          ),
        ]),
      );
    }

    final canBreak = s.isOnline && !s.inSession;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.self_improvement, color: c.red, size: 22),
          const SizedBox(width: 10),
          Expanded(child: Text(Strings.of(context).takeAShortBreak, style: TextStyle(color: c.ink, fontWeight: FontWeight.w700, fontSize: 14.5))),
        ]),
        const SizedBox(height: 4),
        Text(
          s.inSession
              ? "You're in a consultation — finish it before taking a break."
              : !s.isOnline
                  ? Strings.of(context).goOnlineToEnableBreaks
                  : Strings.of(context).pauseIncomingRequestsForAFew,
          style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.3),
        ),
        const SizedBox(height: 14),
        Row(children: [
          _breakChip(c, Strings.of(context).s5Min, 5, canBreak),
          const SizedBox(width: 10),
          _breakChip(c, Strings.of(context).s10Min, 10, canBreak),
          const SizedBox(width: 10),
          _breakChip(c, Strings.of(context).s15Min, 15, canBreak),
        ]),
      ]),
    );
  }

  Widget _breakChip(RgColors c, String label, int minutes, bool enabled) => Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? () => _startBreak(minutes) : null,
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: enabled ? c.redSoft : c.ground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: enabled ? c.red.withValues(alpha: 0.5) : c.line),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.play_circle_outline, size: 18, color: enabled ? c.red : c.muted),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(color: enabled ? c.red : c.muted, fontWeight: FontWeight.w800, fontSize: 13)),
            ]),
          ),
        ),
      );

  Widget _section(RgColors c, String t) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 10),
        child: Text(t, style: TextStyle(color: c.gold, fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 0.3)),
      );

  Widget _navTile(RgColors c, {required IconData icon, required String title, required String sub, required VoidCallback onTap}) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
          child: Row(children: [
            Icon(icon, color: c.red, size: 22),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(color: c.ink, fontWeight: FontWeight.w700, fontSize: 14.5)),
              const SizedBox(height: 2),
              Text(sub, style: TextStyle(color: c.muted, fontSize: 12, height: 1.3)),
            ])),
            Icon(Icons.chevron_right, color: c.muted),
          ]),
        ),
      );

  Widget _switchTile(RgColors c, {required IconData icon, required String title, required String sub, required bool value, required ValueChanged<bool> onChanged}) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
        child: Row(children: [
          Icon(icon, color: c.red, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(color: c.ink, fontWeight: FontWeight.w700, fontSize: 14.5)),
            const SizedBox(height: 2),
            Text(sub, style: TextStyle(color: c.muted, fontSize: 12, height: 1.3)),
          ])),
          Switch(value: value, activeColor: c.red, onChanged: onChanged),
        ]),
      );
}
