import 'package:flutter/material.dart';

import '../models/ai_models.dart';
import '../models/astrologer.dart';
import '../providers/session_provider.dart';

/// A stand-in for a real Claude-backed service. Returns realistic, canned
/// output so the AI features are fully demoable offline. Swap this for a
/// service that calls the Claude API when a backend is wired.
class MockAi {
  /// Rudra Mall catalogue used to back remedy suggestions.
  static const mall = <MallProduct>[
    MallProduct('p_rudraksha5', '5-Mukhi Rudraksha', Icons.spa, Color(0xFFC98A5E), 899),
    MallProduct('p_yellowsapphire', 'Yellow Sapphire', Icons.diamond_outlined, Color(0xFFD4A24E), 5499),
    MallProduct('p_redcoral', 'Red Coral (Moonga)', Icons.brightness_1, Color(0xFFE0584A), 2199),
    MallProduct('p_shrishyantra', 'Shri Yantra (Brass)', Icons.auto_awesome, Color(0xFFC0392B), 1299),
    MallProduct('p_camphor', 'Camphor & Diya Kit', Icons.local_fire_department, Color(0xFFC98A5E), 349),
    MallProduct('p_blackthread', 'Energised Black Thread', Icons.water_drop_outlined, Color(0xFF3B5BA9), 199),
  ];

  static MallProduct _product(String id) => mall.firstWhere((p) => p.id == id);

  /// Analyse the profile and produce an optimizer report. The score + which
  /// suggestions fire depend on the actual profile state (bio length, photo,
  /// expertise/language counts, enabled rates), so "Apply" visibly moves it.
  static OptimizerReport optimizeProfile(Astrologer p) {
    final s = <OptimizerSuggestion>[];

    if (p.avatar == null) {
      s.add(OptimizerSuggestion(
        area: 'Photo', icon: Icons.face_retouching_natural,
        issue: 'No profile photo — profiles with a clear face photo get ~3× more consultations.',
        fix: 'Add a well-lit, front-facing portrait in traditional attire.',
        impact: 5,
      ));
    }
    if (p.coverPhoto == null) {
      s.add(OptimizerSuggestion(
        area: 'Photo', icon: Icons.panorama_outlined,
        issue: 'No cover photo — your header looks generic.',
        fix: 'Add a warm cover image (your puja setup / temple) to build trust.',
        impact: 3,
      ));
    }
    if (p.bio.trim().length < 180) {
      s.add(OptimizerSuggestion(
        area: 'Bio', icon: Icons.notes_outlined,
        issue: 'Your bio is short. Seekers skim for specifics before booking.',
        fix: 'Expand to ~3 lines: systems you practice, years, and the 2–3 problems you solve best.',
        impact: 4,
      ));
    }
    s.add(OptimizerSuggestion(
      area: 'Bio', icon: Icons.format_quote,
      issue: 'Bio lacks a clear specialisation hook in the first sentence.',
      fix: 'Open with "I help with career & marriage timing using KP + Parashari." Specific opens convert.',
      impact: 3,
    ));
    if (p.expertise.length < 4) {
      s.add(OptimizerSuggestion(
        area: 'Expertise', icon: Icons.workspace_premium_outlined,
        issue: 'Only ${p.expertise.length} expertise tags — you appear in fewer search filters.',
        fix: 'Add the systems you genuinely practice (e.g. Numerology, Vastu) to widen discovery.',
        impact: 4,
      ));
    }
    if (p.languages.length < 3) {
      s.add(OptimizerSuggestion(
        area: 'Languages', icon: Icons.translate,
        issue: 'Adding a regional language unlocks a large under-served audience.',
        fix: 'If you can consult in it, add Bengali or Marathi to reach more seekers.',
        impact: 3,
      ));
    }
    // Pricing heuristics.
    if (p.videoRate.enabled && p.videoRate.ratePerMin <= p.callRate.ratePerMin) {
      s.add(OptimizerSuggestion(
        area: 'Pricing', icon: Icons.payments_outlined,
        issue: 'Video is priced at/under call, but it costs you more effort.',
        fix: 'Set video ~40% above call (e.g. ₹${(p.callRate.ratePerMin * 1.4).round()}/min) — buyers expect it.',
        impact: 3,
      ));
    }
    s.add(OptimizerSuggestion(
      area: 'Pricing', icon: Icons.local_offer_outlined,
      issue: 'No first-session offer — new seekers hesitate at full price.',
      fix: 'Run a "first 3 min discounted" hook to lift first-time conversion.',
      impact: 2,
    ));
    // Availability cycle.
    s.add(OptimizerSuggestion(
      area: 'Availability', icon: Icons.schedule,
      issue: 'Your online hours are irregular — followers can\'t predict when to find you.',
      fix: 'Commit to a daily window (e.g. 7–10pm) and auto-notify followers when you go live.',
      impact: 4,
    ));

    // Score: start high, dock per high-impact open suggestion.
    int score = 92;
    for (final x in s) {
      score -= x.impact * 2;
    }
    score = score.clamp(38, 96);

    final headline = score >= 85
        ? 'Strong profile — a few tweaks will push it to the top tier.'
        : score >= 65
            ? 'Good base. Fix the high-impact items to climb the rankings.'
            : 'Several quick wins here — start with the photo and bio.';

    return OptimizerReport(score: score, headline: headline, suggestions: s);
  }

