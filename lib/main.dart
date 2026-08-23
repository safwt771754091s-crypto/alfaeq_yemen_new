import 'package:flutter/material.dart';
import 'screens/products_screen.dart';
import 'screens/login_screen.dart';

void main() {
  runApp(const AlfaeqYemenApp());
}

class AlfaeqYemenApp extends StatelessWidget {
  const AlfaeqYemenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'الفائق يمن',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFFF7FAFC),
        fontFamily: 'sans-serif',
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> categories = [
      {'name': 'الصيدليات والأدوية', 'icon': Icons.local_hospital, 'color': Colors.teal},
      {'name': 'الرحلات والسفر', 'icon': Icons.directions_bus, 'color': Colors.orange},
      {'name': 'السوبرماركت', 'icon': Icons.shopping_basket, 'color': Colors.green},
      {'name': 'المطاعم والوجبات', 'icon': Icons.restaurant, 'color': Colors.red},
      {'name': 'الشحن بين المدن', 'icon': Icons.local_shipping, 'color': Colors.brown},
      {'name': 'توصيل مشاوير', 'icon': Icons.motorcycle, 'color': Colors.blue},
      {'name': 'الملابس والأزياء', 'icon': Icons.checkroom, 'color': Colors.pink},
      {'name': 'أدوات التجميل', 'icon': Icons.face, 'color': Colors.purple},
      {'name': 'المراكز الطبية', 'icon': Icons.medical_services, 'color': Colors.redAccent},
      {'name': 'حجز الفنادق', 'icon': Icons.hotel, 'color': Colors.indigo},
      {'name': 'التوصيل والمالية', 'icon': Icons.account_balance_wallet, 'color': Colors.amber},
      {'name': 'كل الخدمات', 'icon': Icons.grid_view, 'color': Colors.grey},
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A365D),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('الفائق يمن', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            Text('الفائق.. يوصل لبي ما يوصل', style: TextStyle(color: Colors.white70, fontSize: 10)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.admin_panel_settings, color: Colors.white),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // بطاقة الرصيد
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: const Color(0xFF1A365D),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('رصيد الفائق المتاح', style: TextStyle(color: Colors.white70, fontSize: 13)),
                Text('150,000 ر.ي', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(height: 15),
          const Text('أقسام الخدمات الاحترافية', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1A365D))),
          const SizedBox(height: 10),
          // شبكة الأقسام الموصولة مباشرة بشاشة المتاجر والأصناف
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: categories.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 0.85,
            ),
            itemBuilder: (context, index) {
              final cat = categories[index];
              return InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ProductsScreen(categoryName: cat['name']),
                    ),
                  );
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 4, spreadRadius: 1)],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(cat['icon'], color: cat['color'], size: 28),
                      const SizedBox(height: 6),
                      Text(
                        cat['name'],
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black87),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
