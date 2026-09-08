import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import 'live_tracking_map_page.dart';

class DeliveryTracking extends StatelessWidget {
  final String orderId;
  const DeliveryTracking({super.key, required this.orderId});

  @override
  Widget build(BuildContext context) {
    final service = FirestoreService();
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('تتبع الطلب', style: TextStyle(fontWeight: FontWeight.w900))),
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: service.order(orderId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _MessageState(icon: Icons.error_outline, message: 'تعذر تحميل بيانات الطلب.');
            }
            if (!snapshot.hasData || !snapshot.data!.exists) {
              return const _MessageState(icon: Icons.receipt_long_outlined, message: 'الطلب غير موجود.');
            }

            final data = snapshot.data!.data()!;
            final ownerUid = (data['customerId'] ?? '').toString();
            if (currentUid == null || ownerUid != currentUid) {
              return const _MessageState(icon: Icons.lock_outline, message: 'لا تملك صلاحية الوصول لهذا الطلب.');
            }

            final status = (data['status'] ?? 'pending').toString();
            final deliveryStatus = (data['deliveryStatus'] ?? 'awaiting_assignment').toString();
            final stages = _deliveryStages(deliveryStatus);
            final total = data['total'] ?? 0;
            final currency = (data['currency'] ?? 'YER').toString();
            final payment = _paymentLabel((data['paymentMethod'] ?? '').toString());
            final items = data['items'] is List ? data['items'] as List : const [];
            final address = (data['address'] ?? '').toString();
            final location = data['deliveryLocation'];

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('الطلب #$orderId', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(_orderStatusLabel(status), style: TextStyle(fontWeight: FontWeight.w800, color: _statusColor(context, status))),
                const SizedBox(height: 16),
                Card(
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _InfoRow(icon: Icons.shopping_bag_outlined, title: 'الأصناف', value: '${items.length}'),
                        _InfoRow(icon: Icons.payments_outlined, title: 'الإجمالي', value: '$total $currency'),
                        _InfoRow(icon: Icons.account_balance_wallet_outlined, title: 'طريقة الدفع', value: payment),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  elevation: 0,
                  child: ListTile(
                    leading: const Icon(Icons.map_outlined),
                    title: const Text('الخريطة والتتبع الحي', style: TextStyle(fontWeight: FontWeight.w900)),
                    subtitle: Text(location is GeoPoint ? 'عرض آخر موقع مسجل للمندوب وتحديثاته المباشرة.' : 'سيظهر التتبع تلقائياً عند بدء تسجيل موقع المندوب.'),
                    trailing: const Icon(Icons.arrow_back_ios_new, size: 16),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LiveTrackingMapPage(orderId: orderId))),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('حالة التوصيل', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Card(
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    child: Column(
                      children: List.generate(stages.length, (i) {
                        final stage = stages[i];
                        final active = stage['active'] as bool;
                        final current = stage['current'] as bool;
                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 17,
                            child: Icon(current ? Icons.local_shipping : Icons.check, size: 18),
                          ),
                          title: Text(stage['label'] as String, style: TextStyle(fontWeight: active ? FontWeight.w800 : FontWeight.w500)),
                          trailing: Icon(active ? Icons.check_circle : Icons.radio_button_unchecked, color: active ? Colors.green : Colors.grey),
                        );
                      }),
                    ),
                  ),
                ),
                if (address.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Card(
                    elevation: 0,
                    child: ListTile(
                      leading: const Icon(Icons.location_on_outlined),
                      title: const Text('عنوان التوصيل', style: TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(address),
                    ),
                  ),
                ],
                if (location is GeoPoint) ...[
                  const SizedBox(height: 12),
                  Card(
                    elevation: 0,
                    child: ListTile(
                      leading: const Icon(Icons.my_location_outlined),
                      title: const Text('آخر موقع مسجل للمندوب', style: TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text('خط العرض: ${location.latitude}\nخط الطول: ${location.longitude}'),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                const Card(
                  elevation: 0,
                  child: ListTile(
                    leading: Icon(Icons.sync),
                    title: Text('تحديث فوري'),
                    subtitle: Text('هذه الشاشة تستقبل تحديثات Firestore مباشرة عند تغير حالة الطلب أو موقع التوصيل.'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
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
