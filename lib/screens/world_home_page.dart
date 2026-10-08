import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_sections.dart';
import '../core/money.dart';
import '../core/product_units.dart';
import '../services/catalog_service.dart';
import '../services/currency_service.dart';
import '../services/order_service.dart';
import '../services/supabase_service.dart';
import '../services/wallet_service.dart';
import '../services/public_content_service.dart';
import 'cart_page.dart';
import 'account_center_page.dart';
import 'location_picker_page.dart';
import 'my_orders_page.dart';
import 'notifications_page.dart';
import 'ai_assistant_page.dart';
import 'conversations_page.dart';
import 'mini_programs_page.dart';
import 'moments_page.dart';
import 'products_page.dart';
import '../widgets/currency_selector.dart';
import 'product_detail_page.dart';
import 'store_detail_page.dart';
import 'search_page.dart';
import 'support_chat_page.dart';
import 'wallet_qr_page.dart';
import 'barcode_scanner_page.dart';

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
      const ConversationsPage(),
      const MomentsPage(),
      const CartPage(),
      const MyOrdersPage(),
      const AccountCenterPage(),
    ];
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _surface,
        body: SafeArea(child: AnimatedBuilder(animation: CurrencyService.instance, builder: (context, _) => IndexedStack(index: index, children: pages))),
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
    const items = [
      (Icons.home_outlined, Icons.home, 'الرئيسية'),
      (Icons.storefront_outlined, Icons.storefront, 'المتاجر'),
      (Icons.chat_bubble_outline, Icons.chat_bubble, 'المحادثات'),
      (Icons.auto_awesome_outlined, Icons.auto_awesome, 'اللحظات'),
      (Icons.shopping_cart_outlined, Icons.shopping_cart, 'السلة'),
      (Icons.receipt_long_outlined, Icons.receipt_long, 'طلباتي'),
      (Icons.person_outline, Icons.person, 'حسابي'),
    ];
    return Container(
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFE5EAF0)))),
      child: SafeArea(
        top: false,
        child: Row(children: List.generate(items.length, (i) {
          final selected = selectedIndex == i;
          final item = items[i];
          final icon = i == 4
              ? _LiveCartBadge(icon: selected ? item.$2 : item.$1, color: selected ? _blue : _navy)
              : Icon(selected ? item.$2 : item.$1, color: selected ? _blue : _navy, size: 24);
          return Expanded(child: InkWell(
            onTap: () => onSelected(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                icon,
                const SizedBox(height: 3),
                Text(item.$3, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: selected ? _blue : _navy, fontSize: 10, fontWeight: selected ? FontWeight.w900 : FontWeight.w600)),
              ]),
            ),
          ));
        })),
      ),
    );
  }
}
class _LiveCartBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _LiveCartBadge({required this.icon, required this.color});

  int _count(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return 0;
    final raw = rows.first['items'];
    var count = 0;
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          final quantity = item['quantity'];
          if (quantity is num) count += quantity.round();
        }
      }
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null || !SupabaseService.isInitialized) {
      return _CartBadgeIcon(icon: icon, count: 0, color: color);
    }
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: SupabaseService.client.from('carts').stream(primaryKey: ['uid']).eq('uid', user.id),
      builder: (context, snapshot) =>
          _CartBadgeIcon(icon: icon, count: _count(snapshot.data ?? const []), color: color),
    );
  }
}

