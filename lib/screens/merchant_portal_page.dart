import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'merchant_center_page.dart';

/// Secure entry point for the merchant workspace.
/// The Firestore rules remain the final authorization boundary; this page
/// prevents ordinary customers from reaching merchant controls in the UI.
class MerchantPortalPage extends StatefulWidget {
  const MerchantPortalPage({super.key});

  @override
  State<MerchantPortalPage> createState() => _MerchantPortalPageState();
}

class _MerchantPortalPageState extends State<MerchantPortalPage> {
  final AuthService _auth = AuthService();
  late Future<String> _roleFuture;

  @override
  void initState() {
    super.initState();
    _roleFuture = _auth.role();
  }

  void _refresh() {
    setState(() => _roleFuture = _auth.role());
  }

  bool _allowed(String role) =>
      role == 'merchant' || role == 'admin' || role == 'owner' || role == 'developer';

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: FutureBuilder<String>(
        future: _roleFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }

          final role = snapshot.data ?? 'guest';
          if (_allowed(role)) return const MerchantCenterPage();

          return Scaffold(
            appBar: AppBar(title: const Text('بوابة الأعمال')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Card(
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.storefront_outlined, size: 58),
                        const SizedBox(height: 16),
                        const Text('مركز التاجر محمي', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 10),
                        const Text(
                          'هذه المنطقة مخصصة للحسابات التجارية المعتمدة. لا يمكن لحساب العميل العادي إنشاء متجر أو تعديل كتالوج.',
                          textAlign: TextAlign.center,
                          style: TextStyle(height: 1.5, color: Colors.black54),
                        ),
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: _refresh,
                          icon: const Icon(Icons.refresh),
                          label: const Text('إعادة التحقق من الصلاحية'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
