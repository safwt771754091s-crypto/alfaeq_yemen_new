import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'ai_admin_screen.dart';
import 'admin_data_manager_screen.dart';
import 'wallet_topup_screen.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  Stream<int> _count(String collection, {String? field, dynamic value}) {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance.collection(collection);
    if (field != null) q = q.where(field, isEqualTo: value);
    return q.snapshots().map((s) => s.size);
  }

  Widget _stat(String title, IconData icon, Stream<int> stream) {
    return StreamBuilder<int>(
      stream: stream,
      builder: (context, snapshot) => Card(
        child: ListTile(
          leading: CircleAvatar(child: Icon(icon)),
          title: Text(title),
          trailing: Text('${snapshot.data ?? 0}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final roles = [
      ('المدير العام', 'صلاحيات كاملة على النظام وإدارة الشركة', Icons.admin_panel_settings),
      ('المدير المالي', 'إدارة الحسابات والأرصدة وعمليات المحفظة', Icons.account_balance_wallet),
      ('مدير البائعين والتجار', 'إدارة المتاجر والأصناف والبائعين', Icons.store),
      ('مدير المبيعات والتسويق', 'إدارة العروض والكوبونات والحملات', Icons.local_offer),
      ('مدير صيانة النظام', 'مراقبة الأداء والبناء والخدمات', Icons.settings_suggest),
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('لوحة الإدارة والصلاحيات العليا')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: const Color(0xFF1A365D), borderRadius: BorderRadius.circular(16)),
              child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('الفائق يمن — مركز التحكم الحقيقي', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                SizedBox(height: 6),
                Text('الأرقام التالية تقرأ مباشرة من Firestore وليست بيانات تجريبية.', style: TextStyle(color: Colors.white70)),
              ]),
            ),
            const SizedBox(height: 12),
            _stat('المتاجر النشطة', Icons.store, _count('stores', field: 'active', value: true)),
            _stat('المنتجات النشطة', Icons.inventory_2, _count('products', field: 'active', value: true)),
            _stat('المتاجر بانتظار الاعتماد', Icons.pending_actions, _count('stores', field: 'verified', value: false)),
            _stat('المنتجات بانتظار الاعتماد', Icons.fact_check_outlined, _count('products', field: 'verified', value: false)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: ElevatedButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminDataManagerScreen())), icon: const Icon(Icons.dataset), label: const Text('إدارة البيانات'))),
              const SizedBox(width: 10),
              Expanded(child: ElevatedButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AiAdminScreen())), icon: const Icon(Icons.auto_awesome), label: const Text('مساعد الإدارة'))),
            ]),
            const SizedBox(height: 10),
            ElevatedButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletTopupScreen())), icon: const Icon(Icons.account_balance_wallet), label: const Text('إدارة/اختبار المحفظة')),
            const SizedBox(height: 20),
            const Text('هيكل الإدارة والصلاحيات', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...roles.map((role) => Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: CircleAvatar(child: Icon(role.$3)),
                title: Text(role.$1, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(role.$2),
                trailing: const Icon(Icons.verified, color: Colors.green),
              ),
            )),
            const SizedBox(height: 12),
            const Text('الأدوار العليا لا تُنشأ من شاشة التسجيل العادية. تعيين admin/manager يجب أن يتم من جهة موثوقة، بينما التاجر يستطيع إنشاء حساب تاجر وإدارة بيانات متجره.', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
