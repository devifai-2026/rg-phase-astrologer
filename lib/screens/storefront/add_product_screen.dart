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

/// Form for an astrologer to list a new storefront product. On submit it's
/// created with status = pending (awaiting admin approval + commission).
class AddProductScreen extends StatefulWidget {
  const AddProductScreen({super.key});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _mrp = TextEditingController();
  final _price = TextEditingController();
  final _stock = TextEditingController(text: '10');
  final _formKey = GlobalKey<FormState>();

  // Admin-managed categories, loaded from the API. The astrologer can only pick.
  List<StoreCategory>? _categories;
  StoreCategory? _category;

  File? _imageFile; // picked + cropped local file (uploaded on submit)
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final cats = await context.read<AstrologerApi>().categories();
      if (mounted) setState(() { _categories = cats; _category ??= cats.isNotEmpty ? cats.first : null; });
    } catch (_) {
      if (mounted) setState(() => _categories = const []);
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 90);
    if (x == null) return;
    final cropped = await ImageCropper().cropImage(
      sourcePath: x.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      compressQuality: 90,
    );
    final path = cropped?.path ?? x.path;
    if (mounted) setState(() => _imageFile = File(path));
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _mrp.dispose();
    _price.dispose();
    _stock.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    if (_category == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Strings.of(context).pleasePickACategory)));
      return;
    }
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final api = context.read<AstrologerApi>();
    final goldColor = context.rg.gold;
    final strings = Strings.of(context);
    try {
      // Upload the photo first (if any), then create with its hosted URL.
      String? imageUrl;
      if (_imageFile != null) imageUrl = await api.uploadImage(_imageFile!);
      final p = StoreProduct(
        name: _name.text.trim(),
        description: _desc.text.trim(),
        mrp: int.tryParse(_mrp.text.trim()) ?? 0,
        price: int.tryParse(_price.text.trim()) ?? 0,
        stock: int.tryParse(_stock.text.trim()) ?? 0,
        category: _category!.name,
        categoryId: _category!.id,
        image: imageUrl,
        color: goldColor,
        status: ProductStatus.pending,
      );
      await api.createProduct(p);
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(strings.submittedForAdminApproval)));
    } catch (_) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(strings.couldNotSubmitPleaseTryAgain)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    return Scaffold(
      backgroundColor: c.ground,
      appBar: AppBar(title: Text(Strings.of(context).listAProduct, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800))),
      body: Form(
        key: _formKey,
        // The Scaffold already shrinks the body for the keyboard
        // (resizeToAvoidBottomInset), so the ListView must NOT also add
        // viewInsets.bottom — doing both double-counts the inset and causes the
        // jumpy over-scroll. A fixed bottom pad keeps the submit button clear.
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            // Tappable photo picker (pick → crop → preview).
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _pickImage,
              child: Container(
                height: 140,
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
                        Icon(Icons.add_a_photo_outlined, color: c.muted, size: 30),
                        const SizedBox(height: 6),
                        Text(Strings.of(context).addProductPhoto, style: TextStyle(color: c.muted, fontSize: 12.5)),
                      ]),
              ),
            ),
            const SizedBox(height: 18),

            _label(c, Strings.of(context).productName),
            const SizedBox(height: 8),
            TextFormField(controller: _name, decoration: InputDecoration(hintText: Strings.of(context).eGEnergised7MukhiRudraksha), validator: (v) => (v ?? '').trim().isEmpty ? Strings.of(context).requiredLabel : null),
            const SizedBox(height: 16),

            _label(c, Strings.of(context).category),
            const SizedBox(height: 8),
            if (_categories == null)
              Row(children: [SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.muted)), const SizedBox(width: 8), Text(Strings.of(context).loadingCategories, style: TextStyle(color: c.muted, fontSize: 12.5))])
            else if (_categories!.isEmpty)
              Text(Strings.of(context).noCategoriesAvailableAskTheAdmin, style: TextStyle(color: c.muted, fontSize: 12.5))
            else
              Wrap(spacing: 8, runSpacing: 8, children: _categories!.map((cat) {
                final on = cat.id == _category?.id;
                return InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => setState(() => _category = cat),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(color: on ? c.redSoft : c.ground2, borderRadius: BorderRadius.circular(20), border: Border.all(color: on ? c.red : c.line, width: on ? 1.3 : 1)),
                    child: Text(cat.name, style: TextStyle(color: on ? c.red : c.ink, fontWeight: on ? FontWeight.w700 : FontWeight.w500, fontSize: 13)),
                  ),
                );
              }).toList()),
            const SizedBox(height: 16),

            _label(c, Strings.of(context).description),
            const SizedBox(height: 8),
            TextFormField(controller: _desc, maxLines: 3, maxLength: 400, decoration: InputDecoration(hintText: Strings.of(context).materialsSizeWhatItHelpsWith)),
            const SizedBox(height: 8),

            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _label(c, Strings.of(context).mrp),
                const SizedBox(height: 8),
                TextFormField(controller: _mrp, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: const InputDecoration(hintText: '1199')),
              ])),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _label(c, Strings.of(context).price),
                const SizedBox(height: 8),
                TextFormField(controller: _price, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: const InputDecoration(hintText: '899'), validator: (v) => (int.tryParse((v ?? '').trim()) ?? 0) <= 0 ? Strings.of(context).requiredLabel : null),
              ])),
              const SizedBox(width: 12),
              SizedBox(width: 90, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _label(c, Strings.of(context).stock),
                const SizedBox(height: 8),
                TextFormField(controller: _stock, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: const InputDecoration(hintText: '10')),
              ])),
            ]),
            const SizedBox(height: 18),

            // Approval notice.
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(color: c.gold.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: c.gold.withValues(alpha: 0.4))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.gavel, size: 16, color: c.gold),
                const SizedBox(width: 10),
                Expanded(child: Text(Strings.of(context).yourListingGoesToTheAdmin, style: TextStyle(color: c.ink, fontSize: 12.5, height: 1.4))),
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
}
