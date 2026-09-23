import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/app_sections.dart';
import '../services/location_service.dart';
import '../core/product_units.dart';
import '../services/supabase_service.dart';

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
  bool _saving = false;

  @override
  void dispose() {
    _storeName.dispose(); _phone.dispose(); _address.dispose(); _productName.dispose(); _price.dispose(); _stock.dispose(); super.dispose();
  }

  User? get _user => FirebaseAuth.instance.currentUser;

  Future<void> _createStore() async {
    final user = _user;
    final name = _storeName.text.trim();
    final phone = _phone.text.trim();
    if (user == null || name.isEmpty || phone.isEmpty) { _message('أدخل اسم المتجر ورقم الهاتف.'); return; }
    if (!SupabaseService.isInitialized) { _message('قاعدة بيانات الإنتاج غير متاحة حالياً.'); return; }
    setState(() => _saving = true);
    try {
      final position = await LocationService.requireCurrentPosition();
      final storeId = '${user.uid}_${DateTime.now().microsecondsSinceEpoch}';
      await SupabaseService.client.from('stores').insert({
        'id': storeId, 'name': name, 'phone': phone, 'address': _address.text.trim(),
        'section_id': _sectionId, 'status': 'pending', 'owner_id': user.uid,
        'latitude': position.latitude, 'longitude': position.longitude,
        'location': {'latitude': position.latitude, 'longitude': position.longitude, 'source': 'device'},
        'metadata': {'created_by': user.uid, 'location_source': 'device'},
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      if (!mounted) return;
      setState(() => _selectedStoreId = storeId);
      _storeName.clear(); _phone.clear(); _address.clear();
      _message('تم حفظ المتجر في قاعدة الإنتاج وإرساله للمراجعة.');
    } catch (e) { _message('تعذر حفظ المتجر: $e'); }
    finally { if (mounted) setState(() => _saving = false); }
  }

  Future<void> _createProduct() async {
    final user = _user; final storeId = _selectedStoreId;
    final name = _productName.text.trim();
    final price = num.tryParse(_price.text.trim());
    final stock = num.tryParse(_stock.text.trim());
    if (user == null || storeId == null || name.isEmpty) { _message('اختر متجراً وأدخل اسم الصنف.'); return; }
    if (price == null || price < 0 || stock == null || stock < 0) { _message('السعر والكمية يجب أن يكونا أرقاماً غير سالبة.'); return; }
    if (!SupabaseService.isInitialized) { _message('قاعدة بيانات الإنتاج غير متاحة حالياً.'); return; }
    setState(() => _saving = true);
    try {
      final unit = ProductUnit.fromId(_saleUnit);
      await SupabaseService.client.from('products').insert({
        'id': '${storeId}_${DateTime.now().microsecondsSinceEpoch}', 'store_id': storeId, 'owner_id': user.uid,
        'section_id': _sectionId, 'name': name, 'price': price, 'currency': 'YER',
        'stock': stock, 'stock_base': unit.toBase(stock).round(), 'sale_unit': unit.id,
        'unit_label': unit.label, 'base_unit': unit.baseUnit, 'unit_scale': unit.scale,
        'step_base': unit.defaultStepBase, 'min_order_base': unit.defaultStepBase,
        'sold_quantity': 0, 'sold_quantity_base': 0, 'status': 'active',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      _productName.clear(); _price.clear(); _stock.clear();
      _message('تم حفظ الصنف في كتالوج الإنتاج.');
      if (mounted) setState(() {});
    } catch (e) { _message('تعذر حفظ الصنف: $e'); }
    finally { if (mounted) setState(() => _saving = false); }
  }

  Future<void> _updateProduct(Map<String, dynamic> data) async {
    final id = '${data['id'] ?? ''}';
    if (id.isEmpty) return;
    final priceController = TextEditingController(text: '${data['price'] ?? ''}');
    final stockController = TextEditingController(text: '${data['stock'] ?? ''}');
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${data['name'] ?? 'تعديل الصنف'}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: priceController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'السعر')),
          TextField(controller: stockController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'المخزون')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ')),
        ],
      ),
    );
    final price = num.tryParse(priceController.text.trim());
    final stock = num.tryParse(stockController.text.trim());
    priceController.dispose(); stockController.dispose();
    if (result != true) return;
    if (price == null || price < 0 || stock == null || stock < 0) { _message('السعر والمخزون غير صالحين.'); return; }
    if (!SupabaseService.isInitialized) { _message('قاعدة بيانات الإنتاج غير متاحة حالياً.'); return; }
    try {
      final unit = ProductUnit.fromProduct(data);
      await SupabaseService.client.from('products').update({
        'price': price, 'stock': stock, 'stock_base': unit.toBase(stock).round(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', id).eq('owner_id', _user!.uid);
      _message('تم تحديث السعر والمخزون في قاعدة الإنتاج.');
      if (mounted) setState(() {});
    } catch (e) { _message('تعذر تحديث الصنف: $e'); }
  }

  void _message(String text) { if (!mounted) return; ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text))); }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    if (user == null) return const _Gate(message: 'يجب تسجيل الدخول إلى مركز التاجر.');
    return Directionality(textDirection: TextDirection.rtl, child: Scaffold(appBar: AppBar(title: const Text('مركز التاجر'), actions: [IconButton(onPressed: () => setState(() {}), icon: const Icon(Icons.refresh))]), body: ListView(padding: const EdgeInsets.all(16), children: [
      _HeroCard(), const SizedBox(height: 18), _SectionTitle(title: 'متاجري', icon: Icons.storefront_outlined), const SizedBox(height: 8), _stores(user.uid), const SizedBox(height: 18), _SectionTitle(title: 'إضافة متجر', icon: Icons.add_business_outlined), const SizedBox(height: 8), _storeForm(), const SizedBox(height: 18), _SectionTitle(title: 'إضافة صنف', icon: Icons.add_box_outlined), const SizedBox(height: 8), _productForm(), const SizedBox(height: 18), _SectionTitle(title: 'كتالوج الأصناف', icon: Icons.inventory_2_outlined), const SizedBox(height: 8), _products(user.uid)
    ])));
  }

  Widget _stores(String uid) {
    if (!SupabaseService.isInitialized) return const _EmptyCard(text: 'قاعدة بيانات الإنتاج غير متاحة حالياً.');
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: SupabaseService.client.from('stores').select().eq('owner_id', uid).order('created_at', ascending: false).limit(30),
      builder: (context, snapshot) {
        if (snapshot.hasError) return _error(snapshot.error.toString());
        if (snapshot.connectionState == ConnectionState.waiting) return const LinearProgressIndicator();
        final docs = (snapshot.data ?? const <Map<String, dynamic>>[]).map((e) => Map<String, dynamic>.from(e)).toList();
        if (docs.isEmpty) return const _EmptyCard(text: 'لم تنشئ متجراً بعد.');
        final children = <Widget>[];
        for (final data in docs) {
          final id = '\${data['id'] ?? ''}';
          final selected = _selectedStoreId == id;
          children.add(Card(
            elevation: 0,
            child: ListTile(
              selected: selected,
              leading: CircleAvatar(
                backgroundColor: const Color(0xFFE7F3EE),
                child: Icon(Icons.storefront_outlined, color: Theme.of(context).colorScheme.primary),
              ),
              title: Text('\${data['name'] ?? 'متجر'}', style: const TextStyle(fontWeight: FontWeight.w900)),
              subtitle: Text('\${data['status'] ?? 'pending'} • \${data['phone'] ?? ''}'),
              trailing: selected ? const Icon(Icons.check_circle) : const Icon(Icons.chevron_left),
              onTap: () => setState(() => _selectedStoreId = id),
            ),
          ));
        }
        return Column(children: children);
      },
    );
  }

  Widget _storeForm() => Card(elevation: 0, child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
    DropdownButtonFormField<String>(initialValue: _sectionId, decoration: const InputDecoration(labelText: 'القسم'), items: [for (final section in appSections) DropdownMenuItem(value: section.id, child: Text(section.title))], onChanged: (value) { if (value != null) setState(() => _sectionId = value); }),
    TextField(controller: _storeName, decoration: const InputDecoration(labelText: 'اسم المتجر')), TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف')), TextField(controller: _address, decoration: const InputDecoration(labelText: 'العنوان')),
    const SizedBox(height: 8), const Align(alignment: Alignment.centerRight, child: Text('سيتم حفظ موقع المتجر الحالي تلقائياً عند الإرسال.', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))), const SizedBox(height: 12),
    SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _saving ? null : _createStore, icon: const Icon(Icons.my_location), label: const Text('إرسال المتجر مع الموقع للمراجعة')))
  ])));

  Widget _productForm() => Card(elevation: 0, child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [if (_selectedStoreId == null) const Align(alignment: Alignment.centerRight, child: Text('اختر متجراً أولاً من القائمة أعلاه.', style: TextStyle(color: Colors.black54))), TextField(controller: _productName, decoration: const InputDecoration(labelText: 'اسم الصنف')), TextField(controller: _price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'السعر بالريال اليمني')), TextField(controller: _stock, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'المخزون بـ ${ProductUnit.fromId(_saleUnit).label}')),
    DropdownButtonFormField<String>(initialValue: _saleUnit, decoration: const InputDecoration(labelText: 'وحدة البيع'), items: [for (final u in ProductUnit.all) DropdownMenuItem(value: u.id, child: Text(u.label))], onChanged: (value) { if (value != null) setState(() => _saleUnit = value); }), const SizedBox(height: 12), SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _saving || _selectedStoreId == null ? null : _createProduct, icon: const Icon(Icons.add), label: const Text('حفظ الصنف')))])));

  Widget _products(String uid) {
    if (!SupabaseService.isInitialized) return const _EmptyCard(text: 'قاعدة بيانات الإنتاج غير متاحة حالياً.');
    var query = SupabaseService.client.from('products').select().eq('owner_id', uid);
    if (_selectedStoreId != null) query = query.eq('store_id', _selectedStoreId!);
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: query.order('name').limit(100),
      builder: (context, snapshot) {
        if (snapshot.hasError) return _error(snapshot.error.toString());
        if (snapshot.connectionState == ConnectionState.waiting) return const LinearProgressIndicator();
        final docs = (snapshot.data ?? const <Map<String, dynamic>>[]).map((e) => Map<String, dynamic>.from(e)).toList();
        if (docs.isEmpty) return const _EmptyCard(text: 'لا توجد أصناف لهذا المتجر بعد.');
        final children = <Widget>[];
        for (final data in docs) {
          children.add(Card(
            elevation: 0,
            child: ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: Text('\${data['name'] ?? 'صنف'}', style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('مخزون: \${data['stock'] ?? 0} • حالة: \${data['status'] ?? 'active'}'),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('\${data['price'] ?? 0} \${data['currency'] ?? 'YER'}', style: const TextStyle(fontWeight: FontWeight.w900)),
                  TextButton(onPressed: () => _updateProduct(data), child: const Text('تعديل')),
                ],
              ),
            ),
          ));
        }
        return Column(children: children);
      },
    );
  }

  Widget _error(String text) => Card(elevation: 0, child: Padding(padding: const EdgeInsets.all(14), child: Text('تعذر تحميل البيانات.\n$text')));
}

class _HeroCard extends StatelessWidget { @override Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF0B6E4F), Color(0xFF124E78)]), borderRadius: BorderRadius.circular(26)), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.storefront, color: Colors.white, size: 34), SizedBox(height: 10), Text('مركز أعمالك في الفائق يمن', style: TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900)), SizedBox(height: 8), Text('أنشئ متجرك، أدر الكتالوج والأسعار والمخزون، وتابع جاهزية بياناتك للبيع داخل المنصة.', style: TextStyle(color: Colors.white70, height: 1.5))])); }
class _SectionTitle extends StatelessWidget { final String title; final IconData icon; const _SectionTitle({required this.title, required this.icon}); @override Widget build(BuildContext context) => Row(children: [Icon(icon, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 8), Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))]); }
class _EmptyCard extends StatelessWidget { final String text; const _EmptyCard({required this.text}); @override Widget build(BuildContext context) => Card(elevation: 0, child: Padding(padding: const EdgeInsets.all(18), child: Center(child: Text(text)))); }
class _Gate extends StatelessWidget { final String message; const _Gate({required this.message}); @override Widget build(BuildContext context) => Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(message)))); }
