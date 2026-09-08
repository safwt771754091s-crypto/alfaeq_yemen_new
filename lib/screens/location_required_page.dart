import 'package:flutter/material.dart';

import '../services/location_service.dart';

class LocationRequiredPage extends StatefulWidget {
  final Future<void> Function(double latitude, double longitude) onLocationReady;
  const LocationRequiredPage({super.key, required this.onLocationReady});

  @override
  State<LocationRequiredPage> createState() => _LocationRequiredPageState();
}

class _LocationRequiredPageState extends State<LocationRequiredPage> {
  bool _busy = false;
  String? _error;

  Future<void> _enable() async {
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

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.location_on_rounded, size: 72),
                  const SizedBox(height: 18),
                  const Text('الموقع مطلوب للمتابعة', textAlign: TextAlign.center, style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 12),
                  const Text('نستخدم موقعك لتحديد منطقتك، تحسين المتاجر والخدمات القريبة، وحساب التوصيل وتوزيع الطلبات بدقة.', textAlign: TextAlign.center, style: TextStyle(height: 1.5)),
                  const SizedBox(height: 18),
                  if (_error != null) Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  FilledButton.icon(onPressed: _busy ? null : _enable, icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.my_location), label: Text(_busy ? 'جارٍ تحديد موقعك...' : 'تفعيل الموقع والمتابعة')),
                ]),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