  /// Generate AI summaries + remedy suggestions for recent consultations.
  /// Only CHAT consultations are summarised — call & video are not (their
  /// transcripts aren't captured for AI analysis).
  static List<ChatSummary> summarise(List<ConsultRecord> history) {
    final chats = history.where((h) => h.completed && h.kind == ServiceKind.chat).toList();
    final out = <ChatSummary>[];
    for (var i = 0; i < chats.length && i < 5; i++) {
      out.add(_summaryFor(chats[i], i));
    }
    return out;
  }

  static ChatSummary _summaryFor(ConsultRecord r, int seed) {
    // A few canned but varied scenarios, picked deterministically by seed.
    final scenarios = <ChatSummary Function()>[
      () => ChatSummary(
            userName: r.userName, kind: r.kind, when: r.when,
            keyTopics: const ['Career change', 'Saturn transit', 'Timing'],
            sentiment: 'Anxious about a job switch',
            summary:
                'Seeker is weighing a career move. Chart shows Saturn transiting the 10th — '
                'favourable window opens after the next 6 weeks. Advised patience and to avoid '
                'signing before then. Strong Mercury supports communication roles.',
            remedies: [
              RemedySuggestion(title: 'Wear a 5-Mukhi Rudraksha', detail: 'Calms Saturn-related anxiety; wear after energising on a Saturday.', product: _product('p_rudraksha5')),
              RemedySuggestion(title: 'Donate black sesame on Saturdays', detail: 'Simple practice to ease the Saturn transit. No purchase needed.'),
            ],
          ),
      () => ChatSummary(
            userName: r.userName, kind: r.kind, when: r.when,
            keyTopics: const ['Marriage', 'Compatibility', 'Mangal Dosha'],
            sentiment: 'Hopeful about an alliance',
            summary:
                'Discussed a marriage proposal. Mild Mangal Dosha present but cancelled by Jupiter\'s '
                'aspect. Overall compatibility is favourable. Suggested proceeding after a simple '
                'remedy and a Kundli match for confirmation.',
            remedies: [
              RemedySuggestion(title: 'Red Coral for Mars', detail: 'Strengthens Mars; recommend after gemstone testing.', product: _product('p_redcoral')),
              RemedySuggestion(title: 'Mangal Shanti puja', detail: 'One-time puja before fixing the date.'),
            ],
          ),
      () => ChatSummary(
            userName: r.userName, kind: r.kind, when: r.when,
            keyTopics: const ['Finance', 'Property', 'Vastu'],
            sentiment: 'Worried about money flow',
            summary:
                'Cash-flow concerns linked to a recent property purchase. Vastu of the new home\'s '
                'north-east is blocked. Advised correcting it and a Lakshmi-focused practice. 2nd-house '
                'lord is well placed — recovery expected within the quarter.',
            remedies: [
              RemedySuggestion(title: 'Place a Shri Yantra in the north-east', detail: 'Energised brass Shri Yantra for wealth flow.', product: _product('p_shrishyantra')),
              RemedySuggestion(title: 'Friday Lakshmi diya', detail: 'Light a ghee diya facing east every Friday.', product: _product('p_camphor')),
            ],
          ),
      () => ChatSummary(
            userName: r.userName, kind: r.kind, when: r.when,
            keyTopics: const ['Health', 'Stress', 'Protection'],
            sentiment: 'Run down, seeking relief',
            summary:
                'Persistent stress and disturbed sleep. 6th house afflicted by Rahu. Reassured the '
                'seeker — transit is temporary. Recommended grounding practices and protection.',
            remedies: [
              RemedySuggestion(title: 'Energised black thread on right wrist', detail: 'Simple protection against the Rahu phase.', product: _product('p_blackthread')),
              RemedySuggestion(title: 'Daily 10-min meditation', detail: 'Grounding practice at sunrise.'),
            ],
          ),
    ];
    return scenarios[seed % scenarios.length]();
  }

