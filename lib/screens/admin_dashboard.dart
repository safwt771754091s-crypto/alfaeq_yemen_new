import 'package:flutter/material.dart';
import '../core/app_sections.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('لوحة الإدارة')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('صلاحيات الإدارة', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            const Text('المدير يوافق على التجار، ينشئ الأقسام، يدير المنتجات والطلبات، ويتابع التوصيل.'),
            const SizedBox(height: 20),
            _ActionCard(icon: Icons.store, title: 'إضافة / اعتماد تاجر', onTap: () => _message(context, 'نموذج التاجر سيرتبط بـ Firestore')),
            _ActionCard(icon: Icons.category, title: 'إدارة الأقسام الـ16', onTap: () => _message(context, 'الأقسام مسجلة في app_sections.dart ويمكن إدارتها من Firestore')),
            _ActionCard(icon: Icons.inventory_2, title: 'إدارة المنتجات', onTap: () => _message(context, 'المنتجات مرتبطة بالمتجر وFirestore')),
            _ActionCard(icon: Icons.local_shipping, title: 'إدارة التوصيل', onTap: () => _message(context, 'تعيين المندوب وتحديث حالة التوصيل')),
            _ActionCard(icon: Icons.receipt_long, title: 'الطلبات والمدفوعات', onTap: () => _message(context, 'الطلبات والمدفوعات تحفظ مع سجل زمني')),
            const SizedBox(height: 18),
            const Text('الأقسام', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            ...appSections.map((s) => ListTile(leading: const Icon(Icons.check_circle_outline), title: Text(s.title), subtitle: Text(s.id))),
          ],
        ),
      ),
    );
  }

  static void _message(BuildContext context, String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  const _ActionCard({required this.icon, required this.title, required this.onTap});
  @override
  Widget build(BuildContext context) => Card(child: ListTile(leading: Icon(icon), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), trailing: const Icon(Icons.chevron_left), onTap: onTap));
}
