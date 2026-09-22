import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

class DispatchService {
  final FirebaseFirestore db;
  final SupabaseClient? supabase;
  DispatchService({FirebaseFirestore? firestore, SupabaseClient? client})
      : db = firestore ?? FirebaseFirestore.instance,
        supabase = client ?? (SupabaseService.isInitialized ? SupabaseService.client : null);

  double _rad(double v) => v * math.pi / 180;
  double _distance(Map<String,dynamic> p,double lat,double lng) {
    final a=(p['latitude'] as num?)?.toDouble(), b=(p['longitude'] as num?)?.toDouble();
    if(a==null||b==null)return double.infinity;
    final x=_rad(lat-a)/2, y=_rad(lng-b)/2;
    final h=math.sin(x)*math.sin(x)+math.cos(_rad(a))*math.cos(_rad(lat))*math.sin(y)*math.sin(y);
    return 6371*2*math.atan2(math.sqrt(h),math.sqrt(1-h));
  }

  Stream<List<Map<String,dynamic>>> pendingOrdersStream() {
    if(SupabaseService.isInitialized) {
      return SupabaseService.client.from('orders').stream(primaryKey:['id'])
        .eq('delivery_status','awaiting_assignment').order('created_at',ascending:false).limit(100);
    }
    return db.collection('orders').where('deliveryStatus',isEqualTo:'awaiting_assignment').limit(100)
      .snapshots().map((s)=>s.docs.map((d)=>{'id':d.id,...d.data()}).toList());
  }

  Future<void> setDeliveryLocation({required String orderId,required double latitude,required double longitude}) async {
    if(SupabaseService.isInitialized) {
      await SupabaseService.client.from('orders').update({
        'latitude':latitude,'longitude':longitude,
        'delivery_location':{'latitude':latitude,'longitude':longitude},
        'updated_at':DateTime.now().toUtc().toIso8601String(),
      }).eq('id',orderId);
      return;
    }
    await db.collection('orders').doc(orderId).update({'deliveryLocation':GeoPoint(latitude,longitude),'updatedAt':FieldValue.serverTimestamp()});
  }

  Future<DispatchCandidate?> findBestDriver(double latitude,double longitude) async {
    if(SupabaseService.isInitialized) {
      final rows=await SupabaseService.client.from('drivers')
        .select('uid,active_order_count,current_location').eq('approved',true).eq('is_online',true).limit(100);
      DispatchCandidate? best;
      for(final raw in rows) {
        final d=Map<String,dynamic>.from(raw), loc=d['current_location'];
        if(loc is! Map)continue;
        final distance=_distance(Map<String,dynamic>.from(loc),latitude,longitude);
        final active=(d['active_order_count'] as num?)?.toInt()??0;
        if(!distance.isFinite||active>=3)continue;
        final c=DispatchCandidate(driverId:d['uid'].toString(),distanceKm:distance,score:distance+active*2.5,activeOrderCount:active);
        if(best==null||c.score<best.score)best=c;
      }
      return best;
    }
    final snap=await db.collection('drivers').where('approved',isEqualTo:true).where('isOnline',isEqualTo:true).limit(50).get();
    DispatchCandidate? best;
    for(final doc in snap.docs){
      final d=doc.data(), loc=d['currentLocation'];
      if(loc is! GeoPoint)continue;
      final distance=_distance({'latitude':loc.latitude,'longitude':loc.longitude},latitude,longitude);
      final active=(d['activeOrderCount'] as num?)?.toInt()??0;
      if(active>=3)continue;
      final c=DispatchCandidate(driverId:doc.id,distanceKm:distance,score:distance+active*2.5,activeOrderCount:active);
      if(best==null||c.score<best.score)best=c;
    }
    return best;
  }

  Future<DispatchCandidate?> assignBestDriver({required String orderId,required double latitude,required double longitude}) async {
    final c=await findBestDriver(latitude,longitude);
    if(c==null)return null;
    if(SupabaseService.isInitialized){
      await SupabaseService.client.rpc('assign_order_driver',params:{'p_order_id':orderId,'p_driver_id':c.driverId});
      return c;
    }
    final orderRef=db.collection('orders').doc(orderId), driverRef=db.collection('drivers').doc(c.driverId);
    await db.runTransaction((tx) async {
      final o=await tx.get(orderRef), d=await tx.get(driverRef);
      if(!o.exists||!d.exists)throw StateError('بيانات التوزيع غير متاحة.');
      final od=o.data()!, dd=d.data()!;
      if(od['deliveryStatus']!='awaiting_assignment')throw StateError('تم توزيع الطلب مسبقاً.');
      if(dd['approved']!=true||dd['isOnline']!=true)throw StateError('المندوب غير متاح.');
      final active=(dd['activeOrderCount'] as num?)?.toInt()??0;
      if(active>=3)throw StateError('وصل المندوب للحد التشغيلي.');
      tx.update(orderRef,{'driverId':c.driverId,'deliveryStatus':'assigned','assignedAt':FieldValue.serverTimestamp(),'updatedAt':FieldValue.serverTimestamp()});
      tx.update(driverRef,{'activeOrderCount':active+1,'updatedAt':FieldValue.serverTimestamp()});
    });
    return c;
  }
}
class DispatchCandidate {
  final String driverId; final double distanceKm; final double score; final int activeOrderCount;
  const DispatchCandidate({required this.driverId,required this.distanceKm,required this.score,required this.activeOrderCount});
}