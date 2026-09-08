import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'merchant_center_page.dart';
import 'merchant_orders_page.dart';

/// Secure entry point for the merchant workspace.
/// Firestore rules remain the final authorization boundary.
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

  void _refresh() => setState(() => _roleFuture = _auth.role());

  bool _allowed(String role) => role == 'merchant' || role == 'admin' || role == 'owner' || role == 'developer';

  void _open(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

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
          if (!_allowed(role)) {
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
                          const Text('هذه المنطقة مخصصة للحسابات التجارية المعتمدة. لا يمكن لحساب العميل العادي إنشاء متجر أو تعديل كتالوج.', textAlign: TextAlign.center, style: TextStyle(height: 1.5, color: Colors.black54)),
                          const SizedBox(height: 18),
                          FilledButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh), label: const Text('إعادة التحقق من الصلاحية')),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }

          return Scaffold(
            appBar: AppBar(title: const Text('بوابة التاجر')),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF0B6E4F), Color(0xFF124E78)]), borderRadius: BorderRadius.circular(26)),
                  child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.business_center_outlined, color: Colors.white, size: 36),
                    SizedBox(height: 10),
                    Text('مركز أعمالك', style: TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.w900)),
                    SizedBox(height: 6),
                    Text('إدارة المتاجر والمنتجات والطلبات من مساحة واحدة.', style: TextStyle(color: Colors.white70)),
                  ]),
                ),
                const SizedBox(height: 18),
                _ActionCard(title: 'المتاجر والمنتجات', subtitle: 'إدارة المتجر والكتالوج والأسعار والمخزون', icon: Icons.storefront_outlined, onTap: () => _open(const MerchantCenterPage())),
                _ActionCard(title: 'طلبات العملاء', subtitle: 'قبول الطلبات وتجهيزها وتجهيزها للاستلام', icon: Icons.receipt_long_outlined, onTap: () => _open(const MerchantOrdersPage())),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _ActionCard({required this.title, required this.subtitle, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 12),
        child: ListTile(
          contentPadding: const EdgeInsets.all(14),
          leading: CircleAvatar(child: Icon(icon)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_left),
          onTap: onTap,
        ),
      );
}
