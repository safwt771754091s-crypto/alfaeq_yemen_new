import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../core/app_sections.dart';

class AdminDataEntry extends StatefulWidget {
  const AdminDataEntry({super.key});
  @override
  State<AdminDataEntry> createState() => _AdminDataEntryState();
}

class _AdminDataEntryState extends State<AdminDataEntry> {
  final merchantName = TextEditingController();
  final merchantPhone = TextEditingController();
  final merchantAddress = TextEditingController();
  final productName = TextEditingController();
  final productPrice = TextEditingController();
  final productStock = TextEditingController();
  String sectionId = appSections.first.id;
  String? storeId;
  bool saving = false;

  @override
  void dispose() {
    merchantName.dispose(); merchantPhone.dispose(); merchantAddress.dispose();
    productName.dispose(); productPrice.dispose(); productStock.dispose();
    super.dispose();
  }

  Future<void> saveMerchant() async {
    if (merchantName.text.trim().isEmpty || merchantPhone.text.trim().isEmpty) return;
    setState(() => saving = true);
    final ref = await FirebaseFirestore.instance.collection('stores').add({
      'name': merchantName.text.trim(),
      'phone': merchantPhone.text.trim(),
      'address': merchantAddress.text.trim(),
      'sectionId': sectionId,
      'status': 'approved',
      'ownerId': 'admin-created',
      'createdAt': FieldValue.serverTimestamp(),
    });
    storeId = ref.id;
    setState(() => saving = false);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت إضافة التاجر وحفظه في Firestore')));
  }

  Future<void> saveProduct() async {
    if (storeId == null || productName.text.trim().isEmpty) return;
    setState(() => saving = true);
    await FirebaseFirestore.instance.collection('products').add({
      'storeId': storeId,
      'ownerId': 'admin-created',
      'name': productName.text.trim(),
      'price': num.tryParse(productPrice.text.trim()) ?? 0,
      'stock': int.tryParse(productStock.text.trim()) ?? 0,
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
    });
    setState(() => saving = false);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت إضافة الصنف وحفظه في Firestore')));
  }

  @override
  Widget build(BuildContext context) => Directionality(textDirection: TextDirection.rtl, child: Scaffold(
    appBar: AppBar(title: const Text('إضافة بيانات حقيقية')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('التاجر', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(initialValue: sectionId, decoration: const InputDecoration(labelText: 'القسم'), items: [for (final s in appSections) DropdownMenuItem(value: s.id, child: Text(s.title))], onChanged: (v) => setState(() => sectionId = v!)),
      TextField(controller: merchantName, decoration: const InputDecoration(labelText: 'اسم التاجر الحقيقي')),
      TextField(controller: merchantPhone, decoration: const InputDecoration(labelText: 'رقم الهاتف')),
      TextField(controller: merchantAddress, decoration: const InputDecoration(labelText: 'العنوان')),
      const SizedBox(height: 12),
      FilledButton(onPressed: saving ? null : saveMerchant, child: const Text('حفظ التاجر')),
      if (storeId != null) ...[
        const SizedBox(height: 28),
        Text('معرّف المتجر: $storeId', style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 8),
        const Text('الصنف', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
        TextField(controller: productName, decoration: const InputDecoration(labelText: 'اسم الصنف الحقيقي')),
        TextField(controller: productPrice, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'السعر الحقيقي بالريال اليمني')),
        TextField(controller: productStock, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الكمية المتوفرة')),
        const SizedBox(height: 12),
        FilledButton(onPressed: saving ? null : saveProduct, child: const Text('حفظ الصنف')),
      ],
    ]),
  ));
}
