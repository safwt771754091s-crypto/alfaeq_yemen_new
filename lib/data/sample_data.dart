import 'package:flutter/material.dart';
import '../models/models.dart';

class SampleData {
  static final List<Map<String, dynamic>> _serviceDefs = [
    {'title': 'المطاعم', 'icon': Icons.restaurant, 'color': Colors.orange},
    {'title': 'السوبرماركت', 'icon': Icons.shopping_cart, 'color': Colors.green},
    {'title': 'الصيدليات', 'icon': Icons.local_pharmacy, 'color': Colors.red},
    {'title': 'تأجير السيارات', 'icon': Icons.directions_car, 'color': Colors.blue},
    {'title': 'حجز الرحلات', 'icon': Icons.flight, 'color': Colors.indigo},
    {'title': 'الفنادق', 'icon': Icons.hotel, 'color': Colors.purple},
    {'title': 'البنوك', 'icon': Icons.account_balance, 'color': Colors.teal},
    {'title': 'مواد البناء', 'icon': Icons.construction, 'color': Colors.brown},
    {'title': 'أدوات التجميل', 'icon': Icons.brush, 'color': Colors.pink},
    {'title': 'ملابس جاهزة', 'icon': Icons.checkroom, 'color': Colors.pinkAccent},
    {'title': 'منتجات محلية', 'icon': Icons.cottage, 'color': Colors.deepOrange},
  ];

  static List<Service> get services {
    return List.generate(_serviceDefs.length, (sIndex) {
      final def = _serviceDefs[sIndex];
      final title = def['title'] as String;
      final shops = List.generate(10, (shopIndex) {
        final shopId = 's${sIndex}_sh$shopIndex';
        final products = List.generate(10, (pIndex) {
          final prodId = '${shopId}_p$pIndex';
          return Product(
            id: prodId,
            name: '$title المحل ${shopIndex + 1} - منتج ${pIndex + 1}',
            description: 'وصف مختصر للمنتج ${pIndex + 1} من محل ${shopIndex + 1}. جودة عالية وسعر مناسب.',
            price: ((pIndex + 1) * 5.0) + (shopIndex % 3) * 2,
            icon: Icons.shopping_bag,
          );
        });

        return Shop(
          id: shopId,
          name: '$title المحل ${shopIndex + 1}',
          address: 'العنوان ${shopIndex + 1}, المدينة',
          products: products,
          icon: Icons.storefront,
        );
      });

      return Service(
        id: 'svc_$sIndex',
        title: title,
        icon: def['icon'] as IconData,
        color: def['color'] as Color,
        shops: shops,
      );
    });
  }
}
