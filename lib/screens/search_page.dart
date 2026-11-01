import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_sections.dart';
import '../services/currency_service.dart';
import '../services/catalog_service.dart';
import '../services/group_join_service.dart';
import '../services/smart_scan_service.dart';
import '../services/supabase_service.dart';
import '../services/unified_search_service.dart';
import '../services/visual_search_service.dart';
import 'cart_page.dart';
import 'barcode_scanner_page.dart';
import 'group_chat_page.dart';
import 'mini_programs_page.dart';
import 'product_detail_page.dart';
import 'store_detail_page.dart';
import 'wallet_qr_page.dart';

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
  final _visual = VisualSearchService();
  bool _visualBusy = false;
  Uint8List? _visualImage;
  VisualMatchResult? _visualResult;

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
    setState(() {
      _query = q;
      // A manual edit means the user moved on from the picture result.
      _visualResult = null;
      _visualImage = null;
    });
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
    await _handleScan(value);
  }

  /// Offers the three ways to look for a product by its picture: pick from the
  /// gallery, take a photo with the camera, or open the phone's Google Lens /
  /// image search so the picture can be looked up on the web.
  Future<void> _startVisualSearch() async {
    if (_visualBusy) return;
    final source = await showModalBottomSheet<VisualSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Row(children: [
                Icon(Icons.image_search, color: _navy),
                SizedBox(width: 10),
                Text('البحث عن منتج بالصورة', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: _navy)),
              ]),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('اختر مصدر الصورة، وسنبحث لك عن المنتج.', style: TextStyle(color: Colors.black54)),
            ),
            ListTile(
              leading: const CircleAvatar(backgroundColor: Color(0xFFF1F6FF), child: Icon(Icons.photo_library_outlined, color: _blue)),
              title: const Text('من الملفات / المعرض', style: TextStyle(fontWeight: FontWeight.w800)),
              onTap: () => Navigator.pop(context, VisualSource.gallery),
            ),
            ListTile(
              leading: const CircleAvatar(backgroundColor: Color(0xFFF1F6FF), child: Icon(Icons.photo_camera_outlined, color: _blue)),
              title: const Text('التقاط صورة بالكاميرا', style: TextStyle(fontWeight: FontWeight.w800)),
              onTap: () => Navigator.pop(context, VisualSource.camera),
            ),
            ListTile(
              leading: const CircleAvatar(backgroundColor: Color(0xFFF1F6FF), child: Icon(Icons.travel_explore, color: _blue)),
              title: const Text('البحث في جوجل عن الصورة', style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: const Text('يفتح بحث الصور في المتصفح'),
              onTap: () {
                Navigator.pop(context);
                _openGoogleLens();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return;
    await _pickAndSearch(source);
  }

  Future<void> _pickAndSearch(VisualSource source) async {
    setState(() => _visualBusy = true);
    try {
      final picked = await _visual.pick(source);
      if (picked == null) {
        if (mounted) setState(() => _visualBusy = false);
        return;
      }
      setState(() {
        _visualImage = picked.bytes;
        _visualResult = null;
      });
      final result = await _visual.search(picked.bytes, picked.extension);
      if (!mounted) return;
      setState(() {
        _visualResult = result;
        _visualBusy = false;
      });
      if (result.guess.isNotEmpty) {
        _controller.text = result.guess;
        setState(() => _query = result.guess);
      }
    } on VisualSearchException catch (e) {
      if (!mounted) return;
      setState(() => _visualBusy = false);
      _snack(e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _visualBusy = false);
      _snack('تعذّر البحث بالصورة: $e');
    }
  }

  Future<void> _openGoogleLens() async {
    // The camera-search deep link opens Google Lens directly on Android; the
    // web upload page is the fallback on every other platform.
    final lens = Uri.parse('https://lens.google.com/uploadbyurl');
    const fallback = 'https://www.google.com/imghp';
    final uri = Uri.tryParse(fallback)!;
    if (await canLaunchUrl(lens)) {
      await launchUrl(lens, mode: LaunchMode.externalApplication);
    } else if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      _snack('تعذّر فتح بحث جوجل.');
    }
  }

  void _clearVisual() {
    setState(() {
      _visualImage = null;
      _visualResult = null;
    });
  }

  /// Smart scan: classify the code and route it (pay / store / product / link
  /// / search) instead of always treating it as a barcode.
  Future<void> _handleScan(String value) async {
    SmartScanResult result;
    try {
      result = await const SmartScanService().resolve(value);
    } catch (_) {
      result = SmartScanResult(kind: SmartScanKind.search, raw: value);
    }
    if (!mounted) return;
    switch (result.kind) {
      case SmartScanKind.payment:
        await Navigator.push(context, MaterialPageRoute(builder: (_) => WalletQrPage(initialPayeeUid: result.uid)));
      case SmartScanKind.store:
        final id = result.storeId ?? '';
        try {
          final store = await CatalogService().storeById(id);
          if (!mounted) return;
          await Navigator.push(context, MaterialPageRoute(builder: (_) => StoreDetailPage(store: store)));
        } catch (e) {
          if (mounted) _snack('تعذر فتح المتجر: $e');
        }
      case SmartScanKind.product:
        final row = result.product;
        if (row != null) {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailPage(product: CatalogDocument.fromSupabase(row))));
        }
      case SmartScanKind.group:
        final code = result.groupCode ?? '';
        try {
          final threadId = await const GroupJoinService().joinByCode(code);
          if (!mounted) return;
          _snack('تم الانضمام إلى المجموعة ✅');
          await Navigator.push(context, MaterialPageRoute(builder: (_) => GroupChatPage(threadId: threadId, title: 'مجموعة')));
        } on StateError catch (e) {
          _snack(e.message);
        } catch (e) {
          _snack('تعذر الانضمام للمجموعة: $e');
        }
      case SmartScanKind.url:
        final url = result.url;
        if (url != null) {
          final uri = Uri.tryParse(url);
          if (uri != null && await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } else if (mounted) {
            _snack('تعذر فتح الرابط.');
          }
        }
      case SmartScanKind.search:
        _controller.text = value;
        _submit(value);
    }
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
                        tooltip: 'البحث بالصورة',
                        icon: const Icon(Icons.photo_camera_outlined, color: _navy),
                        onPressed: _visualBusy ? null : _startVisualSearch,
                      ),
                      IconButton(
                        tooltip: 'المسح الذكي',
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
            if (_visualBusy)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 10),
                  Text('جارٍ التعرّف على الصورة والبحث…', style: TextStyle(color: _navy, fontWeight: FontWeight.w700)),
                ]),
              )
            else if (_visualResult != null || _visualImage != null)
              _visualPanel(),
            if (_query.isEmpty && _visualResult == null)
              Expanded(child: _suggestionsView())
            else if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_searched && _results.isEmpty && _visualResult == null)
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

  Widget _visualPanel() {
    final guess = _visualResult?.guess ?? '';
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE3E8EF)),
      ),
      child: Row(
        children: [
          if (_visualImage != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(_visualImage!, width: 56, height: 56, fit: BoxFit.cover),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('الصورة المبحوث عنها', style: TextStyle(color: Colors.black45, fontSize: 12)),
                const SizedBox(height: 2),
                Text(
                  guess.isEmpty ? 'لم يتمكّن الذكاء من تحديد الاسم' : 'تعرّفنا على: $guess',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _navy, fontWeight: FontWeight.w900, fontSize: 14),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'بحث جوجل',
            icon: const Icon(Icons.travel_explore, color: _blue),
            onPressed: _openGoogleLens,
          ),
          IconButton(
            tooltip: 'إزالة',
            icon: const Icon(Icons.close, color: Colors.black38),
            onPressed: _clearVisual,
          ),
        ],
      ),
    );
  }

  Widget _resultsView() {
    final r = _results;
    final visual = _visualResult;
    final products = visual != null ? visual.products : r.products;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 28),
      children: [
        if (visual != null && visual.hasGuess) ...[
          _sectionHeader('نتائج الصورة', products.length),
        ],
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
        if (products.isNotEmpty) ...[
          if (visual == null) _sectionHeader('المنتجات', products.length),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: products.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: .78),
            itemBuilder: (context, i) => _ProductResultCard(product: products[i], onAdd: () => _addToCart(products[i])),
          ),
        ] else if (visual != null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Column(children: [
              Icon(Icons.search_off, size: 54, color: Colors.black26),
              SizedBox(height: 12),
              Text('لم نجد منتجاً مطابقاً للصورة.', style: TextStyle(color: _navy, fontWeight: FontWeight.w800)),
              SizedBox(height: 6),
              Text('جرّب صورة أوضح، أو ابحث بالاسم، أو استخدم «بحث جوجل».', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
            ]),
          ),
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
