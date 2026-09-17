import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/app_sections.dart';
import 'ai_assistant_page.dart';
import 'cart_page.dart';
import 'my_orders_page.dart';

class WorldHomePage extends StatefulWidget {
  const WorldHomePage({super.key});

  @override
  State<WorldHomePage> createState() => _WorldHomePageState();
}

class _WorldHomePageState extends State<WorldHomePage> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SafeArea(
          child: IndexedStack(
            index: index,
            children: const [_HomeTab(), ServicesHubPage(), _AccountTab()],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (value) => setState(() => index = value),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.explore_outlined),
              selectedIcon: Icon(Icons.explore),
              label: 'الرئيسية',
            ),
            NavigationDestination(
              icon: Icon(Icons.apps_outlined),
              selectedIcon: Icon(Icons.apps),
              label: 'الخدمات',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'حسابي',
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab();

  void _open(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF0B6E4F),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(Icons.hub_outlined, color: Colors.white),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('الفائق يمن', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
                  Text('منصة واحدة للحياة والأعمال', style: TextStyle(color: Colors.black54, fontSize: 12)),
                ],
              ),
            ),
            IconButton(
              onPressed: () => _open(context, const CartPage()),
              tooltip: 'السلة',
              icon: const Icon(Icons.shopping_cart_outlined),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [Color(0xFF0B6E4F), Color(0xFF124E78)],
            ),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.auto_awesome, color: Colors.white),
                  SizedBox(width: 8),
                  Text('ذكاء الفائق', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'كل ما تحتاجه\nفي منصة واحدة.',
                style: TextStyle(color: Colors.white, fontSize: 29, height: 1.08, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              const Text('متاجر • خدمات • دفع • طلبات • تتبع • سفر • أعمال', style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => _open(context, const AiAssistantPage()),
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('اسأل ذكاء الفائق'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            _action(context, 'السلة', Icons.shopping_cart_outlined, const CartPage()),
            _action(context, 'طلباتي', Icons.local_shipping_outlined, const MyOrdersPage()),
            _action(context, 'المحافظ', Icons.account_balance_wallet_outlined, const WalletCenterPage()),
            _action(context, 'الخدمات', Icons.apps_outlined, const ServicesHubPage()),
          ],
        ),
        const SizedBox(height: 26),
        const Text('اكتشف الأقسام', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        SizedBox(
          height: 112,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: appSections.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) => _CompactSectionCard(section: appSections[i]),
          ),
        ),
        const SizedBox(height: 26),
        const Text('أقسام الفائق', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: appSections.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.02,
          ),
          itemBuilder: (_, i) => _SectionCard(section: appSections[i]),
        ),
      ],
    );
  }

  Widget _action(BuildContext context, String title, IconData icon, Widget page) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: 5),
        child: InkWell(
          borderRadius: BorderRadius.circular(17),
          onTap: () => _open(context, page),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 3),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: const Color(0xFFE4EAE7)),
            ),
            child: Column(
              children: [
                Icon(icon, color: const Color(0xFF0B6E4F)),
                const SizedBox(height: 6),
                Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactSectionCard extends StatelessWidget {
  final AppSection section;

  const _CompactSectionCard({required this.section});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WorldSectionPage(section: section))),
      child: Container(
        width: 112,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF7FAF8),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE3EAE6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: const Color(0xFFE7F3EE), borderRadius: BorderRadius.circular(13)),
              child: Icon(_SectionCard.iconFor(section.icon), color: const Color(0xFF0B6E4F), size: 21),
            ),
            const Spacer(),
            Text(section.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final AppSection section;

  const _SectionCard({required this.section});

  static IconData iconFor(String name) {
    switch (name) {
      case 'storefront': return Icons.storefront_outlined;
      case 'restaurant': return Icons.restaurant_outlined;
      case 'pharmacy': return Icons.local_pharmacy_outlined;
      case 'beauty': return Icons.face_retouching_natural;
      case 'construction': return Icons.construction_outlined;
      case 'car': return Icons.directions_car_outlined;
      case 'flight': return Icons.flight_takeoff_outlined;
      case 'hotel': return Icons.hotel_outlined;
      case 'account_balance': return Icons.account_balance_wallet_outlined;
      case 'handyman': return Icons.handyman_outlined;
      case 'devices': return Icons.devices_outlined;
      case 'home': return Icons.home_work_outlined;
      case 'work': return Icons.work_outline;
      case 'school': return Icons.school_outlined;
      case 'medical': return Icons.medical_services_outlined;
      default: return Icons.explore_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WorldSectionPage(section: section))),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(color: const Color(0xFFE7F3EE), borderRadius: BorderRadius.circular(15)),
                    child: Icon(iconFor(section.icon), color: const Color(0xFF0B6E4F), size: 27),
                  ),
                  const Spacer(),
                  const Icon(Icons.arrow_back_ios_new, size: 14, color: Colors.black38),
                ],
              ),
              const Spacer(),
              Text(section.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(section.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.black54, height: 1.25)),
            ],
          ),
        ),
      ),
    );
  }
}

