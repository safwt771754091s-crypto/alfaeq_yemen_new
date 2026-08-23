import 'package:flutter/material.dart';

class VendorsScreen extends StatelessWidget {
  final String categoryTitle;
  final IconData categoryIcon;
  final Color categoryColor;

  const VendorsScreen({
    super.key,
    required this.categoryTitle,
    required this.categoryIcon,
    required this.categoryColor,
  });

  @override
  Widget build(BuildContext context) {
    // قائمة تجار افتراضية لكل قسم يتم جلبها بناءً على القسم
    List<Map<String, String>> sampleVendors = [
      {'name': 'متجر الفائق المعتمد - فرع مأرب', 'rating': '4.9 ⭐', 'time': '15-20 دقيقة'},
      {'name': 'مؤسسة النشامى للتجارة والخدمات', 'rating': '4.7 ⭐', 'time': '20-30 دقيقة'},
      {'name': 'الوكيل السريع للخدمات والمتاجر', 'rating': '4.8 ⭐', 'time': '10-15 دقيقة'},
      {'name': 'مركز الإنجاز الحديث', 'rating': '4.6 ⭐', 'time': '25-35 دقيقة'},
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(categoryTitle, style: const TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: categoryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: categoryColor.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(categoryIcon, size: 36, color: categoryColor),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('التجار والبائعون المعتمدون في: $categoryTitle', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: categoryColor)),
                      const SizedBox(height: 4),
                      const Text('اختر المتجر المناسب لعرض تفاصيله والتعامل معه.', style: TextStyle(color: Colors.grey, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text('قائمة التجار المتاحين حالياً:', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...sampleVendors.map((vendor) => Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 5, offset: const Offset(0, 2))],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: categoryColor.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                      child: Icon(categoryIcon, color: categoryColor, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(vendor['name']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(vendor['rating']!, style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            Text(vendor['time']!, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                ElevatedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('تم اختيار متجر: ${vendor['name']}')),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: categoryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: const Size(50, 28),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('دخول', style: TextStyle(fontSize: 11)),
                )
              ],
            ),
          )).toList(),
        ],
      ),
    );
  }
}

