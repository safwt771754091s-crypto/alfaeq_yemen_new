import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Distance and travel-time helpers shared by the merchant, courier and
/// tracking screens. Straight-line distance is used for the estimate, with an
/// average city speed to turn it into an ETA.
class GeoUtil {
  const GeoUtil._();

  static const double _earthRadiusKm = 6371.0088;
  static const double _averageCitySpeedKmh = 25;

  static LatLng? pointOf(dynamic raw) {
    if (raw is Map) {
      final lat = raw['latitude'];
      final lng = raw['longitude'];
      if (lat is num && lng is num) return LatLng(lat.toDouble(), lng.toDouble());
    }
    return null;
  }

  static double distanceKm(LatLng from, LatLng to) {
    final dLat = _degToRad(to.latitude - from.latitude);
    final dLon = _degToRad(to.longitude - from.longitude);
    final lat1 = _degToRad(from.latitude);
    final lat2 = _degToRad(to.latitude);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLon / 2), 2);
    final c = 2 * math.atan2(math.sqrt(a.toDouble()), math.sqrt(1 - a.toDouble()));
    return _earthRadiusKm * c;
  }

  static Duration eta(double distanceKm) {
    final minutes = (distanceKm / _averageCitySpeedKmh) * 60;
    return Duration(minutes: math.max(1, minutes.round()));
  }

  static String formatDistance(double km) {
    if (km < 1) return '${(km * 1000).round()} م';
    return '${km.toStringAsFixed(1)} كم';
  }

  static String formatDuration(Duration d) {
    if (d.inMinutes < 60) return '${d.inMinutes} دقيقة';
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    return minutes == 0 ? '$hours ساعة' : '$hours ساعة و$minutes دقيقة';
  }

  static String? formatClock(DateTime? time) {
    if (time == null) return null;
    final local = time.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  static DateTime? parseTime(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  static double _degToRad(double value) => value * math.pi / 180;
}
