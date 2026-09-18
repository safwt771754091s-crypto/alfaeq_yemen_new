import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class LiveTrackingMapPage extends StatelessWidget {
  final String orderId;
  const LiveTrackingMapPage({super.key, required this.orderId});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('الخريطة والتتبع الحي')),
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('orders').doc(orderId).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
              return const Center(child: Text('تعذر تحميل موقع الطلب.'));
            }
            final data = snapshot.data!.data()!;
            if (uid == null || data['customerId'] != uid) {
              return const Center(child: Text('لا تملك صلاحية عرض هذا التتبع.'));
            }
            final customerLocation = data['deliveryLocation'];
            final driverLocation = data['driverLocation'];
            if (customerLocation is! GeoPoint && driverLocation is! GeoPoint) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('لم يبدأ التتبع بعد. ستظهر الخريطة عند تحديد موقع التسليم وبدء المندوب للتتبع الحي.'),
                ),
              );
            }

            final primary = driverLocation is GeoPoint ? driverLocation : customerLocation as GeoPoint;
            final point = LatLng(primary.latitude, primary.longitude);
            final status = (data['deliveryStatus'] ?? 'awaiting_assignment').toString();
            final markers = <Marker>[];
            if (customerLocation is GeoPoint) {
              markers.add(Marker(
                point: LatLng(customerLocation.latitude, customerLocation.longitude),
                width: 70,
                height: 70,
                child: const Icon(Icons.location_on, size: 50),
              ));
            }
            if (driverLocation is GeoPoint) {
              markers.add(Marker(
                point: LatLng(driverLocation.latitude, driverLocation.longitude),
                width: 70,
                height: 70,
                child: const Icon(Icons.delivery_dining, size: 50),
              ));
            }
            return Stack(
              children: [
                FlutterMap(
                  options: MapOptions(initialCenter: point, initialZoom: 15),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.alfaeq.alfaeq_yemen',
                    ),
                    MarkerLayer(markers: markers),
                    const RichAttributionWidget(
                      attributions: [TextSourceAttribution('OpenStreetMap contributors')],
                    ),
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
                      child: Row(
                        children: [
                          const Icon(Icons.my_location),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'تتبع حي • ${_statusLabel(status)}\n' + (driverLocation is GeoPoint ? 'موقع المندوب: ${driverLocation.latitude.toStringAsFixed(5)}, ${driverLocation.longitude.toStringAsFixed(5)}' : 'تم تحديد موقع التسليم بانتظار المندوب.'),
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static String _statusLabel(String status) => switch (status) {
        'awaiting_assignment' => 'بانتظار المندوب',
        'assigned' => 'تم تعيين المندوب',
        'picked_up' => 'تم استلام الطلب',
        'out_for_delivery' => 'في الطريق إليك',
        'delivered' => 'تم التسليم',
        'failed' => 'تعذر التوصيل',
        _ => status,
      };
}
