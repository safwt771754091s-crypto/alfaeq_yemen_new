import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'location_picker_page.dart';
import '../core/product_units.dart';

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
      final unit = ProductUnit.fromId((items[index]['saleUnit'] ?? 'piece').toString());
      final step = (items[index]['stepBase'] as num?)?.round() ?? unit.defaultStepBase;
      final current = (items[index]['quantityBase'] as num?)?.round() ?? (((items[index]['quantity'] as num?) ?? 1) * unit.scale).round();
      final next = current + delta * step;
      if (next <= 0) {
        items.removeAt(index);
      } else if (next <= 100) {
        items[index]['quantityBase'] = next;
        items[index]['quantity'] = unit.fromBase(next);
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
    LatLng? deliveryPoint;
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
            OutlinedButton.icon(
              onPressed: () async {
                final point = await Navigator.push<LatLng>(context, MaterialPageRoute(builder: (_) => const LocationPickerPage(title: 'تحديد موقع التوصيل')));
                if (point != null) setState(() => deliveryPoint = point);
              },
              icon: Icon(deliveryPoint == null ? Icons.location_on_outlined : Icons.location_on),
              label: Text(deliveryPoint == null ? 'حدد موقع التوصيل على الخريطة' : 'تم تحديد موقع التوصيل'),
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
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable('createOrderFromCart');
      final response = await callable.call({
        'address': address,
        'paymentMethod': paymentMethod,
        if (deliveryPoint != null)
          'deliveryLocation': {
            'latitude': deliveryPoint!.latitude,
            'longitude': deliveryPoint!.longitude,
          },
      });
      final resultData = Map<String, dynamic>.from(response.data as Map);
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('تم إنشاء الطلب'),
            content: Text('رقم الطلب: ${resultData['orderId']}\\nالإجمالي: ${resultData['total'] ?? total} ${resultData['currency'] ?? currency}\\nتم تثبيت المخزون بشكل آمن.'),
            actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('حسناً'))],
          ),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إنشاء الطلب: ${e.message ?? e.code}')));
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
              final unit = ProductUnit.fromId((item['saleUnit'] ?? 'piece').toString());
              final base = (item['quantityBase'] as num?)?.toDouble() ?? (((item['quantity'] as num?) ?? 0) * unit.scale);
              final price = (item['price'] as num?) ?? 0;
              total += price * unit.fromBase(base);
            }
            return ListView(padding: const EdgeInsets.all(16), children: [
              ...items.map((item) {
                final productId = (item['productId'] ?? '').toString();
                final name = (item['name'] ?? 'منتج').toString();
                final unit = ProductUnit.fromId((item['saleUnit'] ?? 'piece').toString());
                final base = (item['quantityBase'] as num?)?.toDouble() ?? (((item['quantity'] as num?) ?? 1) * unit.scale);
                final quantity = unit.fromBase(base);
                final price = (item['price'] as num?) ?? 0;
                return Card(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.shopping_bag_outlined)),
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: Text('$quantity ${unit.label} × $price $currency/${unit.label} • المجموع: ${price * quantity} $currency'),
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
