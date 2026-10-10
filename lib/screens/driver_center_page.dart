import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/supabase_service.dart';

class DriverCenterPage extends StatefulWidget {
  const DriverCenterPage({super.key});
  @override State<DriverCenterPage> createState()=>_DriverCenterPageState();
}
class _DriverCenterPageState extends State<DriverCenterPage>{
  final _auth=AuthService(); bool _busy=false; StreamSubscription<Position>? _locationSubscription;
  bool _resumeChecked=false;

  Future<bool> _allowed() async {
    final role=await _auth.role();
    return ['driver','admin','owner','developer'].contains(role);
  }
  Future<void> _ensureProfile(String uid) async {
    if(SupabaseService.isInitialized){await SupabaseService.client.rpc('ensure_driver_profile');return;}
  }
  Future<void> _toggleOnline(bool value) async {
    final user=SupabaseService.client.auth.currentUser;if(user==null)return;
    setState(()=>_busy=true);
    try{
      await _ensureProfile(user.id);
      if(SupabaseService.isInitialized){
        await SupabaseService.client.from('drivers').update({'is_online':value,'last_seen_at':DateTime.now().toUtc().toIso8601String(),'updated_at':DateTime.now().toUtc().toIso8601String()}).eq('uid',user.id);
      }
      if(value)await _startLiveLocation(user.id);else await _stopLiveLocation();
    }catch(e){_message('تعذر تحديث حالة المندوب: $e');}finally{if(mounted)setState(()=>_busy=false);}
  }
  Future<void> _resumeIfOnline(String uid, bool online, bool approved) async {
    if (_resumeChecked) return;
    _resumeChecked = true;
    if (!online || !approved || _locationSubscription != null) return;
    try { await _startLiveLocation(uid); } catch (_) {}
  }
  Future<void> _startLiveLocation(String uid) async {
    await _stopLiveLocation(); await LocationService.requireCurrentPosition();
    const settings=LocationSettings(accuracy:LocationAccuracy.high,distanceFilter:20);
    _locationSubscription=Geolocator.getPositionStream(locationSettings:settings).listen((p)=>_publish(uid,p),onError:(e)=>_message('توقف تتبع الموقع: $e'));
  }
  Future<void> _stopLiveLocation() async {await _locationSubscription?.cancel();_locationSubscription=null;}
  Future<void> _publish(String uid,Position p) async {
    if(!SupabaseService.isInitialized)return;
    try{
      await SupabaseService.client.rpc('driver_update_location',params:{'p_latitude':p.latitude,'p_longitude':p.longitude});
      final orders=await SupabaseService.client.from('orders').select('id,delivery_status').eq('driver_id',uid).inFilter('delivery_status',['assigned','picked_up','out_for_delivery','on_the_way']).limit(20);
      for(final raw in orders){
        await SupabaseService.client.from('orders').update({'driver_location':{'latitude':p.latitude,'longitude':p.longitude},'updated_at':DateTime.now().toUtc().toIso8601String()}).eq('id',raw['id']);
      }
    }catch(_){}
  }
  Future<void> _updateLocation() async {
    final p=await LocationService.requireCurrentPosition();
    if(SupabaseService.isInitialized){
      await SupabaseService.client.rpc('driver_update_location',params:{'p_latitude':p.latitude,'p_longitude':p.longitude});
      _message('تم تحديث موقع المندوب.');
    }
  }
  Future<void> _acceptOrder(String orderId) async {
    final user=SupabaseService.client.auth.currentUser;if(user==null)return;
    setState(()=>_busy=true);
    try{
      if(SupabaseService.isInitialized){
        await SupabaseService.client.rpc('assign_order_driver',params:{'p_order_id':orderId,'p_driver_id':user.id});
      }
      _message('تم استلام المهمة وإسنادها إليك.');
    }catch(e){_message('تعذر استلام المهمة: $e');}finally{if(mounted)setState(()=>_busy=false);}
  }

