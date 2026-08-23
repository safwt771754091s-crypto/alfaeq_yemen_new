import 'package:flutter/material.dart';

class ProductsScreen extends StatelessWidget {
  final String vendorName;
  const ProductsScreen({super.key, required this.vendorName});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, String>> products = [
      {'name': 'منتج 1: وجبة عائلية ممتازة', 'price': '4,500 ر.ي', 'desc': 'وجبة طازجة مع الملحقات'},
      {'name': 'منتج 2: عرض خاص ومميز', 'price': '3,000 ر.ي', 'desc': 'منتج معتمد بجودة عالية'},
      {'name': 'منتج 3: وجبة بروستد حار', 'price': '2,500 ر.ي', 'desc': 'مقرمش مع البطاطس والمشروب'},
      {'name': 'منتج 4: بيتزا عائلية كبيرة', 'price': '5,000 ر.ي', 'desc': 'جبنة موزاريلا إضافية'},
      {'name': 'منتج 5: عصير طبيعي طازج', 'price': '1,200 ر.ي', 'desc': 'فواكه طبيعية 100%'},
      {'name': 'منتج 6: سلة تموينية أساسية', 'price': '15,000 ر.ي', 'desc': 'متطلبات البيت الأساسية'},
      {'name': 'منتج 7: مشويات مشكلة فحم', 'price': '6,000 ر.ي', 'desc': 'لحم طازج مشوي'},
      {'name': 'منتج 8: سندوتش شاورما صاروخ', 'price': '1,500 ر.ي', 'desc': 'خلطة خاصة'},
      {'name': 'منتج 9: مخبوزات وحلويات يومية', 'price': '2,000 ر.ي', 'desc': 'طازجة وساخنة'},
      {'name': 'منتج 10: كرتون مياه معدنية', 'price': '1,000 ر.ي', 'desc': 'مياه نقية معقمة'},
    ];

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
            child: ListTile(
              title: Text(p['name']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p['desc']!, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                  const SizedBox(height: 4),
                  Text(p['price']!, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                ],
              ),
              trailing: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A365D), foregroundColor: Colors.white),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('تمت إضافة ${p['name']} إلى السلة')),
                  );
                },
                child: const Text('شراء', style: TextStyle(fontSize: 11)),
              ),
            ),
          );
        },
      ),
    );
  }
}