class _LiveNotificationsBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _LiveNotificationsBadge({required this.icon, required this.color});

  int _unread(List<Map<String, dynamic>> rows) =>
      rows.where((row) => row['read_at'] == null).length;

  @override
  Widget build(BuildContext context) {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null || !SupabaseService.isInitialized) {
      return _CartBadgeIcon(icon: icon, count: 0, color: color);
    }
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: SupabaseService.client
          .from('notifications')
          .stream(primaryKey: ['id'])
          .eq('user_id', user.id)
          .limit(100),
      builder: (context, snapshot) =>
          _CartBadgeIcon(icon: icon, count: _unread(snapshot.data ?? const []), color: color),
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
            onNotifications: () => widget.onOpen(context, const NotificationsPage()),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              const SizedBox(height: 14),
              const _SearchBar(),
              const SizedBox(height: 16),
              const _HeroBanner(),
              const SizedBox(height: 18),
              _CategoriesSection(onOpen: widget.onOpen),
              const SizedBox(height: 18),
              _AiAssistantEntry(onOpen: widget.onOpen),
              const SizedBox(height: 10),
              _ServicesEntry(onOpen: widget.onOpen),
              const SizedBox(height: 22),
              _OffersSection(onAddToCart: (product) => _addProductToCart(context, product)),
              const SizedBox(height: 22),
              _FeaturedProductsSection(onAddToCart: (product) => _addProductToCart(context, product)),
              const SizedBox(height: 20),
              const _PublicUpdatesSection(),
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
              const CurrencySelector(dark: true),
              IconButton(onPressed: onNotifications, icon: const _LiveNotificationsBadge(icon: Icons.notifications_none, color: Colors.white)),
              IconButton(onPressed: onCart, icon: const _LiveCartBadge(icon: Icons.shopping_cart_outlined, color: Colors.white)),
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
        readOnly: true,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchPage())),
        decoration: InputDecoration(
          hintText: 'ابحث عن منتجات أو خدمات...',
          prefixIcon: const Icon(Icons.search, color: _navy),
          suffixIcon: IconButton(
            tooltip: 'مسح الباركود',
            icon: const Icon(Icons.qr_code_scanner, color: _navy),
            onPressed: () async {
              final code = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const BarcodeScannerPage()));
              final value = code?.trim();
              if (value == null || value.isEmpty || !context.mounted) return;
              Navigator.push(context, MaterialPageRoute(builder: (_) => SearchPage(initialQuery: value)));
            },
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
        ),
      );
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner();

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(20),
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
                    Text('اطلب • ادفع • تتبع • استلم', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
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

class _AiAssistantEntry extends StatelessWidget {
  final void Function(BuildContext, Widget) onOpen;
  const _AiAssistantEntry({required this.onOpen});

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => onOpen(context, const AiAssistantPage()),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF0B6E4F), Color(0xFF0A2540)], begin: Alignment.topRight, end: Alignment.bottomLeft),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(15)),
                child: const Icon(Icons.auto_awesome, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ذكاء الفائق', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                    SizedBox(height: 3),
                    Text('ابحث، تابع طلبك، أو أدر سلتك بالمحادثة', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 16),
            ],
          ),
        ),
      );
}


class _ServicesEntry extends StatelessWidget {
  final void Function(BuildContext, Widget) onOpen;
  const _ServicesEntry({required this.onOpen});

  // WeChat-style quick-services grid on the home screen.
  List<(IconData, String, Widget Function())> get _items => [
        (Icons.search, 'البحث', () => const SearchPage()),
        (Icons.storefront_outlined, 'المنتجات', () => const ProductsPage()),
        (Icons.shopping_cart_outlined, 'السلة', () => const CartPage()),
        (Icons.receipt_long_outlined, 'طلباتي', () => const MyOrdersPage()),
        (Icons.account_balance_wallet_outlined, 'المحفظة', () => const WalletCenterPage()),
        (Icons.auto_awesome, 'ذكاء الفائق', () => const AiAssistantPage()),
        (Icons.auto_awesome_outlined, 'اللحظات', () => const MomentsPage()),
        (Icons.chat_bubble_outline, 'المحادثات', () => const ConversationsPage()),
        (Icons.widgets_outlined, 'البرامج المصغّرة', () => const MiniProgramsPage()),
        (Icons.grid_view_outlined, 'كل الخدمات', () => const ServicesHubPage()),
      ];

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFFE3E8EF))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 14, 10, 8),
          child: Column(
            children: [
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _items.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, crossAxisSpacing: 4, mainAxisSpacing: 14, childAspectRatio: .82),
                itemBuilder: (context, i) {
                  final tile = _items[i];
                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => onOpen(context, tile.$3()),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(color: const Color(0xFFF1F6FF), borderRadius: BorderRadius.circular(16)),
                          child: Icon(tile.$1, color: _blue, size: 26),
                        ),
                        const SizedBox(height: 7),
                        Text(tile.$2, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _navy, fontSize: 11.5, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  );
                },
              ),
            ],
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

