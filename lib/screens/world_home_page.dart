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
            NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: 'الرئيسية'),
            NavigationDestination(icon: Icon(Icons.apps_outlined), selectedIcon: Icon(Icons.apps), label: 'الخدمات'),
            NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'حسابي'),
          ],
        ),
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: const Color(0xFF0B6E4F), borderRadius: BorderRadius.circular(15)),
            child: const Icon(Icons.hub_outlined, color: Colors.white),
          ),
          const SizedBox(width: 12),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('الفائق يمن', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
            Text('منصة واحدة للحياة والأعمال', style: TextStyle(color: Colors.black54, fontSize: 12)),
          ])),
          IconButton(onPressed: () {}, icon: const Icon(Icons.notifications_none)),
          IconButton(onPressed: () => _open(context, const CartPage()), icon: const Icon(Icons.shopping_bag_outlined)),
        ]),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFF0B6E4F), Color(0xFF124E78)]),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [Icon(Icons.auto_awesome, color: Colors.white), SizedBox(width: 8), Text('ذكاء الفائق', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800))]),
            const SizedBox(height: 12),
            const Text('كل ما تحتاجه\nفي منصة واحدة.', style: TextStyle(color: Colors.white, fontSize: 29, height: 1.08, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            const Text('متاجر • خدمات • دفع • طلبات • تتبع • سفر • أعمال', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 18),
            FilledButton.icon(onPressed: () => _open(context, const AiAssistantPage()), icon: const Icon(Icons.chat_bubble_outline), label: const Text('اسأل ذكاء الفائق')),
          ]),
        ),
        const SizedBox(height: 18),
        Row(children: [
          _action(context, 'السلة', Icons.shopping_cart_outlined, const CartPage()),
          _action(context, 'طلباتي', Icons.local_shipping_outlined, const MyOrdersPage()),
          _action(context, 'المحافظ', Icons.account_balance_wallet_outlined, const WalletCenterPage()),
          _action(context, 'الخدمات', Icons.apps_outlined, const ServicesHubPage()),
        ]),
        const SizedBox(height: 26),
        Row(children: [
          const Expanded(child: Text('اكتشف الأقسام', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900))),
          TextButton(onPressed: () {}, child: const Text('عرض الكل')),
        ]),
        const SizedBox(height: 8),
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
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.02),
          itemBuilder: (_, itemIndex) => _SectionCard(section: appSections[itemIndex]),
        ),
      ],
    );
  }

  static void _open(BuildContext context, Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  static Widget _action(BuildContext context, String title, IconData icon, Widget page) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: 5),
        child: InkWell(
          borderRadius: BorderRadius.circular(17),
          onTap: () => _open(context, page),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 3),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(17), border: Border.all(color: const Color(0xFFE4EAE7))),
            child: Column(children: [Icon(icon, color: const Color(0xFF0B6E4F)), const SizedBox(height: 6), Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800))]),
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
        decoration: BoxDecoration(color: const Color(0xFFF7FAF8), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE3EAE6))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(color: const Color(0xFFE7F3EE), borderRadius: BorderRadius.circular(13)), child: Icon(_SectionCard._icon(section.icon), color: const Color(0xFF0B6E4F), size: 21)),
          const Spacer(),
          Text(section.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
        ]),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final AppSection section;
  const _SectionCard({required this.section});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WorldSectionPage(section: section))),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 50, height: 50, decoration: BoxDecoration(color: const Color(0xFFE7F3EE), borderRadius: BorderRadius.circular(15)), child: Icon(_icon(section.icon), color: const Color(0xFF0B6E4F), size: 27)),
              const Spacer(),
              const Icon(Icons.arrow_back_ios_new, size: 14, color: Colors.black38),
            ]),
            const Spacer(),
            Text(section.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(section.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.black54, height: 1.25)),
          ]),
        ),
      ),
    );
  }

  static IconData _icon(String name) {
    return switch (name) {
      'storefront' => Icons.storefront_outlined,
      'restaurant' => Icons.restaurant_outlined,
      'pharmacy' => Icons.local_pharmacy_outlined,
      'beauty' => Icons.face_retouching_natural,
      'construction' => Icons.construction_outlined,
      'car' => Icons.directions_car_outlined,
      'flight' => Icons.flight_takeoff_outlined,
      'hotel' => Icons.hotel_outlined,
      'account_balance' => Icons.account_balance_wallet_outlined,
      'handyman' => Icons.handyman_outlined,
      'devices' => Icons.devices_outlined,
      'home' => Icons.home_work_outlined,
      'work' => Icons.work_outline,
      'school' => Icons.school_outlined,
      'medical' => Icons.medical_services_outlined,
      _ => Icons.explore_outlined,
    };
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
        appBar: AppBar(title: Text(section.title, style: const TextStyle(fontWeight: FontWeight.w900)), actions: [IconButton(onPressed: () => _open(context, const CartPage()), icon: const Icon(Icons.shopping_cart_outlined))]),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 28), children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFE7F3EE), Color(0xFFEAF2F8)]), borderRadius: BorderRadius.circular(24)),
            child: Row(children: [
              Container(width: 56, height: 56, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(17)), child: Icon(_SectionCard._icon(section.icon), color: const Color(0xFF0B6E4F), size: 31)),
              const SizedBox(width: 13),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(section.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)), const SizedBox(height: 3), Text(section.subtitle, style: const TextStyle(color: Colors.black54, height: 1.3))])),
            ]),
          ),
          const SizedBox(height: 14),
          TextField(decoration: InputDecoration(hintText: 'ابحث في ${section.title}...', prefixIcon: const Icon(Icons.search), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none))),
          const SizedBox(height: 18),
          Row(children: [const Expanded(child: Text('المتاجر المعتمدة', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900))), _Pill(label: 'قريباً')]),
          const SizedBox(height: 9),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('stores').where('sectionId', isEqualTo: section.id).where('status', isEqualTo: 'approved').limit(30).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: Padding(padding: EdgeInsets.all(28), child: CircularProgressIndicator()));
              if (snapshot.hasError) return const _Info(title: 'تعذر تحميل المتاجر', text: 'تحقق من الاتصال والصلاحيات.');
              final stores = snapshot.data?.docs ?? const [];
              if (stores.isEmpty) return const _Info(title: 'لا توجد متاجر معتمدة بعد', text: 'سيظهر هنا المحتوى الحقيقي عند اعتماد المتاجر.');
              return Column(children: stores.map((document) => _StoreCard(store: document)).toList());
            },
          ),
        ]),
      ),
    );
  }

  static void _open(BuildContext context, Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));
}

