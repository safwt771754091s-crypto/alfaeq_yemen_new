import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../services/supabase_service.dart';
import 'live_tracking_map_page.dart';

class DeliveryTracking extends StatelessWidget {
  final String orderId;
  const DeliveryTracking({super.key, required this.orderId});

  @override
  Widget build(BuildContext context) {
    final currentUid = SupabaseService.client.auth.currentUser?.uid;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('تتبع الطلب', style: TextStyle(fontWeight: FontWeight.w900))),
        body: currentUid == null
            ? const _MessageState(icon: Icons.lock_outline, message: 'يجب تسجيل الدخول أولاً.')
            : !SupabaseService.isInitialized
                ? const _MessageState(icon: Icons.cloud_off_outlined, message: 'خدمة المنصة غير متاحة حالياً.')
                : StreamBuilder<List<Map<String, dynamic>>>(
                    stream: SupabaseService.client.from('orders').stream(primaryKey: ['id']).eq('id', orderId).limit(1),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                      if (snapshot.hasError) return const _MessageState(icon: Icons.error_outline, message: 'تعذر تحميل بيانات الطلب.');
                      final rows = snapshot.data ?? const <Map<String, dynamic>>[];
                      if (rows.isEmpty) return const _MessageState(icon: Icons.receipt_long_outlined, message: 'الطلب غير موجود أو لا تملك صلاحية الوصول إليه.');
                      final data = rows.first;
                      if ((data['customer_id'] ?? '').toString() != currentUid) return const _MessageState(icon: Icons.lock_outline, message: 'لا تملك صلاحية الوصول لهذا الطلب.');
                      return _OrderTrackingView(orderId: orderId, data: data);
                    },
                  ),
      ),
    );
  }
}

class _OrderTrackingView extends StatelessWidget {
  final String orderId;
  final Map<String, dynamic> data;
  const _OrderTrackingView({required this.orderId, required this.data});

  LatLng? _point(dynamic raw) {
    if (raw is Map) {
      final lat = raw['latitude'];
      final lng = raw['longitude'];
      if (lat is num && lng is num) return LatLng(lat.toDouble(), lng.toDouble());
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final status = (data['status'] ?? 'pending').toString();
    final deliveryStatus = (data['delivery_status'] ?? 'awaiting_assignment').toString();
    final stages = _deliveryStages(deliveryStatus);
    final total = data['total'] ?? 0;
    final currency = (data['currency'] ?? 'YER').toString();
    final payment = _paymentLabel((data['payment_method'] ?? '').toString());
    final items = data['items'] is List ? data['items'] as List : const [];
    final address = (data['address'] ?? '').toString();
    final location = _point(data['delivery_location']);
    final driverLocation = _point(data['driver_location']);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('الطلب #' + orderId, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Text(_orderStatusLabel(status), style: TextStyle(fontWeight: FontWeight.w800, color: _statusColor(context, status))),
        const SizedBox(height: 16),
        Card(elevation: 0, child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            _InfoRow(icon: Icons.shopping_bag_outlined, title: 'الأصناف', value: items.length.toString()),
            _InfoRow(icon: Icons.payments_outlined, title: 'الإجمالي', value: total.toString() + ' ' + currency),
            _InfoRow(icon: Icons.account_balance_wallet_outlined, title: 'طريقة الدفع', value: payment),
          ]),
        )),
        const SizedBox(height: 12),
        Card(elevation: 0, child: ListTile(
          leading: const Icon(Icons.map_outlined),
          title: const Text('الخريطة والتتبع الحي', style: TextStyle(fontWeight: FontWeight.w900)),
          subtitle: Text(driverLocation != null ? 'موقع المندوب يتحدث مباشرة.' : location != null ? 'تم تحديد موقع التسليم.' : 'سيظهر التتبع عند بدء المندوب.'),
          trailing: const Icon(Icons.arrow_back_ios_new, size: 16),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LiveTrackingMapPage(orderId: orderId))),
        )),
        const SizedBox(height: 12),
        const Text('حالة التوصيل', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Card(elevation: 0, child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Column(children: List.generate(stages.length, (i) {
            final stage = stages[i];
            final active = stage['active'] as bool;
            final current = stage['current'] as bool;
            return ListTile(
              dense: true,
              leading: CircleAvatar(radius: 17, child: Icon(current ? Icons.local_shipping : Icons.check, size: 18)),
              title: Text(stage['label'] as String, style: TextStyle(fontWeight: active ? FontWeight.w800 : FontWeight.w500)),
              trailing: Icon(active ? Icons.check_circle : Icons.radio_button_unchecked, color: active ? Colors.green : Colors.grey),
            );
          })),
        )),
        if (address.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(elevation: 0, child: ListTile(leading: const Icon(Icons.location_on_outlined), title: const Text('عنوان التوصيل', style: TextStyle(fontWeight: FontWeight.w800)), subtitle: Text(address))),
        ],
        if (location != null) ...[
          const SizedBox(height: 12),
          Card(elevation: 0, child: ListTile(leading: const Icon(Icons.flag_outlined), title: const Text('موقع التسليم'), subtitle: Text('خط العرض: ' + location.latitude.toString() + '\nخط الطول: ' + location.longitude.toString()))),
        ],
        if (driverLocation != null) ...[
          const SizedBox(height: 12),
          Card(elevation: 0, child: ListTile(leading: const Icon(Icons.delivery_dining), title: const Text('آخر موقع للمندوب'), subtitle: Text('خط العرض: ' + driverLocation.latitude.toString() + '\nخط الطول: ' + driverLocation.longitude.toString()))),
        ],
        const SizedBox(height: 12),
        const Card(elevation: 0, child: ListTile(leading: Icon(Icons.sync), title: Text('تحديث فوري'), subtitle: Text('تستقبل الشاشة تحديثات الطلب وموقع المندوب مباشرة من Supabase.'))),
      ],
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
