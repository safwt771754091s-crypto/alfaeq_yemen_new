import 'package:flutter/material.dart';
import 'vendors_screen.dart';

/// Entry point for browsing marketplace services.
/// Uses the same Firestore-backed merchant flow as the main home screen.
class StartSection extends StatelessWidget {
  const StartSection({super.key});

  static const _services = <Map<String, dynamic>>[
    {'title': 'المطاعم والوجبات', 'icon': Icons.restaurant, 'color': Colors.redAccent},
    {'title': 'السوبرماركت', 'icon': Icons.shopping_basket, 'color': Colors.green},
    {'title': 'الصيدليات والأدوية', 'icon': Icons.local_pharmacy, 'color': Colors.teal},
    {'title': 'الملابس والأزياء', 'icon': Icons.checkroom, 'color': Colors.pink},
    {'title': 'أدوات التجميل', 'icon': Icons.face, 'color': Colors.purple},
    {'title': 'الإلكترونيات والكهربائيات', 'icon': Icons.electrical_services, 'color': Colors.blue},
    {'title': 'السيارات وقطع الغيار', 'icon': Icons.directions_car, 'color': Colors.indigo},
    {'title': 'مواد البناء', 'icon': Icons.construction, 'color': Colors.brown},
    {'title': 'المنتجات المحلية', 'icon': Icons.cottage, 'color': Colors.deepOrange},
    {'title': 'الفنادق والحجوزات', 'icon': Icons.hotel, 'color': Colors.orange},
    {'title': 'الرحلات والسفر', 'icon': Icons.flight, 'color': Colors.cyan},
    {'title': 'المراكز الطبية', 'icon': Icons.local_hospital, 'color': Colors.red},
  ];

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('ابدأ في الفائق يمن')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('اختر الخدمة التي تريد استخدامها', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('تصفح المتاجر والمنتجات المنشورة فعلياً في Firestore.'),
              const SizedBox(height: 16),
              Expanded(
                child: GridView.builder(
                  itemCount: _services.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.15,
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
                            CircleAvatar(
                              backgroundColor: color.withOpacity(.12),
                              child: Icon(icon, color: color),
                            ),
                            const SizedBox(height: 8),
                            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
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
