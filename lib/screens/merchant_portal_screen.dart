import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class MerchantPortalScreen extends StatefulWidget {
  const MerchantPortalScreen({super.key});

  @override
  State<MerchantPortalScreen> createState() => _MerchantPortalScreenState();
}

class _MerchantPortalScreenState extends State<MerchantPortalScreen> {
  final _storeName = TextEditingController();
  final _city = TextEditingController(text: 'عدن');
  final _category = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _productName = TextEditingController();
  final _price = TextEditingController();
  final _description = TextEditingController();
  String? _storeId;
  String _status = 'ابدأ بتسجيل متجرك ليتم ربط المنتجات به مباشرة.';
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_storeName, _city, _category, _address, _phone, _productName, _price, _description]) c.dispose();
    super.dispose();
  }

  Future<void> _createStore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _status = 'يجب تسجيل الدخول أولاً.');
      return;
    }
    if (_storeName.text.trim().isEmpty || _category.text.trim().isEmpty) {
      setState(() => _status = 'أدخل اسم المتجر والقسم.');
      return;
    }
    setState(() => _busy = true);
    try {
      final ref = await FirebaseFirestore.instance.collection('stores').add({
        'name': _storeName.text.trim(),
        'city': _city.text.trim(),
        'category': _category.text.trim(),
        'address': _address.text.trim(),
        'phone': _phone.text.trim(),
        'ownerId': user.uid,
        'ownerEmail': user.email ?? '',
        'active': true,
        'verified': false,
        'source': 'merchant_portal',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      setState(() {
        _storeId = ref.id;
        _status = 'تم إنشاء المتجر فعلياً في Firestore. يمكنك الآن نشر المنتجات داخله.';
      });
    } catch (e) {
      setState(() => _status = 'تعذر إنشاء المتجر: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createProduct() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _storeId == null) {
      setState(() => _status = 'أنشئ المتجر أولاً ثم أضف المنتج.');
      return;
    }
    final name = _productName.text.trim();
    if (name.isEmpty) {
      setState(() => _status = 'أدخل اسم المنتج.');
      return;
    }
    setState(() => _busy = true);
    try {
      await FirebaseFirestore.instance.collection('products').add({
        'name': name,
        'storeId': _storeId,
        'storeName': _storeName.text.trim(),
        'city': _city.text.trim(),
        'category': _category.text.trim(),
        'description': _description.text.trim(),
        'price': double.tryParse(_price.text.trim()) ?? 0,
        'ownerId': user.uid,
        'active': true,
        'verified': false,
        'source': 'merchant_portal',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      setState(() => _status = 'تم نشر المنتج فعلياً داخل Firestore.');
      _productName.clear();
      _price.clear();
      _description.clear();
    } catch (e) {
      setState(() => _status = 'تعذر نشر المنتج: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _dec(String label) => InputDecoration(labelText: label, border: const OutlineInputBorder());

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('بوابة التجار — تشغيل حقيقي')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(16)),
              child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('ربط مباشر مع Firestore', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                SizedBox(height: 6),
                Text('أي متجر أو منتج تضيفه من هنا يُحفظ في قاعدة البيانات ويظهر في واجهة المتاجر بعد تفعيله.'),
              ]),
            ),
            const SizedBox(height: 16),
            TextField(controller: _storeName, decoration: _dec('اسم المتجر')),
            const SizedBox(height: 10),
            TextField(controller: _city, decoration: _dec('المدينة / المحافظة')),
            const SizedBox(height: 10),
            TextField(controller: _category, decoration: _dec('القسم — مثال: قطع الغيار وإكسسوارات السيارات')),
            const SizedBox(height: 10),
            TextField(controller: _address, decoration: _dec('العنوان')),
            const SizedBox(height: 10),
            TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: _dec('هاتف المتجر')),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: _busy ? null : _createStore, icon: const Icon(Icons.store), label: const Text('تسجيل المتجر فعلياً')),
            if (_storeId != null) ...[
              const SizedBox(height: 8),
              SelectableText('معرّف المتجر: $_storeId', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              const Divider(height: 28),
              const Text('إضافة منتج', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              TextField(controller: _productName, decoration: _dec('اسم المنتج')),
              const SizedBox(height: 10),
              TextField(controller: _price, keyboardType: TextInputType.number, decoration: _dec('السعر بالريال اليمني')),
              const SizedBox(height: 10),
              TextField(controller: _description, maxLines: 2, decoration: _dec('وصف المنتج')),
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: _busy ? null : _createProduct, icon: const Icon(Icons.inventory_2), label: const Text('نشر المنتج فعلياً')),
            ],
            const SizedBox(height: 16),
            Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)), child: Text(_status)),
          ],
        ),
      ),
    );
  }
}