int _promoDiscount(Map<String, dynamic> data) {
  final percent = data['discount_percent'] ?? data['discountPercent'];
  final price = data['price'];
  final original = data['original_price'] ?? data['originalPrice'];
  if (percent is num && percent > 0 && percent <= 100) return percent.round();
  if (price is num && original is num && original > price) return ((1 - (price / original)) * 100).round();
  return 0;
}

/// Loads published promotions that are linked to a real product, so the home
/// offers carousel only shows deals the customer can actually add to the cart.
Future<List<(CatalogDocument, int)>> _promotionDeals() async {
  final promos = await const PublicContentService().activePromotions(limit: 40);
  final ids = promos.map((p) => p.data['product_id']).whereType<String>().where((e) => e.isNotEmpty).toSet().toList();
  if (ids.isEmpty) return const [];
  final rows = await SupabaseService.client.from('products').select().inFilter('id', ids).eq('status', 'active');
  final byId = {for (final r in rows) (r['id'] ?? '').toString(): Map<String, dynamic>.from(r)};
  final deals = <(CatalogDocument, int)>[];
  for (final promo in promos) {
    final d = promo.data;
    final product = byId[(d['product_id'] ?? '').toString()];
    if (product == null) continue;
    var discount = _promoDiscount(d);
    if (discount <= 0) discount = 5;
    deals.add((CatalogDocument.fromSupabase(product), discount));
  }
  return deals;
}

class _OffersSection extends StatelessWidget {
  final Future<void> Function(CatalogDocument) onAddToCart;
  const _OffersSection({required this.onAddToCart});
  @override
  Widget build(BuildContext context) => FutureBuilder<List<(CatalogDocument, int)>>(
    future: _promotionDeals(),
    builder: (context, snapshot) {
      final deals = (snapshot.data ?? const <(CatalogDocument, int)>[]).take(8).toList();
      return Column(children: [
        Row(children: [
          const Expanded(child: Text('عروض مميزة 🔥', style: TextStyle(color: _navy, fontSize: 21, fontWeight: FontWeight.w900))),
          TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _OffersPage())), child: const Text('عرض الكل')),
        ]),
        const SizedBox(height: 8),
        if (snapshot.connectionState == ConnectionState.waiting) const LinearProgressIndicator()
        else if (snapshot.hasError) const _Info(title: 'تعذر تحميل العروض', text: 'تحقق من الاتصال والصلاحيات.')
        else if (deals.isEmpty) const _Info(title: 'العروض جاهزة للظهور', text: 'عند نشر عرض مرتبط بصنف سيظهر تلقائياً هنا.')
        else SizedBox(height: 238, child: ListView.separated(
          scrollDirection: Axis.horizontal, itemCount: deals.length, separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, i) { final (product, discount) = deals[i]; return _OfferCard(product: product, discount: discount, onAdd: () => onAddToCart(product)); },
        )),
      ]);
    },
  );
}

class _OfferCard extends StatelessWidget {
  final CatalogDocument product; final int discount; final VoidCallback onAdd;
  const _OfferCard({required this.product, required this.discount, required this.onAdd});
  @override
  Widget build(BuildContext context) {
    final data = product.data; final original = data['originalPrice'] ?? data['original_price'];
    final imageUrl = (data['imageUrl'] ?? data['image_url'] ?? data['image'] ?? '').toString();
    return Container(width: 178, padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFFE3E8EF))), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ClipRRect(borderRadius: BorderRadius.circular(11), child: imageUrl.isEmpty ? Container(height: 108, color: const Color(0xFFF0F3F7), child: const Icon(Icons.image_outlined, size: 42, color: Colors.black26)) : Image.network(imageUrl, height: 108, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(height: 108, color: const Color(0xFFF0F3F7), child: const Icon(Icons.broken_image_outlined)))),
      const SizedBox(height: 7), Text(data['name']?.toString() ?? 'صنف', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _navy, fontWeight: FontWeight.w800)),
      const SizedBox(height: 3), Row(children: [
        Expanded(child: Text(CurrencyService.instance.formatProduct(data), style: const TextStyle(color: _navy, fontWeight: FontWeight.w900))),
        if (original is num) Text(formatAmount(original), style: const TextStyle(color: Colors.grey, decoration: TextDecoration.lineThrough, fontSize: 10)),
      ]),
      const Spacer(), SizedBox(height: 34, child: FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add_shopping_cart, size: 16), label: const Text('أضف'), style: FilledButton.styleFrom(backgroundColor: _blue, padding: EdgeInsets.zero))),
    ]));
  }
}

