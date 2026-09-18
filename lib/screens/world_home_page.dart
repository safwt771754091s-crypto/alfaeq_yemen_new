import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/app_sections.dart';
import '../services/auth_service.dart';
import 'ai_assistant_page.dart';
import 'cart_page.dart';
import 'location_picker_page.dart';
import 'my_orders_page.dart';

const _blue = Color(0xFF0D6EFD);
const _yellow = Color(0xFFFFC107);
const _navy = Color(0xFF0A2540);
const _green = Color(0xFF28A745);
const _surface = Color(0xFFF5F7FA);

class WorldHomePage extends StatefulWidget {
  const WorldHomePage({super.key});
  @override
  State<WorldHomePage> createState() => _WorldHomePageState();
}

class _WorldHomePageState extends State<WorldHomePage> {
  int index = 0;
  void _open(BuildContext context, Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _HomeTab(onOpen: _open),
      const _StoresTab(),
      const CartPage(),
      const MyOrdersPage(),
      const _AccountTab(),
    ];
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _surface,
        body: SafeArea(child: IndexedStack(index: index, children: pages)),
        bottomNavigationBar: _MainBottomBar(selectedIndex: index, onSelected: (v) => setState(() => index = v)),
      ),
    );
  }
}

class _MainBottomBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  const _MainBottomBar({required this.selectedIndex, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final items = const [
      (Icons.home_outlined, Icons.home, 'الرئيسية'),
      (Icons.storefront_outlined, Icons.storefront, 'المتاجر'),
      (Icons.shopping_cart_outlined, Icons.shopping_cart, 'السلة'),
      (Icons.receipt_long_outlined, Icons.receipt_long, 'طلباتي'),
      (Icons.person_outline, Icons.person, 'حسابي'),
    ];
    final user = FirebaseAuth.instance.currentUser;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: user == null ? null : FirebaseFirestore.instance.collection('carts').doc(user.uid).snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? <String, dynamic>{};
        final raw = data['items'];
        var cartCount = 0;
        if (raw is List) {
          for (final item in raw) {
            if (item is Map && item['quantity'] is num) cartCount += (item['quantity'] as num).toInt();
          }
        }
        return Container(
          decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFE5EAF0)))),
          child: SafeArea(
            top: false,
            child: Row(
              children: List.generate(items.length, (i) {
                final selected = selectedIndex == i;
                final item = items[i];
                final icon = i == 2
                    ? _CartBadgeIcon(icon: selected ? item.$2 : item.$1, count: cartCount, color: selected ? _blue : _navy)
                    : Icon(selected ? item.$2 : item.$1, color: selected ? _blue : _navy, size: 24);
                return Expanded(
                  child: InkWell(
                    onTap: () => onSelected(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          icon,
                          const SizedBox(height: 3),
                          Text(item.$3, style: TextStyle(color: selected ? _blue : _navy, fontSize: 11, fontWeight: selected ? FontWeight.w900 : FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        );
      },
    );
  }
}

class _CartBadgeIcon extends StatelessWidget {
  final IconData icon;
  final int count;
  final Color color;
  const _CartBadgeIcon({required this.icon, required this.count, required this.color});
  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      Icon(icon, color: color, size: 24),
      if (count > 0)
        Positioned(
          top: -7,
          right: -10,
          child: Container(
            constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(color: _yellow, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white, width: 1.5)),
            child: Text('$count', textAlign: TextAlign.center, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: _navy)),
          ),
        ),
    ],
  );
}

class _HomeTab extends StatefulWidget {
  final void Function(BuildContext, Widget) onOpen;
  const _HomeTab({required this.onOpen});
  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  String _locationLabel = 'أمانة العاصمة';

  Future<void> _pickLocation() async {
    final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => const LocationPickerPage(title: 'تحديد موقع التوصيل')));
    if (!mounted || result == null) return;
    setState(() => _locationLabel = 'موقعي المحدد');
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _HomeHeader(
            locationLabel: _locationLabel,
            onLocationTap: _pickLocation,
            onCart: () => widget.onOpen(context, const CartPage()),
            onNotifications: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ستظهر إشعارات الطلبات والعروض هنا.'))),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              const SizedBox(height: 14),
              const _SearchBar(),
              const SizedBox(height: 16),
              _HeroBanner(onTap: () => widget.onOpen(context, const AiAssistantPage())),
              const SizedBox(height: 10),
              const _BannerDots(),
              const SizedBox(height: 18),
              _CategoriesSection(onOpen: widget.onOpen),
              const SizedBox(height: 22),
              _OffersSection(onAddToCart: (product) => _addProductToCart(context, product)),
              const SizedBox(height: 24),
              const _BenefitsBar(),
            ]),
          ),
        ),
      ],
    );
  }
}

