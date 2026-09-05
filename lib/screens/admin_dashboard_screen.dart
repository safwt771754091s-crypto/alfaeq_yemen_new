import 'package:flutter/material.dart';
import 'ai_admin_screen.dart';
import 'wallet_topup_screen.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final roles = [
      ('المدير العام', 'صلاحيات كاملة على النظام وإدارة الشركة', Icons.admin_panel_settings, Colors.blue),
      ('المدير المالي', 'إدارة الحسابات والأرصدة وعمليات المحفظة', Icons.account_balance_wallet, Colors.green),
      ('مدير البائعين والتجار', 'إدارة المتاجر والأصناف والبائعين', Icons.store, Colors.orange),
      ('مدير المبيعات والتسويق', 'إدارة العروض والكوبونات والحملات', Icons.local_offer, Colors.pink),
      ('مدير صيانة النظام', 'مراقبة الأداء والبناء والخدمات', Icons.settings_suggest, Colors.purple),
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('لوحة الإدارة والصلاحيات العليا')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: const Color(0xFF1A365D), borderRadius: BorderRadius.circular(16)), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('الفائق يمن — مركز التحكم', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            SizedBox(height: 6),
            Text('إدارة المتاجر والأصناف والمحافظ والخدمات من مكان واحد.', style: TextStyle(color: Colors.white70)),
          ])),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: ElevatedButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AiAdminScreen())), icon: const Icon(Icons.auto_awesome), label: const Text('مساعد الذكاء الاصطناعي'))),
            const SizedBox(width: 10),
            Expanded(child: ElevatedButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletTopupScreen())), icon: const Icon(Icons.account_balance_wallet), label: const Text('اختبار المحفظة'))),
          ]),
          const SizedBox(height: 20),
          const Text('هيكل الإدارة والصلاحيات', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...roles.map((role) => Card(margin: const EdgeInsets.only(bottom: 10), child: ListTile(leading: CircleAvatar(backgroundColor: role.$4.withOpacity(.15), child: Icon(role.$3, color: role.$4)), title: Text(role.$1, style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text(role.$2), trailing: const Icon(Icons.check_circle, color: Colors.green)))),
          const SizedBox(height: 12),
          const Text('تنبيه أمني: إنشاء حساب المدير الفعلي يجب أن يتم عبر Firebase Authentication ببيانات اعتماد يختارها المالك، وليس بكلمة مرور ثابتة داخل التطبيق.', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
        ]),
      ),
    );
  }
}
