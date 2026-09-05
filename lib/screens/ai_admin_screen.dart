import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AiAdminScreen extends StatefulWidget {
  const AiAdminScreen({super.key});
  @override State<AiAdminScreen> createState() => _AiAdminScreenState();
}

class _AiAdminScreenState extends State<AiAdminScreen> {
  final _store = TextEditingController();
  final _product = TextEditingController();
  final _city = TextEditingController(text: 'عدن');
  final _category = TextEditingController(text: 'متاجر وتجزئة');
  String _status = 'جاهز للعمل';

  Future<void> _saveStore() async {
    if (_store.text.trim().isEmpty) return;
    await FirebaseFirestore.instance.collection('stores').add({
      'name': _store.text.trim(),
      'city': _city.text.trim(),
      'category': _category.text.trim(),
      'source': 'admin_ai',
      'verified': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    setState(() => _status = 'تمت إضافة المتجر للمراجعة قبل النشر');
    _store.clear();
  }

  Future<void> _saveProduct() async {
    if (_product.text.trim().isEmpty) return;
    await FirebaseFirestore.instance.collection('products').add({
      'name': _product.text.trim(),
      'storeName': _store.text.trim(),
      'city': _city.text.trim(),
      'category': _category.text.trim(),
      'source': 'admin_ai',
      'verified': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    setState(() => _status = 'تمت إضافة الصنف للمراجعة قبل النشر');
    _product.clear();
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(title: const Text('مساعد الذكاء الاصطناعي — الإدارة')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
          Text('مساعد إدارة الفائق يمن', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text('يُستخدم لإدارة أسماء المتاجر والأصناف والبيانات المحلية. أي بيانات جديدة تُحفظ كمراجعة قبل نشرها للمستخدمين.'),
        ]))),
        const SizedBox(height: 16),
        TextField(controller: _city, decoration: const InputDecoration(labelText: 'المحافظة / المدينة', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(controller: _category, decoration: const InputDecoration(labelText: 'القسم', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(controller: _store, decoration: const InputDecoration(labelText: 'اسم المتجر', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(controller: _product, decoration: const InputDecoration(labelText: 'اسم الصنف', border: OutlineInputBorder())),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: ElevatedButton.icon(onPressed: _saveStore, icon: const Icon(Icons.store), label: const Text('إضافة متجر'))),
          const SizedBox(width: 10),
          Expanded(child: ElevatedButton.icon(onPressed: _saveProduct, icon: const Icon(Icons.inventory_2), label: const Text('إضافة صنف'))),
        ]),
        const SizedBox(height: 14),
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)), child: Text(_status)),
        const SizedBox(height: 20),
        const Text('ملاحظة تشغيلية', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text('لن ينشر المساعد أسماء أو مخزونات غير موثقة على أنها حقيقية. بيانات المتاجر الواقعية يجب تأكيدها من الدليل أو صاحب المتجر قبل اعتمادها.'),
      ]),
    ),
  );
}