class _Pill extends StatelessWidget {
  final String label;
  const _Pill({required this.label});
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: const Color(0xFFE7F3EE), borderRadius: BorderRadius.circular(20)), child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF0B6E4F))));
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
        leading: const CircleAvatar(backgroundColor: Color(0xFFE7F3EE), child: Icon(Icons.storefront_outlined, color: Color(0xFF0B6E4F))),
        title: Text('${data['name'] ?? 'متجر'}', style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text('${data['address'] ?? 'عنوان غير محدد'}'),
        children: [
          Container(height: 1, color: const Color(0xFFE8ECEA)),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('products').where('storeId', isEqualTo: store.id).where('status', isEqualTo: 'active').limit(40).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return const Padding(padding: EdgeInsets.all(12), child: Text('تعذر تحميل الأصناف.'));
              if (snapshot.connectionState == ConnectionState.waiting) return const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator());
              final products = snapshot.data?.docs ?? const [];
              if (products.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text('لا توجد أصناف نشطة حالياً.'));
              return Column(children: products.map((product) {
                final productData = product.data();
                final price = productData['price'];
                return ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text('${productData['name'] ?? 'صنف'}'),
                  subtitle: Text('المتوفر: ${productData['stock'] ?? '—'}'),
                  trailing: price is num ? Text('$price ${productData['currency'] ?? 'YER'}', style: const TextStyle(fontWeight: FontWeight.w900)) : const Text('عند الطلب', style: TextStyle(fontWeight: FontWeight.w800)),
                );
              }).toList());
            },
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
  Widget build(BuildContext context) => Card(elevation: 0, child: ListTile(leading: const Icon(Icons.info_outline, color: Color(0xFF0B6E4F)), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)), subtitle: Text(text)));
}

