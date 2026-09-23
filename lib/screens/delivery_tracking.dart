import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../services/supabase_service.dart';
import 'live_tracking_map_page.dart';

class _SupabaseOrderTracking extends StatelessWidget {
  final String orderId; final String uid;
  const _SupabaseOrderTracking({required this.orderId, required this.uid});
  @override Widget build(BuildContext context) {
    final stream = FirestoreService(preferSupabase: true).supabaseOrderStream(orderId);
    return StreamBuilder<List<Map<String,dynamic>>>(stream: stream, builder: (context,snapshot) {
      if (snapshot.hasError) return const _MessageState(icon: Icons.error_outline, message: 'تعذر تحميل بيانات الطلب من الخادم.');
      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
      final rows = snapshot.data ?? const <Map<String,dynamic>>[];
      if (rows.isEmpty) return const _MessageState(icon: Icons.receipt_long_outlined, message: 'الطلب غير موجود.');
      final data = rows.first;
      if ((data['customer_id'] ?? '').toString() != uid) return const _MessageState(icon: Icons.lock_outline, message: 'لا تملك صلاحية الوصول لهذا الطلب.');
      final status = (data['status'] ?? 'pending').toString();
      final deliveryStatus = (data['delivery_status'] ?? 'awaiting_assignment').toString();
      final stages = DeliveryTracking._deliveryStages(deliveryStatus);
      final rawItems = data['items']; final itemCount = rawItems is List ? rawItems.length : 0;
      final location = data['driver_location'];
      return ListView(padding: const EdgeInsets.all(16), children: [
        Text('الطلب #$orderId', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Text(DeliveryTracking._orderStatusLabel(status), style: TextStyle(fontWeight: FontWeight.w800, color: DeliveryTracking._statusColor(context, status))),
        const SizedBox(height: 16),
        Card(elevation: 0, child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
          _InfoRow(icon: Icons.shopping_bag_outlined, title: 'الأصناف', value: '$itemCount'),
          _InfoRow(icon: Icons.payments_outlined, title: 'الإجمالي', value: '${data['total'] ?? 0} ${data['currency'] ?? 'YER'}'),
          _InfoRow(icon: Icons.account_balance_wallet_outlined, title: 'طريقة الدفع', value: DeliveryTracking._paymentLabel((data['payment_method'] ?? '').toString())),
        ]))),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                for (final stage in stages)
                  ListTile(
                    dense: true,
                    title: Text(stage['label'] as String),
                    trailing: Icon(
                      stage['active'] == true
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if ((data['address'] ?? '').toString().isNotEmpty) ...[const SizedBox(height: 12), Card(elevation: 0, child: ListTile(leading: const Icon(Icons.location_on_outlined), title: const Text('عنوان التوصيل'), subtitle: Text((data['address'] ?? '').toString())))],
        if (location is Map && location['latitude'] is num && location['longitude'] is num) ...[const SizedBox(height: 12), Card(elevation: 0, child: ListTile(leading: const Icon(Icons.my_location_outlined), title: const Text('آخر موقع للمندوب'), subtitle: Text('خط العرض: ${location['latitude']}\nخط الطول: ${location['longitude']}')))],
        const SizedBox(height: 12),
        const Card(elevation: 0, child: ListTile(leading: Icon(Icons.sync), title: Text('تحديث فوري'), subtitle: Text('بيانات الطلب والتتبع تُقرأ مباشرة من Supabase.'))),
      ]);
    });
  }
}
class DeliveryTracking extends StatelessWidget {
  final String orderId;
  const DeliveryTracking({super.key, required this.orderId});

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    return Directionality(textDirection: TextDirection.rtl, child: Scaffold(
      appBar: AppBar(title: const Text('تتبع الطلب', style: TextStyle(fontWeight: FontWeight.w900))),
      body: currentUid == null
          ? const Center(child: Text('يجب تسجيل الدخول لعرض التتبع.'))
          : SupabaseService.isInitialized
              ? _SupabaseOrderTracking(orderId: orderId, uid: currentUid)
              : const Center(child: Text('قاعدة بيانات الإنتاج غير متاحة حالياً.')),
    ));
  }

  static List<Map<String, dynamic>> _deliveryStages(String status) {
    const names = <String, String>{
      'awaiting_assignment': 'بانتظار تعيين مندوب',
      'assigned': 'تم تعيين المندوب',
      'picked_up': 'استلم المندوب الطلب',
      'on_the_way': 'الطلب في الطريق',
      'in_transit': 'الطلب قيد التوصيل',
      'delivered': 'تم التسليم',
    };
    const order = ['awaiting_assignment', 'assigned', 'picked_up', 'on_the_way', 'in_transit', 'delivered'];
    var currentIndex = order.indexOf(status);
    if (currentIndex < 0) currentIndex = 0;
    return [
      for (var i = 0; i < order.length; i++)
        {
          'label': names[order[i]]!,
          'active': i <= currentIndex && status != 'cancelled',
          'current': order[i] == status,
        },
    ];
  }

  static String _orderStatusLabel(String value) => switch (value) {
        'pending' => 'قيد المراجعة',
        'confirmed' => 'تم تأكيد الطلب',
        'preparing' => 'قيد تجهيز الطلب',
        'shipped' => 'تم شحن الطلب',
        'delivered' => 'تم التسليم',
        'cancelled' => 'تم إلغاء الطلب',
        _ => value,
      };

  static Color _statusColor(BuildContext context, String value) => switch (value) {
        'cancelled' => Colors.red,
        'delivered' => Colors.green,
        _ => Theme.of(context).colorScheme.primary,
      };

  static String _paymentLabel(String value) => switch (value) {
        'cash_on_delivery' => 'الدفع عند الاستلام',
        'al_kuraimi' => 'تحويل الكريمي',
        'cash_wallet' => 'محفظة كاش',
        'jeeb_wallet' => 'محفظة جيب',
        _ => value.isEmpty ? 'غير محددة' : value,
      };
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  const _InfoRow({required this.icon, required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
    );
  }
}

class _MessageState extends StatelessWidget {
  final IconData icon;
  final String message;
  const _MessageState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 58),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