class _AlfaeqLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final blue = Paint()..color = _blue..style = PaintingStyle.stroke..strokeWidth = size.width * .075..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
    final yellow = Paint()..color = _yellow..style = PaintingStyle.fill;
    final cart = Path()
      ..moveTo(size.width * .10, size.height * .30)
      ..lineTo(size.width * .27, size.height * .30)
      ..lineTo(size.width * .37, size.height * .76)
      ..lineTo(size.width * .78, size.height * .76)
      ..lineTo(size.width * .90, size.height * .42)
      ..lineTo(size.width * .31, size.height * .42);
    canvas.drawPath(cart, blue);
    canvas.drawLine(Offset(size.width * .13, size.height * .30), Offset(size.width * .05, size.height * .30), blue);
    canvas.drawCircle(Offset(size.width * .45, size.height * .89), size.width * .045, Paint()..color = _blue);
    canvas.drawCircle(Offset(size.width * .77, size.height * .89), size.width * .045, Paint()..color = _blue);
    final yemen = Path()
      ..moveTo(size.width * .30, size.height * .18)
      ..lineTo(size.width * .43, size.height * .08)
      ..lineTo(size.width * .70, size.height * .06)
      ..lineTo(size.width * .86, size.height * .19)
      ..lineTo(size.width * .78, size.height * .38)
      ..lineTo(size.width * .48, size.height * .41)
      ..lineTo(size.width * .32, size.height * .32)
      ..close();
    canvas.drawPath(yemen, yellow);
    final tp = TextPainter(
      text: const TextSpan(text: 'f', style: TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w900, height: 1)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(size.width * .53 - tp.width / 2, size.height * .45));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _HomeHeader extends StatelessWidget {
  final String locationLabel;
  final VoidCallback onLocationTap;
  final VoidCallback onCart;
  final VoidCallback onNotifications;
  const _HomeHeader({required this.locationLabel, required this.onLocationTap, required this.onCart, required this.onNotifications});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 26),
      decoration: const BoxDecoration(color: _navy, borderRadius: BorderRadius.vertical(bottom: Radius.circular(30))),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
                child: CustomPaint(painter: _AlfaeqLogoPainter()),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('الفائق يمن', style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900)),
                    SizedBox(height: 1),
                    Text('ALFAEQ YEMEN', style: TextStyle(color: _yellow, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.7)),
                    SizedBox(height: 2),
                    Text('كل احتياجاتك في تطبيق واحد', style: TextStyle(color: Colors.white70, fontSize: 11)),
                  ],
                ),
              ),
              IconButton(onPressed: onNotifications, icon: const Icon(Icons.notifications_none, color: Colors.white)),
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseAuth.instance.currentUser == null ? null : FirebaseFirestore.instance.collection('carts').doc(FirebaseAuth.instance.currentUser!.uid).snapshots(),
                builder: (context, snapshot) {
                  final raw = snapshot.data?.data()?['items'];
                  var count = 0;
                  if (raw is List) for (final item in raw) if (item is Map && item['quantity'] is num) count += (item['quantity'] as num).toInt();
                  return IconButton(onPressed: onCart, icon: _CartBadgeIcon(icon: Icons.shopping_cart_outlined, count: count, color: Colors.white));
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: onLocationTap,
              icon: const Icon(Icons.location_on_outlined, color: Colors.white, size: 19),
              label: Text(locationLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF4BA1FF)), shape: const StadiumBorder()),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar();
  @override
  Widget build(BuildContext context) => TextField(
        decoration: InputDecoration(
          hintText: 'ابحث عن منتجات أو خدمات...',
          prefixIcon: const Icon(Icons.search, color: _navy),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
        ),
      );
}

