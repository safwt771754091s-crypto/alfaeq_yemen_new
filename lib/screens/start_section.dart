import 'package:flutter/material.dart';
import 'vendors_screen.dart';

/// Marketplace categories. Store/product records come from Firestore.
class StartSection extends StatelessWidget {
  const StartSection({super.key});

  static const _services = <Map<String, dynamic>>[
    {'title': 'المطاعم والوجبات', 'icon': Icons.restaurant, 'color': Colors.redAccent},
    {'title': 'السوبرماركت والمواد الغذائية', 'icon': Icons.shopping_basket, 'color': Colors.green},
    {'title': 'الصيدليات والأدوية', 'icon': Icons.local_pharmacy, 'color': Colors.teal},
    {'title': 'الملابس والأزياء', 'icon': Icons.checkroom, 'color': Colors.pink},
    {'title': 'أدوات التجميل والعناية', 'icon': Icons.face, 'color': Colors.purple},
    {'title': 'الإلكترونيات والكهربائيات', 'icon': Icons.electrical_services, 'color': Colors.blue},
    {'title': 'السيارات', 'icon': Icons.directions_car, 'color': Colors.indigo},
    {'title': 'قطع الغيار وإكسسوارات السيارات', 'icon': Icons.car_repair, 'color': Colors.deepPurple},
    {'title': 'تأجير السيارات', 'icon': Icons.car_rental, 'color': Colors.lightBlue},
    {'title': 'مواد البناء', 'icon': Icons.construction, 'color': Colors.brown},
    {'title': 'المنتجات المحلية والحرف اليدوية', 'icon': Icons.cottage, 'color': Colors.deepOrange},
    {'title': 'الفنادق والحجوزات', 'icon': Icons.hotel, 'color': Colors.orange},
    {'title': 'الرحلات والسفر وتذاكر الطيران', 'icon': Icons.flight, 'color': Colors.cyan},
    {'title': 'الشحن والتوصيل بين المدن', 'icon': Icons.local_shipping, 'color': Colors.blueGrey},
    {'title': 'المراكز الطبية', 'icon': Icons.local_hospital, 'color': Colors.red},
    {'title': 'الخدمات والأسواق المحلية', 'icon': Icons.storefront, 'color': Colors.amber},
  ];

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('الفائق يمن — جميع الأقسام')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('منصة تجارة وخدمات حقيقية', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text('كل متجر ومنتج يظهر هنا يجب أن يكون مسجلاً ومفعلاً في Firestore. لا توجد بيانات وهمية.'),
              const SizedBox(height: 16),
              Expanded(
                child: GridView.builder(
                  itemCount: _services.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.08,
                  ),
                  itemBuilder: (context, index) {
                    final service = _services[index];
                    final title = service['title'] as String;
                    final icon = service['icon'] as IconData;
                    final color = service['color'] as Color;
                    return Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => VendorsScreen(
                              categoryTitle: title,
                              categoryIcon: icon,
                              categoryColor: color,
                            ),
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircleAvatar(backgroundColor: color.withValues(alpha: 0.12), child: Icon(icon, color: color)),
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
