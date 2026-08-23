import 'package:flutter/material.dart';

class ProductsScreen extends StatelessWidget {
  final String categoryName;
  const ProductsScreen({super.key, required this.categoryName});

  @override
  Widget build(BuildContext context) {
    // توليد بائعين متخصصين بناءً على القسم الفعلي
    final List<Map<String, dynamic>> vendors = List.generate(10, (vendorIndex) {
      return {
        'name': 'متجر ${vendorIndex + 1} لـ $categoryName',
        'rating': '4.${5 - (vendorIndex % 4)}',
        'time': '${10 + (vendorIndex * 2)} دقيقة',
        'products': List.generate(10, (pIndex) {
          return {
            'name': 'منتج (${pIndex + 1}) - $categoryName',
            'price': '${(pIndex + 1) * 300 + 500} ر.ي',
            'desc': 'وصف دقيق وجودة عالية معتمدة لدى متجر $categoryName المميز',
          };
        }),
      };
    });

    return Scaffold(
      appBar: AppBar(
        title: Text('أسواق $categoryName', style: const TextStyle(fontSize: 15, color: Colors.white)),
        backgroundColor: const Color(0xFF1A365D),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: vendors.length,
        itemBuilder: (context, index) {
          final vendor = vendors[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ExpansionTile(
              leading: CircleAvatar(
                backgroundColor: const Color(0xFF1A365D),
                child: Text('${index + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              title: Text(vendor['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: Text('التقييم: ${vendor['rating']} ⭐ | التوصيل: ${vendor['time']}', 
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
              children: [
                const Divider(),
                ...List.generate(vendor['products'].length, (pIndex) {
                  final product = vendor['products'][pIndex];
                  return ListTile(
                    dense: true,
                    title: Text(product['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    subtitle: Text('${product['desc']}\nالسعر: ${product['price']}', 
                      style: const TextStyle(fontSize: 11, color: Colors.black87)),
                    isThreeLine: true,
                    trailing: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A365D),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                      ),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('تمت إضافة (${product['name']}) إلى السلة بنجاح')),
                        );
                      },
                      child: const Text('شراء', style: TextStyle(fontSize: 11)),
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }
}