class _OffersPage extends StatelessWidget {
  const _OffersPage();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('العروض المميزة', style: TextStyle(fontWeight: FontWeight.w900))),
    body: FutureBuilder<List<(CatalogDocument, int)>>(
      future: _promotionDeals(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return const Center(child: _Info(title: 'تعذر تحميل العروض', text: 'تحقق من الاتصال والصلاحيات.'));
        final deals = snapshot.data ?? const <(CatalogDocument, int)>[];
        if (deals.isEmpty) return const Center(child: _Info(title: 'لا توجد عروض حالياً', text: 'انشر عرضاً مرتبطاً بصنف ليظهر هنا.'));
        return GridView.builder(
          padding: const EdgeInsets.all(16), itemCount: deals.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: .68),
          itemBuilder: (_, i) { final (product, discount) = deals[i]; return _OfferCard(product: product, discount: discount, onAdd: () => _addProductToCart(context, product)); },
        );
      },
    ),
  );
}

Future<void> _addProductToCart(BuildContext context, CatalogDocument product) async {
  final user = SupabaseService.client.auth.currentUser;
  if (user == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يجب تسجيل الدخول أولاً.'))); return; }
  final name = (product.data['name'] ?? product.data['title'] ?? 'صنف').toString();
  try {
    await const CatalogService().addToCart(user.id, product);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تمت إضافة «' + name + '» إلى السلة.')));
  } on StateError catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تحديث السلة: ' + e.toString())));
  }
}

/// A merchandising grid of real, in-stock products so the storefront always
/// shows shoppable items even when no promotions are published.
class _FeaturedProductsSection extends StatefulWidget {
  final Future<void> Function(CatalogDocument) onAddToCart;
  const _FeaturedProductsSection({required this.onAddToCart});
  @override
  State<_FeaturedProductsSection> createState() => _FeaturedProductsSectionState();
}

class _FeaturedProductsSectionState extends State<_FeaturedProductsSection> {
  late final Future<List<CatalogDocument>> _future = _load();

  Future<List<CatalogDocument>> _load() async {
    final products = await const CatalogService().activeProducts(limit: 200);
    final inStock = products.where((p) {
      final stock = ProductUnit.stockBase(p.data);
      return stock > 0;
    }).toList();
    return (inStock.isEmpty ? products : inStock).take(12).toList();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<CatalogDocument>>(
        future: _future,
        builder: (context, snapshot) {
          final items = snapshot.data ?? const <CatalogDocument>[];
          if (snapshot.connectionState == ConnectionState.waiting && items.isEmpty) {
            return const LinearProgressIndicator();
          }
          if (snapshot.hasError || items.isEmpty) return const SizedBox.shrink();
          return Column(children: [
            Row(children: [
              const Expanded(child: Text('منتجات مختارة لك ✨', style: TextStyle(color: _navy, fontSize: 21, fontWeight: FontWeight.w900))),
              TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductsPage())), child: const Text('تصفّح الكل')),
            ]),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: .72),
              itemBuilder: (context, i) {
                final product = items[i];
                return _FeaturedProductCard(product: product, onAdd: () => widget.onAddToCart(product));
              },
            ),
          ]);
        },
      );
}

