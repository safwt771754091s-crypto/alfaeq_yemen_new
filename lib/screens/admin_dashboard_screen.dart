import 'package:flutter/material.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    List<Map<String, dynamic>> roles = [
      {'title': 'المدير العام (صفوت محمد)', 'desc': 'صلاحيات كاملة على النظام وإدارة الشركة', 'icon': Icons.admin_panel_settings, 'color': Colors.blue},
      {'title': 'المدير المالي', 'desc': 'إدارة الحسابات، الأرصدة، والمحافظ البنكية', 'icon': Icons.account_balance_wallet, 'color': Colors.green},
      {'title': 'مدير البائعين والتجار', 'desc': 'إدارة المتاجر والأصناف في عدن ومأرب وبقية المحافظات', 'icon': Icons.store, 'color': Colors.orange},
      {'title': 'مدير المبيعات والتسويق', 'desc': 'إدارة العروض، الكوبونات، وحملات الترويج', 'icon': Icons.local_offer, 'color': Colors.pink},
      {'title': 'مدير صيانة النظام', 'desc': 'مراقبة السيرفرات، الأداء، وحالة البناء', 'icon': Icons.settings_suggest, 'color': Colors.purple},
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة الإدارة والصلاحيات العليا', style: TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A365D),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('إضافة بائعين عبر الواتساب (فرع عدن)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 6),
                const Text('أرسل رابط الانضمام المباشر لمساعدك في عدن ليقوم بتسجيل المتاجر والمحلات بسهولة.', style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تم نسخ رابط انضمام بائعين عدن: wa.me/alfaeq_yemen/aden_vendors')),
                    );
                  },
                  icon: const Icon(Icons.share, size: 16, color: Color(0xFF1A365D)),
                  label: const Text('مشاركة رابط الواتساب للمساعد', style: TextStyle(color: Color(0xFF1A365D), fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                )
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text('هيكل الإدارة والصلاحيات', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...roles.map((role) {
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 5, offset: const Offset(0, 2))],
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: role['color'].withOpacity(0.15),
                  child: Icon(role['icon'], color: role['color']),
                ),
                title: Text(role['title'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text(role['desc'], style: const TextStyle(fontSize: 11, color: Colors.grey)),
                trailing: const Icon(Icons.check_circle, color: Colors.green, size: 20),
              ),
            );
          }).toList(),
        ],
      ),
    );
  }
}
