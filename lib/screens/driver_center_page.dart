import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/geo_util.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/supabase_service.dart';
import '../widgets/delivery_timeline.dart';

/// Courier workspace: my jobs, the pool of orders I can accept, and a route map
/// that connects the store, me and the customer.
class DriverCenterPage extends StatefulWidget {
  const DriverCenterPage({super.key});
  @override State<DriverCenterPage> createState()=>_DriverCenterPageState();
}

class _DriverCenterPageState extends State<DriverCenterPage> with SingleTickerProviderStateMixin {
  final _auth=AuthService(); bool _busy=false;
  StreamSubscription<Position>? _locationSubscription;
  LatLng? _myPosition;
  bool _resumeChecked=false;
  late final TabController _tabs=TabController(length:3,vsync:this);

  Future<bool> _allowed() async {
    final role=await _auth.role();
    return ['driver','admin','owner','developer'].contains(role);
  }
  Future<void> _ensureProfile(String uid) async {
    if(SupabaseService.isInitialized){await SupabaseService.client.rpc('ensure_driver_profile');}
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
  Future<void> _resumeIfOnline(String uid,bool online,bool approved) async {
    if(_resumeChecked)return;
    _resumeChecked=true;
    if(!online||!approved||_locationSubscription!=null)return;
    try{await _startLiveLocation(uid);}catch(_){}
  }
  Future<void> _startLiveLocation(String uid) async {
    await _stopLiveLocation(); await LocationService.requireCurrentPosition();
    const settings=LocationSettings(accuracy:LocationAccuracy.high,distanceFilter:20);
    _locationSubscription=Geolocator.getPositionStream(locationSettings:settings).listen((p){_publish(uid,p);},onError:(e)=>_message('توقف تتبع الموقع: $e'));
  }
  Future<void> _stopLiveLocation() async {await _locationSubscription?.cancel();_locationSubscription=null;}
  Future<void> _publish(String uid,Position p) async {
    if(mounted)setState(()=>_myPosition=LatLng(p.latitude,p.longitude));
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
    if(mounted)setState(()=>_myPosition=LatLng(p.latitude,p.longitude));
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
      _tabs.animateTo(0);
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
      _message(switch(status){'picked_up'=>'تم تأكيد استلام البضاعة من التاجر.','out_for_delivery'=>'الطلب في الطريق إلى العميل.','delivered'=>'تم تسليم الطلب للعميل.','cancelled'=>'تم إلغاء المهمة.',_=>'تم تحديث حالة مهمة التوصيل.'});
    }catch(e){_message('تعذر تحديث المهمة: $e');}finally{if(mounted)setState(()=>_busy=false);}
  }

