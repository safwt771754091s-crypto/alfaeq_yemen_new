import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_sections.dart';
import '../services/currency_service.dart';
import '../services/catalog_service.dart';
import '../services/supabase_service.dart';
import '../services/unified_search_service.dart';
import 'cart_page.dart';
import 'barcode_scanner_page.dart';
import 'mini_programs_page.dart';

const _blue = Color(0xFF0D6EFD);
const _navy = Color(0xFF0A2540);
const _surface = Color(0xFFF5F7FA);

/// WeChat-style unified search: one box across products, stores, and services.
class SearchPage extends StatefulWidget {
  final String? initialQuery;
  const SearchPage({super.key, this.initialQuery});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  final _service = const UnifiedSearchService();
  Timer? _debounce;
  SearchResults _results = const SearchResults();
  bool _loading = false;
  bool _searched = false;
  String _query = '';

  static const _suggestions = ['أرز', 'ماء', 'خبز', 'سكر', 'صيدلية', 'مطعم', 'هاتف', 'عقار'];

  @override
  void initState() {
    super.initState();
    final initial = widget.initialQuery?.trim() ?? '';
    if (initial.isNotEmpty) {
      _controller.text = initial;
      _run(initial);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    setState(() => _query = q);
    if (q.isEmpty) {
      setState(() {
        _results = const SearchResults();
        _searched = false;
        _loading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _run(q));
  }

  Future<void> _run(String q) async {
    setState(() => _loading = true);
    try {
      final results = await _service.search(q);
      if (!mounted || _query != q.trim()) return;
      setState(() {
        _results = results;
        _loading = false;
        _searched = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _searched = true;
        _results = const SearchResults();
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر البحث: $e')));
    }
  }

  void _submit(String value) {
    _debounce?.cancel();
    final q = value.trim();
    setState(() => _query = q);
    if (q.isNotEmpty) _run(q);
  }

  Future<void> _scanBarcode() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
    );
    final value = code?.trim();
    if (value == null || value.isEmpty || !mounted) return;
    _controller.text = value;
    _submit(value);
  }

  Future<void> _addToCart(Map<String, dynamic> row) async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) {
      _snack('يجب تسجيل الدخول أولاً.');
      return;
    }
    final product = CatalogDocument.fromSupabase(Map<String, dynamic>.from(row));
    final name = (row['name'] ?? 'صنف').toString();
    try {
      await const CatalogService().addToCart(user.id, product);
      _snack('تمت إضافة «$name» إلى السلة.');
    } on StateError catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('تعذر تحديث السلة: $e');
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _surface,
        appBar: AppBar(
          backgroundColor: _navy,
          foregroundColor: Colors.white,
          title: const Text('البحث', style: TextStyle(fontWeight: FontWeight.w900)),
          actions: [
            IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartPage())), tooltip: 'السلة', icon: const Icon(Icons.shopping_cart_outlined)),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: TextField(
                controller: _controller,
                autofocus: widget.initialQuery == null,
                textInputAction: TextInputAction.search,
                onChanged: _onChanged,
                onSubmitted: _submit,
                decoration: InputDecoration(
                  hintText: 'ابحث عن منتج، متجر، أو خدمة…',
                  prefixIcon: const Icon(Icons.search, color: _navy),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'مسح الباركود',
                        icon: const Icon(Icons.qr_code_scanner, color: _navy),
                        onPressed: _scanBarcode,
                      ),
                      if (_query.isNotEmpty)
                        IconButton(icon: const Icon(Icons.close), onPressed: () { _controller.clear(); _onChanged(''); }),
                    ],
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
                ),
              ),
            ),
            if (_query.isEmpty)
              Expanded(child: _suggestionsView())
            else if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_searched && _results.isEmpty)
              const Expanded(child: _EmptySearch())
            else
              Expanded(child: _resultsView()),
          ],
        ),
      ),
    );
  }

  Widget _suggestionsView() => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('بحث سريع', style: TextStyle(color: _navy, fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _suggestions.map((s) => ActionChip(
                  avatar: const Icon(Icons.search, size: 15),
                  label: Text(s),
                  onPressed: () { _controller.text = s; _submit(s); },
                )).toList(),
          ),
        ],
      );

  Widget _resultsView() {
    final r = _results;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 28),
      children: [
        if (r.sections.isNotEmpty) ...[
          _sectionHeader('الخدمات', r.sections.length),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFFE3E8EF))),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: r.sections.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, crossAxisSpacing: 4, mainAxisSpacing: 14, childAspectRatio: .82),
                itemBuilder: (context, i) {
                  final section = r.sections[i];
                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MiniProgramPage(section: section))),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Container(
                        width: 50, height: 50,
                        decoration: BoxDecoration(color: const Color(0xFFF1F6FF), borderRadius: BorderRadius.circular(16)),
                        child: Icon(miniProgramIcon(section.icon), color: _blue, size: 26),
                      ),
                      const SizedBox(height: 7),
                      Text(section.title, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _navy, fontSize: 11.5, fontWeight: FontWeight.w800)),
                    ]),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (r.stores.isNotEmpty) ...[
          _sectionHeader('المتاجر', r.stores.length),
          ...r.stores.map(_storeTile),
          const SizedBox(height: 16),
        ],
        if (r.products.isNotEmpty) ...[
          _sectionHeader('المنتجات', r.products.length),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: r.products.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: .78),
            itemBuilder: (context, i) => _ProductResultCard(product: r.products[i], onAdd: () => _addToCart(r.products[i])),
          ),
        ],
      ],
    );
  }

  Widget _storeTile(Map<String, dynamic> store) {
    final name = (store['name'] ?? 'متجر').toString();
    final address = (store['address'] ?? '').toString();
    final sectionId = (store['section_id'] ?? '').toString();
    final section = _sectionById(sectionId);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFE3E8EF))),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFF1F6FF),
          child: Icon(section != null ? miniProgramIcon(section.icon) : Icons.storefront_outlined, color: _blue),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w900, color: _navy)),
        subtitle: Text(address.isEmpty ? (section?.title ?? 'متجر معتمد') : address, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_left, color: Colors.black26),
        onTap: () {
          final target = section;
          if (target != null) {
            Navigator.push(context, MaterialPageRoute(builder: (_) => MiniProgramPage(section: target)));
          }
        },
      ),
    );
  }

  Widget _sectionHeader(String title, int count) => Padding(
        padding: const EdgeInsets.only(bottom: 8, right: 2, top: 4),
        child: Row(children: [
          Text(title, style: const TextStyle(color: _navy, fontSize: 17, fontWeight: FontWeight.w900)),
          const SizedBox(width: 6),
          Text('($count)', style: const TextStyle(color: Colors.black38, fontWeight: FontWeight.w700)),
        ]),
      );

  AppSection? _sectionById(String id) {
    for (final section in appSections) {
      if (section.id == id) return section;
    }
    return null;
  }
}

class _ProductResultCard extends StatelessWidget {
  final Map<String, dynamic> product;
  final VoidCallback onAdd;
  const _ProductResultCard({required this.product, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final p = product;
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

class _EmptySearch extends StatelessWidget {
  const _EmptySearch();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.search_off, size: 64, color: Colors.black26),
            SizedBox(height: 14),
            Text('لا توجد نتائج مطابقة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _navy)),
            SizedBox(height: 6),
            Text('جرّب كلمة أخرى أو تصفّح الخدمات.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
          ]),
        ),
      );
}
