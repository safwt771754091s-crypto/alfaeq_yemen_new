import 'package:flutter/material.dart';
import 'wallet_history_screen.dart';
import 'vendors_screen.dart';
import 'wallets_screen.dart';
import 'tracking_screen.dart';
import 'cart_screen.dart';
import 'admin_dashboard_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF1A365D).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.flash_on, color: Color(0xFF1A365D), size: 22),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('الفائق يمن', style: TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.bold)),
                Text('الفائق.. يوصل للي ما يوصل!', style: TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.admin_panel_settings, color: Color(0xFF1A365D), size: 26),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminDashboardScreen()));
            },
          ),
          IconButton(
            icon: const Icon(Icons.shopping_cart, color: Color(0xFF1A365D), size: 26),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const CartScreen()));
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildSuperWalletCard(context),
            const SizedBox(height: 20),
            _buildServicesGrid(context),
            const SizedBox(height: 20),
            _buildSmartTripCard(context),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildSuperWalletCard(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A365D),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: const Color(0xFF1A365D).withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('رصيد الفائق المتاح', style: TextStyle(color: Colors.white70, fontSize: 14)),
                  SizedBox(height: 4),
                  Text('150,000 ر.ي', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const WalletsScreen()));
                },
                icon: const Icon(Icons.account_balance, size: 16, color: Color(0xFF1A365D)),
                label: const Text('المحافظ', style: TextStyle(color: Color(0xFF1A365D), fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              )
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildWalletAction(Icons.admin_panel_settings, 'الإدارة', () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminDashboardScreen()));
              }),
              _buildWalletAction(Icons.shopping_cart, 'السلة', () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const CartScreen()));
              }),
              _buildWalletAction(Icons.history, 'السجل', () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const WalletHistoryScreen()));
              }),
              _buildWalletAction(Icons.local_shipping, 'التتبع', () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => TrackingScreen()));
              }),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildWalletAction(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildServicesGrid(BuildContext context) {
    List<Map<String, dynamic>> services = [
      {'icon': Icons.restaurant, 'title': 'المطاعم والوجبات', 'color': Colors.redAccent},
      {'icon': Icons.shopping_basket, 'title': 'السوبرماركت', 'color': Colors.green},
      {'icon': Icons.directions_bus, 'title': 'الرحلات والسفر', 'color': Colors.orange},
      {'icon': Icons.local_pharmacy, 'title': 'الصيدليات والأدوية', 'color': Colors.teal},
      {'icon': Icons.local_shipping, 'title': 'الشحن بين المدن', 'color': Colors.brown},
      {'icon': Icons.two_wheeler, 'title': 'توصيل مشاوير', 'color': Colors.blue},
      {'icon': Icons.checkroom, 'title': 'الملابس والأزياء', 'color': Colors.pink},
      {'icon': Icons.face, 'title': 'أدوات التجميل', 'color': Colors.purple},
      {'icon': Icons.local_hospital, 'title': 'المراكز الطبية', 'color': Colors.red},
      {'icon': Icons.hotel, 'title': 'حجز الفنادق', 'color': Colors.indigo},
      {'icon': Icons.payment, 'title': 'التوصيل والمالية', 'color': Colors.amber.shade800},
      {'icon': Icons.grid_view, 'title': 'كل الخدمات', 'color': Colors.grey.shade700},
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: services.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          childAspectRatio: 0.80,
          crossAxisSpacing: 8,
          mainAxisSpacing: 12,
        ),
        itemBuilder: (context, index) {
          final service = services[index];
          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => VendorsScreen(
                    categoryTitle: service['title'],
                    categoryIcon: service['icon'],
                    categoryColor: service['color'],
                  ),
                ),
              );
            },
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: service['color'].withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(service['icon'], color: service['color'], size: 26),
                ),
                const SizedBox(height: 6),
                Text(
                  service['title'],
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black87),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                )
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSmartTripCard(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.directions_bus, color: Colors.orange),
              SizedBox(width: 8),
              Text('رحلتك القادمة: مأرب ➔ عدن', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 8),
          const Text('تتوقف الحافلة في استراحة شبوة بعد ساعتين.', style: TextStyle(color: Colors.black54, fontSize: 12)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => TrackingScreen()));
              },
              icon: const Icon(Icons.map, size: 16),
              label: const Text('تتبع خط السير على الخريطة', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          )
        ],
      ),
    );
  }
}

