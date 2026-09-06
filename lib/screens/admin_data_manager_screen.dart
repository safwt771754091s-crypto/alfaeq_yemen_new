import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AdminDataManagerScreen extends StatefulWidget {
  const AdminDataManagerScreen({super.key});

  @override
  State<AdminDataManagerScreen> createState() => _AdminDataManagerScreenState();
}

class _AdminDataManagerScreenState extends State<AdminDataManagerScreen> {
  final _categoryName = TextEditingController();
  final _categoryKey = TextEditingController();
  final _walletName = TextEditingController();
  final _walletAccount = TextEditingController();
  final _walletInstructions = TextEditingController();
  String _status = 'إدارة البيانات الحقيقية من Firestore';
  bool _busy = false;

  @override
  void dispose() {
    _categoryName.dispose();
    _categoryKey.dispose();
    _walletName.dispose();
    _walletAccount.dispose();
    _walletInstructions.dispose();
    super.dispose();
  }

  Future<void> _addCategory() async {
    final name = _categoryName.text.trim();
    final key = _categoryKey.text.trim();
    if (name.isEmpty || key.isEmpty) {
      setState(() => _status = 'أدخل اسم القسم والمفتاح.');
      return;
    }
    setState(() => _busy = true);
    try {
      await FirebaseFirestore.instance.collection('categories').doc(key).set({
        'name': name,
        'key': key,
        'active': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _categoryName.clear();
      _categoryKey.clear();
      setState(() => _status = 'تمت إضافة القسم فعلياً.');
    } catch (e) {
      setState(() => _status = 'تعذر إضافة القسم: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addWalletMethod() async {
    final name = _walletName.text.trim();
    final account = _walletAccount.text.trim();
    if (name.isEmpty || account.isEmpty) {
      setState(() => _status = 'أدخل اسم المحفظة ورقم الحساب.');
      return;
    }
    setState(() => _busy = true);
    try {
      await FirebaseFirestore.instance.collection('paymentMethods').add({
        'name': name,
        'account': account,
        'instructions': _walletInstructions.text.trim(),
        'type': 'yemen_wallet',
        'active': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _walletName.clear();
      _walletAccount.clear();
      _walletInstructions.clear();
      setState(() => _status = 'تمت إضافة وسيلة المحفظة/التحويل فعلياً.');
    } catch (e) {
      setState(() => _status = 'تعذر إضافة وسيلة الدفع: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve(String collection, String id) async {
    try {
      await FirebaseFirestore.instance.collection(collection).doc(id).update({
        'verified': true,
        'active': true,
        'verifiedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      setState(() => _status = 'تم اعتماد $collection بنجاح.');
    } catch (e) {
      setState(() => _status = 'تعذر الاعتماد: $e');
    }
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 18),
        child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      );

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('إدارة البيانات والصلاحيات')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(_status),
              ),
            ),
            _sectionTitle('الأقسام'),
            TextField(controller: _categoryName, decoration: const InputDecoration(labelText: 'اسم القسم', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: _categoryKey, decoration: const InputDecoration(labelText: 'مفتاح القسم مثل spare_parts', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            FilledButton.icon(onPressed: _busy ? null : _addCategory, icon: const Icon(Icons.add_business), label: const Text('إضافة قسم')),
            _sectionTitle('المحافظ وطرق التحويل'),
            TextField(controller: _walletName, decoration: const InputDecoration(labelText: 'اسم المحفظة / البنك', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: _walletAccount, decoration: const InputDecoration(labelText: 'رقم الحساب / المحفظة', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: _walletInstructions, maxLines: 2, decoration: const InputDecoration(labelText: 'تعليمات التحويل', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            FilledButton.icon(onPressed: _busy ? null : _addWalletMethod, icon: const Icon(Icons.account_balance_wallet), label: const Text('إضافة وسيلة دفع')),
            _sectionTitle('المتاجر بانتظار الاعتماد'),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('stores').where('verified', isEqualTo: false).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Text('خطأ: ${snapshot.error}');
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final docs = snapshot.data!.docs;
                if (docs.isEmpty) return const Text('لا توجد متاجر بانتظار الاعتماد.');
                return Column(children: docs.map((doc) => Card(child: ListTile(
                  title: Text((doc.data()['name'] ?? 'متجر').toString()),
                  subtitle: Text('${doc.data()['city'] ?? ''} • ${doc.data()['category'] ?? ''}'),
                  trailing: FilledButton(onPressed: () => _approve('stores', doc.id), child: const Text('اعتماد')),
                ))).toList());
              },
            ),
            _sectionTitle('المنتجات بانتظار الاعتماد'),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('products').where('verified', isEqualTo: false).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Text('خطأ: ${snapshot.error}');
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final docs = snapshot.data!.docs;
                if (docs.isEmpty) return const Text('لا توجد منتجات بانتظار الاعتماد.');
                return Column(children: docs.map((doc) => Card(child: ListTile(
                  title: Text((doc.data()['name'] ?? 'منتج').toString()),
                  subtitle: Text('${doc.data()['storeName'] ?? ''} • ${doc.data()['price'] ?? 0} ر.ي'),
                  trailing: FilledButton(onPressed: () => _approve('products', doc.id), child: const Text('اعتماد')),
                ))).toList());
              },
            ),
          ],
        ),
      ),
    );
  }
}
