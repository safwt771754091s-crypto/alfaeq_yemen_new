import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class CartPage extends StatelessWidget {
  const CartPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: Center(child: Text('يجب تسجيل الدخول أولاً.'))),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('سلة التسوق')),
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('carts').doc(user.uid).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('تعذر تحميل السلة: ${snapshot.error}'));
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final data = snapshot.data?.data() ?? <String, dynamic>{};
            final rawItems = data['items'];
            final items = rawItems is List
                ? rawItems.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
                : <Map<String, dynamic>>[];

            if (items.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shopping_cart_outlined, size: 72),
                    SizedBox(height: 12),
                    Text('السلة فارغة', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    SizedBox(height: 6),
                    Text('أضف المنتجات إلى سلتك لتظهر هنا.'),
                  ],
                ),
              );
            }

            num total = 0;
            for (final item in items) {
              final price = item['price'];
              final quantity = item['quantity'];
              if (price is num && quantity is num) total += price * quantity;
            }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ...items.map((item) {
                  final name = (item['name'] ?? 'منتج').toString();
                  final quantity = (item['quantity'] as num?)?.toInt() ?? 1;
                  final price = (item['price'] as num?) ?? 0;
                  return Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.shopping_bag_outlined)),
                      title: Text(name),
                      subtitle: Text('الكمية: $quantity • السعر: $price ${data['currency'] ?? 'YER'}'),
                    ),
                  );
                }),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.calculate_outlined),
                    title: const Text('الإجمالي', style: TextStyle(fontWeight: FontWeight.w900)),
                    trailing: Text('$total ${data['currency'] ?? 'YER'}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
