import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class CartPage extends StatelessWidget {
  const CartPage({super.key});

  Future<void> _changeQuantity(String uid, String productId, int delta) async {
    final ref = FirebaseFirestore.instance.collection('carts').doc(uid);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data() ?? <String, dynamic>{};
      final raw = data['items'];
      final items = raw is List ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];
      final index = items.indexWhere((e) => e['productId'] == productId);
      if (index < 0) return;
      final current = (items[index]['quantity'] as num?)?.toInt() ?? 1;
      final next = current + delta;
      if (next <= 0) {
        items.removeAt(index);
      } else if (next <= 100) {
        items[index]['quantity'] = next;
      }
      tx.set(ref, {'ownerId': uid, 'items': items, 'currency': data['currency'] ?? 'YER', 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    });
  }

  Future<void> _remove(String uid, String productId) async {
    final ref = FirebaseFirestore.instance.collection('carts').doc(uid);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data() ?? <String, dynamic>{};
      final raw = data['items'];
      final items = raw is List ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];
      items.removeWhere((e) => e['productId'] == productId);
      tx.set(ref, {'ownerId': uid, 'items': items, 'currency': data['currency'] ?? 'YER', 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    });
  }

  Future<void> _checkout(BuildContext context, String uid, List<Map<String, dynamic>> items, num total, String currency) async {
    final addressController = TextEditingController();
    String paymentMethod = 'cash_on_delivery';
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('إتمام الطلب'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: addressController, maxLines: 3, decoration: const InputDecoration(labelText: 'عنوان التوصيل', hintText: 'الحي، الشارع، معلم قريب')),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: paymentMethod,
              decoration: const InputDecoration(labelText: 'طريقة الدفع'),
              items: const [
                DropdownMenuItem(value: 'cash_on_delivery', child: Text('الدفع عند الاستلام')),
                DropdownMenuItem(value: 'al_kuraimi', child: Text('الكريمي')),
                DropdownMenuItem(value: 'cash_wallet', child: Text('محفظة نقدية')),
                DropdownMenuItem(value: 'jeeb_wallet', child: Text('جيـب')),
              ],
              onChanged: (value) => setState(() => paymentMethod = value ?? 'cash_on_delivery'),
            ),
            const SizedBox(height: 14),
            Text('الإجمالي: $total $currency', style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            const Text('لن يتم خصم أي مبلغ هنا. سيتم إنشاء الطلب بحالة معلّقة.'),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('تأكيد الطلب')),
          ],
        ),
      ),
    );
    if (result != true) {
      addressController.dispose();
      return;
    }
    final address = addressController.text.trim();
    addressController.dispose();
    if (address.isEmpty) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل عنوان التوصيل أولاً.')));
      return;
    }
    try {
      final merchantIds = items.map((e) => (e['merchantId'] ?? e['ownerId'] ?? '').toString()).where((e) => e.isNotEmpty).toSet().toList();
      final orderItems = items.map((e) => {
        'productId': e['productId'],
        'name': e['name'],
        'quantity': (e['quantity'] as num?)?.toInt() ?? 1,
        'price': (e['price'] as num?) ?? 0,
        'storeId': e['storeId'],
      }).toList();
      final orderRef = FirebaseFirestore.instance.collection('orders').doc();
      await orderRef.set({
        'customerId': uid,
        'merchantIds': merchantIds,
        'items': orderItems,
        'total': total,
        'currency': currency,
        'address': address,
        'paymentMethod': paymentMethod,
        'status': 'pending',
        'deliveryStatus': 'awaiting_assignment',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await FirebaseFirestore.instance.collection('carts').doc(uid).set({'ownerId': uid, 'items': [], 'currency': currency, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      if (context.mounted) {
        await showDialog<void>(context: context, builder: (_) => AlertDialog(title: const Text('تم إنشاء الطلب'), content: Text('رقم الطلب: ${orderRef.id}\nالإجمالي: $total $currency'), actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('حسناً'))]));
      }
    } on FirebaseException catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إنشاء الطلب: ${e.message ?? e.code}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: Center(child: Text('يجب تسجيل الدخول أولاً.'))));
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('سلة التسوق')),
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('carts').doc(user.uid).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return Center(child: Text('تعذر تحميل السلة: ${snapshot.error}'));
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            final data = snapshot.data?.data() ?? <String, dynamic>{};
            final rawItems = data['items'];
            final items = rawItems is List ? rawItems.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];
            final currency = (data['currency'] ?? 'YER').toString();
            if (items.isEmpty) return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.shopping_cart_outlined, size: 72), SizedBox(height: 12), Text('السلة فارغة', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)), SizedBox(height: 6), Text('افتح أي صنف واضغط «أضف للسلة».') ]));
            num total = 0;
            for (final item in items) {
              final price = item['price'];
              final quantity = item['quantity'];
              if (price is num && quantity is num) total += price * quantity;
            }
            return ListView(padding: const EdgeInsets.all(16), children: [
              ...items.map((item) {
                final productId = (item['productId'] ?? '').toString();
                final name = (item['name'] ?? 'منتج').toString();
                final quantity = (item['quantity'] as num?)?.toInt() ?? 1;
                final price = (item['price'] as num?) ?? 0;
                return Card(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.shopping_bag_outlined)),
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: Text('$price $currency • المجموع: ${price is num ? price * quantity : 0} $currency'),
                  trailing: SizedBox(width: 150, child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    IconButton(onPressed: productId.isEmpty ? null : () => _changeQuantity(user.uid, productId, -1), icon: const Icon(Icons.remove_circle_outline)),
                    Text('$quantity', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                    IconButton(onPressed: productId.isEmpty ? null : () => _changeQuantity(user.uid, productId, 1), icon: const Icon(Icons.add_circle_outline)),
                    IconButton(onPressed: productId.isEmpty ? null : () => _remove(user.uid, productId), icon: const Icon(Icons.delete_outline)),
                  ]),),
                )));
              }),
              const SizedBox(height: 12),
              Card(child: ListTile(leading: const Icon(Icons.calculate_outlined), title: const Text('الإجمالي', style: TextStyle(fontWeight: FontWeight.w900)), trailing: Text('$total $currency', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)))),
              const SizedBox(height: 14),
              SizedBox(height: 52, child: FilledButton.icon(onPressed: () => _checkout(context, user.uid, items, total, currency), icon: const Icon(Icons.shopping_cart_checkout), label: const Text('إتمام الطلب والشراء', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)))),
            ]);
          },
        ),
      ),
    );
  }
}