class _HeroBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _HeroBanner({required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          height: 178,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_blue, _navy], begin: Alignment.topRight, end: Alignment.bottomLeft),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Stack(
            children: [
              Positioned(left: -20, bottom: -40, child: Icon(Icons.shopping_cart_rounded, size: 150, color: Colors.white.withValues(alpha: .08))),
              const Align(
                alignment: Alignment.centerRight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('كل احتياجاتك', style: TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.w900)),
                    Text('في تطبيق واحد', style: TextStyle(color: _yellow, fontSize: 25, fontWeight: FontWeight.w900)),
                    SizedBox(height: 12),
                    Text('تسوق • خدمات • توصيل • سفر • أعمال', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    SizedBox(height: 14),
                    Text('اسأل ذكاء الفائق ←', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              Positioned(
                left: 12,
                top: 15,
                child: Container(
                  width: 74,
                  height: 116,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .12), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white24)),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.percent_rounded, color: Colors.white, size: 30),
                      SizedBox(height: 10),
                      Icon(Icons.local_shipping_outlined, color: Colors.white, size: 28),
                      SizedBox(height: 10),
                      Icon(Icons.verified_user_outlined, color: Colors.white, size: 28),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class _BannerDots extends StatelessWidget {
  const _BannerDots();
  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          4,
          (i) => Container(
            width: i == 0 ? 9 : 7,
            height: i == 0 ? 9 : 7,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(color: i == 0 ? _blue : const Color(0xFFD4D9DF), shape: BoxShape.circle),
          ),
        ),
      );
}

class _CategoriesSection extends StatelessWidget {
  final void Function(BuildContext, Widget) onOpen;
  const _CategoriesSection({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final categories = appSections.take(10).toList();
    return Column(
      children: [
        Row(
          children: [
            const Expanded(child: Text('أقسام الفائق', style: TextStyle(color: _navy, fontSize: 21, fontWeight: FontWeight.w900))),
            TextButton(onPressed: () => onOpen(context, const _StoresTab()), child: const Text('عرض الكل')),
          ],
        ),
        const SizedBox(height: 4),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: categories.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5, crossAxisSpacing: 7, mainAxisSpacing: 10, childAspectRatio: .78),
          itemBuilder: (context, i) {
            final section = categories[i];
            return InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => onOpen(context, WorldSectionPage(section: section)),
              child: Container(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 5),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE6EBF1))),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 43,
                      height: 43,
                      decoration: BoxDecoration(color: const Color(0xFFF1F6FF), borderRadius: BorderRadius.circular(13)),
                      child: Icon(_SectionCard.iconFor(section.icon), color: _blue, size: 24),
                    ),
                    const SizedBox(height: 6),
                    Text(section.title, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _navy, fontSize: 10.5, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _OffersSection extends StatelessWidget {
  final Future<void> Function(QueryDocumentSnapshot<Map<String, dynamic>>) onAddToCart;
  const _OffersSection({required this.onAddToCart});

  int _discount(Map<String, dynamic> data) {
    final percent = data['discountPercent'];
    final price = data['price'];
    final original = data['originalPrice'];
    if (percent is num && percent > 0 && percent <= 100) return percent.round();
    if (price is num && original is num && original > price) return ((1 - (price / original)) * 100).round();
    return 0;
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('products').where('status', isEqualTo: 'active').limit(40).snapshots(),
        builder: (context, snapshot) {
          final products = (snapshot.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
              .where((doc) => _discount(doc.data()) > 0)
              .take(8)
              .toList();
          return Column(
            children: [
              Row(
                children: [
                  const Expanded(child: Text('عروض مميزة 🔥', style: TextStyle(color: _navy, fontSize: 21, fontWeight: FontWeight.w900))),
                  TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _OffersPage())), child: const Text('عرض الكل')),
                ],
              ),
              const SizedBox(height: 8),
              if (snapshot.connectionState == ConnectionState.waiting)
                const LinearProgressIndicator()
              else if (products.isEmpty)
                const _Info(title: 'العروض جاهزة للظهور', text: 'عند إضافة خصم حقيقي للصنف سيظهر تلقائياً هنا.')
              else
                SizedBox(
                  height: 238,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: products.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, i) {
                      final product = products[i];
                      return _OfferCard(product: product, discount: _discount(product.data()), onAdd: () => onAddToCart(product));
                    },
                  ),
                ),
            ],
          );
        },
      );
}

