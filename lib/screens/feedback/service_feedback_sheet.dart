import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/service_feedback_api.dart';
import '../../i18n/strings.dart';
import '../../theme/rg_colors.dart';

/// Multi-dimension feedback the astrologer fills after a delivered service/live.
/// Skippable — every dimension is optional. Shown as a bottom sheet from the
/// end-of-session summary and the end-of-live recap.
///
///   kind        'session' | 'live'
///   sourceId    the Session id (session) or LiveSession id (live)
///   serviceType 'chat' | 'call' | 'video' | 'live' — tunes the wording.
class ServiceFeedbackSheet extends StatefulWidget {
  final String kind;
  final String sourceId;
  final String serviceType;
  const ServiceFeedbackSheet({super.key, required this.kind, required this.sourceId, required this.serviceType});

  /// Present the sheet. Returns true if feedback was submitted, false/null if skipped.
  static Future<bool?> show(BuildContext context, {required String kind, required String sourceId, required String serviceType}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // Without this the sheet extends UNDER the system navigation bar, so the
      // pinned Skip/Submit row sits behind the gesture pill — invisible and
      // untappable, which reads as "there is no Submit button, only Skip".
      useSafeArea: true,
      builder: (_) => ServiceFeedbackSheet(kind: kind, sourceId: sourceId, serviceType: serviceType),
    );
  }

  @override
  State<ServiceFeedbackSheet> createState() => _ServiceFeedbackSheetState();
}

class _ServiceFeedbackSheetState extends State<ServiceFeedbackSheet> {
  int _overall = 0;
  int _connection = 0;
  int _seeker = 0;
  final _note = TextEditingController();
  bool _saving = false;

  bool get _isLive => widget.kind == 'live';

  String get _heading => _isLive ? Strings.of(context).howWasYourLiveSession : Strings.of(context).howWasThisWidgetServicetype(widget.serviceType);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await context.read<ServiceFeedbackApi>().submit(
            kind: widget.kind,
            sourceId: widget.sourceId,
            overall: _overall > 0 ? _overall : null,
            connectionQuality: _connection > 0 ? _connection : null,
            seekerBehaviour: _seeker > 0 ? _seeker : null,
            comment: _note.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Strings.of(context).couldNotSaveFeedbackPleaseTry)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    // Cap the sheet so it can never grow taller than the screen (which clipped
    // the Skip/Submit row off the bottom on smaller devices / large font scale →
    // "no submit button"). The rating fields scroll; the actions stay pinned.
    final maxH = MediaQuery.of(context).size.height * 0.9;
    // Gesture-nav inset. When the keyboard is up, viewInsets already covers the
    // bottom, so take the larger of the two rather than stacking them.
    final navInset = MediaQuery.of(context).viewPadding.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset > navInset ? bottomInset : navInset),
      child: Container(
        constraints: BoxConstraints(maxHeight: maxH),
        decoration: BoxDecoration(
          color: c.ground2,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(width: 40, height: 4, decoration: BoxDecoration(color: c.line, borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            // Scrollable content: heading + ratings + note. Lets the sheet shrink
            // to fit while keeping the action row (below) always on screen.
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_heading, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 17)),
                    const SizedBox(height: 2),
                    Text(Strings.of(context).yourFeedbackHelpsUsImproveOptional, style: TextStyle(color: c.muted, fontSize: 12.5)),
                    const SizedBox(height: 18),

                    _StarRow(label: Strings.of(context).overallExperience, value: _overall, onChanged: (v) => setState(() => _overall = v)),
                    const SizedBox(height: 14),
                    _StarRow(
                      label: _isLive ? Strings.of(context).streamQuality : Strings.of(context).connectionQuality,
                      value: _connection,
                      onChanged: (v) => setState(() => _connection = v),
                    ),
                    const SizedBox(height: 14),
                    _StarRow(
                      label: _isLive ? Strings.of(context).audienceBehaviour : Strings.of(context).seekerBehaviour,
                      value: _seeker,
                      onChanged: (v) => setState(() => _seeker = v),
                    ),
                    const SizedBox(height: 16),

                    TextField(
                      controller: _note,
                      maxLines: 3,
                      maxLength: 1000,
                      style: TextStyle(color: c.ink),
                      decoration: InputDecoration(
                        hintText: Strings.of(context).anythingYouWantToShareOptional,
                        hintStyle: TextStyle(color: c.muted),
                        filled: true,
                        fillColor: c.ground,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.line)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.line)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.red)),
                        counterStyle: TextStyle(color: c.muted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Pinned action row — always visible regardless of content height.
            Row(
              children: [
                TextButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                  child: Text(Strings.of(context).skip, style: TextStyle(color: c.muted, fontWeight: FontWeight.w700)),
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: _saving ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                  ),
                  child: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(Strings.of(context).submit, style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StarRow extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  const _StarRow({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: Text(label, style: TextStyle(color: c.ink, fontSize: 14, fontWeight: FontWeight.w600))),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(5, (i) {
            final filled = i < value;
            return GestureDetector(
              onTap: () => onChanged(i + 1),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Icon(filled ? Icons.star_rounded : Icons.star_outline_rounded, color: filled ? c.gold : c.muted, size: 28),
              ),
            );
          }),
        ),
      ],
    );
  }
}
