import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class VendorAddProductScreen extends StatefulWidget {
  final String? storeId;
  final String? storeName;

  const VendorAddProductScreen({super.key, this.storeId, this.storeName});

  @override
  State<VendorAddProductScreen> createState() => _VendorAddProductScreenState();
}

class _VendorAddProductScreenState extends State<VendorAddProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _productNameController = TextEditingController();
  final _priceController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _storeIdController = TextEditingController();
  final _storeNameController = TextEditingController();
  String _selectedCategory = 'المطاعم والوجبات';
  bool _saving = false;

  final List<String> _categories = [
    'المطاعم والوجبات', 'السوبرماركت', 'الصيدليات والأدوية', 'أدوات التجميل',
    'الملابس والأزياء', 'الفنادق والحجوزات', 'المراكز الطبية', 'التوصيل والمالية',
    'الإلكترونيات والكهربائيات', 'السيارات وقطع الغيار', 'مواد البناء', 'المنتجات المحلية',
  ];

  @override
  void initState() {
    super.initState();
    _storeIdController.text = widget.storeId ?? '';
    _storeNameController.text = widget.storeName ?? '';
  }

  @override
  void dispose() {
    _productNameController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    _storeIdController.dispose();
    _storeNameController.dispose();
    super.dispose();
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('products').add({
        'name': _productNameController.text.trim(),
        'price': double.tryParse(_priceController.text.trim()) ?? 0,
        'description': _descriptionController.text.trim(),
        'category': _selectedCategory,
        'storeId': _storeIdController.text.trim(),
        'storeName': _storeNameController.text.trim(),
        'sellerId': user.uid,
        'ownerUserId': user.uid,
        'active': true,
        'verified': false,
        'source': 'vendor_portal',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ المنتج في Firestore بنجاح.'), backgroundColor: Colors.green));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر حفظ المنتج: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(title: const Text('إضافة منتج جديد'), backgroundColor: const Color(0xFF1A365D), foregroundColor: Colors.white),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(children: [
            TextFormField(controller: _storeIdController, decoration: const InputDecoration(labelText: 'معرّف المتجر في Firestore', border: OutlineInputBorder()), validator: (v) => v == null || v.trim().isEmpty ? 'أدخل معرّف المتجر' : null),
            const SizedBox(height: 12),
            TextFormField(controller: _storeNameController, decoration: const InputDecoration(labelText: 'اسم المتجر', border: OutlineInputBorder()), validator: (v) => v == null || v.trim().isEmpty ? 'أدخل اسم المتجر' : null),
            const SizedBox(height: 12),
            TextFormField(controller: _productNameController, decoration: const InputDecoration(labelText: 'اسم المنتج', border: OutlineInputBorder(), prefixIcon: Icon(Icons.shopping_bag)), validator: (v) => v == null || v.trim().isEmpty ? 'يرجى إدخال اسم المنتج' : null),
            const SizedBox(height: 12),
            TextFormField(controller: _priceController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'السعر (ريال يمني)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.payments)), validator: (v) => double.tryParse(v?.trim() ?? '') == null ? 'أدخل سعراً صحيحاً' : null),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(value: _selectedCategory, decoration: const InputDecoration(labelText: 'القسم', border: OutlineInputBorder()), items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(), onChanged: (v) => setState(() => _selectedCategory = v ?? _selectedCategory)),
            const SizedBox(height: 12),
            TextFormField(controller: _descriptionController, maxLines: 3, decoration: const InputDecoration(labelText: 'وصف المنتج', border: OutlineInputBorder())),
            const SizedBox(height: 20),
            SizedBox(height: 50, child: ElevatedButton(onPressed: _saving ? null : _saveProduct, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A365D), foregroundColor: Colors.white), child: _saving ? const CircularProgressIndicator() : const Text('حفظ ونشر المنتج'))),
          ]),
        ),
      ),
    ),
  );
}