class _FeaturedProductCard extends StatelessWidget {
  final CatalogDocument product;
  final VoidCallback onAdd;
  const _FeaturedProductCard({required this.product, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final p = product.data;
    final imageUrl = (p['image_url'] ?? p['imageUrl'] ?? p['image'] ?? '').toString();
    final priceText = CurrencyService.instance.formatProduct(p);
    return InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailPage(product: product))),
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFFE3E8EF))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
              child: imageUrl.isEmpty
                  ? Container(color: const Color(0xFFF0F3F7), child: const Icon(Icons.image_outlined, size: 40, color: Colors.black26))
                  : Image.network(imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: const Color(0xFFF0F3F7), child: const Icon(Icons.broken_image_outlined))),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(9, 7, 9, 9),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p['name']?.toString() ?? 'صنف', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _navy, fontWeight: FontWeight.w800, fontSize: 12.5, height: 1.25)),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(child: Text(priceText, style: const TextStyle(color: _navy, fontWeight: FontWeight.w900))),
                SizedBox(
                  height: 30,
                  child: FilledButton(onPressed: onAdd, style: FilledButton.styleFrom(backgroundColor: _blue, padding: const EdgeInsets.symmetric(horizontal: 10)), child: const Icon(Icons.add_shopping_cart, size: 15)),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _PublicUpdatesSection extends StatelessWidget {
  const _PublicUpdatesSection();
  @override
  Widget build(BuildContext context) => FutureBuilder<List<SiteUpdateDocument>>(
    future: const PublicContentService().publishedUpdates(limit: 6),
    builder: (context, snapshot) {
      final updates = snapshot.data ?? const <SiteUpdateDocument>[];
      if (snapshot.connectionState == ConnectionState.waiting && updates.isEmpty) {
        return const LinearProgressIndicator();
      }
      if (snapshot.hasError || updates.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('آخر تحديثات الفائق', style: TextStyle(color: _navy, fontSize: 21, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          ...updates.map((item) => Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFF1F6FF),
                child: Icon(Icons.campaign_outlined, color: _blue),
              ),
              title: Text(item.data['title']?.toString() ?? 'تحديث جديد', style: const TextStyle(fontWeight: FontWeight.w900)),
              subtitle: Text(item.data['summary']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: () async {
                final url = item.data['cta_url']?.toString() ?? '';
                if (url.isEmpty) return;
                final uri = Uri.tryParse(url);
                if (uri == null || !uri.hasScheme) return;
                final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
                if (!ok && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(item.data['cta_label']?.toString() ?? 'تفاصيل التحديث')),
                  );
                }
              },
            ),
          )),
        ],
      );
    },
  );
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
          const Text('كل المتاجر المعتمدة', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 9),
          FutureBuilder<List<CatalogDocument>>(
            future: CatalogService().allApprovedStores(limit: 200),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
              if (snapshot.hasError) return const _Info(title: 'تعذر تحميل المتاجر', text: 'تحقق من اتصال قاعدة البيانات.');
              final stores = snapshot.data ?? const <CatalogDocument>[];
              if (stores.isEmpty) return const _Info(title: 'لا توجد متاجر معتمدة بعد', text: 'سيظهر هنا المحتوى الحقيقي عند اعتماد المتاجر.');
              return Column(children: stores.map((store) => _StoreCard(store: store)).toList());
            },
          ),
          const SizedBox(height: 18),
          const Text('تصفح حسب القسم', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 9),
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

class WorldSectionPage extends StatefulWidget {
  final AppSection section;
  const WorldSectionPage({super.key, required this.section});

  @override
  State<WorldSectionPage> createState() => _WorldSectionPageState();
}

class _WorldSectionPageState extends State<WorldSectionPage> {
  final _searchController = TextEditingController();
  String _query = '';
  late final Future<List<CatalogDocument>> _productsFuture;
  late final Future<List<CatalogDocument>> _storesFuture;

