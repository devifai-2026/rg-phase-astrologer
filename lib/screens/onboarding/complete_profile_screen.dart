import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../api/astrologer_api.dart';
import '../../api/api_client.dart';
import '../../api/socket_service.dart';
import '../../i18n/strings.dart';
import '../../models/astrologer.dart';
import '../../providers/session_provider.dart';
import '../../theme/rg_colors.dart';
import '../../widgets/slide_route.dart';
import 'first_login_walkthrough.dart';

/// Astrologer "complete your profile" screen.
///
/// Differences from the user app's onboarding (per spec):
///  • NO date / place / time of birth — astrologers don't need a birth chart.
///  • The form opens PRE-FILLED with whatever the admin set up, and those
///    fields are editable.
///  • Reviews, gifts and followers are shown but are READ-ONLY.
///  • Only the profile photo, cover photo and bio (+ display name, expertise,
///    languages, experience) can be edited.
class CompleteProfileScreen extends StatefulWidget {
  /// When the caller (language screen) has already fetched the profile +
  /// expertise catalog AND precached the photos, it passes the catalog here so
  /// this screen renders immediately — no spinner, no second fetch, and the
  /// network photos are already in the image cache → smooth first paint.
  final List<String>? prefetchedExpertiseCatalog;
  const CompleteProfileScreen({super.key, this.prefetchedExpertiseCatalog});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  // Display name is admin-set and read-only here.
  final _bio = TextEditingController();
  final _experience = TextEditingController();

  File? _avatarFile;
  File? _coverFile;
  List<String> _expertise = []; // the astrologer's selected expertise
  List<String> _languages = [];

  // Chip options: the shared catalog from the backend, merged with whatever the
  // astrologer already has (so an admin-saved/custom value always renders AND
  // shows selected). Built in _load().
  List<String> _expertiseOptions = [];

  bool _loading = true; // fetching the admin-created profile from the DB
  bool _saving = false;

  static const _languageOptions = ['Hindi', 'English', 'Bengali', 'Marathi', 'Punjabi', 'Assamese', 'Tamil', 'Telugu'];

  /// Toggle a value in a selection list, case-insensitively (so the same value
  /// with different casing isn't added twice / fails to remove).
  void _toggle(List<String> list, String value) {
    final i = list.indexWhere((s) => s.toLowerCase() == value.toLowerCase());
    i >= 0 ? list.removeAt(i) : list.add(value);
  }

  /// Case-insensitive union preserving order: catalog first, then any selected
  /// values not already present (e.g. an admin-created expertise).
  List<String> _mergeOptions(List<String> catalog, List<String> selected) {
    final out = <String>[];
    final seen = <String>{};
    for (final v in [...catalog, ...selected]) {
      final key = v.trim().toLowerCase();
      if (key.isEmpty || seen.contains(key)) continue;
      seen.add(key);
      out.add(v.trim());
    }
    return out;
  }

  @override
  void initState() {
    super.initState();
    if (widget.prefetchedExpertiseCatalog != null) {
      // Caller already fetched the profile (into the session) + catalog and
      // precached the photos → populate synchronously, render immediately.
      _populateFromSession(widget.prefetchedExpertiseCatalog!);
      _loading = false;
    } else {
      _load(); // fallback for any other entry path (e.g. cold-start deep link)
    }
  }

  /// Fill the form from the session profile, merging the (already-fetched)
  /// catalog with the astrologer's saved expertise.
  void _populateFromSession(List<String> catalog) {
    final p = context.read<SessionProvider>().profile;
    _bio.text = p.bio;
    _experience.text = '${p.experienceYears}';
    _expertise = List.of(p.expertise);
    _languages = List.of(p.languages);
    _expertiseOptions = _mergeOptions(catalog, _expertise);
  }

  /// Fetch the admin-created profile from the backend and populate the form.
  /// Falls back to whatever is in the session (demo) if the fetch fails.
  Future<void> _load() async {
    // Ensure the realtime socket is up (idempotent — already connected after
    // OTP verify; this covers any path that reaches this screen with a session).
    context.read<SocketService>().connect();
    final api = context.read<AstrologerApi>();
    // Fetch the profile + the shared expertise catalog together.
    List<String> catalog = const [];
    try {
      final results = await Future.wait([
        api.myProfile(),
        api.listExpertise(),
      ]);
      if (!mounted) return;
      context.read<SessionProvider>().applyServerProfile(results[0] as Map<String, dynamic>);
      catalog = results[1] as List<String>;
    } catch (_) {/* keep existing/demo profile + empty catalog on failure */}
    if (!mounted) return;
    _populateFromSession(catalog);
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    _bio.dispose();
    _experience.dispose();
    super.dispose();
  }

