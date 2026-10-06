import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';

import '../core/app_sections.dart';
import '../services/currency_service.dart';
import '../services/location_service.dart';
import '../core/product_units.dart';
import '../services/supabase_service.dart';
import '../services/auth_service.dart';
import '../services/alfaeq_event_bus_service.dart';
import 'product_edit_page.dart';

class MerchantCenterPage extends StatefulWidget {
  const MerchantCenterPage({super.key});

  @override
  State<MerchantCenterPage> createState() => _MerchantCenterPageState();
}

class _MerchantCenterPageState extends State<MerchantCenterPage> {
  final _storeName = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _productName = TextEditingController();
  final _price = TextEditingController();
  final _stock = TextEditingController();
  String _sectionId = appSections.first.id;
  String? _selectedStoreId;
  String _saleUnit = 'piece';
  String _priceCurrency = 'YER';
  bool _saving = false;
  final _eventBus = AlfaeqEventBusService();

  @override
  void dispose() {
    _storeName.dispose(); _phone.dispose(); _address.dispose(); _productName.dispose(); _price.dispose(); _stock.dispose(); super.dispose();
  }

  User? get _user => SupabaseService.client.auth.currentUser;

  Future<void> _createStore() async {
    final user = _user;
    final name = _storeName.text.trim();
    final phone = _phone.text.trim();
    if (user == null || name.isEmpty || phone.isEmpty) { _message('أدخل اسم المتجر ورقم الهاتف.'); return; }
    setState(() => _saving = true);
    try {
      final position = await LocationService.requireCurrentPosition();
      final storeId = user.id + '-' + DateTime.now().microsecondsSinceEpoch.toString();
      await SupabaseService.client.from('stores').insert({
        'id': storeId,
        'name': name,
        'phone': phone,
        'address': _address.text.trim(),
        'section_id': _sectionId,
        'status': 'pending',
        'owner_id': user.id,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'location': {'latitude': position.latitude, 'longitude': position.longitude, 'source': 'device'},
        'metadata': {'created_by': user.id},
      });
      await _eventBus.publishStoreUpdated(storeId, data: {
        'ownerId': user.id,
        'status': 'pending',
        'sectionId': _sectionId,
        'name': name,
        'version': 'created',
      });
      await _eventBus.publishMerchantUpdated(user.id, data: {
        'storeId': storeId,
        'action': 'store.created',
        'version': 'store-$storeId',
      });
      _selectedStoreId = storeId;
      _storeName.clear(); _phone.clear(); _address.clear();
      _message('تم إرسال المتجر للمراجعة مع موقعه الجغرافي. لن يظهر للعملاء حتى يتم اعتماده.');
    } catch (e) {
      _message('تعذر حفظ المتجر: $e');
    } finally { if (mounted) setState(() => _saving = false); }
  }

