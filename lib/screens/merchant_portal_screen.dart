import 'package:flutter/material.dart';

class MerchantPortalScreen extends StatelessWidget {
  const MerchantPortalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('بوابة التجار')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            Card(child: ListTile(leading: Icon(Icons.store), title: Text('تسجيل متجر جديد'), subtitle: Text('بيانات المتجر والمالك والموافقة الإدارية'))),
            Card(child: ListTile(leading: Icon(Icons.inventory_2), title: Text('إدارة الأصناف'), subtitle: Text('إضافة المنتجات والأسعار والمخزون والصور'))),
            Card(child: ListTile(leading: Icon(Icons.receipt_long), title: Text('طلبات متجرك'), subtitle: Text('متابعة الطلبات وتحديث حالتها'))),
            SizedBox(height: 12),
            Text('هذه البوابة هي نقطة الدخول المخصصة للتاجر، وسيتم ربط عملياتها مباشرة ببيانات Firebase بعد تسجيل دخول التاجر.', style: TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}
