import 'package:flutter/material.dart';

import '../core/product_units.dart';
import '../services/currency_service.dart';
import '../services/catalog_service.dart';
import '../services/review_service.dart';
import '../services/supabase_service.dart';
import 'cart_page.dart';
import 'product_detail_page.dart';

const _blue = Color(0xFF0D6EFD);
const _navy = Color(0xFF0A2540);

/// Store page: header with contact info + rating, the store's products, and
/// store-level reviews. Reached from the home store cards.
class StoreDetailPage extends StatefulWidget {
  const StoreDetailPage({super.key, required this.store});
  final CatalogDocument store;
  @override
  State<StoreDetailPage> createState() => _StoreDetailPageState();
}

class _StoreDetailPageState extends State<StoreDetailPage> {
  bool _busy = false;
  ({double average, int count, List<Map<String, dynamic>> items})? _reviews;
  bool _reviewsLoading = true;

  Map<String, dynamic> get _data => widget.store.data;
  String get _name => (_data['name'] ?? 'متجر').toString();

  @override
  void initState() {
    super.initState();
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    try {
      final r = await const ReviewService().storeReviews(widget.store.id);
      if (mounted) setState(() { _reviews = r; _reviewsLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _reviewsLoading = false);
    }
  }

  Future<void> _addToCart(CatalogDocument product) async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يجب تسجيل الدخول أولاً.')));
      return;
    }
    try {
      await const CatalogService().addToCart(user.id, product);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تمت إضافة «${(product.data['name'] ?? 'صنف')}» إلى السلة.')));
    } on StateError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تحديث السلة: $e')));
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
            Text('قيّم $_name', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 1; i <= 5; i++)
                IconButton(onPressed: () => setSheet(() => rating = i), icon: Icon(i <= rating ? Icons.star : Icons.star_border, color: Colors.amber, size: 30)),
            ]),
            TextField(controller: bodyController, maxLines: 3, decoration: const InputDecoration(labelText: 'رأيك (اختياري)', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => Navigator.pop(sheetContext, true), child: const Text('إرسال التقييم')),
            const SizedBox(height: 12),
          ]),
        ),
      ),
    );
    if (ok != true) { bodyController.dispose(); return; }
    setState(() => _busy = true);
    try {
      await const ReviewService().submit(storeId: widget.store.id, rating: rating, body: bodyController.text);
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
    final address = (_data['address'] ?? '').toString();
    final phone = (_data['phone'] ?? '').toString();
    final rating = _reviews;
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
            Container(
              padding: const EdgeInsets.all(16),
              color: const Color(0xFFF1F6FF),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const CircleAvatar(radius: 26, backgroundColor: Colors.white, child: Icon(Icons.storefront_outlined, color: _blue, size: 28)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_name, style: const TextStyle(color: _navy, fontWeight: FontWeight.w900, fontSize: 20))),
                ]),
                const SizedBox(height: 10),
                if (address.isNotEmpty) Row(children: [const Icon(Icons.location_on_outlined, size: 16, color: Colors.black54), const SizedBox(width: 4), Expanded(child: Text(address, style: const TextStyle(color: Colors.black54)))]),
                if (phone.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Row(children: [const Icon(Icons.phone_outlined, size: 16, color: Colors.black54), const SizedBox(width: 4), Text(phone, style: const TextStyle(color: Colors.black54))])),
                const SizedBox(height: 8),
                Row(children: [
                  if (rating != null && rating.count > 0) ...[
                    const Icon(Icons.star, color: Colors.amber, size: 20),
                    Text('${rating.average.toStringAsFixed(1)} (${rating.count} تقييم)', style: const TextStyle(fontWeight: FontWeight.w800)),
                  ] else
                    const Text('لا توجد تقييمات للمتجر بعد', style: TextStyle(color: Colors.black54, fontSize: 12)),
                  const Spacer(),
                  TextButton.icon(onPressed: _busy ? null : _writeReview, icon: const Icon(Icons.rate_review_outlined, size: 18), label: const Text('قيّم المتجر')),
                ]),
              ]),
            ),
            const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 8), child: Text('منتجات المتجر', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: SupabaseService.client
                  .from('products')
                  .stream(primaryKey: ['id'])
                  .eq('store_id', widget.store.id)
                  .order('name')
                  .limit(2000),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()));
                if (snapshot.hasError) return const Padding(padding: EdgeInsets.all(16), child: Text('تعذر تحميل المنتجات.'));
                final products = (snapshot.data ?? const <Map<String, dynamic>>[])
                    .map((row) => CatalogDocument.fromSupabase(Map<String, dynamic>.from(row)))
                    .where((doc) => (doc.data['status'] ?? 'active') == 'active')
                    .toList();
                if (products.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text('لا توجد منتجات نشطة في هذا المتجر.', style: TextStyle(color: Colors.black54)));
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: products.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: .78),
                  itemBuilder: (context, i) => _StoreProductCard(
                    product: products[i],
                    onOpen: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailPage(product: products[i]))),
                    onAdd: () => _addToCart(products[i]),
                  ),
                );
              },
            ),
            const Divider(height: 32),
            _StoreReviews(loading: _reviewsLoading, items: _reviews?.items ?? const []),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _StoreProductCard extends StatelessWidget {
  const _StoreProductCard({required this.product, required this.onOpen, required this.onAdd});
  final CatalogDocument product;
  final VoidCallback onOpen;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final p = product.data;
    final imageUrl = (p['image_url'] ?? '').toString();
    final priceText = CurrencyService.instance.formatProduct(p);
    final stockBase = ProductUnit.stockBase(p);
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE3E8EF))),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: imageUrl.isEmpty
                ? Container(color: const Color(0xFFF1F6FF), child: const Icon(Icons.inventory_2_outlined, color: _blue, size: 34))
                : Image.network(imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: const Color(0xFFF1F6FF), child: const Icon(Icons.broken_image_outlined))),
          )),
          Padding(padding: const EdgeInsets.all(9), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p['name']?.toString() ?? 'منتج', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _navy, fontWeight: FontWeight.w800, fontSize: 13)),
            const SizedBox(height: 3),
            Text(priceText, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
            const SizedBox(height: 2),
            Text(stockBase > 0 ? 'المتوفر: ${ProductUnit.formatBase(p, stockBase)}' : 'نفد المخزون',
                style: TextStyle(color: stockBase > 0 ? Colors.black54 : Colors.red.shade700, fontSize: 11)),
            const SizedBox(height: 5),
            SizedBox(width: double.infinity, height: 30, child: FilledButton.icon(
              onPressed: stockBase > 0 ? onAdd : null,
              icon: const Icon(Icons.add_shopping_cart, size: 15),
              label: Text(stockBase > 0 ? 'أضف' : 'نفد', style: const TextStyle(fontSize: 12)),
              style: FilledButton.styleFrom(padding: EdgeInsets.zero),
            )),
          ])),
        ]),
      ),
    );
  }
}

class _StoreReviews extends StatelessWidget {
  const _StoreReviews({required this.loading, required this.items});
  final bool loading;
  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('تقييمات المتجر', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        const SizedBox(height: 6),
        if (loading)
          const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))
        else if (items.isEmpty)
          const Text('لا توجد تقييمات بعد.', style: TextStyle(color: Colors.black54))
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
