import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:alfaeq_yemen/core/geo_util.dart';

void main() {
  group('GeoUtil', () {
    test('distanceKm matches a known Sanaa distance', () {
      // Bab al-Yemen -> Sanaa International Airport, ~13 km straight line.
      const babAlYemen = LatLng(15.3517, 44.2066);
      const airport = LatLng(15.4763, 44.2197);
      final km = GeoUtil.distanceKm(babAlYemen, airport);
      expect(km, greaterThan(12));
      expect(km, lessThan(15));
    });

    test('eta is never below one minute and grows with distance', () {
      expect(GeoUtil.eta(0.1).inMinutes, 1);
      expect(GeoUtil.eta(10).inMinutes, greaterThan(GeoUtil.eta(5).inMinutes));
    });

    test('formatDistance switches between metres and kilometres', () {
      expect(GeoUtil.formatDistance(0.4), contains('م'));
      expect(GeoUtil.formatDistance(3.25), contains('كم'));
    });

    test('formatClock renders HH:mm for a timestamp', () {
      final time = DateTime(2026, 10, 22, 9, 5);
      expect(GeoUtil.formatClock(time), '09:05');
      expect(GeoUtil.formatClock(null), isNull);
    });

    test('pointOf reads a delivery_location jsonb payload', () {
      final point = GeoUtil.pointOf({'latitude': 15.35, 'longitude': 44.2});
      expect(point, isNotNull);
      expect(point!.latitude, closeTo(15.35, 0.001));
      expect(GeoUtil.pointOf({'foo': 'bar'}), isNull);
    });
  });

  group('delivery hand-over migration', () {
    final sql = File('supabase/migrations/20261022010000_delivery_handover_and_timestamps_v1.sql').readAsStringSync();

    test('adds the order timestamps the merchant and courier screens read', () {
      for (final column in const [
        'merchant_ready_at',
        'assigned_at',
        'picked_up_at',
        'out_for_delivery_at',
        'delivered_at',
        'cancelled_at',
      ]) {
        expect(sql, contains(column));
      }
    });

    test('creates a locked-down delivery_events trail', () {
      expect(sql, contains('create table if not exists public.delivery_events'));
      expect(sql, contains('enable row level security'));
      expect(sql, contains('revoke all on public.delivery_events from public, anon, authenticated'));
    });

    test('stamps hand-over moments inside the definer RPCs', () {
      expect(sql, contains('merchant_ready_at = case'));
      expect(sql, contains('picked_up_at = case'));
      expect(sql, contains('insert into public.delivery_events'));
      expect(sql, contains('security definer'));
    });
  });

  group('merchant and courier screens', () {
    test('merchant hands the prepared order over to the courier pool', () {
      final page = File('lib/screens/merchant_orders_page.dart').readAsStringSync();
      expect(page, contains("onStatus(order,'ready_for_pickup')"));
      expect(page, contains("'p_delivery_status':status=='ready_for_pickup'?'awaiting_assignment':null"));
      expect(page, contains('DeliveryTimeline'));
      expect(page, contains('GeoUtil.distanceKm'));
    });

    test('courier can navigate to the store and the customer', () {
      final page = File('lib/screens/driver_center_page.dart').readAsStringSync();
      expect(page, contains('الذهاب إلى التاجر'));
      expect(page, contains('الذهاب إلى العميل'));
      expect(page, contains("_setStatus(id,'picked_up')"));
      expect(page, contains("_setStatus(id,'out_for_delivery')"));
      expect(page, contains("_setStatus(id,'delivered')"));
      expect(page, contains('DeliveryTimeline'));
    });
  });
}
