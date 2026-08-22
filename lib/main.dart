import 'package:flutter/material.dart';
import 'screens/placeholders.dart';
import 'screens/vendor_add_product.dart';

void main() {
  runApp(const AlfaeqYemenApp());
}

class AlfaeqYemenApp extends StatelessWidget {
  const AlfaeqYemenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'الفائق يمن',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Roboto',
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const MainNavigationScreen(),
        '/add_product': (context) => const VendorAddProductScreen(),
       '/travel': (context) => const CategoryScreen(categoryName: 'الرحلات والسفر'),
 '/admin_panel': (context) => const AdminPanelScreen(),
      },
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  String selectedCity = 'عدن - خور مكسر';

  final List<String> yemenCities = [
    'عدن - خور مكسر',
    'صنعاء - السبعين',
    'مأرب - المجمع',
    'تعز - شارع جمال',
    'حضرموت - المكلا',
  ];

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      _buildHomeScreen(context),
      const AdvancedSearchScreen(),
      const YemenMapsScreen(),
      const PaymentWalletScreen(),
      _buildMoreMenuScreen(context),
    ];

    return Scaffold(
      body: pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF1A365D),
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.grid_view), label: 'الرئيسية'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'البحث'),
          BottomNavigationBarItem(icon: Icon(Icons.near_me), label: 'التوصيل'),
          BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet), label: 'المحفظة'),
          BottomNavigationBarItem(icon: Icon(Icons.menu), label: 'المزيد'),
        ],
      ),
    );
  }

  Widget _buildHomeScreen(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A365D),
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.location_on, color: Colors.amber, size: 20),
            const SizedBox(width: 6),
            DropdownButton<String>(
              value: selectedCity,
              dropdownColor: const Color(0xFF1A365D),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              underline: const SizedBox(),
              icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
              onChanged: (String? newValue) {
                if (newValue != null) {
                  setState(() => selectedCity = newValue);
                }
              },
              items: yemenCities.map<DropdownMenuItem<String>>((String city) {
                return DropdownMenuItem<String>(
                  value: city,
                  child: Text(city),
                );
              }).toList(),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              color: const Color(0xFF1A365D),
              padding: const EdgeInsets.all(16),
              child: const TextField(
                decoration: InputDecoration(
                  hintText: 'ابحث عن صيدلية، مطعم، منتج، أو حجز...',
                  fillColor: Colors.white,
                  filled: true,
                  prefixIcon: Icon(Icons.search, color: Colors.grey),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 15),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: Text('الأقسام الرئيسية', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 10),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 4,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              children: [
                _buildCategoryCard(context, 'الملابس والأزياء', Icons.checkroom, Colors.blue),
                _buildCategoryCard(context, 'أدوات التجميل', Icons.face, Colors.purple),
                _buildCategoryCard(context, 'المطاعم والوجبات', Icons.restaurant, Colors.orange),
                _buildCategoryCard(context, 'السوبرماركت', Icons.shopping_basket, Colors.green),
                _buildCategoryCard(context, 'الفنادق والحجوزات', Icons.hotel, Colors.teal),
                _buildCategoryCard(context, 'الصيدليات والأدوية', Icons.medical_services, Colors.red),
                _buildCategoryCard(context, 'المراكز الطبية', Icons.add_business, Colors.indigo),
                _buildCategoryCard(context, 'التوصيل والمالية', Icons.local_shipping, Colors.lightBlue),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryCard(BuildContext context, String title, IconData icon, Color color) {
    return InkWell(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (context) => CategoryScreen(categoryName: title, categoryColor: color, categoryIcon: icon)));
      },
      child: Container(
        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 6),
            Text(title, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold), textAlign: TextAlign.center, maxLines: 2),
          ],
        ),
      ),
    );
  }

  Widget _buildMoreMenuScreen(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المزيد والإعدادات'), backgroundColor: const Color(0xFF1A365D), foregroundColor: Colors.white),
      body: ListView(
        children: [
          UserAccountsDrawerHeader(
            accountName: Text(CurrentUser.name),
            accountEmail: Text(CurrentUser.role == UserRole.admin ? 'الإدارة العليا (المدير)' : 'بائع معتمد - ${CurrentUser.storeName}'),
            currentAccountPicture: const CircleAvatar(backgroundColor: Colors.amber, child: Icon(Icons.person, size: 40, color: Colors.white)),
            decoration: const BoxDecoration(color: Color(0xFF1A365D)),
          ),
          
          // خيارات الإدارة العليا
          ListTile(
            leading: const Icon(Icons.admin_panel_settings, color: Colors.red),
            title: const Text('لوحة تحكم المدير (إضافة بائعين ومحافظ)', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('إدارة التجار وتكشيف وتفعيل المحافظ الإلكترونية'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.pushNamed(context, '/admin_panel');
            },
          ),
          const Divider(),

          // خيارات البائع
          ListTile(
            leading: const Icon(Icons.add_shopping_cart, color: Colors.blue),
            title: const Text('لوحة البائع (إضافة المنتجات)', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('إضافة منتجات وأسعار جديدة لمتجرك'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const VendorDashboardScreen()));
            },
          ),
          const Divider(),

          ListTile(
            leading: const Icon(Icons.account_balance_wallet, color: Colors.green),
            title: const Text('المحفظة وسداد الفواتير'),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const PaymentWalletScreen()));
            },
          ),
        ],
      ),
    );
  }
}
