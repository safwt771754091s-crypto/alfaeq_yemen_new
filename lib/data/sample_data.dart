import 'package:flutter/material.dart';
import '../models/models.dart';

/// Compatibility layer for older screens.
/// Store and product data must never come from this file.
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

  /// Kept only for backwards compatibility with legacy widgets.
  /// It intentionally returns no shops or products so fake data can never appear.
  static List<Service> get services {
    return _serviceDefs.map((def) {
      return Service(
        id: 'legacy_${def['title']}',
        title: def['title'] as String,
        icon: def['icon'] as IconData,
        color: def['color'] as Color,
        shops: const [],
      );
    }).toList(growable: false);
  }
}