  Future<void> _pickImage({required bool cover}) async {
    // Capture theme color before any await (don't touch context across async gaps).
    final accent = context.rg.red;
    final s = Strings.of(context);
    final cropTitle = cover ? s.cropCoverPhoto : s.cropProfilePhoto;

    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: cover ? 1600 : 1024,
      imageQuality: 90,
    );
    if (x == null) return;

    // Crop so the image fits its slot: cover = wide 16:9 header, avatar = square.
    final cropped = await ImageCropper().cropImage(
      sourcePath: x.path,
      aspectRatio: cover
          ? const CropAspectRatio(ratioX: 16, ratioY: 9)
          : const CropAspectRatio(ratioX: 1, ratioY: 1),
      compressQuality: 90,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: cropTitle,
          toolbarColor: accent,
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: accent,
          lockAspectRatio: true,
          hideBottomControls: false,
          initAspectRatio: CropAspectRatioPreset.original,
        ),
        IOSUiSettings(
          title: cropTitle,
          aspectRatioLockEnabled: true,
        ),
      ],
    );
    if (cropped == null) return; // user cancelled the crop

    if (!mounted) return;
    setState(() {
      if (cover) {
        _coverFile = File(cropped.path);
      } else {
        _avatarFile = File(cropped.path);
      }
    });
  }

  Future<void> _finish() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    final session = context.read<SessionProvider>();
    final api = context.read<AstrologerApi>();
    final t = Strings.of(context);
    setState(() => _saving = true);

    try {
      // Upload any newly-picked images first; reuse the existing URL otherwise.
      String? avatarUrl = session.profile.avatar;
      String? coverUrl = session.profile.coverPhoto;
      if (_avatarFile != null) avatarUrl = await api.uploadImage(_avatarFile!);
      if (_coverFile != null) coverUrl = await api.uploadImage(_coverFile!);

      final body = <String, dynamic>{
        'bio': _bio.text.trim(),
        'expertise': _expertise,
        'languages': _languages,
        'experienceYears': int.tryParse(_experience.text.trim()) ?? session.profile.experienceYears,
        if (avatarUrl != null && avatarUrl.startsWith('http')) 'avatar': avatarUrl,
        if (coverUrl != null && coverUrl.startsWith('http')) 'coverPhoto': coverUrl,
        // Mark onboarding done → next login skips language + complete-profile.
        'profileCompleted': true,
      };
      final updated = await api.updateMyProfile(body);
      if (!mounted) return;
      // Reflect the saved server state locally (so the dashboard is in sync).
      session.applyServerProfile(updated);
      session.markProfileCompleted();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.saved)));
      // First-time astrologers see the platform walkthrough before the dashboard.
      Navigator.of(context).pushAndRemoveUntil(slideRoute(const FirstLoginWalkthrough()), (r) => false);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.errGeneric)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final t = Strings.of(context);
    final p = context.watch<SessionProvider>().profile;

    return Scaffold(
      backgroundColor: c.ground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(t.profileTitle, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 18)),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: c.red))
          : SafeArea(
        child: ListView(
          // Drag anywhere to dismiss the keyboard; bottom padding grows with it
          // so the active field/Save button stays visible.
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
          children: [
            // ── Cover + avatar (editable) ──
            _CoverAndAvatar(
              coverFile: _coverFile,
              coverUrl: p.coverPhoto,
              avatarFile: _avatarFile,
              avatarUrl: p.avatar,
              initial: p.displayName.isNotEmpty ? p.displayName[0] : 'A',
              onEditCover: () => _pickImage(cover: true),
              onEditAvatar: () => _pickImage(cover: false),
            ),
            const SizedBox(height: 14),
            Text(t.profileSubtitle, style: TextStyle(fontSize: 13.5, color: c.muted, height: 1.45)),
            const SizedBox(height: 22),

            // ── Editable fields (pre-filled by admin) ──
            _PrefilledBadge(label: t.profilePrefilledNote),
            const SizedBox(height: 10),

            // Display name is set by the admin and cannot be changed here.
            _Label(t.displayName),
            const SizedBox(height: 8),
            _ReadOnlyField(value: p.displayName),
            const SizedBox(height: 6),
            Text(t.readOnlyNote, style: TextStyle(fontSize: 12, color: c.muted)),
            const SizedBox(height: 18),

            _Label(t.bio),
            const SizedBox(height: 8),
            TextField(
              controller: _bio,
              maxLines: 4,
              maxLength: 600,
              decoration: InputDecoration(hintText: t.bioHint),
            ),
            const SizedBox(height: 10),

            _Label(t.expertise),
            const SizedBox(height: 8),
            // Expertise options come from the admin-managed catalog. The
            // astrologer can only select from them (creation is admin-only).
            _ChipPicker(
              options: _expertiseOptions,
              selected: _expertise,
              onToggle: (v) => setState(() => _toggle(_expertise, v)),
            ),
            const SizedBox(height: 18),

            _Label(t.languagesSpoken),
            const SizedBox(height: 8),
            _ChipPicker(
              options: _languageOptions,
              selected: _languages,
              onToggle: (v) => setState(() => _toggle(_languages, v)),
            ),
            const SizedBox(height: 18),

            _Label(t.experienceYears),
            const SizedBox(height: 8),
            SizedBox(
              width: 140,
              child: TextField(
                controller: _experience,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(suffixText: 'yrs'),
              ),
            ),
            const SizedBox(height: 26),

            // ── Read-only: rates set by admin ──
            _SectionHeader(t.ratesTitle, locked: true),
            const SizedBox(height: 10),
            _RatesCard(profile: p),
            const SizedBox(height: 24),

            // ── Read-only: reviews / gifts / followers ──
            _SectionHeader('${t.followers} · ${t.gifts} · ${t.reviews}', locked: true),
            const SizedBox(height: 6),
            Text(t.readOnlyNote, style: TextStyle(fontSize: 12, color: c.muted)),
            const SizedBox(height: 12),
            _StatTriplet(profile: p),
            const SizedBox(height: 16),
            _GiftStrip(gifts: p.gifts),
            const SizedBox(height: 16),
            _ReviewsPreview(reviews: p.reviews),
            const SizedBox(height: 30),

            ElevatedButton(
              onPressed: _saving ? null : _finish,
              child: _saving
                  ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : Text(t.finishSetup),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────── widgets ───────────────────────────────

class _CoverAndAvatar extends StatelessWidget {
  final File? coverFile;
  final String? coverUrl;
  final File? avatarFile;
  final String? avatarUrl;
  final String initial;
  final VoidCallback onEditCover;
  final VoidCallback onEditAvatar;
  const _CoverAndAvatar({
    required this.coverFile,
    required this.coverUrl,
    required this.avatarFile,
    required this.avatarUrl,
    required this.initial,
    required this.onEditCover,
    required this.onEditAvatar,
  });

  ImageProvider? _img(File? f, String? url) {
    if (f != null) return FileImage(f);
    if (url != null && url.startsWith('http')) return NetworkImage(url);
    if (url != null) return FileImage(File(url));
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final cover = _img(coverFile, coverUrl);
    final avatar = _img(avatarFile, avatarUrl);
    return SizedBox(
      height: 168,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Cover.
          GestureDetector(
            onTap: onEditCover,
            child: Container(
              height: 120,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: cover == null
                    ? LinearGradient(colors: [c.redDeep, c.red, c.gold], begin: Alignment.topLeft, end: Alignment.bottomRight)
                    : null,
                image: cover != null ? DecorationImage(image: cover, fit: BoxFit.cover) : null,
              ),
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: _editPill(c, Icons.camera_alt, Strings.of(context).cover),
                ),
              ),
            ),
          ),
          // Avatar overlapping the cover.
          Positioned(
            left: 20,
            bottom: 0,
            child: GestureDetector(
              onTap: onEditAvatar,
              child: Stack(
                children: [
                  Container(
                    height: 92,
                    width: 92,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.ground2,
                      border: Border.all(color: c.ground, width: 4),
                      image: avatar != null ? DecorationImage(image: avatar, fit: BoxFit.cover) : null,
                    ),
                    child: avatar == null
                        ? Center(child: Text(initial, style: TextStyle(fontSize: 36, color: c.muted, fontWeight: FontWeight.w800)))
                        : null,
                  ),
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: Container(
                      height: 28,
                      width: 28,
                      decoration: BoxDecoration(color: c.red, shape: BoxShape.circle, border: Border.all(color: c.ground, width: 2)),
                      child: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _editPill(RgColors c, IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );
}

class _PrefilledBadge extends StatelessWidget {
  final String label;
  const _PrefilledBadge({required this.label});
  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: c.redSoft, borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.auto_fix_high, size: 14, color: c.red),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: c.red, fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) =>
      Text(text, style: TextStyle(color: context.rg.muted, fontWeight: FontWeight.w600, fontSize: 13));
}

/// A locked, non-editable field (e.g. the admin-set display name).
class _ReadOnlyField extends StatelessWidget {
  final String value;
  const _ReadOnlyField({required this.value});
  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        // Slightly dimmer than the editable fields to read as "locked".
        color: c.ground2.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.line),
      ),
      child: Row(children: [
        Expanded(child: Text(value, style: TextStyle(color: c.ink, fontSize: 15, fontWeight: FontWeight.w600))),
        const SizedBox(width: 10),
        Icon(Icons.lock_outline, size: 16, color: c.muted),
      ]),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  final bool locked;
  const _SectionHeader(this.text, {this.locked = false});
  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    return Row(children: [
      Text(text, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 16)),
      if (locked) ...[
        const SizedBox(width: 8),
        Icon(Icons.lock_outline, size: 15, color: c.muted),
      ],
    ]);
  }
}

class _ChipPicker extends StatelessWidget {
  final List<String> options;
  final List<String> selected;
  final ValueChanged<String> onToggle;
  const _ChipPicker({required this.options, required this.selected, required this.onToggle});
  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((o) {
        // Case-insensitive match so an admin-saved value with different casing
        // (e.g. "vedic" vs catalog "Vedic") still renders as selected.
        final on = selected.any((s) => s.toLowerCase() == o.toLowerCase());
        return InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => onToggle(o),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: on ? c.redSoft : c.ground2,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: on ? c.red : c.line, width: on ? 1.3 : 1),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (on) ...[Icon(Icons.check, size: 14, color: c.red), const SizedBox(width: 5)],
              Text(o, style: TextStyle(color: on ? c.red : c.ink, fontWeight: on ? FontWeight.w700 : FontWeight.w500, fontSize: 13.5)),
            ]),
          ),
        );
      }).toList(),
    );
  }
}