  @override
  void initState() {
    super.initState();
    _productsFuture = CatalogService().activeProducts(sectionId: widget.section.id, limit: 2000);
    _storesFuture = CatalogService().approvedStores(widget.section.id, limit: 30);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<CatalogDocument> _filter(List<CatalogDocument> products) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return products;
    return products.where((p) {
      final name = (p.data['name'] ?? '').toString().toLowerCase();
      final barcode = (p.data['metadata'] is Map ? (p.data['metadata'] as Map)['barcode'] : null)?.toString().toLowerCase() ?? '';
      return name.contains(q) || barcode.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    return Directionality(
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
              TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(hintText: 'ابحث في ${section.title}...', prefixIcon: const Icon(Icons.search), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none)),
              ),
              const SizedBox(height: 18),
              const Text('منتجات القسم', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 9),
              FutureBuilder<List<CatalogDocument>>(
                future: _productsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
                  if (snapshot.hasError) return const _Info(title: 'تعذر تحميل المنتجات', text: 'تحقق من اتصال قاعدة البيانات.');
                  final products = _filter(snapshot.data ?? const <CatalogDocument>[]);
                  if (products.isEmpty) return const _Info(title: 'لا توجد منتجات مطابقة', text: 'جرّب كلمة أخرى أو تحقق من الاسم أو الباركود.');
                  return Column(children: products.map((product) => _SectionProductTile(product: product)).toList());
                },
              ),
              const SizedBox(height: 18),
              const Text('المتاجر المعتمدة', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 9),
              FutureBuilder<List<CatalogDocument>>(
                future: _storesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: Padding(padding: EdgeInsets.all(28), child: CircularProgressIndicator()));
                  if (snapshot.hasError) return const _Info(title: 'تعذر تحميل المتاجر', text: 'تحقق من اتصال قاعدة البيانات.');
                  final stores = snapshot.data ?? const <CatalogDocument>[];
                  if (stores.isEmpty) return const _Info(title: 'لا توجد متاجر معتمدة بعد', text: 'سيظهر هنا المحتوى الحقيقي عند اعتماد المتاجر.');
                  return Column(children: stores.map((store) => _StoreCard(store: store)).toList());
                },
              ),
            ],
          ),
        ),
      );
  }
}

class _SectionProductTile extends StatelessWidget {
  const _SectionProductTile({required this.product});
  final CatalogDocument product;

  @override
  Widget build(BuildContext context) {
    final p = product.data;
    final imageUrl = (p['image_url'] ?? p['imageUrl'] ?? p['image'] ?? '').toString();
    final priceText = CurrencyService.instance.formatProduct(p);
    final stock = p['stock_base'] ?? p['stock'];
    final leading = imageUrl.isEmpty
        ? const CircleAvatar(backgroundColor: Color(0xFFF1F6FF), child: Icon(Icons.inventory_2_outlined, color: _blue))
        : ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(imageUrl, width: 52, height: 52, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const CircleAvatar(child: Icon(Icons.broken_image_outlined))));
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: leading,
        title: Text(p['name']?.toString() ?? 'صنف', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
        subtitle: Text('المتوفر: ${stock ?? '—'}'),
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(priceText, style: const TextStyle(fontWeight: FontWeight.w900)),
          IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: () => _addProductToCart(context, product), tooltip: 'أضف للسلة', icon: const Icon(Icons.add_shopping_cart, color: _blue, size: 20)),
        ]),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailPage(product: product))),
      ),
    );
  }
}

class _StoreCard extends StatelessWidget {
  final CatalogDocument store;
  const _StoreCard({required this.store});

