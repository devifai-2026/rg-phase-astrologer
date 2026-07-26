import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../i18n/strings.dart';
import '../../theme/rg_colors.dart';
import 'module_onboarding.dart';

// ─────────────────────── small reusable mock pieces ─────────────────────────

Widget _statusBar(RgColors c, String title, Color tint) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: tint.withValues(alpha: 0.12),
      child: Row(children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: tint, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(title, style: TextStyle(color: c.ink, fontWeight: FontWeight.w700, fontSize: 12)),
      ]),
    );

Widget _bubble(RgColors c, String text, {required bool mine, Color? tint}) => Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 7),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        constraints: const BoxConstraints(maxWidth: 150),
        decoration: BoxDecoration(
          color: mine ? (tint ?? c.blue) : c.ground2,
          borderRadius: BorderRadius.circular(11),
          border: mine ? null : Border.all(color: c.line),
        ),
        child: Text(text, style: TextStyle(color: mine ? Colors.white : c.ink, fontSize: 11, height: 1.25)),
      ),
    );

Widget _avatarRow(RgColors c, String name, String sub, Color tint, IconData icon) => Row(children: [
      Container(height: 34, width: 34, decoration: BoxDecoration(color: tint.withValues(alpha: 0.2), shape: BoxShape.circle), child: Icon(icon, color: tint, size: 18)),
      const SizedBox(width: 8),
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(name, style: TextStyle(color: c.ink, fontWeight: FontWeight.w700, fontSize: 11.5)),
        Text(sub, style: TextStyle(color: c.muted, fontSize: 9.5)),
      ]),
    ]);

Widget _roundBtn(Color color, IconData icon) => Container(
      height: 40, width: 40,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(icon, color: Colors.white, size: 20),
    );

Widget _bar(RgColors c, double widthFactor, Color color, {double h = 9}) => Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: widthFactor,
        child: Container(height: h, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(5))),
      ),
    );

Widget _pad(Widget child) => Padding(padding: const EdgeInsets.all(12), child: child);

// ─────────────────────────── the module library ─────────────────────────────