  Future<void> _editStore(Map<String, dynamic> doc) async {
    final storeId = doc['id'].toString();
    final nameC = TextEditingController(text: '${doc['name'] ?? ''}');
    final phoneC = TextEditingController(text: '${doc['phone'] ?? ''}');
    final addressC = TextEditingController(text: '${doc['address'] ?? ''}');
    var section = (doc['section_id'] ?? appSections.first.id).toString();
    if (!appSections.any((s) => s.id == section)) section = appSections.first.id;
    double? lat = (doc['latitude'] as num?)?.toDouble();
    double? lng = (doc['longitude'] as num?)?.toDouble();

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('تعديل بيانات المتجر', style: TextStyle(fontWeight: FontWeight.w900)),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: nameC, decoration: const InputDecoration(labelText: 'اسم المتجر', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: phoneC, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: addressC, decoration: const InputDecoration(labelText: 'العنوان', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: section,
                  decoration: const InputDecoration(labelText: 'القسم', border: OutlineInputBorder()),
                  items: [for (final s in appSections) DropdownMenuItem(value: s.id, child: Text(s.title))],
                  onChanged: (v) { if (v != null) setLocal(() => section = v); },
                ),
                const SizedBox(height: 10),
                Row(children: [
                  const Icon(Icons.location_on_outlined, size: 18),
                  const SizedBox(width: 6),
                  Expanded(child: Text(lat != null && lng != null ? 'الموقع: ${lat!.toStringAsFixed(4)}, ${lng!.toStringAsFixed(4)}' : 'لم يُحدَّد الموقع')),
                  TextButton(
                    onPressed: () async {
                      try {
                        final p = await LocationService.requireCurrentPosition();
                        setLocal(() { lat = p.latitude; lng = p.longitude; });
                      } catch (_) {}
                    },
                    child: const Text('تحديث الموقع'),
                  ),
                ]),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ')),
            ],
          ),
        ),
      ),
    );
    if (saved != true) return;
    final name = nameC.text.trim();
    if (name.isEmpty) { _message('اسم المتجر مطلوب.'); return; }
    setState(() => _saving = true);
    try {
      await SupabaseService.client.from('stores').update({
        'name': name,
        'phone': phoneC.text.trim().isEmpty ? null : phoneC.text.trim(),
        'address': addressC.text.trim(),
        'section_id': section,
        if (lat != null && lng != null) 'latitude': lat,
        if (lat != null && lng != null) 'longitude': lng,
        if (lat != null && lng != null) 'location': {'latitude': lat, 'longitude': lng, 'source': 'device'},
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', storeId);
      await _eventBus.publishStoreUpdated(storeId, data: {
        'storeId': storeId,
        'action': 'store.updated',
        'version': 'store-$storeId-${DateTime.now().millisecondsSinceEpoch}',
      });
      _message('تم تحديث بيانات المتجر.');
    } catch (e) {
      _message('تعذر تحديث المتجر: $e');
    } finally { if (mounted) setState(() => _saving = false); }
  }

  Future<void> _createProduct() async {
    final user = _user; final storeId = _selectedStoreId; final name = _productName.text.trim(); final price = num.tryParse(_price.text.trim()); final stock = num.tryParse(_stock.text.trim());
    if (user == null || storeId == null || name.isEmpty) { _message('اختر متجراً وأدخل اسم الصنف.'); return; }
    if (price == null || price < 0 || stock == null || stock < 0) { _message('السعر والكمية يجب أن يكونا أرقاماً صحيحة وغير سالبة.'); return; }
    setState(() => _saving = true);
    try {
      final productId = user.id + '-' + DateTime.now().microsecondsSinceEpoch.toString();
      final unit = ProductUnit.fromId(_saleUnit);
      final stockBase = unit.toBase(stock).round();
      await SupabaseService.client.from('products').insert({
        'id': productId,
        'store_id': storeId,
        'owner_id': user.id,
        'name': name,
        'price': price,
        'currency': _priceCurrency,
        'stock': stock,
        'stock_base': stockBase,
        'sale_unit': _saleUnit,
        'unit_label': unit.label,
        'base_unit': unit.baseUnit,
        'unit_scale': unit.scale,
        'step_base': unit.defaultStepBase,
        'min_order_base': unit.defaultStepBase,
        'sold_quantity': 0,
        'sold_quantity_base': 0,
        'status': 'active',
        'metadata': {'created_by': user.id},
      });
      await _eventBus.publishProductCreated(productId, data: {
        'storeId': storeId,
        'ownerId': user.id,
        'stock': stock,
        'stockBase': stockBase,
        'price': price,
      });
      await _eventBus.publishInventoryChanged(productId, data: {
        'storeId': storeId,
        'ownerId': user.id,
        'stock': stock,
        'stockBase': stockBase,
        'reason': 'product.created',
      });
      _productName.clear(); _price.clear(); _stock.clear(); _message('تم حفظ الصنف بنجاح.');
    } catch (e) { _message('تعذر حفظ الصنف: $e'); }
    finally { if (mounted) setState(() => _saving = false); }
  }

  Future<void> _updateProduct(Map<String, dynamic> doc) async {
    final user = _user;
    if (user == null) { _message('يجب تسجيل الدخول أولاً.'); return; }
    final changed = await Navigator.push<bool>(context, MaterialPageRoute(
      builder: (_) => ProductEditPage(product: doc, ownerId: user.id, canChangeSection: false),
    ));
    if (changed == true) _message('تم حفظ تعديلات الصنف.');
  }

  void _message(String text) { if (!mounted) return; ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text))); }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    if (user == null) return const _Gate(message: 'يجب تسجيل الدخول إلى مركز التاجر.');
    return Directionality(textDirection: TextDirection.rtl, child: Scaffold(appBar: AppBar(title: const Text('مركز التاجر'), actions: [IconButton(onPressed: () => setState(() {}), icon: const Icon(Icons.refresh))]), body: ListView(padding: const EdgeInsets.all(16), children: [
      _HeroCard(), const SizedBox(height: 18), _SectionTitle(title: 'متاجري', icon: Icons.storefront_outlined), const SizedBox(height: 8), _stores(user.id), const SizedBox(height: 18), _SectionTitle(title: 'إضافة متجر', icon: Icons.add_business_outlined), const SizedBox(height: 8), _storeForm(), const SizedBox(height: 18), _SectionTitle(title: 'إضافة صنف', icon: Icons.add_box_outlined), const SizedBox(height: 8), _productForm(), const SizedBox(height: 18), _SectionTitle(title: 'كتالوج الأصناف', icon: Icons.inventory_2_outlined), const SizedBox(height: 8), _products(user.id)
    ])));
  }

  Widget _stores(String uid) => StreamBuilder<List<Map<String, dynamic>>>(stream: SupabaseService.client.from('stores').stream(primaryKey: ['id']).eq('owner_id', uid).limit(30), builder: (context, snapshot) {
    if (snapshot.hasError) return _error(snapshot.error.toString());
    if (snapshot.connectionState == ConnectionState.waiting) return const LinearProgressIndicator();
    final docs = snapshot.data ?? const <Map<String, dynamic>>[];
    if (docs.isEmpty) return const _EmptyCard(text: 'لم تنشئ متجراً بعد.');
    return Column(children: docs.map((doc) { final data = doc; final selected = _selectedStoreId == doc['id']; return Card(elevation: 0, child: ListTile(selected: selected, leading: CircleAvatar(backgroundColor: const Color(0xFFE7F3EE), child: Icon(Icons.storefront_outlined, color: Theme.of(context).colorScheme.primary)), title: Text('${data['name'] ?? 'متجر'}', style: const TextStyle(fontWeight: FontWeight.w900)), subtitle: Text('${data['status'] ?? 'pending'} • ${data['phone'] ?? ''}'), trailing: IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'تعديل المتجر', onPressed: () => _editStore(doc)), onTap: () => setState(() => _selectedStoreId = doc['id'].toString()))); }).toList());
  });

  Widget _storeForm() => Card(elevation: 0, child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
    DropdownButtonFormField<String>(initialValue: _sectionId, decoration: const InputDecoration(labelText: 'القسم'), items: [for (final section in appSections) DropdownMenuItem(value: section.id, child: Text(section.title))], onChanged: (value) { if (value != null) setState(() => _sectionId = value); }),
    TextField(controller: _storeName, decoration: const InputDecoration(labelText: 'اسم المتجر')), TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف')), TextField(controller: _address, decoration: const InputDecoration(labelText: 'العنوان')),
    const SizedBox(height: 8), const Align(alignment: Alignment.centerRight, child: Text('سيتم حفظ موقع المتجر الحالي تلقائياً عند الإرسال.', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))), const SizedBox(height: 12),
    SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _saving ? null : _createStore, icon: const Icon(Icons.my_location), label: const Text('إرسال المتجر مع الموقع للمراجعة')))
  ])));

  Widget _productForm() => Card(elevation: 0, child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [if (_selectedStoreId == null) const Align(alignment: Alignment.centerRight, child: Text('اختر متجراً أولاً من القائمة أعلاه.', style: TextStyle(color: Colors.black54))), TextField(controller: _productName, decoration: const InputDecoration(labelText: 'اسم الصنف')), TextField(controller: _price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'السعر')), const SizedBox(height: 12),
    DropdownButtonFormField<String>(initialValue: _priceCurrency, decoration: const InputDecoration(labelText: 'عملة السعر'), items: [for (final c in CurrencyService.supported) DropdownMenuItem(value: c, child: Text('${CurrencyService.labelFor(c)} (${CurrencyService.symbolFor(c)})'))], onChanged: (value) { if (value != null) setState(() => _priceCurrency = value); }), const SizedBox(height: 12),
    TextField(controller: _stock, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'المخزون بـ ${ProductUnit.fromId(_saleUnit).label}')),
    DropdownButtonFormField<String>(initialValue: _saleUnit, decoration: const InputDecoration(labelText: 'وحدة البيع'), items: [for (final u in ProductUnit.all) DropdownMenuItem(value: u.id, child: Text(u.label))], onChanged: (value) { if (value != null) setState(() => _saleUnit = value); }), const SizedBox(height: 12), SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _saving || _selectedStoreId == null ? null : _createProduct, icon: const Icon(Icons.add), label: const Text('حفظ الصنف')))])));

  Widget _products(String uid) => FutureBuilder<bool>(
        future: AuthService().hasOwnerClaim(),
        builder: (context, ownerSnapshot) {
          final isOwner = ownerSnapshot.data == true;
          return StreamBuilder<List<Map<String, dynamic>>>(
            stream: isOwner
                ? SupabaseService.client.from('products').stream(primaryKey: ['id']).limit(1000)
                : SupabaseService.client.from('products').stream(primaryKey: ['id']).eq('owner_id', uid).limit(100),
            builder: (context, snapshot) {
    if (snapshot.hasError) return _error(snapshot.error.toString());
    if (snapshot.connectionState == ConnectionState.waiting) return const LinearProgressIndicator();
    final docs = snapshot.data ?? const <Map<String, dynamic>>[]; final filtered = _selectedStoreId == null ? docs : docs.where((doc) => doc['store_id'] == _selectedStoreId).toList();
    if (filtered.isEmpty) return const _EmptyCard(text: 'لا توجد أصناف لهذا المتجر بعد.');
    return Column(children: filtered.map((doc) { final data = doc; return Card(elevation: 0, child: ListTile(leading: const Icon(Icons.inventory_2_outlined), title: Text('${data['name'] ?? 'صنف'}', style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text('مخزون: ${data['stock'] ?? 0} • حالة: ${data['status'] ?? 'active'}'), trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [Text(CurrencyService.instance.formatProduct(data), style: const TextStyle(fontWeight: FontWeight.w900)), TextButton(onPressed: () => _updateProduct(doc), child: const Text('تعديل'))]), onTap: () => _updateProduct(doc))); }).toList());
          });
        },
      );

  Widget _error(String text) => Card(elevation: 0, child: Padding(padding: const EdgeInsets.all(14), child: Text('تعذر تحميل البيانات.\n$text')));
}

class _HeroCard extends StatelessWidget { @override Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF0B6E4F), Color(0xFF124E78)]), borderRadius: BorderRadius.circular(26)), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.storefront, color: Colors.white, size: 34), SizedBox(height: 10), Text('مركز أعمالك في الفائق يمن', style: TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900)), SizedBox(height: 8), Text('أنشئ متجرك، أدر الكتالوج والأسعار والمخزون، وتابع جاهزية بياناتك للبيع داخل المنصة.', style: TextStyle(color: Colors.white70, height: 1.5))])); }
class _SectionTitle extends StatelessWidget { final String title; final IconData icon; const _SectionTitle({required this.title, required this.icon}); @override Widget build(BuildContext context) => Row(children: [Icon(icon, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 8), Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))]); }
class _EmptyCard extends StatelessWidget { final String text; const _EmptyCard({required this.text}); @override Widget build(BuildContext context) => Card(elevation: 0, child: Padding(padding: const EdgeInsets.all(18), child: Center(child: Text(text)))); }
class _Gate extends StatelessWidget { final String message; const _Gate({required this.message}); @override Widget build(BuildContext context) => Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(message)))); }
