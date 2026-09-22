import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../services/auth_service.dart';
import '../services/dispatch_service.dart';
import 'driver_fleet_map_page.dart';
import 'location_picker_page.dart';

class DispatchCenterPage extends StatefulWidget {
  const DispatchCenterPage({super.key});
  @override State<DispatchCenterPage> createState()=>_DispatchCenterPageState();
}
class _DispatchCenterPageState extends State<DispatchCenterPage> {
  final _auth=AuthService(); final _dispatch=DispatchService(); bool _busy=false;

  Future<bool> _allowed() async {
    final role=await _auth.role();
    if(['admin','owner','developer'].contains(role))return true;
    final c=await _auth.claims();
    final p=c['permissions'];
    return p is List && p.contains('manageDispatch');
  }

  LatLng? _location(Map<String,dynamic> d) {
    final raw=d['delivery_location']??d['deliveryLocation'];
    if(raw is Map) {
      final a=(raw['latitude'] as num?)?.toDouble(), b=(raw['longitude'] as num?)?.toDouble();
      if(a!=null&&b!=null)return LatLng(a,b);
    }
    if(raw is GeoPoint)return LatLng(raw.latitude,raw.longitude);
    final a=(d['latitude'] as num?)?.toDouble(), b=(d['longitude'] as num?)?.toDouble();
    return a!=null&&b!=null?LatLng(a,b):null;
  }

  Future<void> _setLocation(Map<String,dynamic> order) async {
    final current=_location(order);
    final point=await Navigator.push<LatLng>(context,MaterialPageRoute(builder:(_)=>LocationPickerPage(
      title:'تحديد موقع استلام الطلب',
      initialLatitude:current?.latitude,
      initialLongitude:current?.longitude,
    )));
    if(point==null)return;
    setState(()=>_busy=true);
    try {
      await _dispatch.setDeliveryLocation(orderId:order['id'].toString(),latitude:point.latitude,longitude:point.longitude);
      _message('تم حفظ موقع استلام الطلب على قاعدة الطلب.');
    } catch(e){_message('تعذر حفظ الموقع: $e');} finally{if(mounted)setState(()=>_busy=false);}
  }

  Future<void> _assign(Map<String,dynamic> order) async {
    final p=_location(order);
    if(p==null){_message('حدد موقع استلام الطلب أولاً.');return;}
    setState(()=>_busy=true);
    try {
      final candidate=await _dispatch.assignBestDriver(orderId:order['id'].toString(),latitude:p.latitude,longitude:p.longitude);
      _message(candidate==null?'لا يوجد مندوب معتمد ومتصل وبموقع صالح حالياً.':'تم تعيين المندوب '+candidate.driverId+' على الطلب ('+candidate.distanceKm.toStringAsFixed(2)+' كم).');
    } catch(e){_message('تعذر تعيين المندوب: $e');} finally{if(mounted)setState(()=>_busy=false);}
  }

  void _message(String s){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));}

  @override Widget build(BuildContext context)=>Directionality(textDirection:TextDirection.rtl,child:FutureBuilder<bool>(
    future:_allowed(),
    builder:(context,access){
      if(access.connectionState!=ConnectionState.done)return const Scaffold(body:Center(child:CircularProgressIndicator()));
      if(access.data!=true)return const Scaffold(body:Center(child:Text('مركز التوزيع مخصص للحسابات المخولة.')));
      return Scaffold(
        appBar:AppBar(title:const Text('التوزيع والمندوبون'),actions:[IconButton(tooltip:'خريطة المندوبين',onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const DriverFleetMapPage())),icon:const Icon(Icons.map_outlined))]),
        body:StreamBuilder<List<Map<String,dynamic>>>(
          stream:_dispatch.pendingOrdersStream(),
          builder:(context,snapshot){
            if(snapshot.hasError)return Center(child:Padding(padding:const EdgeInsets.all(24),child:Text('تعذر تحميل طابور التوزيع.\n${snapshot.error}')));
            if(snapshot.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator());
            final orders=snapshot.data??const <Map<String,dynamic>>[];
            if(orders.isEmpty)return const Center(child:Padding(padding:EdgeInsets.all(24),child:Text('لا توجد طلبات بانتظار التوزيع حالياً.')));
            return ListView.builder(padding:const EdgeInsets.all(16),itemCount:orders.length,itemBuilder:(context,i){
              final o=orders[i]; final p=_location(o); final id=o['id'].toString();
              return Card(margin:const EdgeInsets.only(bottom:12),child:ListTile(
                leading:CircleAvatar(child:Icon(p==null?Icons.location_off_outlined:Icons.route_outlined)),
                title:Text('طلب #'+id.substring(0,id.length>8?8:id.length),style:const TextStyle(fontWeight:FontWeight.w900)),
                subtitle:Text((o['address']??'—').toString()+'\n'+(p==null?'يحتاج تحديد الموقع':'موقع الاستلام جاهز')),
                isThreeLine:true,
                trailing:Wrap(spacing:4,children:[
                  IconButton(tooltip:'تحديد موقع الاستلام',onPressed:_busy?null:()=>_setLocation(o),icon:const Icon(Icons.edit_location_alt_outlined)),
                  FilledButton.icon(onPressed:_busy||p==null?null:()=>_assign(o),icon:const Icon(Icons.local_shipping_outlined),label:const Text('تعيين')),
                ]),
              );
            });
          },
        ),
      );
    },
  ));
}
