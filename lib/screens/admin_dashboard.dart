import 'package:flutter/material.dart';
import '../core/app_sections.dart';
import 'admin_data_entry.dart';
import 'merchant_center_page.dart';

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
            const Text('الإدارة الفعلية', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            const Text('إدارة بيانات المنصة الحقيقية مع فصل واضح بين إنشاء البيانات واعتمادها.'),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MerchantCenterPage())),
              icon: const Icon(Icons.storefront_outlined),
              label: const Text('مركز التاجر الاحترافي'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminDataEntry())),
              icon: const Icon(Icons.add_business),
              label: const Text('إضافة بيانات إدارية مباشرة'),
            ),
            const SizedBox(height: 12),
            _ActionCard(icon: Icons.store, title: 'اعتماد وإدارة التجار', onTap: () => _message(context, 'التجار الجدد يدخلون بحالة pending حتى المراجعة.')),
            _ActionCard(icon: Icons.category, title: 'إدارة الأقسام الـ16', onTap: () => _message(context, 'الأقسام معرفة مركزيًا ويمكن نقلها إلى مجموعة sections عند تفعيل الإدارة الديناميكية.')),
            _ActionCard(icon: Icons.inventory_2, title: 'إدارة المنتجات', onTap: () => _message(context, 'مركز التاجر يدير الأسعار والمخزون، مع بقاء الصلاحيات محكومة بقواعد Firestore.')),
            _ActionCard(icon: Icons.local_shipping, title: 'إدارة التوصيل', onTap: () => _message(context, 'الطلب يحتوي deliveryStatus ويمكن ربطه بالمندوب والموقع.')),
            _ActionCard(icon: Icons.receipt_long, title: 'الطلبات والمدفوعات', onTap: () => _message(context, 'الطلبات والمدفوعات تحفظ بسجل زمني في Firestore.')),
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
