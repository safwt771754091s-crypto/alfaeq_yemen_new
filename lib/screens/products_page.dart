import 'package:flutter/material.dart';

import '../core/app_sections.dart';
import '../services/catalog_service.dart';
import '../services/supabase_service.dart';
import 'cart_page.dart';
import 'mini_programs_page.dart';

const _blue = Color(0xFF0D6EFD);
const _navy = Color(0xFF0A2540);

/// WeChat "Channels"-style shop feed: browse every active product across all
/// sections with a search box and category filter chips.
class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});
  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  final _search = TextEditingController();
  String _query = '';
  String _sectionId = 'all';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _addToCart(CatalogDocument product) async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يجب تسجيل الدخول أولاً.')));
      return;
    }
    final name = (product.data['name'] ?? 'صنف').toString();
    try {
      await const CatalogService().addToCart(user.id, product);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تمت إضافة «$name» إلى السلة.')));
    } on StateError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تحديث السلة: $e')));
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('المنتجات', style: TextStyle(fontWeight: FontWeight.w900)),
            actions: [
              IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartPage())), tooltip: 'السلة', icon: const Icon(Icons.shopping_cart_outlined)),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              TextField(
                controller: _search,
                onChanged: (v) => setState(() => _query = v.trim()),
                decoration: InputDecoration(
                  hintText: 'ابحث عن منتج...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  itemCount: appSections.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final isAll = i == 0;
                    final id = isAll ? 'all' : appSections[i - 1].id;
                    final label = isAll ? 'الكل' : appSections[i - 1].title;
                    final icon = isAll ? Icons.apps : miniProgramIcon(appSections[i - 1].icon);
                    return ChoiceChip(
                      avatar: Icon(icon, size: 16),
                      label: Text(label, style: const TextStyle(fontSize: 12)),
                      selected: _sectionId == id,
                      onSelected: (_) => setState(() => _sectionId = id),
                    );
                  },
                ),
              ),
              const SizedBox(height: 18),
              FutureBuilder<List<CatalogDocument>>(
                future: const CatalogService().activeProducts(limit: 500),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: Padding(padding: EdgeInsets.all(28), child: CircularProgressIndicator()));
                  }
                  if (snapshot.hasError) return const Text('تعذر تحميل المنتجات.');
                  var products = snapshot.data ?? const <CatalogDocument>[];
                  if (_sectionId != 'all') {
                    products = products.where((p) => (p.data['section_id'] ?? '').toString() == _sectionId).toList();
                  }
                  if (_query.isNotEmpty) {
                    products = products.where((p) => (p.data['name'] ?? '').toString().contains(_query)).toList();
                  }
                  if (products.isEmpty) {
                    return const Text('لا توجد منتجات مطابقة.', style: TextStyle(color: Colors.black54));
                  }
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: products.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: .78),
                    itemBuilder: (context, i) => _ProductCard(product: products[i], onAdd: () => _addToCart(products[i])),
                  );
                },
              ),
            ],
          ),
        ),
      );
}

class _ProductCard extends StatelessWidget {
  final CatalogDocument product;
  final VoidCallback onAdd;
  const _ProductCard({required this.product, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final p = product.data;
    final imageUrl = (p['image_url'] ?? '').toString();
    final price = p['price'];
    final priceText = price is num ? '${price.toStringAsFixed(0)} ${p['currency'] ?? 'YER'}' : 'عند الطلب';
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE3E8EF))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: imageUrl.isEmpty
                  ? Container(color: const Color(0xFFF1F6FF), child: const Icon(Icons.inventory_2_outlined, color: _blue, size: 34))
                  : Image.network(imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: const Color(0xFFF1F6FF), child: const Icon(Icons.broken_image_outlined))),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p['name']?.toString() ?? 'منتج', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _navy, fontWeight: FontWeight.w800, fontSize: 13)),
                const SizedBox(height: 3),
                Text(priceText, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                const SizedBox(height: 5),
                SizedBox(
                  width: double.infinity,
                  height: 30,
                  child: FilledButton.icon(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add_shopping_cart, size: 15),
                    label: const Text('أضف', style: TextStyle(fontSize: 12)),
                    style: FilledButton.styleFrom(padding: EdgeInsets.zero),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
