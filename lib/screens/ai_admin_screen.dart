import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AiAdminScreen extends StatefulWidget {
  const AiAdminScreen({super.key});

  @override
  State<AiAdminScreen> createState() => _AiAdminScreenState();
}

class _AiAdminScreenState extends State<AiAdminScreen> {
  final _store = TextEditingController();
  final _storeId = TextEditingController();
  final _product = TextEditingController();
  final _price = TextEditingController();
  final _description = TextEditingController();
  final _city = TextEditingController(text: 'عدن');
  final _category = TextEditingController(text: 'متاجر وتجزئة');
  String _status = 'جاهز للعمل';

  @override
  void dispose() {
    _store.dispose();
    _storeId.dispose();
    _product.dispose();
    _price.dispose();
    _description.dispose();
    _city.dispose();
    _category.dispose();
    super.dispose();
  }

  Future<void> _saveStore() async {
    final name = _store.text.trim();
    if (name.isEmpty) return;
    try {
      final ref = await FirebaseFirestore.instance.collection('stores').add({
        'name': name,
        'city': _city.text.trim(),
        'category': _category.text.trim(),
        'active': true,
        'verified': false,
        'source': 'admin_ai',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _storeId.text = ref.id;
      setState(() => _status = 'تم إنشاء المتجر ونشره، وتم حفظ رقم المتجر لاستخدامه مع المنتجات.');
    } catch (e) {
      setState(() => _status = 'تعذر إنشاء المتجر: $e');
    }
  }

  Future<void> _saveProduct() async {
    final name = _product.text.trim();
    final storeId = _storeId.text.trim();
    if (name.isEmpty || storeId.isEmpty) {
      setState(() => _status = 'أدخل اسم المنتج ورقم المتجر أولاً.');
      return;
    }

    final parsedPrice = double.tryParse(_price.text.trim());
    try {
      await FirebaseFirestore.instance.collection('products').add({
        'name': name,
        'storeId': storeId,
        'storeName': _store.text.trim(),
        'city': _city.text.trim(),
        'category': _category.text.trim(),
        'description': _description.text.trim(),
        'price': parsedPrice ?? 0,
        'active': true,
        'verified': false,
        'source': 'admin_ai',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      setState(() => _status = 'تم نشر المنتج داخل المتجر بنجاح.');
      _product.clear();
      _price.clear();
      _description.clear();
    } catch (e) {
      setState(() => _status = 'تعذر نشر المنتج: $e');
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: const Text('مساعد الذكاء الاصطناعي — الإدارة')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('مساعد إدارة الفائق يمن', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      SizedBox(height: 8),
                      Text('إدارة المتاجر والمنتجات مباشرة عبر Firestore. البيانات الواقعية لا تُعتبر موثقة إلا بعد التحقق من المصدر أو صاحب المتجر.'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(controller: _city, decoration: const InputDecoration(labelText: 'المحافظة / المدينة', border: OutlineInputBorder())),
              const SizedBox(height: 10),
              TextField(controller: _category, decoration: const InputDecoration(labelText: 'القسم', border: OutlineInputBorder())),
              const SizedBox(height: 10),
              TextField(controller: _store, decoration: const InputDecoration(labelText: 'اسم المتجر', border: OutlineInputBorder())),
              const SizedBox(height: 10),
              TextField(controller: _storeId, decoration: const InputDecoration(labelText: 'معرّف المتجر في Firestore', border: OutlineInputBorder())),
              const SizedBox(height: 14),
              ElevatedButton.icon(onPressed: _saveStore, icon: const Icon(Icons.store), label: const Text('إنشاء متجر نشط')),
              const SizedBox(height: 16),
              TextField(controller: _product, decoration: const InputDecoration(labelText: 'اسم المنتج', border: OutlineInputBorder())),
              const SizedBox(height: 10),
              TextField(controller: _price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'السعر بالريال اليمني', border: OutlineInputBorder())),
              const SizedBox(height: 10),
              TextField(controller: _description, maxLines: 2, decoration: const InputDecoration(labelText: 'وصف المنتج', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              ElevatedButton.icon(onPressed: _saveProduct, icon: const Icon(Icons.inventory_2), label: const Text('نشر المنتج داخل المتجر')),
              const SizedBox(height: 14),
              Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)), child: Text(_status)),
            ],
          ),
        ),
      );
}