class WorldSectionPage extends StatelessWidget {
  final AppSection section;

  const WorldSectionPage({super.key, required this.section});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(section.title, style: const TextStyle(fontWeight: FontWeight.w900)),
          actions: [
            IconButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartPage())),
              tooltip: 'السلة',
              icon: const Icon(Icons.shopping_cart_outlined),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFE7F3EE), Color(0xFFEAF2F8)]),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(17)),
                    child: Icon(_SectionCard.iconFor(section.icon), color: const Color(0xFF0B6E4F), size: 31),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(section.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 3),
                        Text(section.subtitle, style: const TextStyle(color: Colors.black54, height: 1.3)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              decoration: InputDecoration(
                hintText: 'ابحث في ${section.title}...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 18),
            const Text('المتاجر المعتمدة', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 9),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('stores')
                  .where('sectionId', isEqualTo: section.id)
                  .where('status', isEqualTo: 'approved')
                  .limit(30)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: Padding(padding: EdgeInsets.all(28), child: CircularProgressIndicator()));
                }
                if (snapshot.hasError) {
                  return const _Info(title: 'تعذر تحميل المتاجر', text: 'تحقق من الاتصال والصلاحيات.');
                }
                final stores = snapshot.data?.docs ?? const [];
                if (stores.isEmpty) {
                  return const _Info(title: 'لا توجد متاجر معتمدة بعد', text: 'سيظهر هنا المحتوى الحقيقي عند اعتماد المتاجر.');
                }
                return Column(children: stores.map((document) => _StoreCard(store: document)).toList());
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _StoreCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> store;

  const _StoreCard({required this.store});

  Future<void> _addToCart(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> product) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يجب تسجيل الدخول أولاً.')));
      return;
    }

    final data = product.data();
    final price = data['price'];
    final stock = data['stock'];
    if (price is! num || price < 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('سعر الصنف غير صالح.')));
      return;
    }
    if (stock is num && stock <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('هذا الصنف غير متوفر حالياً.')));
      return;
    }

    final name = (data['name'] ?? data['title'] ?? 'صنف').toString();
    final cartRef = FirebaseFirestore.instance.collection('carts').doc(user.uid);

    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(cartRef);
        final cart = snap.data() ?? <String, dynamic>{};
        final rawItems = cart['items'];
        final items = rawItems is List
            ? rawItems.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
            : <Map<String, dynamic>>[];

        final itemIndex = items.indexWhere((item) => item['productId'] == product.id);
        if (itemIndex >= 0) {
          final current = (items[itemIndex]['quantity'] as num?)?.toInt() ?? 1;
          final next = current + 1;
          if (stock is num && next > stock.toInt()) {
            throw StateError('لا يمكن تجاوز الكمية المتوفرة.');
          }
          if (next > 100) {
            throw StateError('الحد الأقصى 100 قطعة للصنف.');
          }
          items[itemIndex]['quantity'] = next;
        } else {
          items.add({
            'productId': product.id,
            'name': name,
            'price': price,
            'currency': data['currency'] ?? 'YER',
            'quantity': 1,
            'storeId': data['storeId'] ?? store.id,
            'merchantId': data['merchantId'] ?? data['ownerId'] ?? '',
            'ownerId': data['ownerId'] ?? '',
            'imageUrl': data['imageUrl'] ?? data['image'] ?? '',
            'addedAt': Timestamp.now(),
          });
        }

        tx.set(
          cartRef,
          {
            'ownerId': user.uid,
            'customerId': user.uid,
            'items': items,
            'currency': data['currency'] ?? cart['currency'] ?? 'YER',
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تمت إضافة «$name» إلى السلة.')));
      }
    } on StateError catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'تعذر تحديث السلة.')));
      }
    } on FirebaseException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تحديث السلة: ${e.message ?? e.code}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = store.data();
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: const CircleAvatar(
          backgroundColor: Color(0xFFE7F3EE),
          child: Icon(Icons.storefront_outlined, color: Color(0xFF0B6E4F)),
        ),
        title: Text('${data['name'] ?? 'متجر'}', style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text('${data['address'] ?? 'عنوان غير محدد'}'),
        children: [
          Container(height: 1, color: const Color(0xFFE8ECEA)),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('products')
                .where('storeId', isEqualTo: store.id)
                .where('status', isEqualTo: 'active')
                .limit(40)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return const Padding(padding: EdgeInsets.all(16), child: Text('تعذر تحميل الأصناف.'));
              }
              final products = snapshot.data?.docs ?? const [];
              if (products.isEmpty) {
                return const Padding(padding: EdgeInsets.all(16), child: Text('لا توجد أصناف نشطة حالياً.'));
              }

              return Column(
                children: products.map((product) {
                  final productData = product.data();
                  final price = productData['price'];
                  final imageUrl = (productData['imageUrl'] ?? productData['image'] ?? '').toString();
                  return ListTile(
                    leading: imageUrl.isEmpty
                        ? const CircleAvatar(
                            backgroundColor: Color(0xFFE7F3EE),
                            child: Icon(Icons.inventory_2_outlined, color: Color(0xFF0B6E4F)),
                          )
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.network(
                              imageUrl,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const CircleAvatar(child: Icon(Icons.broken_image_outlined)),
                            ),
                          ),
                    title: Text('${productData['name'] ?? 'صنف'}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('المتوفر: ${productData['stock'] ?? '—'}'),
                    trailing: SizedBox(
                      width: 150,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Text(
                              price is num ? '$price ${productData['currency'] ?? 'YER'}' : 'عند الطلب',
                              textAlign: TextAlign.end,
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                          IconButton(
                            onPressed: () => _addToCart(context, product),
                            tooltip: 'أضف للسلة',
                            icon: const Icon(Icons.add_shopping_cart, color: Color(0xFF0B6E4F)),
                          ),
                        ],
                      ),
                    ),
                    onTap: () => _addToCart(context, product),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class ServicesHubPage extends StatelessWidget {
  const ServicesHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('الخدمات', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          const Text('الوصول السريع إلى خدمات الفائق يمن.', style: TextStyle(color: Colors.black54)),
          const SizedBox(height: 18),
          _ServiceTile(icon: Icons.shopping_cart_outlined, title: 'السلة', subtitle: 'مراجعة الأصناف قبل الطلب', page: const CartPage()),
          _ServiceTile(icon: Icons.local_shipping_outlined, title: 'طلباتي', subtitle: 'متابعة الطلبات والتوصيل', page: const MyOrdersPage()),
          _ServiceTile(icon: Icons.account_balance_wallet_outlined, title: 'المحافظ', subtitle: 'مركز المحافظ والخدمات المالية', page: const WalletCenterPage()),
          _ServiceTile(icon: Icons.auto_awesome, title: 'ذكاء الفائق', subtitle: 'مساعد المنصة', page: const AiAssistantPage()),
        ],
      ),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget page;

  const _ServiceTile({required this.icon, required this.title, required this.subtitle, required this.page});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: ListTile(
        leading: CircleAvatar(backgroundColor: const Color(0xFFE7F3EE), child: Icon(icon, color: const Color(0xFF0B6E4F))),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_left),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
      ),
    );
  }
}

class WalletCenterPage extends StatelessWidget {
  const WalletCenterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('المحافظ', style: TextStyle(fontWeight: FontWeight.w900))),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.account_balance_wallet_outlined, size: 42, color: Color(0xFF0B6E4F)),
                    SizedBox(height: 12),
                    Text('مركز المحافظ', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                    SizedBox(height: 8),
                    Text('تظهر هنا المحافظ والخدمات المالية المرتبطة بالحساب عند تفعيلها من المنصة.'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountTab extends StatelessWidget {
  const _AccountTab();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('حسابي', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
          const SizedBox(height: 18),
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title: Text(user?.displayName ?? 'مستخدم الفائق'),
              subtitle: Text(user?.email ?? 'حساب مسجل الدخول'),
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.shopping_cart_outlined),
            title: const Text('السلة', style: TextStyle(fontWeight: FontWeight.w800)),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartPage())),
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: const Text('طلباتي', style: TextStyle(fontWeight: FontWeight.w800)),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyOrdersPage())),
          ),
        ],
      ),
    );
  }
}

class _Info extends StatelessWidget {
  final String title;
  final String text;

  const _Info({required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(text, style: const TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}