class _OfferCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> product;
  final int discount;
  final VoidCallback onAdd;
  const _OfferCard({required this.product, required this.discount, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final data = product.data();
    final price = data['price'];
    final original = data['originalPrice'];
    final imageUrl = (data['imageUrl'] ?? data['image'] ?? '').toString();
    return Container(
      width: 178,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFFE3E8EF))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: imageUrl.isEmpty
                    ? Container(height: 108, color: const Color(0xFFF0F3F7), child: const Icon(Icons.image_outlined, size: 42, color: Colors.black26))
                    : Image.network(imageUrl, height: 108, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(height: 108, color: const Color(0xFFF0F3F7), child: const Icon(Icons.broken_image_outlined))),
              ),
              Positioned(
                top: 5,
                right: 5,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(8)),
                  child: Text('خصم $discount%', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text('${data['name'] ?? 'صنف'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _navy, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Row(
            children: [
              Expanded(child: Text(price is num ? '${price.toStringAsFixed(0)} ر.ي' : 'عند الطلب', style: const TextStyle(color: _navy, fontWeight: FontWeight.w900))),
              if (original is num) Text('${original.toStringAsFixed(0)}', style: const TextStyle(color: Colors.grey, decoration: TextDecoration.lineThrough, fontSize: 10)),
            ],
          ),
          const Spacer(),
          SizedBox(height: 34, child: FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add_shopping_cart, size: 16), label: const Text('أضف'), style: FilledButton.styleFrom(backgroundColor: _blue, padding: EdgeInsets.zero))),
        ],
      ),
    );
  }
}

class _BenefitsBar extends StatelessWidget {
  const _BenefitsBar();
  @override
  Widget build(BuildContext context) {
    final benefits = const [
      (Icons.credit_card_outlined, 'طرق دفع متعددة'),
      (Icons.percent_rounded, 'عروض وخصومات'),
      (Icons.local_shipping_outlined, 'توصيل سريع'),
      (Icons.headset_mic_outlined, 'دعم 24/7'),
      (Icons.verified_user_outlined, 'آمن وموثوق'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(color: _navy, borderRadius: BorderRadius.circular(18)),
      child: Row(children: benefits.map((item) => Expanded(child: Column(children: [
        Icon(item.$1, color: Colors.white, size: 25),
        const SizedBox(height: 6),
        Text(item.$2, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
      ]))).toList()),
    );
  }
}

class _StoresTab extends StatelessWidget {
  const _StoresTab();
  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
        children: [
          const Text('المتاجر', style: TextStyle(color: _navy, fontSize: 28, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          const Text('متاجر الفائق المعتمدة ومنتجاتها الحقيقية.', style: TextStyle(color: Colors.black54)),
          const SizedBox(height: 16),
          ...appSections.map((section) => Card(
                elevation: 0,
                child: ListTile(
                  leading: Container(width: 45, height: 45, decoration: BoxDecoration(color: const Color(0xFFF1F6FF), borderRadius: BorderRadius.circular(13)), child: Icon(_SectionCard.iconFor(section.icon), color: _blue)),
                  title: Text(section.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: Text(section.subtitle),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WorldSectionPage(section: section))),
                ),
              )),
        ],
      );
}

class _OffersPage extends StatelessWidget {
  const _OffersPage();
  int _discount(Map<String, dynamic> data) {
    final p = data['discountPercent'];
    final price = data['price'];
    final original = data['originalPrice'];
    if (p is num && p > 0 && p <= 100) return p.round();
    if (price is num && original is num && original > price) return ((1 - price / original) * 100).round();
    return 0;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('العروض المميزة', style: TextStyle(fontWeight: FontWeight.w900))),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('products').where('status', isEqualTo: 'active').limit(100).snapshots(),
          builder: (context, snapshot) {
            final docs = (snapshot.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]).where((d) => _discount(d.data()) > 0).toList();
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (docs.isEmpty) return const Center(child: _Info(title: 'لا توجد عروض حالياً', text: 'أضف خصماً حقيقياً إلى منتجاتك ليظهر هنا.'));
            return GridView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: docs.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: .68),
              itemBuilder: (_, i) {
                final d = docs[i];
                return _OfferCard(product: d, discount: _discount(d.data()), onAdd: () => _addProductToCart(context, d));
              },
            );
          },
        ),
      );
}

