import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/supabase_service.dart';

class LiveTrackingMapPage extends StatelessWidget {
  final String orderId;
  const LiveTrackingMapPage({super.key, required this.orderId});

  @override
  Widget build(BuildContext context) {
    final uid = SupabaseService.client.auth.currentUser?.uid;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('الخريطة والتتبع الحي')),
        body: uid == null
            ? const Center(child: Text('يجب تسجيل الدخول لعرض التتبع.'))
            : SupabaseService.isInitialized
                ? _SupabaseTracking(orderId: orderId, uid: uid)
                : _FirebaseTracking(orderId: orderId, uid: uid),
      ),
    );
  }
}

class _SupabaseTracking extends StatelessWidget {
  final String orderId;
  final String uid;
  const _SupabaseTracking({required this.orderId, required this.uid});

  @override
  Widget build(BuildContext context) {
    final stream = SupabaseService.client.from('orders').stream(primaryKey: ['id']).eq('id', orderId).limit(1);
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text('تعذر الاتصال بخدمة التتبع. حاول تحديث الصفحة.'));
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        final rows = snapshot.data ?? const <Map<String, dynamic>>[];
        if (rows.isEmpty) return const Center(child: Text('الطلب غير موجود أو لا تملك صلاحية عرضه.'));
        final data = rows.first;
        if (data['customer_id'] != uid) return const Center(child: Text('لا تملك صلاحية عرض هذا التتبع.'));
        return _TrackingMap(data: data);
      },
    );
  }
}

class _FirebaseTracking extends StatelessWidget {
  final String orderId;
  final String uid;
  const _FirebaseTracking({required this.orderId, required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('orders').doc(orderId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) return const Center(child: Text('تعذر تحميل موقع الطلب.'));
        final data = snapshot.data!.data()!;
        if (data['customerId'] != uid) return const Center(child: Text('لا تملك صلاحية عرض هذا التتبع.'));
        return _TrackingMap(data: data);
      },
    );
  }
}

class _TrackingMap extends StatelessWidget {
  final Map<String, dynamic> data;
  const _TrackingMap({required this.data});

  LatLng? _point(dynamic raw) {
    if (raw is GeoPoint) return LatLng(raw.latitude, raw.longitude);
    if (raw is Map) {
      final lat = raw['latitude'];
      final lng = raw['longitude'];
      if (lat is num && lng is num) return LatLng(lat.toDouble(), lng.toDouble());
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final customer = _point(data['delivery_location'] ?? data['deliveryLocation']);
    final driver = _point(data['driver_location'] ?? data['driverLocation']);
    final primary = driver ?? customer;
    if (primary == null) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('لم يبدأ التتبع بعد. حدد موقع التسليم وانتظر بدء المندوب للتتبع الحي.'),
      ));
    }

    final status = (data['delivery_status'] ?? data['deliveryStatus'] ?? 'awaiting_assignment').toString();
    final markers = <Marker>[];
    if (customer != null) markers.add(Marker(point: customer, width: 64, height: 64, child: const Icon(Icons.location_on, size: 48)));
    if (driver != null) markers.add(Marker(point: driver, width: 64, height: 64, child: const Icon(Icons.delivery_dining, size: 48)));

    final trackingText = driver != null
        ? 'موقع المندوب: ' + driver.latitude.toStringAsFixed(5) + ', ' + driver.longitude.toStringAsFixed(5)
        : 'تم تحديد موقع التسليم بانتظار المندوب.';

    return Stack(children: [
      FlutterMap(
        options: MapOptions(initialCenter: primary, initialZoom: 15),
        children: [
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.alfaeq.alfaeq_yemen'),
          MarkerLayer(markers: markers),
          const RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors')]),
        ],
      ),
      Positioned(
        top: 12,
        right: 12,
        left: 12,
        child: Card(
          elevation: 3,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              const Icon(Icons.my_location),
              const SizedBox(width: 10),
              Expanded(child: Text(
                'تتبع حي • ' + _statusLabel(status) + '\n' + trackingText,
                style: const TextStyle(fontWeight: FontWeight.w800),
              )),
            ]),
          ),
        ),
      ),
    ]);
  }

  static String _statusLabel(String status) => switch (status) {
    'awaiting_assignment' => 'بانتظار المندوب',
    'assigned' => 'تم تعيين المندوب',
    'picked_up' => 'استلم المندوب',
    'on_the_way' => 'الطلب في الطريق',
    'in_transit' => 'الطلب قيد التوصيل',
    'delivered' => 'تم التسليم',
    'cancelled' => 'تم إلغاء التوصيل',
    _ => status,
  };
}