final List<OnboardModule> onboardModules = [
  // 1) CHAT
  OnboardModule(key: 'chat', name: 'CHAT CONSULTATIONS', nameL10n: (ctx) => Strings.of(ctx).onbModChat, cards: [
    OnboardCard(
      titleL10n: (ctx) => Strings.of(ctx).onbChatTitle,
      bodyL10n: (ctx) => Strings.of(ctx).onbChatBody,
      icon: Icons.chat_bubble,
      tint: (c) => c.blue,
      mock: (ctx, c) => Column(children: [
        _statusBar(c, Strings.of(ctx).chatMeera0412, c.blue),
        // Scrollable: the phone frame is a fixed 290px, and translated bubble
        // text wraps to more lines than English (overflowed by ~2px in some
        // locales). Clipping/scrolling beats a hard overflow in a decorative mock.
        Expanded(child: _pad(SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Column(children: [
            _bubble(c, Strings.of(ctx).namasteQuestionOnMyCareer, mine: false),
            _bubble(c, Strings.of(ctx).shareYourDateTimeOfBirth, mine: true),
            _bubble(c, Strings.of(ctx).s14Aug1996930Am, mine: false),
          ]),
        ))),
        Container(padding: const EdgeInsets.all(8), color: c.ground2, child: Row(children: [
          Expanded(child: Container(height: 26, decoration: BoxDecoration(color: c.ground, borderRadius: BorderRadius.circular(13), border: Border.all(color: c.line)))),
          const SizedBox(width: 6),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5), decoration: BoxDecoration(color: c.green.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(10)), child: Text('₹104', style: TextStyle(color: c.green, fontSize: 10, fontWeight: FontWeight.w800))),
        ])),
      ]),
    ),
  ]),

  // 2) CALL
  OnboardModule(key: 'call', name: 'VOICE CALLS', nameL10n: (ctx) => Strings.of(ctx).onbModCall, cards: [
    OnboardCard(
      titleL10n: (ctx) => Strings.of(ctx).onbCallTitle,
      bodyL10n: (ctx) => Strings.of(ctx).onbCallBody,
      icon: Icons.call,
      tint: (c) => c.green,
      mock: (ctx, c) => Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const SizedBox(height: 14),
        Container(height: 70, width: 70, decoration: BoxDecoration(color: c.green.withValues(alpha: 0.15), shape: BoxShape.circle), child: Icon(Icons.person, color: c.green, size: 40)),
        const SizedBox(height: 10),
        Text(Strings.of(ctx).meeraJoshi, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 13)),
        Text(Strings.of(ctx).incomingCallRings38s, style: TextStyle(color: c.green, fontSize: 10, fontWeight: FontWeight.w600)),
        const Spacer(),
        Padding(padding: const EdgeInsets.only(bottom: 16), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _roundBtn(c.red, Icons.call_end),
          _roundBtn(c.green, Icons.call),
        ])),
      ]),
    ),
  ]),

  // 3) VIDEO
  OnboardModule(key: 'video', name: 'VIDEO CONSULTATIONS', nameL10n: (ctx) => Strings.of(ctx).onbModVideo, cards: [
    OnboardCard(
      titleL10n: (ctx) => Strings.of(ctx).onbVideoTitle,
      bodyL10n: (ctx) => Strings.of(ctx).onbVideoBody,
      icon: Icons.videocam,
      tint: (c) => c.violet,
      mock: (ctx, c) => Column(children: [
        Expanded(child: Container(
          decoration: BoxDecoration(gradient: LinearGradient(colors: [c.violet.withValues(alpha: 0.4), c.ground])),
          child: Stack(children: [
            // Bundled illustrations, not network images: this walkthrough plays on
            // first login, exactly when connectivity is least reliable.
            Positioned.fill(child: SvgPicture.asset('assets/images/avatar_seeker.svg', fit: BoxFit.cover)),
            // Self-view picture-in-picture.
            Positioned(right: 8, top: 8, child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Container(
                height: 44, width: 32,
                decoration: BoxDecoration(color: c.ground2, border: Border.all(color: c.line)),
                child: SvgPicture.asset('assets/images/avatar_astrologer.svg', fit: BoxFit.cover),
              ),
            )),
            Positioned(left: 8, top: 8, child: Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(10)), child: const Text('12:40', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)))),
          ]),
        )),
        Container(padding: const EdgeInsets.all(10), color: c.ground2, child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          Icon(Icons.mic, color: c.ink, size: 18), Icon(Icons.videocam, color: c.ink, size: 18), Icon(Icons.call_end, color: c.red, size: 22),
        ])),
      ]),
    ),
  ]),

  // 4) AI PROFILE OPTIMIZER
  OnboardModule(key: 'optimizer', name: 'AI PROFILE OPTIMIZER', nameL10n: (ctx) => Strings.of(ctx).onbModOptimizer, cards: [
    OnboardCard(
      titleL10n: (ctx) => Strings.of(ctx).onbOptTitle,
      bodyL10n: (ctx) => Strings.of(ctx).onbOptBody,
      icon: Icons.auto_fix_high,
      tint: (c) => c.violet,
      mock: (ctx, c) => _pad(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          SizedBox(height: 56, width: 56, child: Stack(alignment: Alignment.center, children: [
            SizedBox(height: 56, width: 56, child: CircularProgressIndicator(value: 0.78, strokeWidth: 6, backgroundColor: c.line, valueColor: AlwaysStoppedAnimation(c.gold))),
            Text('78', style: TextStyle(color: c.ink, fontWeight: FontWeight.w900, fontSize: 16)),
          ])),
          const SizedBox(width: 10),
          Expanded(child: Text(Strings.of(ctx).goodBaseFixTheHighImpact, style: TextStyle(color: c.muted, fontSize: 10.5, height: 1.3))),
        ]),
        const SizedBox(height: 12),
        ...[Strings.of(ctx).addAProfilePhoto, Strings.of(ctx).expandYourBio, Strings.of(ctx).setAVideoPrice].map((t) => Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Row(children: [
            Icon(Icons.lightbulb, size: 13, color: c.gold), const SizedBox(width: 6),
            Expanded(child: Text(t, style: TextStyle(color: c.ink, fontSize: 10.5))),
            Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: c.violet.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)), child: Text(Strings.of(ctx).apply, style: TextStyle(color: c.violet, fontSize: 8.5, fontWeight: FontWeight.w700))),
          ]),
        )),
      ])),
    ),
    OnboardCard(
      titleL10n: (ctx) => Strings.of(ctx).onbOptApplyTitle,
      bodyL10n: (ctx) => Strings.of(ctx).onbOptApplyBody,
      icon: Icons.trending_up,
      tint: (c) => c.green,
      mock: (ctx, c) => _pad(Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(Strings.of(ctx).score, style: TextStyle(color: c.muted, fontSize: 11)),
        const SizedBox(height: 8),
        _bar(c, 0.78, c.gold, h: 12), const SizedBox(height: 6),
        Row(children: [Icon(Icons.arrow_downward, size: 12, color: c.muted), Text(' 78', style: TextStyle(color: c.muted, fontSize: 10))]),
        const SizedBox(height: 14),
        _bar(c, 0.94, c.green, h: 12), const SizedBox(height: 6),
        Row(children: [Icon(Icons.arrow_upward, size: 12, color: c.green), Text(Strings.of(ctx).s94AfterApplying3Fixes, style: TextStyle(color: c.green, fontSize: 10, fontWeight: FontWeight.w700))]),
      ])),
    ),
  ]),

  // 5) GO LIVE + how AI works
  OnboardModule(key: 'live', name: 'GO LIVE', nameL10n: (ctx) => Strings.of(ctx).onbModLive, cards: [
    OnboardCard(
      titleL10n: (ctx) => Strings.of(ctx).hostALiveSession,
      bodyL10n: (ctx) => Strings.of(ctx).broadcastALiveQAViewers,
      icon: Icons.sensors,
      tint: (c) => c.indigo,
      mock: (ctx, c) => Column(children: [
        Expanded(flex: 2, child: Container(
          decoration: BoxDecoration(gradient: LinearGradient(colors: [c.redDeep, const Color(0xFF1A0E0C)])),
          child: Stack(children: [
            Positioned(left: 8, top: 8, child: Row(children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: c.red, borderRadius: BorderRadius.circular(4)), child: Text(Strings.of(ctx).live, style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900))),
              const SizedBox(width: 5),
              Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(10)), child: const Text('👁 312', style: TextStyle(color: Colors.white, fontSize: 8))),
            ])),
            const Center(child: Icon(Icons.person, color: Colors.white24, size: 44)),
          ]),
        )),
        Expanded(flex: 2, child: _pad(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _bubble(c, Strings.of(ctx).whenToStartABusiness, mine: false),
          Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(7), decoration: BoxDecoration(gradient: LinearGradient(colors: [c.gold, c.gold.withValues(alpha: 0.6)]), borderRadius: BorderRadius.circular(9)), child: Text(Strings.of(ctx).pooja501, style: const TextStyle(color: Color(0xFF1A1408), fontSize: 10, fontWeight: FontWeight.w800))),
        ]))),
      ]),
    ),
    OnboardCard(
      titleL10n: (ctx) => Strings.of(ctx).aiModeratesEverything,
      bodyL10n: (ctx) => Strings.of(ctx).theAiRemovesAbuseSpamPhone,
      icon: Icons.smart_toy,
      tint: (c) => c.mint,
      mock: (ctx, c) => _pad(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(Strings.of(ctx).aiModerator, style: TextStyle(color: c.mint, fontWeight: FontWeight.w800, fontSize: 11)),
        const SizedBox(height: 8),
        ...[
          (Icons.link_off, Strings.of(ctx).removedExternalLink, c.red),
          (Icons.phone_disabled, Strings.of(ctx).redactedAPhoneNumber, c.red),
          (Icons.merge_type, Strings.of(ctx).clubbed3SimilarQuestions, c.blue),
          (Icons.poll_outlined, Strings.of(ctx).autoLaunchedAPoll, c.violet),
        ].map((a) => Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(9), border: Border.all(color: c.line)),
          child: Row(children: [Icon(a.$1, size: 13, color: a.$3), const SizedBox(width: 7), Expanded(child: Text(a.$2, style: TextStyle(color: c.ink, fontSize: 10)))]),
        )),
      ])),
    ),
    OnboardCard(
      titleL10n: (ctx) => Strings.of(ctx).aiRecapWhenYouEnd,
      bodyL10n: (ctx) => Strings.of(ctx).afterTheSessionAiSummarisesHighlights,
      icon: Icons.auto_awesome,
      tint: (c) => c.violet,
      mock: (ctx, c) => _pad(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: _statTile(c, '312', 'viewers', c.blue)),
          const SizedBox(width: 6),
          Expanded(child: _statTile(c, '₹1.2k', 'superchats', c.gold)),
        ]),
        const SizedBox(height: 8),
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: c.violet.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(9), border: Border.all(color: c.violet.withValues(alpha: 0.4))), child: Row(children: [
          Icon(Icons.tips_and_updates, size: 13, color: c.violet), const SizedBox(width: 6),
          Expanded(child: Text(Strings.of(ctx).runACareerMoneyLiveTomorrow, style: TextStyle(color: c.ink, fontSize: 9.5, height: 1.3))),
        ])),
      ])),
    ),
  ]),

  // 6) STOREFRONT
  OnboardModule(key: 'storefront', name: 'YOUR STOREFRONT', nameL10n: (ctx) => Strings.of(ctx).onbModStorefront, cards: [
    OnboardCard(
      titleL10n: (ctx) => Strings.of(ctx).onbStoreTitle,
      bodyL10n: (ctx) => Strings.of(ctx).onbStoreBody,
      icon: Icons.storefront,
      tint: (c) => c.gold,
      mock: (ctx, c) => _pad(Column(children: [
        Container(height: 36, width: 36, decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [c.gold, c.red])), child: const Icon(Icons.person, color: Colors.white, size: 20)),
        const SizedBox(height: 4),
        Text(Strings.of(ctx).vikramsharma, style: TextStyle(color: c.gold, fontSize: 9, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        ...[
          (Icons.spa, Strings.of(ctx).rudraksha, '₹899'),
          (Icons.menu_book_outlined, Strings.of(ctx).janamKundliPdf, '₹699'),
          (Icons.local_fire_department, Strings.of(ctx).navagrahaPuja, '₹2100'),
        ].map((p) => Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(11), border: Border.all(color: c.line)),
          child: Row(children: [
            Container(height: 26, width: 26, decoration: BoxDecoration(color: c.gold.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(7)), child: Icon(p.$1, size: 14, color: c.gold)),
            const SizedBox(width: 7),
            Expanded(child: Text(p.$2, style: TextStyle(color: c.ink, fontSize: 10, fontWeight: FontWeight.w600))),
            Text(p.$3, style: TextStyle(color: c.ink, fontSize: 10, fontWeight: FontWeight.w800)),
            const SizedBox(width: 4),
            Icon(Icons.arrow_forward_ios, size: 9, color: c.muted),
          ]),
        )),
      ])),
    ),
    OnboardCard(
      titleL10n: (ctx) => Strings.of(ctx).onbStoreAdminTitle,
      bodyL10n: (ctx) => Strings.of(ctx).onbStoreAdminBody,
      icon: Icons.verified,
      tint: (c) => c.green,
      mock: (ctx, c) => _pad(Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        _avatarRow(c, Strings.of(ctx).s5MukhiRudraksha, '₹899', c.gold, Icons.spa),
        const SizedBox(height: 10),
        Container(padding: const EdgeInsets.all(9), decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.line)), child: Column(children: [
          _kv(c, Strings.of(ctx).status, Strings.of(ctx).approved, c.green),
          const SizedBox(height: 6),
          _kv(c, Strings.of(ctx).adminCommission, '15% · ₹135', c.red),
          const SizedBox(height: 6),
          _kv(c, Strings.of(ctx).youEarn, Strings.of(ctx).s764Sale, c.green),
        ])),
      ])),
    ),
  ]),
];

Widget _statTile(RgColors c, String v, String l, Color tint) => Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(9), border: Border.all(color: c.line)),
      child: Column(children: [
        Text(v, style: TextStyle(color: tint, fontWeight: FontWeight.w800, fontSize: 13)),
        Text(l, style: TextStyle(color: c.muted, fontSize: 9)),
      ]),
    );

Widget _kv(RgColors c, String k, String v, Color tint) => Row(children: [
      Expanded(child: Text(k, style: TextStyle(color: c.muted, fontSize: 10))),
      Text(v, style: TextStyle(color: tint, fontWeight: FontWeight.w800, fontSize: 10.5)),
    ]);

/// The ordered first-login walkthrough.
List<OnboardModule> get firstLoginSequence => onboardModules;
