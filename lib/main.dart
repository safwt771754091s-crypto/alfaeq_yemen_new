import 'package:flutter/material.dart';
import 'core/app_sections.dart';
import 'screens/admin_dashboard.dart';

void main() => runApp(const AlfaeqYemenApp());

class AlfaeqYemenApp extends StatelessWidget {
  const AlfaeqYemenApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'الفائق يمن',
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF0B6E4F), scaffoldBackgroundColor: const Color(0xFFF7F9F8)),
    home: const HomePage(),
  );
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('الفائق يمن', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.notifications_none)),
          IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminDashboard())), icon: const Icon(Icons.admin_panel_settings_outlined)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(decoration: InputDecoration(hintText: 'ابحث عن متجر أو منتج أو خدمة...', prefixIcon: const Icon(Icons.search), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none))),
          const SizedBox(height: 16),
          Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), color: const Color(0xFF0B6E4F)), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('مرحباً بك في الفائق يمن', style: TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900)), SizedBox(height: 8), Text('16 قطاعاً في منصة واحدة، مع التجار والطلبات والتوصيل والإدارة.', style: TextStyle(color: Colors.white70))])),
          const SizedBox(height: 24),
          const Text('الأقسام الـ16', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: appSections.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.08),
            itemBuilder: (context, index) {
              final section = appSections[index];
              return Card(
                elevation: 0,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SectionPage(section: section))),
                  child: Padding(padding: const EdgeInsets.all(14), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(_icon(section.icon), size: 36, color: const Color(0xFF0B6E4F)), const SizedBox(height: 10), Text(section.title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 5), Text(section.subtitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.grey))])),
                ),
              );
            },
          ),
        ],
      ),
    ),
  );

  static IconData _icon(String name) => switch (name) {
    'storefront' => Icons.storefront_outlined,
    'restaurant' => Icons.restaurant_outlined,
    'pharmacy' => Icons.local_pharmacy_outlined,
    'beauty' => Icons.face_retouching_natural,
    'construction' => Icons.construction_outlined,
    'car' => Icons.directions_car_outlined,
    'flight' => Icons.flight_takeoff_outlined,
    'hotel' => Icons.hotel_outlined,
    'account_balance' => Icons.account_balance_outlined,
    'handyman' => Icons.handyman_outlined,
    'devices' => Icons.devices_outlined,
    'home' => Icons.home_work_outlined,
    'work' => Icons.work_outline,
    'school' => Icons.school_outlined,
    'medical' => Icons.medical_services_outlined,
    _ => Icons.explore_outlined,
  };
}

class SectionPage extends StatelessWidget {
  final AppSection section;
  const SectionPage({super.key, required this.section});
  @override
  Widget build(BuildContext context) => Directionality(textDirection: TextDirection.rtl, child: Scaffold(appBar: AppBar(title: Text(section.title)), body: ListView(padding: const EdgeInsets.all(20), children: [Text(section.title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)), const SizedBox(height: 8), Text(section.subtitle), const SizedBox(height: 24), const Card(child: ListTile(leading: Icon(Icons.cloud_outlined), title: Text('بيانات القسم من Firebase'), subtitle: Text('لن يتم عرض منتجات أو أسعار وهمية. سيظهر المحتوى بعد اعتماد التاجر والبيانات الحقيقية.'))), const SizedBox(height: 12), const Card(child: ListTile(leading: Icon(Icons.store_outlined), title: Text('التجار المعتمدون'), subtitle: Text('المتاجر والمنتجات تُدار من لوحة الإدارة والتاجر.'))), const SizedBox(height: 12), const Card(child: ListTile(leading: Icon(Icons.local_shipping_outlined), title: Text('التوصيل وتتبع الطلب'), subtitle: Text('الطلبات يمكن ربطها بمندوب وحالات توصيل وموقع آخر مسجل.')))]));
}
