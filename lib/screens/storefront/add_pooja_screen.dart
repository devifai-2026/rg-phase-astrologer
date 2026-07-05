import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../api/astrologer_api.dart';
import '../../i18n/strings.dart';
import '../../models/ai_models.dart';
import '../../theme/rg_colors.dart';

/// Form for an astrologer to list a pooja they perform. Created with
/// status = pending (awaiting admin approval + commission).
class AddPoojaScreen extends StatefulWidget {
  const AddPoojaScreen({super.key});

  @override
  State<AddPoojaScreen> createState() => _AddPoojaScreenState();
}

class _AddPoojaScreenState extends State<AddPoojaScreen> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _price = TextEditingController();
  final _duration = TextEditingController(text: 'approx 60 min');
  final _formKey = GlobalKey<FormState>();

  File? _imageFile; // picked + cropped banner (16:9), uploaded on submit

  /// Pick + crop a wide banner photo (16:9) for the pooja.
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 90);
    if (x == null) return;
    final cropped = await ImageCropper().cropImage(
      sourcePath: x.path,
      aspectRatio: const CropAspectRatio(ratioX: 16, ratioY: 9),
      compressQuality: 90,
    );
    final path = cropped?.path ?? x.path;
    if (mounted) setState(() => _imageFile = File(path));
  }

  // Availability mode: any day, a single date, or a from–to range.
  String _availMode = 'any'; // 'any' | 'single' | 'range'
  DateTime? _dateFrom;
  DateTime? _dateTo;

  Future<void> _pickDate({required bool from}) async {
    final now = DateTime.now();
    final init = (from ? _dateFrom : _dateTo) ?? now;
    final d = await showDatePicker(
      context: context,
      initialDate: init.isBefore(now) ? now : init,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (d == null) return;
    setState(() {
      if (from) {
        _dateFrom = d;
        if (_dateTo != null && _dateTo!.isBefore(d)) _dateTo = d;
      } else {
        _dateTo = d;
      }
    });
  }

  String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

  String _type = 'Havan / Jaap';
  static const _types = ['Havan / Jaap', 'Graha Shanti', 'Wealth puja', 'Health puja', 'Protection', 'Other'];
  static const _typeIcon = <String, IconData>{
    'Havan / Jaap': Icons.local_fire_department,
    'Graha Shanti': Icons.brightness_7,
    'Wealth puja': Icons.auto_awesome,
    'Health puja': Icons.healing,
    'Protection': Icons.shield_outlined,
    'Other': Icons.temple_hindu,
  };

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _price.dispose();
    _duration.dispose();
    super.dispose();
  }

  bool _saving = false;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    // A banner photo is required for the pooja card + detail header.
    if (_imageFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Strings.of(context).addABannerPhotoForThe)));
      return;
    }
    // Validate the date selections per mode.
    if (_availMode == 'single' && _dateFrom == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Strings.of(context).pickADate)));
      return;
    }
    if (_availMode == 'range' && (_dateFrom == null || _dateTo == null)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Strings.of(context).pickBothFromAndToDates)));
      return;
    }
    // Derive the booking window + a human label from the mode.
    DateTime? from, to;
    String availLabel;
    if (_availMode == 'single') {
      from = _dateFrom; to = _dateFrom; availLabel = Strings.of(context).onFmtdateDatefrom(_fmtDate(_dateFrom!));
    } else if (_availMode == 'range') {
      from = _dateFrom; to = _dateTo; availLabel = '${_fmtDate(_dateFrom!)} – ${_fmtDate(_dateTo!)}';
    } else {
      availLabel = Strings.of(context).anyDay;
    }
    final redColor = context.rg.red;
    final api = context.read<AstrologerApi>();
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final s = Strings.of(context);
    final navigator = Navigator.of(context);
    try {
      // Upload the banner first, then create the pooja with its hosted URL.
      final imageUrl = await api.uploadImage(_imageFile!);
      final p = PoojaOffering(
        name: _name.text.trim(),
        description: _desc.text.trim(),
        price: int.tryParse(_price.text.trim()) ?? 0,
        durationNote: _duration.text.trim(),
        availability: availLabel,
        availableFrom: from,
        availableTo: to,
        image: imageUrl,
        icon: _typeIcon[_type] ?? Icons.local_fire_department,
        color: redColor,
        status: ProductStatus.pending,
      );
      await api.createPooja(p);
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(s.poojaSubmittedForAdminApproval)));
    } catch (_) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(s.couldNotSubmitPleaseTryAgain)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    return Scaffold(
      backgroundColor: c.ground,
      appBar: AppBar(title: Text(Strings.of(context).listAPooja, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800))),
      body: Form(
        key: _formKey,
        // The Scaffold already shrinks the body for the keyboard
        // (resizeToAvoidBottomInset), so the ListView must NOT also add
        // viewInsets.bottom — doing both double-counts the inset and causes the
        // jumpy over-scroll. A fixed bottom pad keeps the submit button clear.
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            // Tappable banner photo picker (pick → 16:9 crop → preview).
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _pickImage,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.line)),
                  child: _imageFile != null
                      ? Stack(fit: StackFit.expand, children: [
                          Image.file(_imageFile!, fit: BoxFit.cover),
                          Positioned(
                            right: 8, bottom: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(20)),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.edit, size: 13, color: Colors.white),
                                const SizedBox(width: 4),
                                Text(Strings.of(context).change, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
                              ]),
                            ),
                          ),
                        ])
                      : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.add_photo_alternate_outlined, color: c.muted, size: 30),
                          const SizedBox(height: 6),
                          Text(Strings.of(context).addBannerPhoto, style: TextStyle(color: c.muted, fontSize: 12.5)),
                          const SizedBox(height: 2),
                          Text(Strings.of(context).wide169ImageShownOn, style: TextStyle(color: c.muted, fontSize: 10.5)),
                        ]),
                ),
              ),
            ),
            const SizedBox(height: 18),

            _label(c, Strings.of(context).poojaName),
            const SizedBox(height: 8),
            TextFormField(controller: _name, decoration: InputDecoration(hintText: Strings.of(context).eGNavagrahaShantiPuja), validator: (v) => (v ?? '').trim().isEmpty ? Strings.of(context).requiredLabel : null),
            const SizedBox(height: 16),

            _label(c, Strings.of(context).type),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: _types.map((tp) {
              final on = tp == _type;
              return InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => setState(() => _type = tp),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(color: on ? c.redSoft : c.ground2, borderRadius: BorderRadius.circular(20), border: Border.all(color: on ? c.red : c.line, width: on ? 1.3 : 1)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_typeIcon[tp], size: 15, color: on ? c.red : c.muted),
                    const SizedBox(width: 6),
                    Text(tp, style: TextStyle(color: on ? c.red : c.ink, fontWeight: on ? FontWeight.w700 : FontWeight.w500, fontSize: 13)),
                  ]),
                ),
              );
            }).toList()),
            const SizedBox(height: 16),

            _label(c, Strings.of(context).description),
            const SizedBox(height: 8),
            TextFormField(controller: _desc, maxLines: 3, maxLength: 400, decoration: InputDecoration(hintText: Strings.of(context).whatThePoojaIsForWhat)),
            const SizedBox(height: 8),

            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _label(c, Strings.of(context).price),
                const SizedBox(height: 8),
                TextFormField(controller: _price, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: const InputDecoration(hintText: '2100'), validator: (v) => (int.tryParse((v ?? '').trim()) ?? 0) <= 0 ? Strings.of(context).requiredLabel : null),
              ])),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _label(c, Strings.of(context).duration),
                const SizedBox(height: 8),
                TextFormField(controller: _duration, decoration: InputDecoration(hintText: Strings.of(context).approx90Min)),
              ])),
            ]),
            const SizedBox(height: 16),

            _label(c, Strings.of(context).availability),
            const SizedBox(height: 8),
            // Mode: Any day · Single date · Date range.
            Wrap(spacing: 8, runSpacing: 8, children: [
              ('any', Strings.of(context).anyDay), ('single', Strings.of(context).singleDate), ('range', Strings.of(context).dateRange),
            ].map((opt) {
              final on = opt.$1 == _availMode;
              return InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => setState(() => _availMode = opt.$1),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(color: on ? c.redSoft : c.ground2, borderRadius: BorderRadius.circular(20), border: Border.all(color: on ? c.red : c.line, width: on ? 1.3 : 1)),
                  child: Text(opt.$2, style: TextStyle(color: on ? c.red : c.ink, fontWeight: on ? FontWeight.w700 : FontWeight.w500, fontSize: 13)),
                ),
              );
            }).toList()),
            if (_availMode != 'any') ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _dateField(c, label: _availMode == 'single' ? Strings.of(context).date : Strings.of(context).from, date: _dateFrom, onTap: () => _pickDate(from: true))),
                if (_availMode == 'range') ...[
                  const SizedBox(width: 12),
                  Expanded(child: _dateField(c, label: Strings.of(context).to, date: _dateTo, onTap: () => _pickDate(from: false))),
                ],
              ]),
            ],
            const SizedBox(height: 18),

            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(color: c.gold.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: c.gold.withValues(alpha: 0.4))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.gavel, size: 16, color: c.gold),
                const SizedBox(width: 10),
                Expanded(child: Text(Strings.of(context).yourPoojaGoesToTheAdmin, style: TextStyle(color: c.ink, fontSize: 12.5, height: 1.4))),
              ]),
            ),
            const SizedBox(height: 18),

            ElevatedButton.icon(
              icon: _saving ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send),
              label: Text(_saving ? Strings.of(context).submitting : Strings.of(context).submitForApproval),
              onPressed: _saving ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(RgColors c, String t) => Text(t, style: TextStyle(color: c.muted, fontWeight: FontWeight.w700, fontSize: 13));

  Widget _dateField(RgColors c, {required String label, required DateTime? date, required VoidCallback onTap}) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: InputDecorator(
          decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18)),
          child: Text(date != null ? _fmtDate(date) : 'Select', style: TextStyle(color: date != null ? c.ink : c.muted, fontSize: 14)),
        ),
      );
}
