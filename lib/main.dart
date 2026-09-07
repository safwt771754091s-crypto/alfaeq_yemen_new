import 'package:flutter/material.dart';

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
        useMaterial3: true,
        fontFamily: 'Arial',
        colorSchemeSeed: const Color(0xFF0B6E4F),
        scaffoldBackgroundColor: const Color(0xFFF7F9F8),
      ),
      home: const FreshHomePage(),
    );
  }
}

class FreshHomePage extends StatelessWidget {
  const FreshHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final services = <({String title, IconData icon})>[
      (title: 'المتاجر', icon: Icons.storefront_outlined),
      (title: 'المطاعم', icon: Icons.restaurant_outlined),
      (title: 'الصيدليات', icon: Icons.local_pharmacy_outlined),
      (title: 'السفر والفنادق', icon: Icons.flight_takeoff_outlined),
      (title: 'السيارات', icon: Icons.directions_car_outlined),
      (title: 'الخدمات', icon: Icons.handyman_outlined),
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الفائق يمن', style: TextStyle(fontWeight: FontWeight.w800)),
          centerTitle: false,
          actions: [
            IconButton(onPressed: () {}, icon: const Icon(Icons.notifications_none)),
            IconButton(onPressed: () {}, icon: const Icon(Icons.shopping_cart_outlined)),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            TextField(
              decoration: InputDecoration(
                hintText: 'ابحث عن متجر أو خدمة...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(
                  colors: [Color(0xFF0B6E4F), Color(0xFF12805D)],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('مرحباً بك في الفائق يمن', style: TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900)),
                  SizedBox(height: 8),
                  Text('منصة يمنية واحدة للتسوق والخدمات والحجوزات.', style: TextStyle(color: Colors.white70, fontSize: 15)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text('الأقسام', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: services.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.25,
              ),
              itemBuilder: (context, index) {
                final item = services[index];
                return Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {},
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(item.icon, size: 38, color: const Color(0xFF0B6E4F)),
                        const SizedBox(height: 10),
                        Text(item.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
