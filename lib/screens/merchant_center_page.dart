import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/app_sections.dart';

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
  bool _saving = false;

  @override
  void dispose() {
    _storeName.dispose();
    _phone.dispose();
    _address.dispose();
    _productName.dispose();
    _price.dispose();
    _stock.dispose();
    super.dispose();
  }

  User? get _user => FirebaseAuth.instance.currentUser;

  Future<void> _createStore() async {
    final user = _user;
    final name = _storeName.text.trim();
    final phone = _phone.text.trim();
    if (user == null || name.isEmpty || phone.isEmpty) {
      _message('أدخل اسم المتجر ورقم الهاتف.');
      return;
    }

    setState(() => _saving = true);
    try {
      final ref = await FirebaseFirestore.instance.collection('stores').add({
        'name': name,
        'phone': phone,
        'address': _address.text.trim(),
        'sectionId': _sectionId,
        'status': 'pending',
        'ownerId': user.uid,
        'createdBy': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _selectedStoreId = ref.id;
      _storeName.clear();
      _phone.clear();
      _address.clear();
      _message('تم إرسال المتجر للمراجعة. لن يظهر للعملاء حتى يتم اعتماده.');
    } on FirebaseException catch (e) {
      _message('تعذر حفظ المتجر: ${e.message ?? e.code}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _createProduct() async {
    final user = _user;
    final storeId = _selectedStoreId;
    final name = _productName.text.trim();
    final price = num.tryParse(_price.text.trim());
    final stock = int.tryParse(_stock.text.trim());
    if (user == null || storeId == null || name.isEmpty) {
      _message('اختر متجراً وأدخل اسم الصنف.');
      return;
    }
    if (price == null || price < 0 || stock == null || stock < 0) {
      _message('السعر والكمية يجب أن يكونا أرقاماً صحيحة وغير سالبة.');
      return;
    }

    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('products').add({
        'storeId': storeId,
        'ownerId': user.uid,
        'createdBy': user.uid,
        'name': name,
        'price': price,
        'currency': 'YER',
        'stock': stock,
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _productName.clear();
      _price.clear();
      _stock.clear();
      _message('تم حفظ الصنف بنجاح.');
    } on FirebaseException catch (e) {
      _message('تعذر حفظ الصنف: ${e.message ?? e.code}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _updateProduct(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data();
    final priceController = TextEditingController(text: '${data['price'] ?? ''}');
    final stockController = TextEditingController(text: '${data['stock'] ?? ''}');
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${data['name'] ?? 'تعديل الصنف'}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: priceController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'السعر')),
          TextField(controller: stockController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'المخزون')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (result != true) return;
    final price = num.tryParse(priceController.text.trim());
    final stock = int.tryParse(stockController.text.trim());
    if (price == null || price < 0 || stock == null || stock < 0) {
      _message('السعر والمخزون غير صالحين.');
      return;
    }
    await doc.reference.update({'price': price, 'stock': stock, 'updatedAt': FieldValue.serverTimestamp()});
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    if (user == null) return const _Gate(message: 'يجب تسجيل الدخول إلى مركز التاجر.');

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('مركز التاجر'), actions: [IconButton(onPressed: () => setState(() {}), icon: const Icon(Icons.refresh))]),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          _HeroCard(),
          const SizedBox(height: 18),
          _SectionTitle(title: 'متاجري', icon: Icons.storefront_outlined),
          const SizedBox(height: 8),
          _stores(user.uid),
          const SizedBox(height: 18),
          _SectionTitle(title: 'إضافة متجر', icon: Icons.add_business_outlined),
          const SizedBox(height: 8),
          _storeForm(),
          const SizedBox(height: 18),
          _SectionTitle(title: 'إضافة صنف', icon: Icons.add_box_outlined),
          const SizedBox(height: 8),
          _productForm(),
          const SizedBox(height: 18),
          _SectionTitle(title: 'كتالوج الأصناف', icon: Icons.inventory_2_outlined),
          const SizedBox(height: 8),
          _products(user.uid),
        ]),
      ),
    );
  }

  Widget _stores(String uid) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('stores').where('ownerId', isEqualTo: uid).limit(30).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return _error(snapshot.error.toString());
        if (snapshot.connectionState == ConnectionState.waiting) return const LinearProgressIndicator();
        final docs = snapshot.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        if (docs.isEmpty) return const _EmptyCard(text: 'لم تنشئ متجراً بعد.');
        return Column(children: docs.map((doc) {
          final data = doc.data();
          final selected = _selectedStoreId == doc.id;
          return Card(elevation: 0, child: ListTile(
            selected: selected,
            leading: CircleAvatar(backgroundColor: const Color(0xFFE7F3EE), child: Icon(Icons.storefront_outlined, color: Theme.of(context).colorScheme.primary)),
            title: Text('${data['name'] ?? 'متجر'}', style: const TextStyle(fontWeight: FontWeight.w900)),
            subtitle: Text('${data['status'] ?? 'pending'} • ${data['phone'] ?? ''}'),
            trailing: selected ? const Icon(Icons.check_circle) : const Icon(Icons.chevron_left),
            onTap: () => setState(() => _selectedStoreId = doc.id),
          ));
        }).toList());
      },
    );
  }

  Widget _storeForm() {
    return Card(elevation: 0, child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      DropdownButtonFormField<String>(
        initialValue: _sectionId,
        decoration: const InputDecoration(labelText: 'القسم'),
        items: [for (final section in appSections) DropdownMenuItem(value: section.id, child: Text(section.title))],
        onChanged: (value) { if (value != null) setState(() => _sectionId = value); },
      ),
      TextField(controller: _storeName, decoration: const InputDecoration(labelText: 'اسم المتجر')),
      TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف')),
      TextField(controller: _address, decoration: const InputDecoration(labelText: 'العنوان')),
      const SizedBox(height: 12),
      SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _saving ? null : _createStore, icon: const Icon(Icons.verified_outlined), label: const Text('إرسال المتجر للمراجعة'))),
    ])));
  }

  Widget _productForm() {
    return Card(elevation: 0, child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      if (_selectedStoreId == null) const Align(alignment: Alignment.centerRight, child: Text('اختر متجراً أولاً من القائمة أعلاه.', style: TextStyle(color: Colors.black54))),
      TextField(controller: _productName, decoration: const InputDecoration(labelText: 'اسم الصنف')),
      TextField(controller: _price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'السعر بالريال اليمني')),
      TextField(controller: _stock, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'المخزون')),
      const SizedBox(height: 12),
      SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _saving || _selectedStoreId == null ? null : _createProduct, icon: const Icon(Icons.add), label: const Text('حفظ الصنف'))),
    ])));
  }

  Widget _products(String uid) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('products').where('ownerId', isEqualTo: uid).limit(100).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return _error(snapshot.error.toString());
        if (snapshot.connectionState == ConnectionState.waiting) return const LinearProgressIndicator();
        final docs = snapshot.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final filtered = _selectedStoreId == null ? docs : docs.where((doc) => doc.data()['storeId'] == _selectedStoreId).toList();
        if (filtered.isEmpty) return const _EmptyCard(text: 'لا توجد أصناف لهذا المتجر بعد.');
        return Column(children: filtered.map((doc) {
          final data = doc.data();
          return Card(elevation: 0, child: ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: Text('${data['name'] ?? 'صنف'}', style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('مخزون: ${data['stock'] ?? 0} • حالة: ${data['status'] ?? 'active'}'),
            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${data['price'] ?? 0} ${data['currency'] ?? 'YER'}', style: const TextStyle(fontWeight: FontWeight.w900)),
              TextButton(onPressed: () => _updateProduct(doc), child: const Text('تعديل')),
            ]),
          ));
        }).toList());
      },
    );
  }

  Widget _error(String text) => Card(elevation: 0, child: Padding(padding: const EdgeInsets.all(14), child: Text('تعذر تحميل البيانات.\n$text')));
}

class _HeroCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF0B6E4F), Color(0xFF124E78)]), borderRadius: BorderRadius.circular(26)),
    child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Icons.storefront, color: Colors.white, size: 34),
      SizedBox(height: 10),
      Text('مركز أعمالك في الفائق يمن', style: TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900)),
      SizedBox(height: 8),
      Text('أنشئ متجرك، أدر الكتالوج والأسعار والمخزون، وتابع جاهزية بياناتك للبيع داخل المنصة.', style: TextStyle(color: Colors.white70, height: 1.5)),
    ]),
  );
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionTitle({required this.title, required this.icon});
  @override
  Widget build(BuildContext context) => Row(children: [Icon(icon, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 8), Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))]);
}

class _EmptyCard extends StatelessWidget {
  final String text;
  const _EmptyCard({required this.text});
  @override
  Widget build(BuildContext context) => Card(elevation: 0, child: Padding(padding: const EdgeInsets.all(18), child: Center(child: Text(text))));
}

class _Gate extends StatelessWidget {
  final String message;
  const _Gate({required this.message});
  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(message))));
}
