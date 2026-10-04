import 'package:flutter/material.dart';

import '../core/app_sections.dart';
import '../services/catalog_service.dart';
import '../services/supabase_service.dart';
import 'cart_page.dart';

const _blue = Color(0xFF0D6EFD);
const _navy = Color(0xFF0A2540);

IconData miniProgramIcon(String name) {
  switch (name) {
    case 'storefront': return Icons.storefront_outlined;
    case 'restaurant': return Icons.restaurant_outlined;
    case 'pharmacy': return Icons.local_pharmacy_outlined;
    case 'beauty': return Icons.face_retouching_natural;
    case 'construction': return Icons.construction_outlined;
    case 'car': return Icons.directions_car_outlined;
    case 'flight': return Icons.flight_takeoff_outlined;
    case 'hotel': return Icons.hotel_outlined;
    case 'account_balance': return Icons.account_balance_outlined;
    case 'handyman': return Icons.handyman_outlined;
    case 'devices': return Icons.devices_outlined;
    case 'home': return Icons.home_work_outlined;
    case 'work': return Icons.work_outline;
    case 'school': return Icons.school_outlined;
    case 'medical': return Icons.medical_services_outlined;
    default: return Icons.explore_outlined;
  }
}

/// WeChat-style mini-program launcher: every platform section is a compact,
/// self-contained "app" that opens with its own header and product surface.
class MiniProgramsPage extends StatelessWidget {
  const MiniProgramsPage({super.key});

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: const Text('البرامج المصغّرة', style: TextStyle(fontWeight: FontWeight.w900))),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('البرامج المصغّرة', style: TextStyle(color: _navy, fontSize: 26, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              const Text('افتح خدمة الفائق كتطبيق مصغّر مستقل: تسوّق، اطلب، واحجز دون مغادرة المنصة.', style: TextStyle(color: Colors.black54)),
              const SizedBox(height: 18),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: appSections.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: .92),
                itemBuilder: (context, i) {
                  final section = appSections[i];
                  return _MiniProgramCard(section: section);
                },
              ),
            ],
          ),
        ),
      );
}

class _MiniProgramCard extends StatelessWidget {
  final AppSection section;
  const _MiniProgramCard({required this.section});

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MiniProgramPage(section: section))),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE3E8EF)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFE7F0FF), Color(0xFFDCE9FF)]),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(miniProgramIcon(section.icon), color: _blue, size: 28),
              ),
              const SizedBox(height: 8),
              Text(section.title, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _navy, fontSize: 11.5, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      );
}

/// A single mini-program surface: header, search, sibling-program switcher and
/// a product grid for the program's section.
class MiniProgramPage extends StatefulWidget {
  final AppSection section;
  const MiniProgramPage({super.key, required this.section});
  @override
  State<MiniProgramPage> createState() => _MiniProgramPageState();
}

class _MiniProgramPageState extends State<MiniProgramPage> {
  final _search = TextEditingController();
  String _query = '';

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
  Widget build(BuildContext context) {
    final section = widget.section;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(section.title, style: const TextStyle(fontWeight: FontWeight.w900)),
          actions: [
            IconButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartPage())),
              tooltip: 'السلة',
              icon: const Icon(Icons.shopping_cart_outlined),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFE7F3EE), Color(0xFFEAF2F8)]),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(17)),
                    child: Icon(miniProgramIcon(section.icon), color: _blue, size: 31),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(section.title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 3),
                      Text(section.subtitle, style: const TextStyle(color: Colors.black54, height: 1.3)),
                    ]),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v.trim()),
              decoration: InputDecoration(
                hintText: 'ابحث في ${section.title}...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                reverse: true,
                itemCount: appSections.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final s = appSections[i];
                  return ChoiceChip(
                    avatar: Icon(miniProgramIcon(s.icon), size: 16),
                    label: Text(s.title, style: const TextStyle(fontSize: 12)),
                    selected: s.id == section.id,
                    onSelected: (_) {
                      if (s.id != section.id) {
                        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => MiniProgramPage(section: s)));
                      }
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 18),
            const Text('الأصناف المتاحة', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
            const SizedBox(height: 9),
            FutureBuilder<List<CatalogDocument>>(
              future: const CatalogService().activeProducts(limit: 500),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: Padding(padding: EdgeInsets.all(28), child: CircularProgressIndicator()));
                }
                if (snapshot.hasError) return const Text('تعذر تحميل الأصناف.');
                var products = snapshot.data ?? const <CatalogDocument>[];
                products = products.where((p) => (p.data['section_id'] ?? '').toString() == section.id).toList();
                if (_query.isNotEmpty) {
                  products = products.where((p) => (p.data['name'] ?? '').toString().contains(_query)).toList();
                }
                if (products.isEmpty) {
                  return const Text('لا توجد أصناف نشطة في هذا البرنامج بعد.', style: TextStyle(color: Colors.black54));
                }
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: products.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: .78),
                  itemBuilder: (context, i) => _ProgramProductCard(product: products[i], onAdd: () => _addToCart(products[i])),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgramProductCard extends StatelessWidget {
  final CatalogDocument product;
  final VoidCallback onAdd;
  const _ProgramProductCard({required this.product, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final p = product.data;
    final imageUrl = (p['image_url'] ?? '').toString();
    final price = p['price'];
    final priceText = price is num ? '${price.toStringAsFixed(0)} ${p['currency'] ?? 'YER'}' : 'عند الطلب';
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE3E8EF)),
      ),
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
                Text(p['name']?.toString() ?? 'صنف', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _navy, fontWeight: FontWeight.w800, fontSize: 13)),
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
