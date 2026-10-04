import 'package:flutter/material.dart';

import '../core/product_units.dart';
import '../services/catalog_service.dart';
import '../services/review_service.dart';
import '../services/supabase_service.dart';
import 'cart_page.dart';

const _blue = Color(0xFF0D6EFD);
const _navy = Color(0xFF0A2540);

/// WeChat-shop-style product detail: gallery, price, quantity picker, rating
/// summary, and a reviews list with a write-review sheet.
class ProductDetailPage extends StatefulWidget {
  const ProductDetailPage({super.key, required this.product});
  final CatalogDocument product;
  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  late ProductUnit _unit;
  int _qtyBase = 1;
  int _stepBase = 1;
  int _stockBase = 0;
  bool _busy = false;
  ({double average, int count, List<Map<String, dynamic>> items})? _reviews;
  bool _reviewsLoading = true;

  Map<String, dynamic> get _data => widget.product.data;

  @override
  void initState() {
    super.initState();
    _unit = ProductUnit.fromProduct(_data);
    _stepBase = _unit.stepFor(_data);
    _stockBase = ProductUnit.stockBase(_data);
    _qtyBase = _unit.minFor(_data);
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    try {
      final r = await const ReviewService().productReviews(widget.product.id);
      if (mounted) setState(() { _reviews = r; _reviewsLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _reviewsLoading = false);
    }
  }

  num get _price => (_data['price'] as num?) ?? 0;
  String get _currency => (_data['currency'] ?? 'YER').toString();
  String get _name => (_data['name'] ?? 'منتج').toString();
  String get _description => (_data['description'] ?? _data['details'] ?? '').toString();
  String get _imageUrl => (_data['image_url'] ?? _data['imageUrl'] ?? '').toString();
  String get _storeId => (_data['store_id'] ?? '').toString();

  void _changeQty(int direction) {
    final next = _qtyBase + direction * _stepBase;
    if (next < _unit.minFor(_data)) return;
    if (_stockBase > 0 && next > _stockBase) return;
    setState(() => _qtyBase = next);
  }

  Future<void> _addToCart() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يجب تسجيل الدخول أولاً.')));
      return;
    }
    setState(() => _busy = true);
    try {
      final saleQty = _unit.fromBase(_qtyBase);
      await const CatalogService().addToCart(user.id, widget.product, saleQuantity: saleQty);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تمت إضافة «$_name» (${saleQty.toStringAsFixed(0)} ${_unit.label}) إلى السلة.')));
      }
    } on StateError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تحديث السلة: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _writeReview() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يجب تسجيل الدخول لإضافة تقييم.')));
      return;
    }
    var rating = 5;
    final bodyController = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 16, right: 16, top: 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('قيّم هذا المنتج', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  onPressed: () => setSheet(() => rating = i),
                  icon: Icon(i <= rating ? Icons.star : Icons.star_border, color: Colors.amber, size: 30),
                ),
            ]),
            TextField(controller: bodyController, maxLines: 3, decoration: const InputDecoration(labelText: 'رأيك (اختياري)', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pop(sheetContext, true),
              child: const Text('إرسال التقييم'),
            ),
            const SizedBox(height: 12),
          ]),
        ),
      ),
    );
    if (ok != true) { bodyController.dispose(); return; }
    setState(() => _busy = true);
    try {
      await const ReviewService().submit(productId: widget.product.id, storeId: _storeId, rating: rating, body: bodyController.text);
      bodyController.dispose();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('شكراً لتقييمك!')));
      await _loadReviews();
    } on StateError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إرسال التقييم: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = _stockBase > 0 || _data['stock'] == null;
    final priceText = _price > 0 ? '${_price.toStringAsFixed(0)} $_currency' : 'عند الطلب';
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
          actions: [
            IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartPage())), tooltip: 'السلة', icon: const Icon(Icons.shopping_cart_outlined)),
          ],
        ),
        body: ListView(
          children: [
            AspectRatio(
              aspectRatio: 1.1,
              child: _imageUrl.isEmpty
                  ? Container(color: const Color(0xFFF1F6FF), child: const Icon(Icons.inventory_2_outlined, color: _blue, size: 72))
                  : Image.network(_imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: const Color(0xFFF1F6FF), child: const Icon(Icons.broken_image_outlined, color: _blue, size: 72))),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_name, style: const TextStyle(color: _navy, fontWeight: FontWeight.w900, fontSize: 20)),
                const SizedBox(height: 8),
                Row(children: [
                  Text(priceText, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: _blue)),
                  const SizedBox(width: 10),
                  if (available) const Chip(label: Text('متوفر', style: TextStyle(fontSize: 11)), visualDensity: VisualDensity.compact)
                  else const Chip(label: Text('غير متوفر', style: TextStyle(fontSize: 11)), visualDensity: VisualDensity.compact),
                ]),
                if (_description.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(_description, style: const TextStyle(height: 1.5)),
                ],
                const SizedBox(height: 16),
                Row(children: [
                  const Text('الكمية:', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(width: 10),
                  IconButton.filledTonal(onPressed: _qtyBase > _unit.minFor(_data) ? () => _changeQty(-1) : null, icon: const Icon(Icons.remove)),
                  Text('${_unit.fromBase(_qtyBase).toStringAsFixed(_unit.scale == 1 ? 0 : 2)} ${_unit.label}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  IconButton.filledTonal(onPressed: (_stockBase > 0 && _qtyBase + _stepBase > _stockBase) ? null : () => _changeQty(1), icon: const Icon(Icons.add)),
                ]),
                if (_stockBase > 0) Text('المتوفر: ${_unit.fromBase(_stockBase).toStringAsFixed(_unit.scale == 1 ? 0 : 2)} ${_unit.label}', style: const TextStyle(color: Colors.black54, fontSize: 12)),
              ]),
            ),
            const Divider(height: 1),
            _ReviewsSection(
              loading: _reviewsLoading,
              average: _reviews?.average ?? 0,
              count: _reviews?.count ?? 0,
              items: _reviews?.items ?? const [],
              onWrite: _writeReview,
            ),
            const SizedBox(height: 90),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              height: 50,
              child: FilledButton.icon(
                onPressed: (_busy || !available) ? null : _addToCart,
                icon: const Icon(Icons.add_shopping_cart),
                label: Text(_busy ? 'جارٍ الإضافة...' : 'أضف إلى السلة'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewsSection extends StatelessWidget {
  const _ReviewsSection({required this.loading, required this.average, required this.count, required this.items, required this.onWrite});
  final bool loading;
  final double average;
  final int count;
  final List<Map<String, dynamic>> items;
  final VoidCallback onWrite;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('التقييمات', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(width: 10),
          if (count > 0) ...[
            const Icon(Icons.star, color: Colors.amber, size: 20),
            Text('${average.toStringAsFixed(1)} ($count)', style: const TextStyle(fontWeight: FontWeight.w800)),
          ] else
            const Text('لا توجد تقييمات بعد', style: TextStyle(color: Colors.black54, fontSize: 12)),
          const Spacer(),
          TextButton.icon(onPressed: onWrite, icon: const Icon(Icons.rate_review_outlined, size: 18), label: const Text('اكتب تقييماً')),
        ]),
        if (loading)
          const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))
        else
          ...items.map((r) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    CircleAvatar(radius: 14, child: Text((r['author_name'] ?? '؟').toString().characters.first)),
                    const SizedBox(width: 8),
                    Text((r['author_name'] ?? 'مستخدم').toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(width: 8),
                    for (var i = 1; i <= 5; i++)
                      Icon(i <= ((r['rating'] as num?)?.toInt() ?? 0) ? Icons.star : Icons.star_border, color: Colors.amber, size: 14),
                  ]),
                  if ((r['body'] ?? '').toString().trim().isNotEmpty)
                    Padding(padding: const EdgeInsets.only(top: 4, right: 36), child: Text((r['body']).toString(), style: const TextStyle(height: 1.4))),
                ]),
              )),
      ]),
    );
  }
}
