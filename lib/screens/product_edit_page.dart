import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/app_sections.dart';
import '../core/product_units.dart';
import '../services/currency_service.dart';
import '../services/media_service.dart';
import '../services/supabase_service.dart';

/// Edits an existing product: name, description, price, stock, sale unit,
/// catalog section, barcode and image.
///
/// The image is uploaded to Supabase Storage and linked to the product; the
/// storage object is overwritten in place so the existing public URL keeps
/// working and `products.image_url` can simply be pointed at it.
class ProductEditPage extends StatefulWidget {
  const ProductEditPage({
    super.key,
    required this.product,
    required this.ownerId,
    this.canChangeSection = true,
    this.title = 'تعديل الصنف',
  });

  final Map<String, dynamic> product;
  final String ownerId;
  final bool canChangeSection;
  final String title;

  @override
  State<ProductEditPage> createState() => _ProductEditPageState();
}

class _ProductEditPageState extends State<ProductEditPage> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _price;
  late final TextEditingController _stock;
  late final TextEditingController _barcode;

  late String _saleUnit;
  late String _sectionId;
  late String _currency;
  String _imageUrl = '';
  bool _uploading = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _name = TextEditingController(text: '${p['name'] ?? ''}');
    _description = TextEditingController(text: '${p['description'] ?? ''}');
    _price = TextEditingController(text: '${p['price'] ?? ''}');
    _stock = TextEditingController(text: '${p['stock'] ?? ''}');
    final meta = p['metadata'];
    final barcode = meta is Map ? meta['barcode'] : null;
    _barcode = TextEditingController(text: '${barcode ?? ''}');
    _saleUnit = (p['sale_unit'] ?? 'piece').toString();
    final cur = (p['currency'] ?? 'USD').toString().toUpperCase();
    _currency = CurrencyService.supported.contains(cur) ? cur : 'USD';
    final section = (p['section_id'] ?? '').toString();
    _sectionId = appSections.any((s) => s.id == section) ? section : appSections.first.id;
    _imageUrl = (p['image_url'] ?? p['imageUrl'] ?? p['image'] ?? '').toString();
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    _stock.dispose();
    _barcode.dispose();
    super.dispose();
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final file = result?.files.single;
    if (file == null || file.bytes == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      final url = await MediaService.uploadProductImage(
        ownerId: widget.ownerId,
        bytes: file.bytes!,
        extension: file.extension ?? 'jpg',
        productId: '${widget.product['id']}',
        overwrite: true,
      );
      if (!mounted) return;
      setState(() => _imageUrl = url);
      _message('تم رفع الصورة إلى قاعدة صور الفائق.');
    } catch (e) {
      _message('تعذر رفع الصورة: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final price = num.tryParse(_price.text.trim());
    final stock = num.tryParse(_stock.text.trim());
    if (name.isEmpty) { _message('أدخل اسم الصنف.'); return; }
    if (price == null || price < 0 || stock == null || stock < 0) {
      _message('السعر والمخزون يجب أن يكونا رقمين غير سالبين.');
      return;
    }
    final productId = '${widget.product['id']}';
    setState(() => _saving = true);
    try {
      final unit = ProductUnit.fromId(_saleUnit);
      final existingMeta = widget.product['metadata'];
      final metadata = existingMeta is Map
          ? Map<String, dynamic>.from(existingMeta)
          : <String, dynamic>{};
      final barcode = _barcode.text.trim();
      if (barcode.isEmpty) {
        metadata.remove('barcode');
      } else {
        metadata['barcode'] = barcode;
      }
      await SupabaseService.client.from('products').update({
        'name': name,
        'description': _description.text.trim(),
        'price': price,
        'currency': _currency,
        'stock': stock,
        'stock_base': unit.toBase(stock).round(),
        'sale_unit': _saleUnit,
        'unit_label': unit.label,
        'base_unit': unit.baseUnit,
        'unit_scale': unit.scale,
        'step_base': unit.defaultStepBase,
        'min_order_base': unit.defaultStepBase,
        if (widget.canChangeSection) 'section_id': _sectionId,
        if (_imageUrl.isNotEmpty) 'image_url': _imageUrl,
        'metadata': metadata,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', productId);
      if (_imageUrl.isNotEmpty) {
        await SupabaseService.client
            .from('media_assets')
            .update({'entity_id': productId})
            .eq('owner_id', widget.ownerId)
            .eq('public_url', _imageUrl)
            .isFilter('entity_id', null);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      _message('تعذر حفظ التعديلات: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _saving || _uploading;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w900)),
          actions: [
            TextButton(
              onPressed: busy ? null : _save,
              child: const Text('حفظ', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _imageCard(),
            const SizedBox(height: 16),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'اسم الصنف', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: _description, maxLines: 3, decoration: const InputDecoration(labelText: 'الوصف', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: _barcode, decoration: const InputDecoration(labelText: 'الباركود (اختياري)', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: _price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'السعر', border: OutlineInputBorder()))),
              const SizedBox(width: 12),
              SizedBox(
                width: 170,
                child: DropdownButtonFormField<String>(
                  initialValue: _currency,
                  decoration: const InputDecoration(labelText: 'عملة السعر', border: OutlineInputBorder()),
                  items: [for (final c in CurrencyService.supported) DropdownMenuItem(value: c, child: Text('${CurrencyService.labelFor(c)} (${CurrencyService.symbolFor(c)})'))],
                  onChanged: (value) { if (value != null) setState(() => _currency = value); },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: _stock, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'المخزون (${ProductUnit.fromId(_saleUnit).label})', border: const OutlineInputBorder()))),
            ]),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _saleUnit,
              decoration: const InputDecoration(labelText: 'وحدة البيع', border: OutlineInputBorder()),
              items: [for (final u in ProductUnit.all) DropdownMenuItem(value: u.id, child: Text(u.label))],
              onChanged: (v) { if (v != null) setState(() => _saleUnit = v); },
            ),
            if (widget.canChangeSection) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _sectionId,
                decoration: const InputDecoration(labelText: 'القسم', border: OutlineInputBorder()),
                items: [for (final s in appSections) DropdownMenuItem(value: s.id, child: Text(s.title))],
                onChanged: (v) { if (v != null) setState(() => _sectionId = v); },
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: busy ? null : _save,
                icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
                label: const Text('حفظ التعديلات', style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imageCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: _imageUrl.isEmpty
                ? Container(height: 170, color: const Color(0xFFF0F3F7), child: const Center(child: Icon(Icons.image_outlined, size: 56, color: Colors.black26)))
                : Image.network(_imageUrl, height: 170, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(height: 170, color: const Color(0xFFF0F3F7), child: const Center(child: Icon(Icons.broken_image_outlined, size: 56))),),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: _uploading ? null : _pickImage,
              icon: _uploading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.photo_library_outlined),
              label: Text(_imageUrl.isEmpty ? 'اختيار صورة' : 'تغيير الصورة'),
            )),
            if (_imageUrl.isNotEmpty) ...[
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'إزالة الصورة',
                onPressed: _uploading ? null : () => setState(() => _imageUrl = ''),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ]),
        ]),
      ),
    );
  }
}
