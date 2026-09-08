import 'package:cloud_firestore/cloud_firestore.dart';
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
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      body: SafeArea(child: IndexedStack(index: index, children: const [_HomeTab(), ServicesHubPage(), _AccountTab()])),
      bottomNavigationBar: NavigationBar(selectedIndex: index, onDestinationSelected: (v) => setState(() => index = v), destinations: const [
        NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: 'الرئيسية'),
        NavigationDestination(icon: Icon(Icons.apps_outlined), selectedIcon: Icon(Icons.apps), label: 'الخدمات'),
        NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'حسابي'),
      ]),
    ),
  );
}

class _HomeTab extends StatelessWidget {
  const _HomeTab();
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    Row(children: [Container(width: 48, height: 48, decoration: BoxDecoration(color: const Color(0xFF0B6E4F), borderRadius: BorderRadius.circular(15)), child: const Icon(Icons.hub_outlined, color: Colors.white)), const SizedBox(width: 12), const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('الفائق يمن', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)), Text('منصة واحدة للحياة والأعمال', style: TextStyle(color: Colors.black54, fontSize: 12))])), IconButton(onPressed: () {}, icon: const Icon(Icons.notifications_none)), IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartPage())), icon: const Icon(Icons.shopping_bag_outlined))]),
    const SizedBox(height: 14),
    Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF0B6E4F), Color(0xFF124E78)]), borderRadius: BorderRadius.circular(28)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Row(children: [Icon(Icons.auto_awesome, color: Colors.white), SizedBox(width: 8), Text('ذكاء الفائق', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800))]), const SizedBox(height: 12), const Text('كل ما تحتاجه\nفي منصة واحدة.', style: TextStyle(color: Colors.white, fontSize: 29, height: 1.08, fontWeight: FontWeight.w900)), const SizedBox(height: 10), const Text('متاجر • خدمات • دفع • طلبات • تتبع • سفر • أعمال', style: TextStyle(color: Colors.white70)), const SizedBox(height: 18), FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF0B6E4F)), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AiAssistantPage())), icon: const Icon(Icons.chat_bubble_outline), label: const Text('اسأل ذكاء الفائق'))]),
    const SizedBox(height: 18),
    Row(children: [_action(context, 'السلة', Icons.shopping_cart_outlined, const CartPage()), _action(context, 'طلباتي', Icons.local_shipping_outlined, const MyOrdersPage()), _action(context, 'المحافظ', Icons.account_balance_wallet_outlined, const WalletCenterPage()), _action(context, 'الخدمات', Icons.apps_outlined, const ServicesHubPage())]),
    const SizedBox(height: 24), const Text('اكتشف الأقسام', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)), const SizedBox(height: 12),
    GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: appSections.length, gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.16), itemBuilder: (_, i) => _SectionCard(section: appSections[i])),
  ]);

  static Widget _action(BuildContext c, String title, IconData icon, Widget page) => Expanded(child: Padding(padding: const EdgeInsetsDirectional.only(start: 5), child: InkWell(borderRadius: BorderRadius.circular(17), onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => page)), child: Container(padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 3), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(17), border: Border.all(color: const Color(0xFFE4EAE7))), child: Column(children: [Icon(icon, color: const Color(0xFF0B6E4F)), const SizedBox(height: 6), Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800))]))));
}

class _SectionCard extends StatelessWidget {
  final AppSection section;
  const _SectionCard({required this.section});
  @override
  Widget build(BuildContext context) => Card(elevation: 0, child: InkWell(borderRadius: BorderRadius.circular(14), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WorldSectionPage(section: section))), child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Container(width: 45, height: 45, decoration: BoxDecoration(color: const Color(0xFFE7F3EE), borderRadius: BorderRadius.circular(14)), child: Icon(_icon(section.icon), color: const Color(0xFF0B6E4F))), const SizedBox(height: 10), Text(section.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text(section.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.black54))]))));
  static IconData _icon(String n) => switch (n) { 'storefront' => Icons.storefront_outlined, 'restaurant' => Icons.restaurant_outlined, 'pharmacy' => Icons.local_pharmacy_outlined, 'beauty' => Icons.face_retouching_natural, 'construction' => Icons.construction_outlined, 'car' => Icons.directions_car_outlined, 'flight' => Icons.flight_takeoff_outlined, 'hotel' => Icons.hotel_outlined, 'account_balance' => Icons.account_balance_wallet_outlined, 'handyman' => Icons.handyman_outlined, 'devices' => Icons.devices_outlined, 'home' => Icons.home_work_outlined, 'work' => Icons.work_outline, 'school' => Icons.school_outlined, 'medical' => Icons.medical_services_outlined, _ => Icons.explore_outlined };
}