  Future<void> _openNavigation(LatLng destination) async {
    final uri=Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${destination.latitude},${destination.longitude}&travelmode=driving');
    try{
      if(!await launchUrl(uri,mode:LaunchMode.externalApplication))_message('تعذر فتح تطبيق الخرائط.');
    }catch(_){_message('تعذر فتح تطبيق الخرائط.');}
  }
  Future<void> _call(String phone) async {
    try{if(!await launchUrl(Uri(scheme:'tel',path:phone)))_message('تعذر إجراء الاتصال.');}catch(_){_message('تعذر إجراء الاتصال.');}
  }
  void _message(String s){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));}
  @override void dispose(){_stopLiveLocation();_tabs.dispose();super.dispose();}

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
            if(profile.connectionState==ConnectionState.active){_resumeIfOnline(user.id,online,approved);}
            final active=(d['active_order_count'] as num?)?.toInt()??0;
            return Scaffold(
              appBar:AppBar(
                title:const Text('مركز المندوب'),
                bottom:TabBar(controller:_tabs,tabs:const[
                  Tab(icon:Icon(Icons.assignment_outlined),text:'مهامي'),
                  Tab(icon:Icon(Icons.inbox_outlined),text:'متاحة'),
                  Tab(icon:Icon(Icons.map_outlined),text:'الخريطة'),
                ]),
              ),
              body:TabBarView(controller:_tabs,children:[
                _tasksTab(user.id,approved,online,active,d),
                _availableTab(approved),
                _mapTab(user.id),
              ]),
            );
          },
        );
      },
    ));
  }

  Widget _header(bool approved,bool online,int active,Map<String,dynamic> d)=>Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Row(children:[
      const Icon(Icons.delivery_dining,size:36),const SizedBox(width:10),
      const Expanded(child:Text('المندوب الذكي',style:TextStyle(fontSize:22,fontWeight:FontWeight.w900))),
      Chip(label:Text(approved?'معتمد':'بانتظار الاعتماد')),
    ]),
    const SizedBox(height:6),
    SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('متاح لاستلام الطلبات'),subtitle:Text(online?'متصل — الموقع يتحدث تلقائياً':'غير متصل'),value:online,onChanged:_busy||!approved?null:_toggleOnline),
    Row(children:[
      const Icon(Icons.assignment_outlined,size:18),const SizedBox(width:6),
      Text('الطلبات النشطة: $active',style:const TextStyle(fontWeight:FontWeight.w800)),
      const Spacer(),
      TextButton.icon(onPressed:approved?_updateLocation:null,icon:const Icon(Icons.my_location,size:18),label:const Text('تحديث موقعي')),
    ]),
  ])));

  Widget _tasksTab(String uid,bool approved,bool online,int active,Map<String,dynamic> d)=>ListView(padding:const EdgeInsets.all(16),children:[
    _header(approved,online,active,d),
    const SizedBox(height:12),
    StreamBuilder<List<Map<String,dynamic>>>(
      stream:SupabaseService.client.from('orders').stream(primaryKey:['id']).eq('driver_id',uid).order('created_at',ascending:false).limit(50),
      builder:(context,orders){
        if(orders.hasError)return Text('تعذر تحميل المهام: ${orders.error}');
        final docs=(orders.data??const <Map<String,dynamic>>[]).where((o)=>!['delivered','completed','cancelled'].contains((o['delivery_status']??'').toString())).toList();
        return FutureBuilder<_DriverContext>(
          future:_context(docs),
          builder:(context,ctx){
            final data=ctx.data??const _DriverContext(<String,Map<String,dynamic>>{},<String,List<Map<String,dynamic>>>{});
            if(docs.isEmpty)return const Card(child:Padding(padding:EdgeInsets.all(16),child:Text('لا توجد مهام مسندة حالياً. استلم طلباً من تبويب «متاحة».')));
            return Column(children:docs.map((o)=>_jobCard(o,data)).toList());
          },
        );
      },
    ),
  ]);

  Widget _availableTab(bool approved)=>ListView(padding:const EdgeInsets.all(16),children:[
    if(!approved)const Card(child:Padding(padding:EdgeInsets.all(16),child:Text('اعتماد حسابك مطلوب قبل استلام الطلبات.',style:TextStyle(color:Colors.black54)))),
    StreamBuilder<List<Map<String,dynamic>>>(
      stream:SupabaseService.client.from('orders').stream(primaryKey:['id']).inFilter('delivery_status',['pending','awaiting_assignment']).neq('status','cancelled').order('created_at',ascending:false).limit(30),
      builder:(context,avail){
        if(avail.hasError)return Text('تعذر تحميل الطلبات: ${avail.error}');
        final docs=(avail.data??const <Map<String,dynamic>>[]).where((o)=>(o['driver_id']??'')==''&&!['cancelled','delivered','completed'].contains((o['status']??'').toString())).toList();
        if(docs.isEmpty)return const Card(child:Padding(padding:EdgeInsets.all(16),child:Text('لا توجد طلبات متاحة حالياً.')));
        return FutureBuilder<_DriverContext>(
          future:_context(docs),
          builder:(context,ctx){
            final data=ctx.data??const _DriverContext(<String,Map<String,dynamic>>{},<String,List<Map<String,dynamic>>>{});
            return Column(children:docs.map((o){
              final id=o['id'].toString();
              final store=data.stores['${o['merchant_id']??''}']??_firstStore(o,data.stores);
              final pickup=GeoUtil.pointOf(store);
              final dest=GeoUtil.pointOf(o['delivery_location']);
              final km=(pickup!=null&&dest!=null)?GeoUtil.distanceKm(pickup,dest):null;
              return Card(elevation:0,margin:const EdgeInsets.only(bottom:10),child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Text('طلب #${id.length>8?id.substring(0,8):id}',style:const TextStyle(fontWeight:FontWeight.w900)),
                const SizedBox(height:4),
                Text('التاجر: ${store?['name']??'—'}'),
                Text('العميل: ${o['address']??'—'}'),
                if(km!=null)Text('من التاجر إلى العميل: ${GeoUtil.formatDistance(km)} • ${GeoUtil.formatDuration(GeoUtil.eta(km))}',style:const TextStyle(color:Colors.black54)),
                const SizedBox(height:8),
                Align(alignment:AlignmentDirectional.centerEnd,child:FilledButton.icon(onPressed:_busy?null:()=>_acceptOrder(id),icon:const Icon(Icons.check),label:const Text('استلام المهمة'))),
              ])));
            }).toList());
          },
        );
      },
    ),
  ]);

  Map<String,dynamic>? _firstStore(Map<String,dynamic> order,Map<String,Map<String,dynamic>> stores){
    for(final s in stores.values){return s;}
    return null;
  }

  Widget _jobCard(Map<String,dynamic> o,_DriverContext data){
    final id=o['id'].toString();
    final status=(o['delivery_status']??'assigned').toString();
    final store=data.stores['${o['merchant_id']??''}']??_firstStore(o,data.stores);
    final pickup=GeoUtil.pointOf(store);
    final dest=GeoUtil.pointOf(o['delivery_location']);
    final km=(pickup!=null&&dest!=null)?GeoUtil.distanceKm(pickup,dest):null;
    final phone=(o['customer_phone']??o['phone']??o['contact_phone'])?.toString();
    return Card(elevation:0,margin:const EdgeInsets.only(bottom:12),child:ExpansionTile(
      initiallyExpanded:true,
      leading:const Icon(Icons.local_shipping_outlined),
      title:Text('طلب #${id.length>8?id.substring(0,8):id}',style:const TextStyle(fontWeight:FontWeight.w900)),
      subtitle:Text('$status${km!=null?' • ${GeoUtil.formatDistance(km)}':''}'),
      children:[Padding(padding:const EdgeInsets.fromLTRB(16,0,16,16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        ListTile(dense:true,contentPadding:EdgeInsets.zero,leading:const Icon(Icons.storefront_outlined),title:const Text('التاجر (نقطة الاستلام)'),subtitle:Text(store?['name']?.toString()??'—')),
        if(pickup!=null)Align(alignment:AlignmentDirectional.centerEnd,child:OutlinedButton.icon(onPressed:()=>_openNavigation(pickup),icon:const Icon(Icons.navigation_outlined),label:const Text('الذهاب إلى التاجر'))),
        ListTile(dense:true,contentPadding:EdgeInsets.zero,leading:const Icon(Icons.person_pin_circle_outlined),title:const Text('العميل (نقطة التسليم)'),subtitle:Text(o['address']?.toString()??'—')),
        if(dest!=null)Align(alignment:AlignmentDirectional.centerEnd,child:OutlinedButton.icon(onPressed:()=>_openNavigation(dest),icon:const Icon(Icons.directions_outlined),label:const Text('الذهاب إلى العميل'))),
        if(km!=null)Padding(padding:const EdgeInsets.symmetric(vertical:6),child:Row(children:[const Icon(Icons.route_outlined,size:16),const SizedBox(width:6),Expanded(child:Text('المسافة ${GeoUtil.formatDistance(km)} • الزمن المتوقع ${GeoUtil.formatDuration(GeoUtil.eta(km))}',style:const TextStyle(color:Colors.black54)))])),
        const Divider(height:20),
        const Text('مسار الطلب والأوقات',style:TextStyle(fontWeight:FontWeight.w900)),
        const SizedBox(height:8),
        DeliveryTimeline(order:o,events:data.events[id]??const <Map<String,dynamic>>[],dense:true),
        const SizedBox(height:4),
        Wrap(spacing:8,runSpacing:8,children:[
          if(status=='assigned')FilledButton.icon(onPressed:_busy?null:()=>_setStatus(id,'picked_up'),icon:const Icon(Icons.inventory_outlined),label:const Text('استلمت البضاعة من التاجر')),
          if(status=='picked_up')FilledButton.icon(onPressed:_busy?null:()=>_setStatus(id,'out_for_delivery'),icon:const Icon(Icons.directions_car_outlined),label:const Text('خرجت للتوصيل')),
          if(status=='out_for_delivery'||status=='on_the_way')FilledButton.icon(onPressed:_busy?null:()=>_setStatus(id,'delivered'),icon:const Icon(Icons.check_circle_outline),label:const Text('تم التسليم للعميل')),
          if(phone!=null&&phone.isNotEmpty)OutlinedButton.icon(onPressed:()=>_call(phone),icon:const Icon(Icons.call_outlined),label:const Text('اتصال بالعميل')),
        ]),
      ]))],
    ));
  }

  Widget _mapTab(String uid)=>StreamBuilder<List<Map<String,dynamic>>>(
    stream:SupabaseService.client.from('orders').stream(primaryKey:['id']).eq('driver_id',uid).order('created_at',ascending:false).limit(50),
    builder:(context,orders){
      final docs=(orders.data??const <Map<String,dynamic>>[]).where((o)=>!['delivered','completed','cancelled'].contains((o['delivery_status']??'').toString())).toList();
      return FutureBuilder<_DriverContext>(
        future:_context(docs),
        builder:(context,ctx){
          final data=ctx.data??const _DriverContext(<String,Map<String,dynamic>>{},<String,List<Map<String,dynamic>>>{});
          final markers=<Marker>[];
          final lines=<Polyline>[];
          if(_myPosition!=null){
            markers.add(Marker(point:_myPosition!,width:44,height:44,child:const Icon(Icons.my_location,color:Colors.blue,size:36)));
          }
          for(final o in docs){
            final store=data.stores['${o['merchant_id']??''}']??_firstStore(o,data.stores);
            final pickup=GeoUtil.pointOf(store);
            final dest=GeoUtil.pointOf(o['delivery_location']);
            if(pickup!=null){
              markers.add(Marker(point:pickup,width:44,height:44,child:const Icon(Icons.storefront,color:Colors.orange,size:36)));
              if(_myPosition!=null)lines.add(Polyline(points:[_myPosition!,pickup],strokeWidth:3,color:Colors.orange));
            }
            if(dest!=null){
              markers.add(Marker(point:dest,width:44,height:44,child:const Icon(Icons.location_on,color:Colors.red,size:36)));
              if(pickup!=null)lines.add(Polyline(points:[pickup,dest],strokeWidth:3,color:Colors.red));
            }
          }
          final center=_myPosition??(markers.isNotEmpty?markers.first.point:const LatLng(15.3694,44.1910));
          return Stack(children:[
            FlutterMap(
              options:MapOptions(initialCenter:center,initialZoom:_myPosition!=null?14:7),
              children:[
                TileLayer(urlTemplate:'https://tile.openstreetmap.org/{z}/{x}/{y}.png',userAgentPackageName:'com.alfaeq.alfaeq_yemen'),
                if(lines.isNotEmpty)PolylineLayer(polylines:lines),
                MarkerLayer(markers:markers),
                const RichAttributionWidget(attributions:[TextSourceAttribution('OpenStreetMap contributors')]),
              ],
            ),
            Positioned(top:12,right:12,left:12,child:Card(child:Padding(padding:const EdgeInsets.all(12),child:Row(children:[
              const Icon(Icons.route_outlined),const SizedBox(width:8),
              Expanded(child:Text('مسار التاجر ← العميل • ${docs.length} مهمة نشطة',style:const TextStyle(fontWeight:FontWeight.w900))),
            ])))),
          ]);
        },
      );
    },
  );

  Future<_DriverContext> _context(List<Map<String,dynamic>> orders) async {
    final stores=<String,Map<String,dynamic>>{};
    final ids=<String>{};
    for(final o in orders){
      final mid='${o['merchant_id']??''}';if(mid.isNotEmpty)ids.add(mid);
      final mids=o['merchant_ids'];
      if(mids is List){for(final m in mids){ids.add('$m');}}
    }
    if(ids.isNotEmpty){
      try{
        final rows=await SupabaseService.client.from('stores').select('id,name,latitude,longitude').inFilter('id',ids.toList());
        for(final raw in List<Map<String,dynamic>>.from(rows)){stores['${raw['id']}']=raw;}
      }catch(_){}
    }
    final events=<String,List<Map<String,dynamic>>>{};
    final orderIds=orders.map((o)=>'${o['id']}').toList();
    if(orderIds.isNotEmpty){
      try{
        final ev=await SupabaseService.client.from('order_delivery_events').select().inFilter('order_id',orderIds).order('created_at',ascending:true);
        for(final raw in List<Map<String,dynamic>>.from(ev)){events.putIfAbsent('${raw['order_id']}',()=><Map<String,dynamic>>[]).add(raw);}
      }catch(_){}
    }
    return _DriverContext(stores,events);
  }
}

class _DriverContext {
  final Map<String,Map<String,dynamic>> stores;
  final Map<String,List<Map<String,dynamic>>> events;
  const _DriverContext(this.stores,this.events);
}
