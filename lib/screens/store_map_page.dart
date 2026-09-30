import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class StoreMapPage extends StatelessWidget {
  final List<Map<String, dynamic>> stores;
  const StoreMapPage({super.key, required this.stores});

  @override
  Widget build(BuildContext context) {
    final points = <_StorePoint>[];
    for (final store in stores) {
      final lat = (store['latitude'] as num?)?.toDouble();
      final lng = (store['longitude'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        points.add(_StorePoint(name: store['name']?.toString() ?? 'متجر', point: LatLng(lat, lng)));
      }
    }
    final center = points.isNotEmpty ? points.first.point : const LatLng(15.3694, 44.1910);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('خريطة المتاجر')),
        body: Stack(
          children: [
            FlutterMap(
              options: MapOptions(initialCenter: center, initialZoom: points.isNotEmpty ? 12 : 6),
              children: [
                TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.alfaeq.alfaeq_yemen'),
                MarkerLayer(markers: points.map((store) => Marker(
                  point: store.point, width: 70, height: 70,
                  child: GestureDetector(onTap: () => _showStore(context, store), child: const Icon(Icons.storefront, size: 42)),
                )).toList()),
                const RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors')]),
              ],
            ),
            Positioned(top: 12, right: 12, left: 12, child: Card(child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(points.isEmpty ? 'لا توجد متاجر لها إحداثيات حتى الآن.' : 'المتاجر المحددة على الخريطة: \${points.length}', style: const TextStyle(fontWeight: FontWeight.w900)),
            ))),
          ],
        ),
      ),
    );
  }

  void _showStore(BuildContext context, _StorePoint store) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => Directionality(textDirection: TextDirection.rtl, child: SafeArea(child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(store.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text('الإحداثيات: \${store.point.latitude.toStringAsFixed(6)}, \${store.point.longitude.toStringAsFixed(6)}'),
        ]),
      ))),
    );
  }
}

class _StorePoint {
  final String name;
  final LatLng point;
  const _StorePoint({required this.name, required this.point});
}