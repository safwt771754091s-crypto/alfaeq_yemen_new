import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core/app_sections.dart';
import '../services/auth_service.dart';
import 'admin_data_entry.dart';
import 'developer_page.dart';
import 'dispatch_center_page.dart';
import 'merchant_approval_page.dart';
import 'merchant_invites_page.dart';
import 'merchant_portal_page.dart';
import 'platform_automation_page.dart';
import 'platform_control_page.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('مركز الإدارة', style: TextStyle(fontWeight: FontWeight.w900)),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: () => (context as Element).markNeedsBuild(),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: FutureBuilder<bool>(
          future: AuthService().hasAdminClaim(),
          builder: (context, access) {
            if (access.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (access.data != true) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('الوصول إلى مركز الإدارة يتطلب صلاحية admin.', textAlign: TextAlign.center),
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
              children: [
                _hero(context),
                const SizedBox(height: 14),
                _liveOverview(),
                const SizedBox(height: 18),
                const Text('التشغيل السريع', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                _grid(context),
                const SizedBox(height: 18),
                const Text('الإدارة الأساسية', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                _ActionCard(icon: Icons.tune_outlined, title: 'مركز تشغيل المنصة', subtitle: 'الأقسام، الدفع، التجار والإعدادات التشغيلية', onTap: () => _open(context, const PlatformControlPage())),
                _ActionCard(icon: Icons.radar_outlined, title: 'أتمتة وجاهزية المنصة', subtitle: 'قراءة حالة الجاهزية القادمة من الخادم', onTap: () => _open(context, const PlatformAutomationPage())),
                _ActionCard(icon: Icons.fact_check_outlined, title: 'اعتماد المتاجر', subtitle: 'مراجعة واعتماد طلبات التجار', onTap: () => _open(context, const MerchantApprovalPage())),
                _ActionCard(icon: Icons.add_link, title: 'التجار والروابط', subtitle: 'إنشاء وإدارة دعوات التجار', onTap: () => _open(context, const MerchantInvitesPage())),
                _ActionCard(icon: Icons.storefront_outlined, title: 'مركز التاجر', subtitle: 'الكتالوج والمنتجات والطلبات', onTap: () => _open(context, const MerchantPortalPage())),
                _ActionCard(icon: Icons.add_business_outlined, title: 'إدخال البيانات', subtitle: 'إضافة المتاجر والمنتجات من الإدارة', onTap: () => _open(context, const AdminDataEntry())),
                _ActionCard(icon: Icons.local_shipping_outlined, title: 'التوزيع والمندوبون', subtitle: 'تشغيل التوزيع ومتابعة الطلبات', onTap: () => _open(context, const DispatchCenterPage())),
                _ActionCard(icon: Icons.code_outlined, title: 'مركز المطور والأمن', subtitle: 'الفحص، سجل التدقيق، وتقارير الحماية', onTap: () => _open(context, const DeveloperPage())),
                const SizedBox(height: 18),
                const Text('الأقسام الحالية', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: appSections
                        .map((section) => ListTile(
                              leading: const Icon(Icons.check_circle_outline),
                              title: Text(section.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text(section.id),
                            ))
                        .toList(),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _hero(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFF0B6E4F), Color(0xFF124E78)],
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.admin_panel_settings_outlined, color: Colors.white, size: 34),
            SizedBox(width: 10),
            Text('الإدارة الآمنة', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
          ]),
          const SizedBox(height: 10),
          const Text('تحكم في تشغيل الفائق يمن من مكان واحد', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('الصلاحيات الحقيقية تظل مفروضة من Firebase Security Rules وCustom Claims على الخادم.', style: TextStyle(color: Colors.white70, height: 1.45)),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () => _open(context, const PlatformAutomationPage()),
            icon: const Icon(Icons.health_and_safety_outlined),
            label: const Text('فحص جاهزية المنصة'),
          ),
        ]),
      ),
    );
  }

  Widget _liveOverview() {
    return FutureBuilder<_AdminStats>(
      future: _loadStats(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(child: Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())));
        }
        if (snapshot.hasError) {
          return const Card(child: ListTile(leading: Icon(Icons.warning_amber_outlined), title: Text('تعذر تحميل المؤشرات'), subtitle: Text('تحقق من اتصال Firebase وصلاحيات حساب الإدارة.')));
        }
        final stats = snapshot.data!;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('مؤشرات التشغيل', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _Metric(label: 'المستخدمون', value: stats.users, icon: Icons.people_outline)),
                const SizedBox(width: 8),
                Expanded(child: _Metric(label: 'المتاجر', value: stats.stores, icon: Icons.storefront_outlined)),
                const SizedBox(width: 8),
                Expanded(child: _Metric(label: 'المنتجات', value: stats.products, icon: Icons.inventory_2_outlined)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _Metric(label: 'الطلبات', value: stats.orders, icon: Icons.receipt_long_outlined)),
                const SizedBox(width: 8),
                Expanded(child: _Metric(label: 'عمليات المحفظة', value: stats.walletOperations, icon: Icons.account_balance_wallet_outlined)),
                const SizedBox(width: 8),
                Expanded(child: _Metric(label: 'سجل التدقيق', value: stats.auditLogs, icon: Icons.fact_check_outlined)),
              ]),
            ]),
          ),
        );
      },
    );
  }

  Widget _grid(BuildContext context) {
    final actions = <_QuickAction>[
      _QuickAction(Icons.store, 'اعتماد المتاجر', () => _open(context, const MerchantApprovalPage())),
      _QuickAction(Icons.add_business, 'إضافة بيانات', () => _open(context, const AdminDataEntry())),
      _QuickAction(Icons.account_balance_wallet_outlined, 'الدفع والمحافظ', () => _open(context, const PlatformControlPage())),
      _QuickAction(Icons.inventory_2_outlined, 'المنتجات', () => _open(context, const MerchantPortalPage())),
      _QuickAction(Icons.delivery_dining_outlined, 'التوزيع', () => _open(context, const DispatchCenterPage())),
      _QuickAction(Icons.security_outlined, 'الأمن والتدقيق', () => _open(context, const DeveloperPage())),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: actions.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.55),
      itemBuilder: (_, index) => Card(child: InkWell(onTap: actions[index].onTap, borderRadius: BorderRadius.circular(12), child: Padding(padding: const EdgeInsets.all(12), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(actions[index].icon, size: 28), const SizedBox(height: 8), Text(actions[index].title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800))])))),
    );
  }

  Future<_AdminStats> _loadStats() async {
    final db = FirebaseFirestore.instance;
    final results = await Future.wait([
      db.collection('users').get(),
      db.collection('stores').get(),
      db.collection('products').get(),
      db.collection('orders').get(),
      db.collection('walletOperations').get(),
      db.collection('auditLogs').get(),
    ]);
    return _AdminStats(
      users: results[0].size,
      stores: results[1].size,
      products: results[2].size,
      orders: results[3].size,
      walletOperations: results[4].size,
      auditLogs: results[5].size,
    );
  }

  static void _open(BuildContext context, Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));
}

class _AdminStats {
  final int users;
  final int stores;
  final int products;
  final int orders;
  final int walletOperations;
  final int auditLogs;
  const _AdminStats({required this.users, required this.stores, required this.products, required this.orders, required this.walletOperations, required this.auditLogs});
}

class _Metric extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  const _Metric({required this.label, required this.value, required this.icon});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(14)),
        child: Column(children: [Icon(icon, size: 22), const SizedBox(height: 5), Text('$value', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)), Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10))]),
      );
}

class _QuickAction {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  const _QuickAction(this.icon, this.title, this.onTap);
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ActionCard({required this.icon, required this.title, required this.subtitle, required this.onTap});
  @override
  Widget build(BuildContext context) => Card(child: ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5), leading: CircleAvatar(child: Icon(icon)), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text(subtitle), trailing: const Icon(Icons.chevron_left), onTap: onTap));
}
