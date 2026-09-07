import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/firestore_service.dart';

class DeliveryTracking extends StatelessWidget {
  final String orderId;
  const DeliveryTracking({super.key, required this.orderId});

  @override
  Widget build(BuildContext context) {
    final service = FirestoreService();
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('تتبع التوصيل')),
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: service.order(orderId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (!snapshot.hasData || !snapshot.data!.exists) return const Center(child: Text('الطلب غير موجود'));
            final data = snapshot.data!.data()!;
            final status = (data['deliveryStatus'] ?? 'awaiting_assignment').toString();
            const stages = ['awaiting_assignment', 'assigned', 'picked_up', 'on_the_way', 'delivered'];
            final index = stages.indexOf(status);
            return ListView(padding: const EdgeInsets.all(20), children: [
              Text('الطلب #$orderId', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 20),
              ...List.generate(stages.length, (i) => ListTile(leading: CircleAvatar(child: Text('${i + 1}')), title: Text(_label(stages[i])), trailing: Icon(i <= index ? Icons.check_circle : Icons.radio_button_unchecked, color: i <= index ? Colors.green : Colors.grey))),
              const SizedBox(height: 20),
              if (data['deliveryLocation'] is GeoPoint) Text('آخر موقع مسجل: ${(data['deliveryLocation'] as GeoPoint).latitude}, ${(data['deliveryLocation'] as GeoPoint).longitude}'),
            ]);
          },
        ),
      ),
    );
  }

  static String _label(String value) => switch (value) {
    'awaiting_assignment' => 'بانتظار تعيين مندوب',
    'assigned' => 'تم تعيين المندوب',
    'picked_up' => 'تم استلام الطلب',
    'on_the_way' => 'الطلب في الطريق',
    'delivered' => 'تم التسليم',
    _ => value,
  };
}