class _RatesCard extends StatelessWidget {
  final Astrologer profile;
  const _RatesCard({required this.profile});
  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    Widget row(IconData icon, String label, ServiceRate r, Color tint) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(children: [
          Icon(icon, size: 18, color: tint),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: TextStyle(color: c.ink, fontSize: 14, fontWeight: FontWeight.w600))),
          Text(r.enabled ? Strings.of(context).rRateperminMin(r.ratePerMin) : Strings.of(context).disabled,
              style: TextStyle(color: r.enabled ? c.ink : c.muted, fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          Text(r.enabled ? Strings.of(context).youEarnREarnpermin(r.earnPerMin) : '',
              style: TextStyle(color: c.green, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
      child: Column(children: [
        row(Icons.call_outlined, Strings.of(context).call, profile.callRate, c.green),
        Divider(height: 1, color: c.line),
        row(Icons.chat_bubble_outline, Strings.of(context).chat, profile.chatRate, c.blue),
        Divider(height: 1, color: c.line),
        row(Icons.videocam_outlined, Strings.of(context).video, profile.videoRate, c.violet),
      ]),
    );
  }
}

class _StatTriplet extends StatelessWidget {
  final Astrologer profile;
  const _StatTriplet({required this.profile});
  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final t = Strings.of(context);
    Widget cell(IconData icon, String value, String label, Color tint) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
            child: Column(children: [
              Icon(icon, color: tint, size: 22),
              const SizedBox(height: 8),
              Text(value, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 18)),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(color: c.muted, fontSize: 12)),
            ]),
          ),
        );
    return Row(children: [
      cell(Icons.favorite, _fmt(profile.followers), t.followers, c.red),
      cell(Icons.card_giftcard, '${profile.giftCount}', t.gifts, c.gold),
      cell(Icons.star, '${profile.rating} (${profile.reviewCount})', t.reviews, c.green),
    ]);
  }

  String _fmt(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';
}