  /// A scripted stream of live chat events (chat, superchats, questions, and a
  /// couple the AI moderator will flag). Drives the Go Live demo.
  static List<LiveChatMsg> liveScript() => const [
        LiveChatMsg(user: 'Ankit', text: 'Namaste guruji 🙏'),
        LiveChatMsg(user: 'Sneha', text: 'When is a good time to start a business?', isQuestion: true),
        LiveChatMsg(user: 'Ramesh', text: 'Pranam! Watching from Pune'),
        LiveChatMsg(user: 'Divya', text: 'Please look at my Saturn period 🙏', superchatAmount: 199, isQuestion: true),
        LiveChatMsg(user: 'spam_bot_92', text: 'CHEAP FOLLOWERS click bit.ly/xxx', flaggedByAi: true),
        LiveChatMsg(user: 'Karan', text: 'Is gemstone safe without consultation?', isQuestion: true),
        LiveChatMsg(user: 'Meena', text: 'Thank you guruji, very helpful ❤️'),
        LiveChatMsg(user: 'angry_user', text: 'this is all fake nonsense!!', flaggedByAi: true),
        LiveChatMsg(user: 'Pooja', text: 'Superchat: bless my daughter\'s exams 🙏', superchatAmount: 501, isQuestion: true),
        LiveChatMsg(user: 'Vivek', text: 'Which day to buy gold this month?', isQuestion: true),
      ];

  /// Moderator actions the AI takes as the script plays. Covers abuse, hate
  /// speech, spam, phone numbers, external links and self-promotion removal.
  static List<ModeratorAction> moderatorLog() => const [
        ModeratorAction(Icons.link_off, 'Removed external link from "spam_bot_92"', Color(0xFFE0584A)),
        ModeratorAction(Icons.sentiment_very_dissatisfied, 'Muted abuse / hate speech from "angry_user"', Color(0xFFE0584A)),
        ModeratorAction(Icons.phone_disabled, 'Redacted a phone number shared in chat', Color(0xFFE0584A)),
        ModeratorAction(Icons.campaign_outlined, 'Blocked self-promotion ("follow my channel")', Color(0xFFE0584A)),
        ModeratorAction(Icons.merge_type, 'Clubbed 3 similar "business timing" questions', Color(0xFF2D6FB0)),
        ModeratorAction(Icons.push_pin_outlined, 'Pinned ₹501 superchat from Pooja', Color(0xFFD4A24E)),
        ModeratorAction(Icons.translate, 'Auto-translated 1 Marathi question', Color(0xFF6D4B9E)),
      ];

  /// AI groups similar incoming questions into a few clusters the astrologer
  /// can answer once. Returns (theme, count, representativeQuestion).
  static List<(String, int, String)> groupedQuestions() => const [
        ('Business / career timing', 4, 'When is a good muhurat to start a business?'),
        ('Marriage & compatibility', 3, 'Is this alliance favourable for me?'),
        ('Gemstones — safe to wear?', 2, 'Can I wear a gemstone without consultation?'),
        ('Saturn / Sade Sati', 2, 'How long will my Saturn period last?'),
      ];

  /// An AI-generated audience poll for the live session.
  static (String, List<String>) generatePoll() => (
        'What should guruji cover next?',
        const ['Career & money', 'Love & marriage', 'Health & remedies', 'Daily horoscope'],
      );

  /// AI summary produced when the live session ends.
  static LiveSummary liveSummary({required int viewers, required int superchatTotal, required int questions}) =>
      LiveSummary(
        peakViewers: viewers,
        totalQuestions: questions,
        superchatEarnings: superchatTotal,
        highlights: const [
          'Strongest engagement on the "business timing" segment.',
          'Top superchat: ₹501 from Pooja (daughter\'s exams).',
          'AI moderator removed 4 violations (spam, abuse, a phone number, self-promo).',
          '8 of 11 questions answered; 3 grouped as duplicates.',
        ],
        followUpProducts: const ['5-Mukhi Rudraksha', 'Shri Yantra (Brass)'],
        suggestedNextTopic: 'Run a 20-min "career & money" live tomorrow at the same time — it drew the most questions.',
      );
}
