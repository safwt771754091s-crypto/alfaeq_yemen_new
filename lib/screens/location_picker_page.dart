import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/location_service.dart';

class LocationPickerPage extends StatefulWidget {
  final double? initialLatitude;
  final double? initialLongitude;
  final String title;
  const LocationPickerPage({super.key, this.initialLatitude, this.initialLongitude, this.title = 'تحديد موقعك'});

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  static const _fallback = LatLng(12.7855, 45.0187);
  final _mapController = MapController();
  LatLng? _selected;
  bool _busy = false;
  String? _error;

  LatLng get _center => _selected ?? LatLng(widget.initialLatitude ?? _fallback.latitude, widget.initialLongitude ?? _fallback.longitude);

  Future<void> _useDeviceLocation() async {
    setState(() { _busy = true; _error = null; });
    try {
      final position = await LocationService.requireCurrentPosition();
      final point = LatLng(position.latitude, position.longitude);
      setState(() => _selected = point);
      _mapController.move(point, 16);
    } catch (_) {
      setState(() => _error = 'تعذر تحديد موقعك. فعّل GPS واسمح بالوصول إلى الموقع ثم حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _select(LatLng point) => setState(() { _selected = point; _error = null; });

  @override
  Widget build(BuildContext context) {
    final point = _selected;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Card(elevation: 0, child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('حدد موقعك على الخريطة أو استخدم موقع الهاتف الحالي.', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: OutlinedButton.icon(onPressed: _busy ? null : _useDeviceLocation, icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.my_location), label: const Text('موقع الهاتف'))),
                  const SizedBox(width: 8),
                  Expanded(child: FilledButton.icon(onPressed: point == null ? null : () => Navigator.pop(context, point), icon: const Icon(Icons.check_circle_outline), label: const Text('تأكيد الموقع'))),
                ]),
                if (_error != null) ...[const SizedBox(height: 8), Text(_error!, style: const TextStyle(fontWeight: FontWeight.w700))],
              ]),
            )),
          ),
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _center,
                initialZoom: _selected == null && widget.initialLatitude == null ? 12 : 15,
                onTap: (_, latLng) => _select(latLng),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.alfaeq.alfaeq_yemen',
                ),
                if (point != null)
                  MarkerLayer(markers: [Marker(point: point, width: 52, height: 52, child: const Icon(Icons.location_on, size: 48))]),
                const RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors')]),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
