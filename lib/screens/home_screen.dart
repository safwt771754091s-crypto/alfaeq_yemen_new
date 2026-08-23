import 'package:flutter/material.dart';

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
            CircleAvatar(
              backgroundColor: const Color(0xFF1A365D).withOpacity(0.1),
              child: const Icon(Icons.person, color: Color(0xFF1A365D)),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('مرحباً بك، صفوت', style: TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.bold)),
                Text('📍 مأرب، المجمع', style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none, color: Colors.black87, size: 28),
            onPressed: () {},
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
            _buildSmartTripCard(),
            const SizedBox(height: 20),
            _buildPromotionsSection(),
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
        boxShadow: [
          BoxShadow(color: const Color(0xFF1A365D).withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5)),
        ],
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
                onPressed: () {},
                icon: const Icon(Icons.add, size: 18, color: Color(0xFF1A365D)),
                label: const Text('شحن', style: TextStyle(color: Color(0xFF1A365D), fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              )
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildWalletAction(Icons.qr_code_scanner, 'مسح الدفع', () {}),
              _buildWalletAction(Icons.send_to_mobile, 'تحويل', () {}),
              _buildWalletAction(Icons.history, 'السجل', () {}),
              _buildWalletAction(Icons.account_balance_wallet, 'الخدمات المالية', () {}),
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
          return GestureDetector(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('الانتقال إلى قسم: ${services[index]['title']}')),
              );
            },
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: services[index]['color'].withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(services[index]['icon'], color: services[index]['color'], size: 26),
                ),
                const SizedBox(height: 6),
                Text(
                  services[index]['title'],
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

  Widget _buildSmartTripCard() {
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
            child: ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('اطلب وجبتك الآن لتجهز قبل وصولك! 🍽️', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildPromotionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('عروض الفائق 🚀', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 130,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: 3,
            itemBuilder: (context, index) {
              List<Color> cardColors = [Colors.blueAccent, Colors.pinkAccent, Colors.green];
              List<String> titles = [
                'توصيل مجاني\nلأول 3 طلبات!',
                'خصم 20%\nعلى حجوزات السفر',
                'وجبتك تسبقك\nاحجز باصك واطلب'
              ];
              return Container(
                width: 260,
                margin: const EdgeInsets.only(left: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardColors[index],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(titles[index], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                            child: Text('اكتشف الآن', style: TextStyle(color: cardColors[index], fontSize: 10, fontWeight: FontWeight.bold)),
                          )
                        ],
                      ),
                    ),
                    const Icon(Icons.local_offer, color: Colors.white54, size: 45),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
	

