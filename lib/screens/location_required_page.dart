import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../services/location_service.dart';
import 'location_picker_page.dart';

class LocationRequiredPage extends StatefulWidget {
  final Future<void> Function(double latitude, double longitude) onLocationReady;
  const LocationRequiredPage({super.key, required this.onLocationReady});

  @override
  State<LocationRequiredPage> createState() => _LocationRequiredPageState();
}

class _LocationRequiredPageState extends State<LocationRequiredPage> {
  bool _busy = false;
  String? _error;

  Future<void> _save(LatLng point) async {
    setState(() { _busy = true; _error = null; });
    try {
      await widget.onLocationReady(point.latitude, point.longitude);
    } catch (_) {
      setState(() => _error = 'تعذر حفظ موقع الحساب. حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _useDevice() async {
    setState(() { _busy = true; _error = null; });
    try {
      final position = await LocationService.requireCurrentPosition();
      await widget.onLocationReady(position.latitude, position.longitude);
    } catch (_) {
      setState(() => _error = 'يجب تفعيل خدمة الموقع ومنح الفائق يمن صلاحية الوصول إلى موقعك للمتابعة.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openMap() async {
    final point = await Navigator.of(context).push<LatLng>(MaterialPageRoute(builder: (_) => const LocationPickerPage(title: 'تحديد موقع الحساب')));
    if (point != null) await _save(point);
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      body: SafeArea(child: Center(child: Padding(padding: const EdgeInsets.all(24), child: Card(elevation: 0, child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.location_on_rounded, size: 72),
        const SizedBox(height: 18),
        const Text('الموقع مطلوب للمتابعة', textAlign: TextAlign.center, style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        const Text('حدد موقعك على الخريطة أو استخدم موقع الهاتف. نحتاج الموقع لتحديد الخدمات القريبة وحساب التوصيل وتوزيع الطلبات.', textAlign: TextAlign.center, style: TextStyle(height: 1.5)),
        const SizedBox(height: 18),
        if (_error != null) Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _busy ? null : _useDevice, icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.my_location), label: Text(_busy ? 'جارٍ تحديد موقعك...' : 'استخدام موقع الهاتف'))),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _busy ? null : _openMap, icon: const Icon(Icons.map_outlined), label: const Text('تحديد الموقع على الخريطة'))),
      ]))))))));
}