Future<void> _addProductToCart(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> product) async {
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
      final items = rawItems is List ? rawItems.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList() : <Map<String, dynamic>>[];
      final itemIndex = items.indexWhere((item) => item['productId'] == product.id);
      if (itemIndex >= 0) {
        final current = (items[itemIndex]['quantity'] as num?)?.toInt() ?? 1;
        final next = current + 1;
        if (stock is num && next > stock.toInt()) throw StateError('لا يمكن تجاوز الكمية المتوفرة.');
        if (next > 100) throw StateError('الحد الأقصى 100 قطعة للصنف.');
        items[itemIndex]['quantity'] = next;
      } else {
        items.add({
          'productId': product.id,
          'name': name,
          'price': price,
          'currency': data['currency'] ?? 'YER',
          'quantity': 1,
          'storeId': data['storeId'] ?? '',
          'merchantId': data['merchantId'] ?? data['ownerId'] ?? '',
          'ownerId': data['ownerId'] ?? '',
          'imageUrl': data['imageUrl'] ?? data['image'] ?? '',
          'addedAt': Timestamp.now(),
        });
      }
      tx.set(cartRef, {'ownerId': user.uid, 'customerId': user.uid, 'items': items, 'currency': data['currency'] ?? cart['currency'] ?? 'YER', 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    });
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تمت إضافة «$name» إلى السلة.')));
  } on StateError catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
  } on FirebaseException catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تحديث السلة: ${e.message}')));
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
      case 'account_balance': return Icons.account_balance_outlined;
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
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class WorldSectionPage extends StatelessWidget {
  final AppSection section;
  const WorldSectionPage({super.key, required this.section});

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(
            title: Text(section.title, style: const TextStyle(fontWeight: FontWeight.w900)),
            actions: [
              IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartPage())), tooltip: 'السلة', icon: const Icon(Icons.shopping_cart_outlined)),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFE7F3EE), Color(0xFFEAF2F8)]), borderRadius: BorderRadius.circular(24)),
                child: Row(
                  children: [
                    Container(width: 56, height: 56, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(17)), child: Icon(_SectionCard.iconFor(section.icon), color: _green, size: 31)),
                    const SizedBox(width: 13),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(section.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 3),
                      Text(section.subtitle, style: const TextStyle(color: Colors.black54, height: 1.3)),
                    ])),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(decoration: InputDecoration(hintText: 'ابحث في ${section.title}...', prefixIcon: const Icon(Icons.search), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none))),
              const SizedBox(height: 18),
              const Text('المتاجر المعتمدة', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 9),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance.collection('stores').where('sectionId', isEqualTo: section.id).where('status', isEqualTo: 'approved').limit(30).snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: Padding(padding: EdgeInsets.all(28), child: CircularProgressIndicator()));
                  if (snapshot.hasError) return const _Info(title: 'تعذر تحميل المتاجر', text: 'تحقق من الاتصال والصلاحيات.');
                  final stores = snapshot.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                  if (stores.isEmpty) return const _Info(title: 'لا توجد متاجر معتمدة بعد', text: 'سيظهر هنا المحتوى الحقيقي عند اعتماد المتاجر.');
                  return Column(children: stores.map((document) => _StoreCard(store: document)).toList());
                },
              ),
            ],
          ),
        ),
      );
}

