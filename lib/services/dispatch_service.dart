import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

class DispatchService {
  final FirebaseFirestore db;

  DispatchService({FirebaseFirestore? firestore})
      : db = firestore ?? FirebaseFirestore.instance;

  double distanceKm(GeoPoint a, GeoPoint b) {
    const earthRadiusKm = 6371.0;
    final dLat = _rad(b.latitude - a.latitude);
    final dLon = _rad(b.longitude - a.longitude);
    final lat1 = _rad(a.latitude);
    final lat2 = _rad(b.latitude);
    final h = math.pow(math.sin(dLat / 2), 2) +
        math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLon / 2), 2);
    return earthRadiusKm * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  double _rad(double value) => value * math.pi / 180;

  Future<DispatchCandidate?> findBestDriver(GeoPoint destination) async {
    final snapshot = await db
        .collection('drivers')
        .where('approved', isEqualTo: true)
        .where('isOnline', isEqualTo: true)
        .limit(50)
        .get();

    DispatchCandidate? best;
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final location = data['currentLocation'];
      if (location is! GeoPoint) continue;
      final distance = distanceKm(location, destination);
      final active = (data['activeOrderCount'] as num?)?.toInt() ?? 0;
      if (active >= 3) continue;
      final rating = (data['rating'] as num?)?.toDouble() ?? 5.0;
      final score = distance + (active * 2.5) + ((5.0 - rating).clamp(0, 5) * 0.8);
      final candidate = DispatchCandidate(
        driverId: doc.id,
        distanceKm: distance,
        score: score,
        activeOrderCount: active,
      );
      if (best == null || candidate.score < best.score) best = candidate;
    }
    return best;
  }

  Future<DispatchCandidate?> assignBestDriver({
    required String orderId,
    required GeoPoint destination,
    required String actorUid,
    required String actorRole,
  }) async {
    final candidate = await findBestDriver(destination);
    if (candidate == null) return null;

    final orderRef = db.collection('orders').doc(orderId);
    final driverRef = db.collection('drivers').doc(candidate.driverId);
    final auditRef = db.collection('auditLogs').doc();

    await db.runTransaction((transaction) async {
      final orderSnap = await transaction.get(orderRef);
      final driverSnap = await transaction.get(driverRef);
      if (!orderSnap.exists || !driverSnap.exists) {
        throw StateError('بيانات التوزيع لم تعد متاحة.');
      }
      final order = orderSnap.data() ?? <String, dynamic>{};
      final driver = driverSnap.data() ?? <String, dynamic>{};
      if ((order['driverId'] as String?)?.isNotEmpty == true ||
          order['deliveryStatus'] != 'awaiting_assignment') {
        throw StateError('تم توزيع الطلب مسبقاً.');
      }
      if (driver['approved'] != true || driver['isOnline'] != true) {
        throw StateError('المندوب لم يعد متاحاً.');
      }
      final active = (driver['activeOrderCount'] as num?)?.toInt() ?? 0;
      if (active >= 3) throw StateError('وصل المندوب إلى الحد التشغيلي.');

      transaction.update(orderRef, {
        'driverId': candidate.driverId,
        'deliveryStatus': 'assigned',
        'assignedAt': FieldValue.serverTimestamp(),
        'dispatchScore': candidate.score,
        'dispatchDistanceKm': candidate.distanceKm,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(driverRef, {
        'activeOrderCount': active + 1,
        'lastAssignedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(auditRef, {
        'actorUid': actorUid,
        'role': actorRole,
        'action': 'smart_dispatch_assign',
        'result': 'success',
        'source': 'smart_dispatch',
        'details': {
          'orderId': orderId,
          'driverId': candidate.driverId,
          'distanceKm': candidate.distanceKm,
          'score': candidate.score,
        },
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
    return candidate;
  }
}

class DispatchCandidate {
  final String driverId;
  final double distanceKm;
  final double score;
  final int activeOrderCount;

  const DispatchCandidate({
    required this.driverId,
    required this.distanceKm,
    required this.score,
    required this.activeOrderCount,
  });
}