class WalletCenterPage extends StatelessWidget {
  const WalletCenterPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('المحافظ والدفع')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(color: const Color(0xFF0B6E4F), borderRadius: BorderRadius.circular(24)), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.shield_outlined, color: Colors.white, size: 34), SizedBox(height: 10), Text('مركز الدفع الآمن', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)), SizedBox(height: 7), Text('إنشاء الطلب منفصل عن تنفيذ الدفع. لا تتم أي عملية مالية دون مزود دفع معتمد وموافقة واضحة.', style: TextStyle(color: Colors.white70, height: 1.5))])),
          const SizedBox(height: 18),
          const _Info(title: 'الكريمي', text: 'تحويل ودفع محلي — متاح كخيار دفع للطلبات'),
          const _Info(title: 'كاش / محافظ', text: 'الدفع عند الاستلام وخيارات المحافظ اليمنية'),
          const _Info(title: 'جيـب', text: 'محفظة إلكترونية — الربط API الحقيقي يحتاج اعتماد المزود'),
          const _Info(title: 'البنية المالية', text: 'هذه الشاشة حالياً تعريفية فقط. الرصيد والمعاملات الحقيقية ستأتي من دفتر محاسبي غير قابل للتلاعب ومزود دفع معتمد.'),
        ]),
      ),
    );
  }
}

class ServicesHubPage extends StatelessWidget {
  const ServicesHubPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Directionality(textDirection: TextDirection.rtl, child: Scaffold(appBar: AppBar(title: const Text('مركز الخدمات')), body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('منصة واحدة، خدمات مترابطة', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      const Text('تجارة، خدمات، دفع، تتبع، ذكاء، وبنية قابلة للتوسع إلى Mini Apps.', style: TextStyle(color: Colors.black54, height: 1.5)),
      const SizedBox(height: 18),
      _service(context, 'التتبع والطلبات', Icons.local_shipping_outlined, const MyOrdersPage()),
      _service(context, 'ذكاء الفائق', Icons.auto_awesome, const AiAssistantPage()),
      _service(context, 'المحافظ والدفع', Icons.account_balance_wallet_outlined, const WalletCenterPage()),
    ])));
  }
  Widget _service(BuildContext context, String title, IconData icon, Widget page) => Card(elevation: 0, child: ListTile(contentPadding: const EdgeInsets.all(10), leading: CircleAvatar(backgroundColor: const Color(0xFFE7F3EE), child: Icon(icon, color: const Color(0xFF0B6E4F))), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)), trailing: const Icon(Icons.chevron_left), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page))));
}

class _AccountTab extends StatelessWidget {
  const _AccountTab();
  Future<void> _signOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(title: const Text('تسجيل الخروج'), content: const Text('هل تريد تسجيل الخروج من حسابك على الفائق يمن؟'), actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('تسجيل الخروج'))]));
    if (confirmed != true) return;
    await FirebaseAuth.instance.signOut();
  }
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18), children: [
    const SizedBox(height: 18),
    const CircleAvatar(radius: 34, child: Icon(Icons.person, size: 34)),
    const SizedBox(height: 12),
    const Center(child: Text('حسابي في الفائق يمن', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900))),
    const SizedBox(height: 24),
    Card(elevation: 0, child: ListTile(leading: const Icon(Icons.account_balance_wallet_outlined), title: const Text('المحافظ والدفع'), trailing: const Icon(Icons.chevron_left), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletCenterPage())))),
    Card(elevation: 0, child: ListTile(leading: const Icon(Icons.local_shipping_outlined), title: const Text('طلباتي والتتبع'), trailing: const Icon(Icons.chevron_left), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyOrdersPage())))),
    const SizedBox(height: 12),
    Card(elevation: 0, child: ListTile(leading: const Icon(Icons.logout, color: Colors.redAccent), title: const Text('تسجيل الخروج', style: TextStyle(fontWeight: FontWeight.w900)), subtitle: const Text('إنهاء الجلسة الحالية بأمان'), trailing: const Icon(Icons.chevron_left), onTap: () => _signOut(context))),
  ]);
}
