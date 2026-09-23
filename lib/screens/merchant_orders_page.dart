import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';

class MerchantOrdersPage extends StatefulWidget {
  const MerchantOrdersPage({super.key});
  @override State<MerchantOrdersPage> createState()=>_MerchantOrdersPageState();
}
class _MerchantOrdersPageState extends State<MerchantOrdersPage>{
  final _auth=AuthService(); bool _busy=false;
  Future<bool> _allowed() async { final r=await _auth.role(); return r=='merchant'||r=='admin'||r=='owner'||r=='developer'; }
  Future<List<Map<String,dynamic>>> _orders(String uid) async {
    final stores=await SupabaseService.client.from('stores').select('id').eq('owner_id',uid);
    final ids=List<Map<String,dynamic>>.from(stores).map((x)=>'${x['id']}').toList();
    if(ids.isEmpty)return [];
    final rows=await SupabaseService.client.from('orders').select().overlaps('merchant_ids',ids).order('created_at',ascending:false).limit(100);
    return List<Map<String,dynamic>>.from(rows);
  }
  Future<void> _setStatus(Map<String,dynamic> o,String status) async {
    if(FirebaseAuth.instance.currentUser==null||!await _allowed())return;
    setState(()=>_busy=true);
    try{
      await SupabaseService.client.rpc('transition_order',params:{'p_order_id':'${o['id']}','p_status':status,'p_delivery_status':status=='ready_for_pickup'?'awaiting_assignment':null});
      _message('تم تحديث حالة الطلب.'); if(mounted)setState((){});
    }catch(e){_message('تعذر تحديث الطلب: ${e}');}finally{if(mounted)setState(()=>_busy=false);}
  }
  @override Widget build(BuildContext context)=>Directionality(textDirection:TextDirection.rtl,child:FutureBuilder<bool>(
    future:_allowed(),builder:(context,a){
      if(a.connectionState==ConnectionState.waiting)return const Scaffold(body:Center(child:CircularProgressIndicator()));
      if(a.data!=true)return const Scaffold(body:Center(child:Text('مركز الطلبات مخصص للحسابات التجارية المعتمدة.')));
      final u=FirebaseAuth.instance.currentUser;if(u==null)return const Scaffold(body:Center(child:Text('يجب تسجيل الدخول.')));
      return Scaffold(appBar:AppBar(title:const Text('طلبات التاجر')),body:FutureBuilder<List<Map<String,dynamic>>>(
        future:_orders(u.uid),builder:(context,s){
          if(s.hasError)return Center(child:Text('تعذر تحميل الطلبات.\n${s.error}'));
          if(s.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator());
          final os=s.data??const <Map<String,dynamic>>[];if(os.isEmpty)return const Center(child:Text('لا توجد طلبات مرتبطة بمتجرك حالياً.'));
          return RefreshIndicator(onRefresh:()async{setState((){});},child:ListView.builder(padding:const EdgeInsets.all(16),itemCount:os.length,itemBuilder:(c,i)=>_OrderCard(order:os[i],busy:_busy,onStatus:_setStatus));
        }),);
    }));
  void _message(String t){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(t)));}
}
class _OrderCard extends StatelessWidget{
 final Map<String,dynamic> order;final bool busy;final Future<void> Function(Map<String,dynamic>,String) onStatus;
 const _OrderCard({required this.order,required this.busy,required this.onStatus});
 @override Widget build(BuildContext context){
  final id='${order['id']??''}',status='${order['status']??'pending'}',delivery='${order['delivery_status']??'awaiting_assignment'}',items=order['items'] is List?List<dynamic>.from(order['items'] as List):const <dynamic>[];
  return Card(elevation:0,margin:const EdgeInsets.only(bottom:12),child:ExpansionTile(
   leading:CircleAvatar(child:Icon(_icon(status))),title:Text('طلب #${id.length>8?id.substring(0,8):id}',style:const TextStyle(fontWeight:FontWeight.w900)),subtitle:Text('$status • $delivery'),
   children:[Padding(padding:const EdgeInsets.fromLTRB(16,0,16,16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Text('${order['total']??0} ${order['currency']??'YER'}',style:const TextStyle(fontSize:17,fontWeight:FontWeight.w900)),
    Text('عدد الأصناف: ${items.length}'),Text('العنوان: ${order['address']??'—'}'),Text('الدفع: ${order['payment_method']??'—'}'),const SizedBox(height:8),
    ...items.whereType<Map>().map((x)=>ListTile(dense:true,contentPadding:EdgeInsets.zero,title:Text('${x['name']??'صنف'}'),subtitle:Text('الكمية: ${x['quantity']??0}'),trailing:Text('${x['line_total']??x['unit_price']??0}'))),
    Wrap(spacing:8,children:[
      if(status=='pending')FilledButton.icon(onPressed:busy?null:()=>onStatus(order,'accepted'),icon:const Icon(Icons.check),label:const Text('قبول')),
      if(status=='accepted')FilledButton.icon(onPressed:busy?null:()=>onStatus(order,'preparing'),icon:const Icon(Icons.inventory_2_outlined),label:const Text('بدء التجهيز')),
      if(status=='preparing')FilledButton.icon(onPressed:busy?null:()=>onStatus(order,'ready_for_pickup'),icon:const Icon(Icons.local_shipping_outlined),label:const Text('جاهز للاستلام')),
      if(status=='pending'||status=='accepted')OutlinedButton.icon(onPressed:busy?null:()=>onStatus(order,'cancelled'),icon:const Icon(Icons.close),label:const Text('إلغاء'))
    ])
   ]))]));}
 static IconData _icon(String s)=>switch(s){'accepted'=>Icons.check_circle_outline,'preparing'=>Icons.inventory_2_outlined,'ready_for_pickup'=>Icons.local_shipping_outlined,'cancelled'=>Icons.cancel_outlined,_=>Icons.pending_actions_outlined};
}