class _StoreCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> store;
  const _StoreCard({required this.store});

  @override
  Widget build(BuildContext context) {
    final data = store.data();
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: const CircleAvatar(
          backgroundColor: Color(0xFFF1F6FF),
          child: Icon(Icons.storefront_outlined, color: _blue),
        ),
        title: Text(
          data['name']?.toString() ?? 'متجر',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(data['address']?.toString() ?? 'عنوان غير محدد'),
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
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                );
              }
              if (snapshot.hasError) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('تعذر تحميل الأصناف.'),
                );
              }
              final products = snapshot.data?.docs ??
                  const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
              if (products.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('لا توجد أصناف نشطة حالياً.'),
                );
              }
              return Column(
                children: products.map((product) {
                  final p = product.data();
                  final imageUrl =
                      (p['imageUrl'] ?? p['image'] ?? '').toString();
                  final price = p['price'];
                  Widget leading;
                  if (imageUrl.isEmpty) {
                    leading = const CircleAvatar(
                      backgroundColor: Color(0xFFF1F6FF),
                      child: Icon(Icons.inventory_2_outlined, color: _blue),
                    );
                  } else {
                    leading = ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        imageUrl,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const CircleAvatar(
                          child: Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    );
                  }

                  final priceText = price is num
                      ? '${price.toStringAsFixed(0)} ${p['currency'] ?? 'YER'}'
                      : 'عند الطلب';

                  return ListTile(
                    leading: leading,
                    title: Text(
                      p['name']?.toString() ?? 'صنف',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text('المتوفر: ${p['stock'] ?? '—'}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          priceText,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        IconButton(
                          onPressed: () =>
                              _addProductToCart(context, product),
                          tooltip: 'أضف للسلة',
                          icon: const Icon(
                            Icons.add_shopping_cart,
                            color: _blue,
                          ),
                        ),
                      ],
                    ),
                    onTap: () => _addProductToCart(context, product),
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
  Widget build(BuildContext context) => Directionality(
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

class _ServiceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget page;
  const _ServiceTile({required this.icon, required this.title, required this.subtitle, required this.page});
  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        child: ListTile(
          leading: CircleAvatar(backgroundColor: const Color(0xFFF1F6FF), child: Icon(icon, color: _blue)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_left),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
        ),
      );
}

class WalletCenterPage extends StatelessWidget {
  const WalletCenterPage({super.key});
  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: const Text('المحافظ', style: TextStyle(fontWeight: FontWeight.w900))),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: const [
              Card(child: Padding(padding: EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.account_balance_wallet_outlined, size: 42, color: _blue),
                SizedBox(height: 12),
                Text('مركز المحافظ', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                SizedBox(height: 8),
                Text('تظهر هنا المحافظ والخدمات المالية المرتبطة بالحساب عند تفعيلها من المنصة.'),
              ]))),
            ],
          ),
        ),
      );
}

class _AccountTab extends StatelessWidget {
  const _AccountTab();
  Future<void> _logout(BuildContext context) async => AuthService().signOut();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 28),
      children: [
        const Text('حسابي', style: TextStyle(color: _navy, fontSize: 28, fontWeight: FontWeight.w900)),
        const SizedBox(height: 16),
        Card(child: ListTile(
          leading: const CircleAvatar(backgroundColor: Color(0xFFF1F6FF), child: Icon(Icons.person_outline, color: _blue)),
          title: Text(user?.displayName ?? 'مستخدم الفائق', style: const TextStyle(fontWeight: FontWeight.w900)),
          subtitle: Text(user?.email ?? user?.phoneNumber ?? 'حساب مسجل الدخول'),
        )),
        ListTile(leading: const Icon(Icons.shopping_cart_outlined, color: _blue), title: const Text('السلة', style: TextStyle(fontWeight: FontWeight.w800)), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartPage()))),
        ListTile(leading: const Icon(Icons.receipt_long_outlined, color: _blue), title: const Text('طلباتي وتتبع التوصيل', style: TextStyle(fontWeight: FontWeight.w800)), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyOrdersPage()))),
        ListTile(leading: const Icon(Icons.account_balance_wallet_outlined, color: _blue), title: const Text('محفظتي', style: TextStyle(fontWeight: FontWeight.w800)), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletCenterPage()))),
        ListTile(leading: const Icon(Icons.auto_awesome, color: _blue), title: const Text('ذكاء الفائق يمن', style: TextStyle(fontWeight: FontWeight.w800)), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AiAssistantPage()))),
        const Divider(height: 24),
        FilledButton.icon(onPressed: () => _logout(context), icon: const Icon(Icons.logout), label: const Text('تسجيل الخروج'), style: FilledButton.styleFrom(backgroundColor: _navy)),
      ],
    );
  }
}

class _Info extends StatelessWidget {
  final String title;
  final String text;
  const _Info({required this.title, required this.text});
  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(text, style: const TextStyle(color: Colors.black54)),
        ])),
      );
}