class WorldSectionPage extends StatelessWidget {
  final AppSection section;
  const WorldSectionPage({super.key, required this.section});
  @override
  Widget build(BuildContext context) => Directionality(textDirection: TextDirection.rtl, child: Scaffold(appBar: AppBar(title: Text(section.title), actions: [IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartPage())), icon: const Icon(Icons.shopping_cart_outlined))]), body: ListView(padding: const EdgeInsets.all(16), children: [Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: const Color(0xFFE7F3EE), borderRadius: BorderRadius.circular(24)), child: Row(children: [Icon(_SectionCard._icon(section.icon), color: const Color(0xFF0B6E4F), size: 34), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(section.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)), Text(section.subtitle, style: const TextStyle(color: Colors.black54))]))])), const SizedBox(height: 16), TextField(decoration: InputDecoration(hintText: 'ابحث داخل القسم...', prefixIcon: const Icon(Icons.search), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none))), const SizedBox(height: 20), const Text('المتاجر المعتمدة', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)), const SizedBox(height: 8), StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: FirebaseFirestore.instance.collection('stores').where('sectionId', isEqualTo: section.id).where('status', isEqualTo: 'approved').limit(30).snapshots(), builder: (context, snap) { if (snap.connectionState == ConnectionState.waiting) return const Center(child: Padding(padding: EdgeInsets.all(28), child: CircularProgressIndicator())); if (snap.hasError) return const _Info(title: 'تعذر تحميل المتاجر', text: 'تحقق من الاتصال والصلاحيات.'); final stores = snap.data?.docs ?? const []; if (stores.isEmpty) return const _Info(title: 'لا توجد متاجر معتمدة بعد', text: 'يمكن إضافة متجر حقيقي من مركز الإدارة.'); return Column(children: stores.map((d) => _StoreCard(store: d)).toList()); })]));
}

class _StoreCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> store;
  const _StoreCard({required this.store});
  @override
  Widget build(BuildContext context) { final data = store.data(); return Card(elevation: 0, margin: const EdgeInsets.only(bottom: 12), child: ExpansionTile(leading: const CircleAvatar(backgroundColor: Color(0xFFE7F3EE), child: Icon(Icons.storefront_outlined, color: Color(0xFF0B6E4F))), title: Text('${data['name'] ?? 'متجر'}', style: const TextStyle(fontWeight: FontWeight.w900)), subtitle: Text('${data['address'] ?? 'عنوان غير محدد'}'), children: [StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: FirebaseFirestore.instance.collection('products').where('storeId', isEqualTo: store.id).where('status', isEqualTo: 'active').limit(40).snapshots(), builder: (context, snap) { if (snap.hasError) return const Padding(padding: EdgeInsets.all(12), child: Text('تعذر تحميل الأصناف.')); if (snap.connectionState == ConnectionState.waiting) return const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()); final products = snap.data?.docs ?? const []; if (products.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text('لا توجد أصناف نشطة حالياً.')); return Column(children: products.map((p) { final d = p.data(); return ListTile(leading: const Icon(Icons.inventory_2_outlined), title: Text('${d['name'] ?? 'صنف'}'), subtitle: Text('المتوفر: ${d['stock'] ?? '—'}'), trailing: Text(d['price'] is num ? '${d['price']} ${d['currency'] ?? 'YER'}' : 'عند الطلب', style: const TextStyle(fontWeight: FontWeight.w900))); }).toList()); })])); }
}

