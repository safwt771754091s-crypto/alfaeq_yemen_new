import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'delivery_tracking.dart';

class MyOrdersPage extends StatelessWidget {
  const MyOrdersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('طلباتي', style: TextStyle(fontWeight: FontWeight.w900))),
        body: user == null
            ? const Center(child: Text('يجب تسجيل الدخول لعرض طلباتك.'))
            : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance.collection('orders').where('customerId', isEqualTo: user.uid).limit(50).snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('تعذر تحميل الطلبات.\n${snapshot.error}', textAlign: TextAlign.center)));
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

                  final orders = [...(snapshot.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[])]
                    ..sort((a, b) => _timestamp(b.data()['createdAt']).compareTo(_timestamp(a.data()['createdAt'])));

                  if (orders.isEmpty) {
                    return const Center(child: Padding(padding: EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.receipt_long_outlined, size: 64),
                      SizedBox(height: 12),
                      Text('لا توجد طلبات بعد', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                      SizedBox(height: 6),
                      Text('ستظهر طلباتك هنا مع التحديث الفوري لحالتها.'),
                    ])));
                  }

                  return RefreshIndicator(
                    onRefresh: () async {},
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: orders.length,
                      separatorBuilder: (_, index) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final doc = orders[index];
                        final data = doc.data();
                        final status = (data['status'] ?? 'pending').toString();
                        final deliveryStatus = (data['deliveryStatus'] ?? 'awaiting_assignment').toString();
                        final total = data['total'];
                        final currency = (data['currency'] ?? 'YER').toString();
                        final itemCount = data['items'] is List ? (data['items'] as List).length : 0;

                        return Card(
                          elevation: 0,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DeliveryTracking(orderId: doc.id))),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  const Icon(Icons.receipt_long_outlined),
                                  const SizedBox(width: 10),
                                  Expanded(child: Text('الطلب #${doc.id.substring(0, doc.id.length > 8 ? 8 : doc.id.length)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17))),
                                  _StatusChip(label: _orderLabel(status), status: status),
                                ]),
                                const SizedBox(height: 12),
                                Row(children: [
                                  Expanded(child: Text('$itemCount ${itemCount == 1 ? 'صنف' : 'أصناف'}')),
                                  Text('${total ?? 0} $currency', style: const TextStyle(fontWeight: FontWeight.w900)),
                                ]),
                                const SizedBox(height: 8),
                                Row(children: [
                                  const Icon(Icons.local_shipping_outlined, size: 18),
                                  const SizedBox(width: 6),
                                  Expanded(child: Text(_deliveryLabel(deliveryStatus))),
                                  const Icon(Icons.chevron_left),
                                ]),
                              ]),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }

  static DateTime _timestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static String _orderLabel(String value) => switch (value) {
        'pending' => 'قيد المراجعة',
        'confirmed' => 'تم التأكيد',
        'preparing' => 'قيد التجهيز',
        'shipped' => 'تم الشحن',
        'delivered' => 'تم التسليم',
        'cancelled' => 'ملغي',
        _ => value,
      };

  static String _deliveryLabel(String value) => switch (value) {
        'awaiting_assignment' => 'بانتظار تعيين مندوب',
        'assigned' => 'تم تعيين المندوب',
        'picked_up' => 'استلم المندوب الطلب',
        'on_the_way' => 'الطلب في الطريق',
        'in_transit' => 'الطلب قيد التوصيل',
        'delivered' => 'تم التسليم',
        'cancelled' => 'تم إلغاء التوصيل',
        _ => value,
      };
}

class _StatusChip extends StatelessWidget {
  final String label;
  final String status;
  const _StatusChip({required this.label, required this.status});

  @override
  Widget build(BuildContext context) {
    final cancelled = status == 'cancelled';
    final delivered = status == 'delivered';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: cancelled
            ? Colors.red.withValues(alpha: .10)
            : delivered
                ? Colors.green.withValues(alpha: .10)
                : Theme.of(context).colorScheme.primary.withValues(alpha: .10),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}