  Future<void> _setStatus(String orderId,String status) async {
    final user=SupabaseService.client.auth.currentUser;if(user==null)return;
    setState(()=>_busy=true);
    try{
      Position? p;
      try{p=await LocationService.requireCurrentPosition();}catch(_){}
      if(SupabaseService.isInitialized){
        await SupabaseService.client.rpc('driver_update_order',params:{
          'p_order_id':orderId,'p_status':status,'p_latitude':p?.latitude,'p_longitude':p?.longitude,
        });
      }
      _message('تم تحديث حالة مهمة التوصيل.');
    }catch(e){_message('تعذر تحديث المهمة: $e');}finally{if(mounted)setState(()=>_busy=false);}
  }
  void _message(String s){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));}
  @override void dispose(){_stopLiveLocation();super.dispose();}

  @override Widget build(BuildContext context){
    final user=SupabaseService.client.auth.currentUser;
    return Directionality(textDirection:TextDirection.rtl,child:FutureBuilder<bool>(
      future:_allowed(),
      builder:(context,access){
        if(access.connectionState!=ConnectionState.done)return const Scaffold(body:Center(child:CircularProgressIndicator()));
        if(access.data!=true||user==null)return const Scaffold(body:Center(child:Text('مركز المندوب محمي للحسابات المعتمدة.')));
        if(!SupabaseService.isInitialized)return const Scaffold(body:Center(child:Text('مركز المندوب يتطلب اتصال قاعدة المنصة الجديدة.')));
        return StreamBuilder<List<Map<String,dynamic>>>(
          stream:SupabaseService.client.from('drivers').stream(primaryKey:['uid']).eq('uid',user.id).limit(1),
          builder:(context,profile){
            final d=profile.data?.isNotEmpty==true?profile.data!.first:<String,dynamic>{};
            final approved=d['approved']==true, online=d['is_online']==true;
            if (profile.connectionState==ConnectionState.active) { _resumeIfOnline(user.id, online, approved); }
            final active=(d['active_order_count'] as num?)?.toInt()??0;
            return Scaffold(
              appBar:AppBar(title:const Text('مركز المندوب')),
              body:ListView(padding:const EdgeInsets.all(16),children:[
                Card(child:Padding(padding:const EdgeInsets.all(20),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  const Icon(Icons.delivery_dining,size:42),const SizedBox(height:10),
                  const Text('المندوب الذكي',style:TextStyle(fontSize:25,fontWeight:FontWeight.w900)),
                  const SizedBox(height:6),Text(approved?'حسابك معتمد للتوزيع.':'حسابك بانتظار اعتماد المالك.'),
                  SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('متاح لاستلام الطلبات'),subtitle:Text(online?'متصل — الموقع يتحدث':'غير متصل'),value:online,onChanged:_busy||!approved?null:_toggleOnline),
                ]))),
                const SizedBox(height:12),
                Card(child:ListTile(leading:const Icon(Icons.assignment_outlined),title:const Text('الطلبات النشطة'),trailing:Text('$active',style:const TextStyle(fontSize:22,fontWeight:FontWeight.w900)))),
                Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  const Text('طلبات متاحة للاستلام',style:TextStyle(fontSize:19,fontWeight:FontWeight.w900)),const SizedBox(height:10),
                  if(!approved)const Text('اعتماد حسابك مطلوب قبل استلام الطلبات.',style:TextStyle(color:Colors.black54))
                  else StreamBuilder<List<Map<String,dynamic>>>(
                    stream:SupabaseService.client.from('orders').stream(primaryKey:['id']).inFilter('delivery_status',['pending','awaiting_assignment']).neq('status','cancelled').order('created_at',ascending:false).limit(30),
                    builder:(context,avail){
                      if(avail.hasError)return Text('تعذر تحميل الطلبات: ${avail.error}');
                      final docs=(avail.data??const <Map<String,dynamic>>[]).where((o)=>(o['driver_id']??'')==''&&!['cancelled','delivered','completed'].contains((o['status']??'').toString())).toList();
                      if(docs.isEmpty)return const Text('لا توجد طلبات متاحة حالياً.');
                      return Column(children:docs.map((o){
                        final id=o['id'].toString();
                        return Card(elevation:0,child:ListTile(
                          leading:const Icon(Icons.inbox_outlined),
                          title:Text('طلب #'+id.substring(0,id.length>8?8:id.length)),
                          subtitle:Text((o['address']??'—').toString()),
                          trailing:FilledButton(onPressed:_busy?null:()=>_acceptOrder(id),child:const Text('استلام')),
                        ));
                      }).toList());
                    },
                  ),
                ]))),
                Card(child:ListTile(leading:const Icon(Icons.my_location),title:const Text('موقع المندوب'),subtitle:Text(d['current_location'] is Map?'الموقع مسجل ويُحدّث عند الاتصال.':'لم يتم تسجيل موقع بعد.'),onTap:approved?_updateLocation:null)),
                const SizedBox(height:12),
                StreamBuilder<List<Map<String,dynamic>>>(
                  stream:SupabaseService.client.from('orders').stream(primaryKey:['id']).eq('driver_id',user.id).order('created_at',ascending:false).limit(50),
                  builder:(context,orders){
                    if(orders.hasError)return Text('تعذر تحميل المهام: ${orders.error}');
                    final docs=orders.data??const <Map<String,dynamic>>[];
                    return Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                      const Text('مهام التوصيل',style:TextStyle(fontSize:19,fontWeight:FontWeight.w900)),const SizedBox(height:10),
                      if(docs.isEmpty)const Text('لا توجد مهام مسندة حالياً.') else ...docs.map((o){
                        final id=o['id'].toString(), status=(o['delivery_status']??'assigned').toString();
                        return Card(elevation:0,child:ExpansionTile(
                          leading:const Icon(Icons.local_shipping_outlined),
                          title:Text('طلب #'+id.substring(0,id.length>8?8:id.length)),
                          subtitle:Text(status+' • '+(o['address']??'—').toString()),
                          children:[Padding(padding:const EdgeInsets.all(12),child:Wrap(spacing:8,runSpacing:8,children:[
                            if(status=='assigned')FilledButton(onPressed:_busy?null:()=>_setStatus(id,'picked_up'),child:const Text('استلام الطلب')),
                            if(status=='picked_up')FilledButton(onPressed:_busy?null:()=>_setStatus(id,'out_for_delivery'),child:const Text('خرج للتوصيل')),
                            if(status=='out_for_delivery'||status=='on_the_way')FilledButton(onPressed:_busy?null:()=>_setStatus(id,'delivered'),child:const Text('تم التسليم')),
                          ]))],
                        ));
                      }),
                    ])));
                  },
                ),
              ]),
            );
          },
        );
      },
    ));
  }
}