import 'package:flutter/material.dart';
import '../models/app_database.dart';

class ProductsScreen extends StatelessWidget {
  final String vendorName;
  const ProductsScreen({super.key, required this.vendorName});

  @override
  Widget build(BuildContext context) {
    final products = AppDatabase.getProductsForVendor(vendorName);

    return Scaffold(
      appBar: AppBar(
        title: Text('منتجات: $vendorName', style: const TextStyle(fontSize: 15, color: Colors.white)),
        backgroundColor: const Color(0xFF1A365D),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: products.length,
        itemBuilder: (context, index) {
          final p = products[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: ListTile(
              title: Text(p['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p['desc'], style: const TextStyle(color: Colors.grey, fontSize: 11)),
                  const SizedBox(height: 4),
                  Text('${p['price']} ر.ي', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                ],
              ),
              trailing: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A365D), foregroundColor: Colors.white),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('تمت إضافة ${p['name']} إلى السلة بنجاح')),
                  );
                },
                child: const Text('شراء / سلة', style: TextStyle(fontSize: 11)),
              ),
            ),
          );
        },
      ),
    );
  }
}

