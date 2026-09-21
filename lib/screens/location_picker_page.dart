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

  @override
  void initState() {
    super.initState();
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _selected = LatLng(widget.initialLatitude!, widget.initialLongitude!);
    } else {
      // Initiate the browser/device permission prompt as soon as the picker opens.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _useDeviceLocation();
      });
    }
  }

  Future<void> _useDeviceLocation() async {
    if (!mounted || _busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      final position = await LocationService.requireCurrentPosition();
      if (!mounted) return;
      final point = LatLng(position.latitude, position.longitude);
      setState(() => _selected = point);
      _mapController.move(point, 16);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'تعذر تحديد موقعك تلقائيًا. تحقق من إذن الموقع وفعّل GPS، أو اختر موقعك بالنقر على الخريطة.');
      }
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
                const Text('يجري تحديد موقعك تلقائيًا. يمكنك أيضًا تحريك الخريطة والنقر لاختيار موقع آخر.', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: OutlinedButton.icon(onPressed: _busy ? null : _useDeviceLocation, icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.my_location), label: const Text('إعادة تحديد موقعي'))),
                  const SizedBox(width: 8),
                  Expanded(child: FilledButton.icon(onPressed: point == null ? null : () => Navigator.pop(context, point), icon: const Icon(Icons.check_circle_outline), label: const Text('تأكيد الموقع'))),
                ]),
                if (_busy) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
                if (_error != null) ...[const SizedBox(height: 8), Text(_error!, style: const TextStyle(fontWeight: FontWeight.w700))],
                if (point != null) ...[const SizedBox(height: 6), Text('الإحداثيات: ${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}', textDirection: TextDirection.ltr, textAlign: TextAlign.center)],
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
