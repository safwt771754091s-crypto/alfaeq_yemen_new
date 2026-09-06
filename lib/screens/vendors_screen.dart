import 'package:cloud_firestore/cloud_firestore.dart';
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

  static const _buildTag = 'DATA-FLOW • 07-09-2026';

  Query<Map<String, dynamic>> _storesQuery() => FirebaseFirestore.instance
      .collection('stores')
      .where('active', isEqualTo: true);

  bool _matchesCategory(Map<String, dynamic> data) {
    final category = (data['category'] ?? '').toString().trim();
    if (category.isEmpty || categoryTitle == 'كل المتاجر' || categoryTitle == 'العروض') return true;
    final a = category.replaceAll('وال', '').trim();
    final b = categoryTitle.replaceAll('وال', '').trim();
    return category == categoryTitle || category.contains(categoryTitle) || categoryTitle.contains(category) || a.contains(b) || b.contains(a);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(categoryTitle),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(24),
            child: Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: EdgeInsets.only(right: 16, bottom: 7),
                child: Text(_buildTag, style: TextStyle(fontSize: 9, color: Colors.blueGrey)),
              ),
            ),
          ),
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _storesQuery().snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _MessageState(
                icon: Icons.cloud_off,
                title: 'تعذر تحميل المتاجر',
                message: 'خطأ Firebase: ${snapshot.error}',
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final stores = (snapshot.data?.docs ?? [])
                .where((doc) => _matchesCategory(doc.data()))
                .toList();

            if (stores.isEmpty) {
              return _MessageState(
                icon: Icons.store_outlined,
                title: 'لا توجد متاجر منشورة حالياً',
                message: categoryTitle == 'العروض'
                    ? 'لا توجد عروض منشورة في Firestore حالياً.'
                    : 'لم يتم العثور على متجر نشط في Firestore لهذا القسم. لن نعرض بيانات وهمية.',
              );
            }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: categoryColor.withOpacity(.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: categoryColor.withOpacity(.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(categoryIcon, size: 34, color: categoryColor),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('المتاجر المنشورة: ${stores.length}', style: TextStyle(fontWeight: FontWeight.bold, color: categoryColor)),
                            const SizedBox(height: 3),
                            const Text('المصدر: Firestore • بدون بيانات تجريبية', style: TextStyle(color: Colors.grey, fontSize: 11)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                ...stores.map((doc) => _StoreCard(
                      storeId: doc.id,
                      data: doc.data(),
                      categoryIcon: categoryIcon,
                      categoryColor: categoryColor,
                    )),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StoreCard extends StatelessWidget {
  final String storeId;
  final Map<String, dynamic> data;
  final IconData categoryIcon;
  final Color categoryColor;

  const _StoreCard({required this.storeId, required this.data, required this.categoryIcon, required this.categoryColor});

  String _text(String key, [String fallback = '']) => (data[key] ?? fallback).toString().trim();

  @override
  Widget build(BuildContext context) {
    final name = _text('name', 'متجر بدون اسم');
    final city = _text('city');
    final address = _text('address');
    final rating = _text('rating');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StoreProductsScreen(storeId: storeId, storeName: name, categoryColor: categoryColor),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: categoryColor.withOpacity(.12),
                child: Icon(categoryIcon, color: categoryColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    if (city.isNotEmpty || address.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text([city, address].where((v) => v.isNotEmpty).join(' • '), style: const TextStyle(color: Colors.grey, fontSize: 11)),
                      ),
                    if (rating.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text('التقييم: $rating', style: const TextStyle(color: Colors.amber, fontSize: 11)),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left),
            ],
          ),
        ),
      ),
    );
  }
}

class StoreProductsScreen extends StatelessWidget {
  final String storeId;
  final String storeName;
  final Color categoryColor;

  const StoreProductsScreen({super.key, required this.storeId, required this.storeName, required this.categoryColor});

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance.collection('products').where('storeId', isEqualTo: storeId).where('active', isEqualTo: true);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text(storeName)),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: query.snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return Center(child: Text('تعذر تحميل المنتجات: ${snapshot.error}'));
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            final products = snapshot.data?.docs ?? [];
            if (products.isEmpty) {
              return const _MessageState(
                icon: Icons.inventory_2_outlined,
                title: 'لا توجد منتجات منشورة',
                message: 'سيظهر المنتج هنا بعد ربطه بالمتجر ونشره في Firestore.',
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: products.length,
              itemBuilder: (context, index) {
                final data = products[index].data();
                final name = (data['name'] ?? 'منتج بدون اسم').toString();
                final description = (data['description'] ?? '').toString();
                final price = data['price'];
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: CircleAvatar(backgroundColor: categoryColor.withOpacity(.12), child: Icon(Icons.shopping_bag, color: categoryColor)),
                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(description.isEmpty ? 'منتج منشور من المتجر' : description),
                    trailing: Text(price is num ? '${price.toStringAsFixed(0)} ر.ي' : '$price', style: TextStyle(color: categoryColor, fontWeight: FontWeight.bold)),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _MessageState({required this.icon, required this.title, required this.message});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
}