class _GiftStrip extends StatelessWidget {
  final List<GiftItem> gifts;
  const _GiftStrip({required this.gifts});
  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: gifts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final g = gifts[i];
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
            child: Row(children: [
              Container(
                height: 36, width: 36,
                decoration: BoxDecoration(color: g.color.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: Icon(g.icon, color: g.color, size: 20),
              ),
              const SizedBox(width: 8),
              Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${g.count}', style: TextStyle(color: c.ink, fontWeight: FontWeight.w800)),
                Text(g.name, style: TextStyle(color: c.muted, fontSize: 11)),
              ]),
            ]),
          );
        },
      ),
    );
  }
}

class _ReviewsPreview extends StatelessWidget {
  final List<ReviewItem> reviews;
  const _ReviewsPreview({required this.reviews});
  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    return Column(
      children: reviews.take(2).map((r) {
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(radius: 14, backgroundColor: c.redSoft, child: Text(r.userName[0], style: TextStyle(color: c.red, fontWeight: FontWeight.w700, fontSize: 13))),
              const SizedBox(width: 10),
              Text(r.userName, style: TextStyle(color: c.ink, fontWeight: FontWeight.w700, fontSize: 13.5)),
              const Spacer(),
              Row(children: List.generate(5, (i) => Icon(i < r.rating ? Icons.star : Icons.star_border, size: 14, color: c.gold))),
            ]),
            const SizedBox(height: 8),
            Text(r.comment, style: TextStyle(color: c.muted, fontSize: 13, height: 1.35)),
            const SizedBox(height: 4),
            Text(r.timeAgo, style: TextStyle(color: c.muted, fontSize: 11)),
          ]),
        );
      }).toList(),
    );
  }
}
