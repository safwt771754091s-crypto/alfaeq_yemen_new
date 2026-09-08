import 'package:cloud_firestore/cloud_firestore.dart';
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

  String _saveError(Object error) {
    if (error is FirebaseException) {
      if (error.code == 'permission-denied') {
        return 'تم تحديد الموقع، لكن Firebase رفض حفظه. سأحتاج إصلاح صلاحيات قاعدة البيانات قبل المتابعة.';
      }
      if (error.code == 'unavailable') {
        return 'تم تحديد الموقع، لكن قاعدة البيانات غير متاحة الآن. تحقق من الإنترنت وحاول مرة أخرى.';
      }
    }
    return 'تعذر حفظ الموقع في قاعدة بيانات الفائق يمن. حاول مرة أخرى.';
  }

  Future<void> _save(LatLng point) async {
    setState(() { _busy = true; _error = null; });
    try {
      await widget.onLocationReady(point.latitude, point.longitude);
    } catch (error) {
      if (mounted) setState(() => _error = _saveError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _useDevice() async {
    setState(() { _busy = true; _error = null; });
    try {
      final position = await LocationService.requireCurrentPosition();
      await widget.onLocationReady(position.latitude, position.longitude);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is FirebaseException
              ? _saveError(error)
              : 'تعذر الوصول إلى موقع الهاتف. اسمح للموقع من إعدادات المتصفح ثم حاول مرة أخرى، أو حدد موقعك يدويًا على الخريطة.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openMap() async {
    final point = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(builder: (_) => const LocationPickerPage(title: 'تحديد موقع الحساب')),
    );
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
        const Text('حدد موقعك على الخريطة أو استخدم موقع الهاتف. الموقع الحقيقي يُحفظ في Firebase لاستخدام الخدمات القريبة والتوصيل وتوزيع الطلبات.', textAlign: TextAlign.center, style: TextStyle(height: 1.5)),
        const SizedBox(height: 18),
        if (_error != null) Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Theme.of(context).colorScheme.errorContainer, borderRadius: BorderRadius.circular(12)), child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onErrorContainer))),
        if (_error != null) const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _busy ? null : _useDevice, icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.my_location), label: Text(_busy ? 'جارٍ الحفظ...' : 'استخدام موقع الهاتف'))),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _busy ? null : _openMap, icon: const Icon(Icons.map_outlined), label: const Text('تحديد الموقع على الخريطة'))),
      ]))))))));
}
