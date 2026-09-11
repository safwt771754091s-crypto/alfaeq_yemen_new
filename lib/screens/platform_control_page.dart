import 'package:flutter/material.dart';

/// مركز تشغيل المنصة.
///
/// هذه الصفحة هي نقطة الدخول لإدارة المنصة، مع الحفاظ على الشاشات
/// المتخصصة الحالية وعدم استبدالها أو حذفها.
class PlatformControlPage extends StatelessWidget {
  const PlatformControlPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('مركز تشغيل المنصة')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            Card(
              child: ListTile(
                leading: Icon(Icons.settings_suggest_outlined),
                title: Text('مركز التحكم'),
                subtitle: Text('واجهة مركزية لإدارة الأقسام والدفع والتجار.'),
              ),
            ),
            SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: Icon(Icons.category_outlined),
                title: Text('الأقسام'),
                subtitle: Text('إدارة الأقسام الديناميكية ستعمل من هذا المركز.'),
              ),
            ),
            Card(
              child: ListTile(
                leading: Icon(Icons.account_balance_wallet_outlined),
                title: Text('الدفع'),
                subtitle: Text('إدارة قنوات الدفع وحالة إعدادها.'),
              ),
            ),
            Card(
              child: ListTile(
                leading: Icon(Icons.storefront_outlined),
                title: Text('التجار'),
                subtitle: Text('إدارة التجار والمتاجر مع الحفاظ على الملكية والصلاحيات.'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