  @override
  Widget build(BuildContext context) {
    final data = store.data;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: const CircleAvatar(
          backgroundColor: Color(0xFFF1F6FF),
          child: Icon(Icons.storefront_outlined, color: _blue),
        ),
        title: Text(data['name']?.toString() ?? 'متجر', style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text(data['address']?.toString() ?? 'عنوان غير محدد'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StoreDetailPage(store: store))),
                icon: const Icon(Icons.storefront_outlined, size: 18),
                label: const Text('صفحة المتجر والتقييمات'),
              ),
            ),
          ),
          Container(height: 1, color: const Color(0xFFE8ECEA)),
          FutureBuilder<List<CatalogDocument>>(
            future: CatalogService().activeProducts(storeId: store.id, limit: 5000),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator());
              if (snapshot.hasError) return const Padding(padding: EdgeInsets.all(16), child: Text('تعذر تحميل الأصناف.'));
              final products = snapshot.data ?? const <CatalogDocument>[];
              if (products.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text('لا توجد أصناف نشطة حالياً.'));
              // Cap the inline preview; the full catalog is a lazy list on the store page.
              final preview = products.take(8).toList();
              return Column(children: [
                ...preview.map((product) {
                final p = product.data;
                final imageUrl = (p['image_url'] ?? p['imageUrl'] ?? p['image'] ?? '').toString();
                            final leading = imageUrl.isEmpty
                    ? const CircleAvatar(backgroundColor: Color(0xFFF1F6FF), child: Icon(Icons.inventory_2_outlined, color: _blue))
                    : ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(imageUrl, width: 48, height: 48, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const CircleAvatar(child: Icon(Icons.broken_image_outlined))));
                final priceText = CurrencyService.instance.formatProduct(p);
                final stock = p['stock_base'] ?? p['stock'];
                return ListTile(
                  leading: leading,
                  title: Text(p['name']?.toString() ?? 'صنف', style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text('المتوفر: ' + (stock ?? '—').toString()),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(priceText, style: const TextStyle(fontWeight: FontWeight.w900)),
                    IconButton(onPressed: () => _addProductToCart(context, product), tooltip: 'أضف للسلة', icon: const Icon(Icons.add_shopping_cart, color: _blue)),
                  ]),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailPage(product: product))),
                );
              }),
                if (products.length > preview.length)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StoreDetailPage(store: store))),
                        child: Text('عرض كل الأصناف (${products.length})'),
                      ),
                    ),
                  ),
              ]);
            },
          ),
        ],
      ),
    );
  }
}
class ServicesHubPage extends StatelessWidget {
  const ServicesHubPage({super.key});

  // WeChat-style "discover" hub: one grid grouping every super-app service.
  List<(String, List<(IconData, String, Widget Function())>)> _groups() => [
        ('الطلب والشراء', [
          (Icons.search, 'البحث الموحّد', () => const SearchPage()),
          (Icons.storefront_outlined, 'المنتجات', () => const ProductsPage()),
          (Icons.shopping_cart_outlined, 'السلة', () => const CartPage()),
          (Icons.local_offer_outlined, 'العروض', () => const _OffersPage()),
          (Icons.storefront_outlined, 'المتاجر', () => const _StoresTab()),
          (Icons.widgets_outlined, 'البرامج المصغّرة', () => const MiniProgramsPage()),
        ]),
        ('طلباتي والمال', [
          (Icons.receipt_long_outlined, 'طلباتي', () => const MyOrdersPage()),
          (Icons.account_balance_wallet_outlined, 'المحفظة', () => const WalletCenterPage()),
          (Icons.qr_code_2, 'الدفع والاستلام', () => const WalletQrPage()),
        ]),
        ('الخدمات الذكية', [
          (Icons.chat_bubble_outline, 'المحادثات', () => const ConversationsPage()),
          (Icons.auto_awesome, 'ذكاء الفائق', () => const AiAssistantPage()),
          (Icons.support_agent_outlined, 'دعم الفائق', () => const SupportChatPage()),
          (Icons.notifications_none, 'الإشعارات', () => const NotificationsPage()),
        ]),
        ('المجتمع', [
          (Icons.auto_awesome_outlined, 'اللحظات', () => const MomentsPage()),
        ]),
      ];

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: const Text('كل الخدمات', style: TextStyle(fontWeight: FontWeight.w900))),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('كل الخدمات', style: TextStyle(color: _navy, fontSize: 26, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              const Text('منصة الفائق يمن: تسوّق، اطلب، تابع، وادفع من مكان واحد.', style: TextStyle(color: Colors.black54)),
              const SizedBox(height: 18),
              for (final group in _groups()) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 10, right: 4),
                  child: Text(group.$1, style: const TextStyle(color: _navy, fontSize: 17, fontWeight: FontWeight.w900)),
                ),
                Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFFE3E8EF))),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: group.$2.length,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, crossAxisSpacing: 4, mainAxisSpacing: 14, childAspectRatio: .82),
                      itemBuilder: (context, i) {
                        final tile = group.$2[i];
                        return InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => tile.$3())),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(color: const Color(0xFFF1F6FF), borderRadius: BorderRadius.circular(16)),
                                child: Icon(tile.$1, color: _blue, size: 26),
                              ),
                              const SizedBox(height: 7),
                              Text(tile.$2, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _navy, fontSize: 12, fontWeight: FontWeight.w800)),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
}

