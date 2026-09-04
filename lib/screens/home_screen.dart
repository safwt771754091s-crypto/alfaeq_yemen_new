import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'wallet_history_screen.dart';
import 'vendors_screen.dart';
import 'wallets_screen.dart';
import 'tracking_screen.dart';
import 'cart_screen.dart';
import 'admin_dashboard_screen.dart';
import 'merchant_portal_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: const Text('الفائق يمن', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
          actions: [
            IconButton(icon: const Icon(Icons.storefront, color: Color(0xFF1A365D)), tooltip: 'بوابة التجار', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MerchantPortalScreen()))),
            IconButton(icon: const Icon(Icons.shopping_cart, color: Color(0xFF1A365D)), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartScreen()))),
            PopupMenuButton<String>(
              onSelected: (v) async { if (v == 'logout') await FirebaseAuth.instance.signOut(); if (v == 'admin' && context.mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminDashboardScreen())); },
              itemBuilder: (_) => const [PopupMenuItem(value: 'admin', child: Text('لوحة الإدارة')), PopupMenuItem(value: 'logout', child: Text('تسجيل الخروج'))],
            ),
          ],
        ),
        body: SingleChildScrollView(child: Column(children: [_buildSuperWalletCard(context), const SizedBox(height: 20), _buildServicesGrid(context), const SizedBox(height: 20), _buildSmartTripCard(context), const SizedBox(height: 30)])),
      ),
    );
  }

  Widget _buildSuperWalletCard(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: const Color(0xFF1A365D), borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: const Color(0xFF1A365D).withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))]),
    child: Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('رصيد الفائق المتاح', style: TextStyle(color: Colors.white70)), SizedBox(height: 4), Text('150,000 ر.ي', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold))]), ElevatedButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletsScreen())), icon: const Icon(Icons.account_balance, size: 16), label: const Text('المحافظ'))]),
      const SizedBox(height: 20), Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [_buildWalletAction(context, Icons.storefront, 'التجار', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MerchantPortalScreen()))), _buildWalletAction(context, Icons.shopping_cart, 'السلة', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartScreen()))), _buildWalletAction(context, Icons.history, 'السجل', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletHistoryScreen()))), _buildWalletAction(context, Icons.local_shipping, 'التتبع', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TrackingScreen())))])
    ]),
  );

  Widget _buildWalletAction(BuildContext context, IconData icon, String label, VoidCallback onTap) => GestureDetector(onTap: onTap, child: Column(children: [Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: Colors.white, size: 24)), const SizedBox(height: 8), Text(label, style: const TextStyle(color: Colors.white, fontSize: 11))]));

  Widget _buildServicesGrid(BuildContext context) {
    final services = [
      {'icon': Icons.restaurant, 'title': 'المطاعم والوجبات', 'color': Colors.redAccent}, {'icon': Icons.shopping_basket, 'title': 'السوبرماركت', 'color': Colors.green}, {'icon': Icons.directions_bus, 'title': 'الرحلات والسفر', 'color': Colors.orange}, {'icon': Icons.local_pharmacy, 'title': 'الصيدليات والأدوية', 'color': Colors.teal}, {'icon': Icons.local_shipping, 'title': 'الشحن بين المدن', 'color': Colors.brown}, {'icon': Icons.two_wheeler, 'title': 'توصيل مشاوير', 'color': Colors.blue}, {'icon': Icons.checkroom, 'title': 'الملابس والأزياء', 'color': Colors.pink}, {'icon': Icons.face, 'title': 'أدوات التجميل', 'color': Colors.purple}, {'icon': Icons.local_hospital, 'title': 'المراكز الطبية', 'color': Colors.red}, {'icon': Icons.hotel, 'title': 'حجز الفنادق', 'color': Colors.indigo}, {'icon': Icons.payment, 'title': 'التوصيل والمالية', 'color': Colors.amber}, {'icon': Icons.grid_view, 'title': 'كل الخدمات', 'color': Colors.grey},
    ];
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: services.length, gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, childAspectRatio: .80, crossAxisSpacing: 8, mainAxisSpacing: 12), itemBuilder: (context, index) { final s=services[index]; return GestureDetector(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VendorsScreen(categoryTitle: s['title'] as String, categoryIcon: s['icon'] as IconData, categoryColor: s['color'] as Color))), child: Column(children: [Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: (s['color'] as Color).withOpacity(.1), borderRadius: BorderRadius.circular(16)), child: Icon(s['icon'] as IconData, color: s['color'] as Color, size: 26)), const SizedBox(height: 6), Text(s['title'] as String, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis)])); }));
  }

  Widget _buildSmartTripCard(BuildContext context) => Container(margin: const EdgeInsets.symmetric(horizontal: 16), padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Row(children: [Icon(Icons.directions_bus, color: Colors.orange), SizedBox(width: 8), Text('رحلتك القادمة: مأرب ➔ عدن', style: TextStyle(fontWeight: FontWeight.bold))]), const SizedBox(height: 8), const Text('تتبع خط السير وخدمات السفر من مكان واحد.'), const SizedBox(height: 12), SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TrackingScreen())), icon: const Icon(Icons.map), label: const Text('تتبع خط السير')))]));
}
