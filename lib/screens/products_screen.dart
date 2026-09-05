import 'package:flutter/material.dart';
import 'vendors_screen.dart';

/// Compatibility wrapper for older routes.
///
/// The marketplace must never manufacture stores or products in the client.
/// All visible merchants and products are loaded from Firestore by VendorsScreen.
class ProductsScreen extends StatelessWidget {
  final String categoryName;

  const ProductsScreen({super.key, required this.categoryName});

  @override
  Widget build(BuildContext context) {
    return VendorsScreen(
      categoryTitle: categoryName,
      categoryIcon: Icons.store,
      categoryColor: const Color(0xFF1A365D),
    );
  }
}