class WalletCenterPage extends StatefulWidget {
  const WalletCenterPage({super.key});
  @override
  State<WalletCenterPage> createState() => _WalletCenterPageState();
}

class _WalletCenterPageState extends State<WalletCenterPage> {
  Future<Map<String, dynamic>?> _loadWallet(String uid) async {
    try {
      // One wallet per user; ensure it exists and read its real currency.
      final row = await OrderService(preferSupabase: true).walletInfo();
      return {
        'available_balance': row.balance,
        'currency': row.currency,
        'status': 'active',
      };
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return const Scaffold(body: Center(child: Text('يجب تسجيل الدخول أولاً.')));
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('المحفظة المالية', style: TextStyle(fontWeight: FontWeight.w900))),
        body: FutureBuilder<Map<String, dynamic>?>(
          future: _loadWallet(user.id),
          builder: (context, walletSnapshot) {
            if (walletSnapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (walletSnapshot.hasError) return Center(child: Text('تعذر تحميل المحفظة: ${walletSnapshot.error}'));
            final data = walletSnapshot.data ?? <String, dynamic>{};
            final balance = num.tryParse('${data['available_balance'] ?? 0}') ?? 0;
            final walletMissing = walletSnapshot.data == null;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(color: _navy, child: Padding(padding: const EdgeInsets.all(22), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('الرصيد المتاح', style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 6),
                  Text(formatMoney(balance, (data['currency'] ?? 'USD').toString(), fallback: '0'), style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Text(data['status'] == 'active' ? 'المحفظة نشطة' : 'حالة المحفظة: ' + (data['status']?.toString() ?? 'غير معروفة'), style: const TextStyle(color: Colors.white70)),
                ])),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletQrPage())),
                  icon: const Icon(Icons.qr_code_2),
                  label: const Text('الدفع والاستلام (QR)'),
                ),
                const SizedBox(height: 14),
                if (walletMissing)
                  FilledButton.icon(
                    onPressed: () async {
                      try {
                        await const WalletService().ensureMyWallet();
                        if (mounted) setState(() {});
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('تعذر إنشاء المحفظة: $e')),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.account_balance_wallet_outlined),
                    label: const Text('إنشاء محفظتي الإلكترونية'),
                  ),
                if (walletMissing) const SizedBox(height: 14),
                const _Info(
                  title: 'العمليات المالية',
                  text: 'الإيداع والسحب والتحويل تُنفّذ فقط عبر العمليات الآمنة في الخادم. لا يتم تعديل الرصيد مباشرة من التطبيق.',
                ),
                const SizedBox(height: 14),
                const Text('آخر العمليات', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: SupabaseService.client.from('wallet_operations').select().eq('uid', user.id).order('created_at', ascending: false).limit(30),
                  builder: (context, ops) {
                    if (ops.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                    if (ops.hasError) return Text('تعذر تحميل العمليات: '+ops.error.toString());
                    final rows = ops.data ?? const <Map<String, dynamic>>[];
                    if (rows.isEmpty) return const Card(child: ListTile(title: Text('لا توجد عمليات مالية بعد.')));
                    return Column(children: rows.map((row) {
                      final type = row['type']?.toString() ?? 'operation';
                      return Card(elevation: 0, child: ListTile(
                        leading: const Icon(Icons.receipt_long_outlined, color: _blue),
                        title: Text(type+' • '+formatAmount(num.tryParse('${row['amount'] ?? 0}') ?? 0), style: const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text('الحالة: '+(row['status'] ?? 'pending').toString()),
                      ));
                    }).toList());
                  },
                )
              ],
            );
          },
        ),
      ),
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
