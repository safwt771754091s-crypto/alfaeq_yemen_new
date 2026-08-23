import 'package:flutter/material.dart';

class ProductsScreen extends StatelessWidget {
  final String categoryName;
  const ProductsScreen({super.key, required this.categoryName});

  @override
  Widget build(BuildContext context) {
    // توليد 10 بائعين لكل قسم بشكل ديناميكي واحترافي
    final List<Map<String, dynamic>> vendors = List.generate(10, (vendorIndex) {
      return {
        'name': 'متجر $categoryName المميز رقم (${vendorIndex + 1})',
        'rating': '4.${5 - (vendorIndex % 3)}',
        'time': '${15 + (vendorIndex * 3)} دقيقة',
        'products': List.generate(10, (productIndex) {
          return {
            'name': 'صنف رقم (${productIndex + 1}) - منتج فاخر',
            'price': '${(productIndex + 1) * 500 + 1000} ر.ي',
            'desc': 'وصف تفصيلي لهذا الصنف الممتاز والجودة العالية المعتمدة في الفائق يمن',
          };
        }),
      };
    });

    return Scaffold(
      appBar: AppBar(
        title: Text('قائمة المتاجر: $categoryName', style: const TextStyle(fontSize: 14, color: Colors.white)),
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
            elevation: 3,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ExpansionTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF1A365D),
                child: Icon(Icons.store, color: Colors.white),
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
                    subtitle: Text('${product['desc']} \nالسعر: ${product['price']}', 
                      style: const TextStyle(fontSize: 10, color: Colors.black87)),
                    isThreeLine: true,
                    trailing: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A365D),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      ),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('تمت إضافة (${product['name']}) إلى السلة بنجاح')),
                        );
                      },
                      child: const Text('شراء', style: TextStyle(fontSize: 10)),
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

