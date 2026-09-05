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

  Query<Map<String, dynamic>> _storesQuery() {
    return FirebaseFirestore.instance
        .collection('stores')
        .where('active', isEqualTo: true);
  }

  bool _matchesCategory(Map<String, dynamic> data) {
    final category = (data['category'] ?? '').toString().trim();
    if (category.isEmpty || categoryTitle == 'كل المتاجر' || categoryTitle == 'العروض') {
      return true;
    }
    final normalizedCategory = category.replaceAll('وال', '').trim();
    final normalizedTitle = categoryTitle.replaceAll('وال', '').trim();
    return category == categoryTitle ||
        category.contains(categoryTitle) ||
        categoryTitle.contains(category) ||
        normalizedCategory.contains(normalizedTitle) ||
        normalizedTitle.contains(normalizedCategory);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            categoryTitle,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.black87),
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _storesQuery().snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _MessageState(
                icon: Icons.cloud_off,
                title: 'تعذر تحميل المتاجر',
                message: 'تحقق من اتصال Firebase وقواعد Firestore ثم حاول مرة أخرى.',
                action: () => _showFirebaseError(context, snapshot.error),
              );
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final stores = (snapshot.data?.docs ?? [])
                .where((doc) => _matchesCategory(doc.data()))
                .toList();

            if (stores.isEmpty) {
              return _EmptyStoresState(categoryTitle: categoryTitle);
            }

            return ListView(
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
                            Text(
                              'المتاجر المنشورة في: $categoryTitle',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: categoryColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'هذه القائمة تُقرأ مباشرة من Firestore وليست بيانات تجريبية.',
                              style: TextStyle(color: Colors.grey, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'المتاجر المتاحة: ${stores.length}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
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

  void _showFirebaseError(BuildContext context, Object? error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Firebase: ${error ?? 'خطأ غير معروف'}')),
    );
  }
}

class _StoreCard extends StatelessWidget {
  final String storeId;
  final Map<String, dynamic> data;
  final IconData categoryIcon;
  final Color categoryColor;

  const _StoreCard({
    required this.storeId,
    required this.data,
    required this.categoryIcon,
    required this.categoryColor,
  });

  String _text(String key, [String fallback = '']) =>
      (data[key] ?? fallback).toString().trim();

  @override
  Widget build(BuildContext context) {
    final name = _text('name', 'متجر بدون اسم');
    final city = _text('city');
    final address = _text('address');
    final rating = _text('rating');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StoreProductsScreen(
              storeId: storeId,
              storeName: name,
              categoryColor: categoryColor,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: categoryColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(categoryIcon, color: categoryColor, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    if (city.isNotEmpty || address.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        [city, address].where((v) => v.isNotEmpty).join(' • '),
                        style: const TextStyle(color: Colors.grey, fontSize: 11),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (rating.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text('التقييم: $rating', style: const TextStyle(color: Colors.amber, fontSize: 11)),
                    ],
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

  const StoreProductsScreen({
    super.key,
    required this.storeId,
    required this.storeName,
    required this.categoryColor,
  });

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance
        .collection('products')
        .where('storeId', isEqualTo: storeId)
        .where('active', isEqualTo: true);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text(storeName)),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: query.snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(child: Text('تعذر تحميل منتجات المتجر.'));
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final products = snapshot.data?.docs ?? [];
            if (products.isEmpty) {
              return const _MessageState(
                icon: Icons.inventory_2_outlined,
                title: 'لا توجد منتجات منشورة',
                message: 'سيظهر هنا المنتج بعد أن يضيفه التاجر ويصبح نشطاً.',
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
                    leading: CircleAvatar(
                      backgroundColor: categoryColor.withOpacity(.12),
                      child: Icon(Icons.shopping_bag, color: categoryColor),
                    ),
                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(description.isEmpty ? 'منتج منشور من المتجر' : description),
                    trailing: Text(
                      price is num ? '${price.toStringAsFixed(0)} ر.ي' : '$price',
                      style: TextStyle(color: categoryColor, fontWeight: FontWeight.bold),
                    ),
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

class _EmptyStoresState extends StatelessWidget {
  final String categoryTitle;

  const _EmptyStoresState({required this.categoryTitle});

  @override
  Widget build(BuildContext context) {
    return _MessageState(
      icon: Icons.store_outlined,
      title: 'لا توجد متاجر منشورة حالياً',
      message: categoryTitle == 'العروض'
          ? 'لا توجد عروض منشورة في Firestore حالياً.'
          : 'لم يتم نشر متجر نشط لهذا القسم بعد. لن نعرض بيانات وهمية مكانها.',
    );
  }
}

class _MessageState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? action;

  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
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
            if (action != null) ...[
              const SizedBox(height: 16),
              ElevatedButton(onPressed: action, child: const Text('عرض الخطأ')),
            ],
          ],
        ),
      ),
    );
  }
}
