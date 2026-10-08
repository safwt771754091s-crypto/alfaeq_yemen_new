import 'dart:math' as math;
import 'supabase_service.dart';

class DispatchService {
  double _rad(double v) => v * math.pi / 180;
  double _distance(Map<String,dynamic> p,double lat,double lng) {
    final a=(p['latitude'] as num?)?.toDouble(), b=(p['longitude'] as num?)?.toDouble();
    if(a==null||b==null)return double.infinity;
    final x=_rad(lat-a)/2, y=_rad(lng-b)/2;
    final h=math.sin(x)*math.sin(x)+math.cos(_rad(a))*math.cos(_rad(lat))*math.sin(y)*math.sin(y);
    return 6371*2*math.atan2(math.sqrt(h),math.sqrt(1-h));
  }

  Stream<List<Map<String,dynamic>>> pendingOrdersStream() {
    // Orders awaiting a courier can be created with either delivery_status:
    // 'pending' (default) or 'awaiting_assignment' (merchant marked ready).
    return SupabaseService.client.from('orders').stream(primaryKey:['id']).inFilter('delivery_status',['pending','awaiting_assignment']).order('created_at',ascending:false).limit(100);
  }

  Stream<List<Map<String,dynamic>>> couriersStream() {
    return SupabaseService.client.from('drivers').stream(primaryKey:['uid']).order('created_at',ascending:false).limit(200);
  }

  Future<void> approveCourier({required String driverId, required bool approved}) async {
    await SupabaseService.client.rpc('approve_courier',params:{'p_driver_id':driverId,'p_approved':approved});
  }

  Future<List<Map<String,dynamic>>> listCouriers() async {
    final rows = await SupabaseService.client.rpc('list_couriers');
    return (rows as List).map((e) => Map<String,dynamic>.from(e as Map)).toList();
  }

  Future<void> setDeliveryLocation({required String orderId,required double latitude,required double longitude}) async {
    await SupabaseService.client.from('orders').update({'latitude':latitude,'longitude':longitude,'delivery_location':{'latitude':latitude,'longitude':longitude},'updated_at':DateTime.now().toUtc().toIso8601String()}).eq('id',orderId);
  }

  Future<DispatchCandidate?> findBestDriver(double latitude,double longitude) async {
    final rows=await SupabaseService.client.from('drivers').select('uid,active_order_count,current_location').eq('approved',true).eq('is_online',true).limit(100);
    DispatchCandidate? best;
    for(final raw in rows){final d=Map<String,dynamic>.from(raw),loc=d['current_location'];if(loc is! Map)continue;final distance=_distance(Map<String,dynamic>.from(loc),latitude,longitude);final active=(d['active_order_count'] as num?)?.toInt()??0;if(!distance.isFinite||active>=3)continue;final c=DispatchCandidate(driverId:d['uid'].toString(),distanceKm:distance,score:distance+active*2.5,activeOrderCount:active);if(best==null||c.score<best.score)best=c;}return best;
  }

  Future<void> assignDriver({required String orderId, required String driverId}) async {
    await SupabaseService.client.rpc('assign_order_driver',params:{'p_order_id':orderId,'p_driver_id':driverId});
  }

  Future<DispatchCandidate?> assignBestDriver({required String orderId,required double latitude,required double longitude}) async {
    final c=await findBestDriver(latitude,longitude);
    if(c==null)return null;
    await assignDriver(orderId:orderId,driverId:c.driverId);
    return c;
  }
}
class DispatchCandidate {
  final String driverId; final double distanceKm; final double score; final int activeOrderCount;
  const DispatchCandidate({required this.driverId,required this.distanceKm,required this.score,required this.activeOrderCount});
}