class _Info extends StatelessWidget { final String title; final String text; const _Info({required this.title, required this.text}); @override Widget build(BuildContext context) => Card(elevation: 0, child: ListTile(leading: const Icon(Icons.info_outline, color: Color(0xFF0B6E4F)), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)), subtitle: Text(text))); }

class WalletCenterPage extends StatelessWidget {
  const WalletCenterPage({super.key});
  @override
  Widget build(BuildContext context) => Directionality(textDirection: TextDirection.rtl, child: Scaffold(appBar: AppBar(title: const Text('المحافظ والدفع')), body: ListView(padding: const EdgeInsets.all(16), children: [Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(color: const Color(0xFF0B6E4F), borderRadius: BorderRadius.circular(24)), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.shield_outlined, color: Colors.white, size: 34), SizedBox(height: 10), Text('مركز الدفع الآمن', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)), SizedBox(height: 7), Text('إنشاء الطلب منفصل عن تنفيذ الدفع. لا تتم أي عملية مالية دون مزود دفع معتمد وموافقة واضحة.', style: TextStyle(color: Colors.white70, height: 1.5))])), const SizedBox(height: 18), const _Info(title: 'الكريمي', text: 'تحويل ودفع محلي — متاح كخيار دفع للطلبات'), const _Info(title: 'كاش / محافظ', text: 'الدفع عند الاستلام وخيارات المحافظ اليمنية'), const _Info(title: 'جيـب', text: 'محفظة إلكترونية — الربط API الحقيقي يحتاج اعتماد المزود'), const _Info(title: 'البنية المالية', text: 'المرحلة الإنتاجية ستستخدم طبقة دفع مستقلة مع تحقق، idempotency وسجل تدقيق. لا توضع مفاتيح API داخل التطبيق.')]));
}

class ServicesHubPage extends StatelessWidget {
  const ServicesHubPage({super.key});
  @override
  Widget build(BuildContext context) => Directionality(textDirection: TextDirection.rtl, child: Scaffold(appBar: AppBar(title: const Text('مركز الخدمات')), body: ListView(padding: const EdgeInsets.all(16), children: [const Text('منصة واحدة، خدمات مترابطة', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900)), const SizedBox(height: 8), const Text('تجارة، خدمات، دفع، تتبع، ذكاء، وبنية قابلة للتوسع إلى Mini Apps.', style: TextStyle(color: Colors.black54, height: 1.5)), const SizedBox(height: 18), _service(context, 'التتبع والطلبات', Icons.local_shipping_outlined, const MyOrdersPage()), _service(context, 'ذكاء الفائق', Icons.auto_awesome, const AiAssistantPage()), _service(context, 'المحافظ والدفع', Icons.account_balance_wallet_outlined, const WalletCenterPage())]));
  Widget _service(BuildContext c, String title, IconData icon, Widget page) => Card(elevation: 0, child: ListTile(contentPadding: const EdgeInsets.all(10), leading: CircleAvatar(backgroundColor: const Color(0xFFE7F3EE), child: Icon(icon, color: const Color(0xFF0B6E4F))), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)), trailing: const Icon(Icons.chevron_left), onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => page))));
}

class _AccountTab extends StatelessWidget { const _AccountTab(); @override Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18), children: [const SizedBox(height: 18), const CircleAvatar(radius: 34, child: Icon(Icons.person, size: 34)), const SizedBox(height: 12), const Center(child: Text('حسابي في الفائق يمن', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900))), const SizedBox(height: 24), Card(elevation: 0, child: ListTile(leading: const Icon(Icons.account_balance_wallet_outlined), title: const Text('المحافظ والدفع'), trailing: const Icon(Icons.chevron_left), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletCenterPage())))), Card(elevation: 0, child: ListTile(leading: const Icon(Icons.local_shipping_outlined), title: const Text('طلباتي والتتبع'), trailing: const Icon(Icons.chevron_left), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyOrdersPage()))))]); }
