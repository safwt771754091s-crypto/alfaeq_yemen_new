import 'package:flutter/material.dart';
import 'vendors_screen.dart';

/// Compatibility entry point kept for older imports.
/// The active marketplace flow is Firestore-backed through VendorsScreen.
class CartManager {
  static final List<Map<String, dynamic>> items = [];

  static void addItem(String name, int price) {
    final index = items.indexWhere((item) => item['name'] == name);
    if (index >= 0) {
      items[index]['quantity'] = (items[index]['quantity'] as int) + 1;
    } else {
      items.add({'name': name, 'price': price, 'quantity': 1});
    }
  }

  static void removeItem(int index) {
    if (index < 0 || index >= items.length) return;
    final quantity = items[index]['quantity'] as int;
    if (quantity > 1) {
      items[index]['quantity'] = quantity - 1;
    } else {
      items.removeAt(index);
    }
  }

  static void addItemQuantity(int index) {
    if (index >= 0 && index < items.length) {
      items[index]['quantity'] = (items[index]['quantity'] as int) + 1;
    }
  }

  static int get totalCount => items.fold<int>(
        0,
        (sum, item) => sum + (item['quantity'] as int),
      );

  static int get totalPrice => items.fold<int>(
        0,
        (sum, item) => sum + ((item['price'] as int) * (item['quantity'] as int)),
      );
}

/// Legacy category screen now delegates to the live Firestore marketplace.
/// No hard-coded vendors or products are shown from this screen.
class CategoryScreen extends StatelessWidget {
  final String categoryName;
  final Color categoryColor;
  final IconData categoryIcon;

  const CategoryScreen({
    super.key,
    required this.categoryName,
    required this.categoryColor,
    required this.categoryIcon,
  });

  @override
  Widget build(BuildContext context) {
    return VendorsScreen(
      categoryTitle: categoryName,
      categoryIcon: categoryIcon,
      categoryColor: categoryColor,
    );
  }
}
