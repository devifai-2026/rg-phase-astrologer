import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../api/astrologer_api.dart';
import '../../i18n/strings.dart';
import '../../screens/dashboard/dashboard_shell.dart';
import '../../services/media_permission.dart';
import '../../services/push_service.dart';
import '../../theme/rg_colors.dart';
import '../../widgets/slide_route.dart';
import 'language_select_screen.dart';

/// Shown right after OTP verification. Mirrors the user app's permissions
/// screen, MINUS location (astrologers don't need it). Required permissions:
/// notifications, microphone, camera, photos. If every permission is already
/// granted, this screen auto-skips.
///
/// After permissions: first-time astrologers go through onboarding (language →
/// complete-profile); returning astrologers go straight to the dashboard.
class PermissionsScreen extends StatefulWidget {
  /// True on first login (run the language + complete-profile onboarding).
  /// False for returning logins (skip straight to the dashboard).
  final bool firstTime;
  const PermissionsScreen({super.key, this.firstTime = true});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> with WidgetsBindingObserver {
  bool _requesting = false;
  bool _finishing = false;
  bool _ready = false; // false until we've resolved the photos perm + first read

  // Version-correct photos permission (READ_MEDIA_IMAGES 33+, else storage).
  Permission _photosPerm = Permission.photos;

  // Required permissions, in display order. No location.
  List<Permission> get _perms => <Permission>[
        Permission.notification,
        Permission.microphone,
        Permission.camera,
        _photosPerm,
      ];

  final Map<Permission, PermissionStatus> _status = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    _photosPerm = await MediaPermission.photos();
    if (!mounted) return;
    await _refreshStatuses();
    // Skip the whole screen if everything is already granted (re-login / return).
    if (_allGranted) {
      _finish(silent: true);
      return;
    }
    if (mounted) setState(() => _ready = true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshStatuses();
  }

  Future<void> _refreshStatuses() async {
    for (final p in _perms) {
      _status[p] = await p.status;
    }
    if (mounted) setState(() {});
  }

  bool _isGranted(Permission p) {
    final s = _status[p];
    return s == PermissionStatus.granted || s == PermissionStatus.limited;
  }

  bool get _allGranted => _perms.every(_isGranted);
  bool get _anyBlocked => _perms.any((p) => _status[p] == PermissionStatus.permanentlyDenied || _status[p] == PermissionStatus.restricted);

  /// Request all not-yet-granted permissions (the OS prompts each in turn).
  Future<void> _requestAll() async {
    if (_anyBlocked) { await openAppSettings(); return; }
    setState(() => _requesting = true);
    try {
      final pending = _perms.where((p) => !_isGranted(p)).toList();
      final results = await pending.request();
      results.forEach((p, s) => _status[p] = s);
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
    if (_allGranted) _finish();
  }

  Future<void> _handleItem(Permission p) async {
    if (_isGranted(p)) return;
    final s = _status[p];
    if (s == PermissionStatus.permanentlyDenied || s == PermissionStatus.restricted) {
      await openAppSettings();
      return;
    }
    final res = await p.request();
    _status[p] = res;
    if (mounted) setState(() {});
    if (_allGranted) _finish();
  }

  /// Persist grants to the DB, register FCM (notification just granted), proceed.
  Future<void> _finish({bool silent = false}) async {
    if (_finishing) return;
    _finishing = true;
    final api = context.read<AstrologerApi>();

    // Save the grant map (best-effort — never blocks navigation).
    api.savePermissions({
      'notifications': _isGranted(Permission.notification),
      'microphone': _isGranted(Permission.microphone),
      'camera': _isGranted(Permission.camera),
      'photos': _isGranted(_photosPerm),
    }).catchError((_) {});

    // Notification permission is now granted → register the FCM token.
    try { PushService.instance.registerWithBackend(); } catch (_) {}

    _proceed();
  }

  void _proceed() {
    if (!mounted) return;
    // First login → onboarding (language → complete-profile). Returning login →
    // straight to the dashboard (those one-time screens are skipped).
    Navigator.of(context).pushAndRemoveUntil(
      slideRoute(widget.firstTime ? const LanguageSelectScreen() : const DashboardShell()),
      (r) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;

    // While resolving / when auto-skipping, show a tiny loader (no flash of UI).
    if (!_ready) {
      return Scaffold(backgroundColor: c.ground, body: Center(child: CircularProgressIndicator(color: c.red)));
    }

    final items = <(Permission, IconData, String, String)>[
      (Permission.notification, Icons.notifications_active_outlined, Strings.of(context).notifications, Strings.of(context).getNotifiedOfIncomingConsultationsAnd),
      (Permission.microphone, Icons.mic_none_rounded, Strings.of(context).microphone, Strings.of(context).requiredForVoiceCallsWithSeekers),
      (Permission.camera, Icons.videocam_outlined, Strings.of(context).camera, Strings.of(context).requiredForVideoConsultations),
      (_photosPerm, Icons.photo_library_outlined, Strings.of(context).photos, Strings.of(context).toSetYourProfileAndCover),
    ];

    final blocked = _anyBlocked;
    final allGranted = _allGranted;
    final btnLabel = allGranted ? Strings.of(context).continueLabel : (blocked ? Strings.of(context).openSettings : Strings.of(context).allowAccess);

    return PopScope(
      canPop: false, // mandatory — can't back out
      child: Scaffold(
        backgroundColor: c.ground,
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24, 16 + MediaQuery.of(context).padding.bottom),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Container(
                  height: 56, width: 56,
                  decoration: BoxDecoration(color: c.redSoft, borderRadius: BorderRadius.circular(16)),
                  child: Icon(Icons.shield_outlined, color: c.red, size: 30),
                ),
                const SizedBox(height: 20),
                Text(Strings.of(context).permissions, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: c.ink)),
                const SizedBox(height: 8),
                Text(
                  blocked
                      ? Strings.of(context).somePermissionsAreBlockedTapA
                      : Strings.of(context).thesePermissionsAreRequiredToTake,
                  style: TextStyle(fontSize: 14, color: c.muted, height: 1.45),
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) {
                      final (perm, icon, title, desc) = items[i];
                      return _PermCard(
                        c: c, icon: icon, title: title, desc: desc,
                        status: _status[perm] ?? PermissionStatus.denied,
                        granted: _isGranted(perm),
                        onTap: () => _handleItem(perm),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _requesting ? null : (allGranted ? _finish : _requestAll),
                    child: _requesting
                        ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                        : Text(btnLabel),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One permission row with status-aware styling + a trailing action chip.
class _PermCard extends StatelessWidget {
  final RgColors c;
  final IconData icon;
  final String title;
  final String desc;
  final PermissionStatus status;
  final bool granted;
  final VoidCallback onTap;
  const _PermCard({required this.c, required this.icon, required this.title, required this.desc, required this.status, required this.granted, required this.onTap});

  bool get _blocked => status == PermissionStatus.permanentlyDenied || status == PermissionStatus.restricted;

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF2E9E6B);
    final accent = granted ? green : (_blocked ? c.red : c.gold);
    final Widget trailing = granted
        ? const Icon(Icons.check_circle, color: green, size: 22)
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
            child: Text(_blocked ? Strings.of(context).settings : Strings.of(context).allow, style: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 12)),
          );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: granted ? null : onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.ground2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: granted ? green : (_blocked ? c.red.withValues(alpha: 0.5) : c.line)),
          ),
          child: Row(
            children: [
              Container(
                height: 42, width: 42,
                decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(11), border: Border.all(color: c.line)),
                child: Icon(icon, color: c.gold, size: 21),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(color: c.ink, fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(
                      _blocked ? Strings.of(context).blockedEnableItInSettings : desc,
                      style: TextStyle(color: _blocked ? c.red : c.muted, fontSize: 12.5, height: 1.3),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}
