import 'package:flutter/material.dart';

import '../core/app_sections.dart';
import '../core/mini_programs_prefs.dart';
import '../services/currency_service.dart';
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
/// The launcher adds search, favorites and a "recently used" row.
class MiniProgramsPage extends StatefulWidget {
  const MiniProgramsPage({super.key});

  @override
  State<MiniProgramsPage> createState() => _MiniProgramsPageState();
}

class _MiniProgramsPageState extends State<MiniProgramsPage> {
  final _search = TextEditingController();
  String _query = '';
  List<String> _recent = const [];
  List<String> _favorites = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final recent = await MiniProgramsPrefs.recent();
    final favorites = await MiniProgramsPrefs.favorites();
    if (mounted) setState(() { _recent = recent; _favorites = favorites; });
  }

  List<AppSection> get _filtered {
    final q = _query.trim();
    if (q.isEmpty) return appSections;
    return appSections
        .where((s) => s.title.contains(q) || s.subtitle.contains(q))
        .toList();
  }

  List<AppSection> _sectionsFor(List<String> ids) {
    final byId = {for (final s in appSections) s.id: s};
    return [for (final id in ids) if (byId[id] != null) byId[id]!];
  }

  List<AppSection> get _recentSections => _sectionsFor(_recent);
  List<AppSection> get _favoriteSections => _sectionsFor(_favorites);

  Future<void> _open(AppSection section) async {
    await MiniProgramsPrefs.markUsed(section.id);
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => MiniProgramPage(section: section)));
  }

  Future<void> _toggleFavorite(AppSection section) async {
    await MiniProgramsPrefs.toggleFavorite(section.id);
    await _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final favorites = _favoriteSections;
    final recents = _recentSections;
    final filtered = _filtered;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('البرامج المصغّرة', style: TextStyle(fontWeight: FontWeight.w900))),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('البرامج المصغّرة', style: TextStyle(color: _navy, fontSize: 26, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            const Text('افتح خدمة الفائق كتطبيق مصغّر مستقل: تسوّق، اطلب، واحجز دون مغادرة المنصة.', style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 14),
            TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v.trim()),
              decoration: InputDecoration(
                hintText: 'ابحث عن خدمة...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
              ),
            ),
            if (_query.isEmpty && favorites.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Text('المفضلة', style: TextStyle(color: _navy, fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              _miniGrid(favorites, onLongPress: _toggleFavorite),
            ],
            if (_query.isEmpty && recents.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Text('المستخدمة مؤخراً', style: TextStyle(color: _navy, fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              _miniGrid(recents, onLongPress: _toggleFavorite),
            ],
            const SizedBox(height: 18),
            Text(_query.isEmpty ? 'كل البرامج' : 'نتائج البحث', style: const TextStyle(color: _navy, fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            if (filtered.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: Text('لا توجد خدمة مطابقة لبحثك.', style: TextStyle(color: Colors.black54))),
              )
            else
              _miniGrid(filtered, onLongPress: _toggleFavorite),
          ],
        ),
      ),
    );
  }

  Widget _miniGrid(List<AppSection> sections, {required Future<void> Function(AppSection) onLongPress}) => GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: sections.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: .92),
        itemBuilder: (context, i) {
          final section = sections[i];
          return _MiniProgramCard(
            section: section,
            isFavorite: _favorites.contains(section.id),
            onTap: () => _open(section),
            onLongPress: () => onLongPress(section),
          );
        },
      );
}

class _MiniProgramCard extends StatelessWidget {
  final AppSection section;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _MiniProgramCard({required this.section, this.isFavorite = false, required this.onTap, required this.onLongPress});

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        onLongPress: onLongPress,
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
              Stack(
                clipBehavior: Clip.none,
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
                  if (isFavorite)
                    const Positioned(
                      top: -4,
                      left: -4,
                      child: Icon(Icons.star, color: Colors.amber, size: 16),
                    ),
                ],
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
  int _loaded = 0;
  int _total = 0;
  late final Future<CatalogPage> _productsFuture;

  @override
  void initState() {
    super.initState();
    // PostgREST caps each response at 1000 rows; page through the section.
    _productsFuture = CatalogService().activeProductsPaged(
      sectionId: widget.section.id,
      onProgress: (loaded, total) {
        if (mounted) setState(() { _loaded = loaded; _total = total; });
      },
    );
  }

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
            FutureBuilder<CatalogPage>(
              future: _productsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Column(children: [
                    const Center(child: Padding(padding: EdgeInsets.all(28), child: CircularProgressIndicator())),
                    if (_total > 0) Text('جارٍ تحميل الأصناف… $_loaded من $_total', style: const TextStyle(color: Colors.black54)),
                  ]);
                }
                if (snapshot.hasError) return const Text('تعذر تحميل الأصناف.');
                final page = snapshot.data;
                var products = page?.items ?? const <CatalogDocument>[];
                final total = page?.total ?? products.length;
                if (_query.isNotEmpty) {
                  final q = _query.trim().toLowerCase();
                  products = products.where((p) {
                    final name = (p.data['name'] ?? '').toString().toLowerCase();
                    final barcode = (p.data['metadata'] is Map ? (p.data['metadata'] as Map)['barcode'] : null)?.toString().toLowerCase() ?? '';
                    return name.contains(q) || barcode.contains(q);
                  }).toList();
                }
                if (products.isEmpty) {
                  return const Text('لا توجد أصناف نشطة في هذا البرنامج بعد.', style: TextStyle(color: Colors.black54));
                }
                // shrinkWrap grid inside a ListView: cap the render, refine by search.
                const maxCards = 300;
                final visible = products.take(maxCards).toList();
                return Column(children: [
                  Text('إجمالي الأصناف: $total', style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: visible.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: .78),
                    itemBuilder: (context, i) => _ProgramProductCard(product: visible[i], onAdd: () => _addToCart(visible[i])),
                  ),
                  if (products.length > visible.length)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text('يُعرض أول ${visible.length} من ${products.length} صنفًا — استخدم البحث للوصول إلى الباقي.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
                    ),
                ]);
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
    final priceText = CurrencyService.instance.formatProduct(p);
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
