import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/auth_service.dart';

class DriverFleetMapPage extends StatelessWidget {
  const DriverFleetMapPage({super.key});

  Future<bool> _allowed() async {
    final auth = AuthService();
    final role = await auth.role();
    if (role == 'owner' || role == 'admin' || role == 'developer') return true;
    final claims = await auth.claims();
    final permissions = claims['permissions'];
    return permissions is List && permissions.contains('manageDispatch');
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('خريطة المندوبين', style: TextStyle(fontWeight: FontWeight.w900)),
        ),
        body: FutureBuilder<bool>(
          future: _allowed(),
          builder: (context, access) {
            if (access.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (access.data != true) {
              return const Center(child: Text('لا تملك صلاحية متابعة المندوبين.'));
            }
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('drivers').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('تعذر تحميل المندوبين.\n${snapshot.error}')));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final drivers = snapshot.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                final points = <_DriverPoint>[];
                for (final doc in drivers) {
                  final data = doc.data();
                  final location = data['currentLocation'];
                  if (location is GeoPoint) {
                    points.add(_DriverPoint(
                      id: doc.id,
                      point: LatLng(location.latitude, location.longitude),
                      online: data['isOnline'] == true,
                      approved: data['approved'] == true,
                      activeOrders: (data['activeOrderCount'] as num?)?.toInt() ?? 0,
                    ));
                  }
                }

                final center = points.isNotEmpty ? points.first.point : const LatLng(15.3694, 44.1910);
                return Stack(
                  children: [
                    FlutterMap(
                      options: MapOptions(initialCenter: center, initialZoom: points.isNotEmpty ? 13 : 6),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.alfaeq.alfaeq_yemen',
                        ),
                        MarkerLayer(
                          markers: points.map((driver) => Marker(
                            point: driver.point,
                            width: 90,
                            height: 72,
                            child: GestureDetector(
                              onTap: () => _showDriver(context, driver),
                              child: Column(
                                children: [
                                  Icon(Icons.delivery_dining, size: 40, color: driver.online ? Colors.green : Colors.grey),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                                    child: Text(driver.online ? 'متصل' : 'غير متصل', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
                                  ),
                                ],
                              ),
                            ),
                          )).toList(),
                        ),
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
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              const Icon(Icons.radar_outlined),
                              const SizedBox(width: 8),
                              Expanded(child: Text('تتبع مباشر للمندوبين • ${points.length} موقع مسجل', style: const TextStyle(fontWeight: FontWeight.w900))),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (points.isEmpty)
                      const Center(
                        child: Card(
                          child: Padding(
                            padding: EdgeInsets.all(18),
                            child: Text('لا يوجد مندوب لديه موقع مسجل حالياً.'),
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  void _showDriver(BuildContext context, _DriverPoint driver) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('المندوب ${driver.id.substring(0, driver.id.length > 8 ? 8 : driver.id.length)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text(driver.online ? 'متصل والتتبع الحي يعمل' : 'غير متصل — آخر موقع مسجل'),
                Text('الطلبات النشطة: ${driver.activeOrders}'),
                Text('الإحداثيات: ${driver.point.latitude.toStringAsFixed(5)}, ${driver.point.longitude.toStringAsFixed(5)}'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DriverPoint {
  final String id;
  final LatLng point;
  final bool online;
  final bool approved;
  final int activeOrders;
  const _DriverPoint({required this.id, required this.point, required this.online, required this.approved, required this.activeOrders});
}
