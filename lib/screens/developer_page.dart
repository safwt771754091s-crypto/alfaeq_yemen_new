import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';

class DeveloperPage extends StatefulWidget {
  const DeveloperPage({super.key});
  @override State<DeveloperPage> createState() => _DeveloperPageState();
}

class _DeveloperPageState extends State<DeveloperPage> {
  final _auth = AuthService();
  bool _allowed=false, _loading=true, _scanning=false;
  String _role='';
  Map<String,dynamic> _profile={};
  Map<String,int> _counts={};
  List<String> _findings=[];
  DateTime? _lastScan;

  @override void initState(){super.initState();_load();}
  Future<void> _writeAudit({required String action,required String result,Map<String,dynamic>? details}) async {
    final user=SupabaseService.client.auth.currentUser;if(user==null)return;
    try{await SupabaseService.client.from('audit_logs').insert({'actor_uid':user.id,'actor_email':user.email,'role':_role,'action':action,'result':result,'details':details??{},'source':'developer_center'});}catch(_){}
  }

  Future<void> _load() async {
    final user=SupabaseService.client.auth.currentUser;
    if(user==null){if(mounted)setState(()=>_loading=false);return;}
    try{
      final rows=await SupabaseService.client.from('users').select().eq('uid',user.id).limit(1);
      final data=rows.isEmpty?<String,dynamic>{}:Map<String,dynamic>.from(rows.first);
      final role=await _auth.role();
      final allowed=await _auth.canOpenDeveloperCenter();
      if(mounted)setState(()=>{_role=role,_profile=data,_allowed=allowed,_loading=false});
      if(allowed)await _writeAudit(action:'developer_center_access',result:'success');
    }catch(_){if(mounted)setState(()=>_loading=false);}
  }

  Future<void> _runSecurityScan() async {
    if(_scanning)return;
    setState(()=>_scanning=true);
    final findings=<String>[],counts=<String,int>{};
    try{
      final client=SupabaseService.client;
      final results=await Future.wait([
        client.from('users').select('uid,role').limit(200),
        client.from('stores').select('id,owner_id').limit(200),
        client.from('products').select('id,owner_id').limit(200),
        client.from('orders').select('id,customer_id').limit(200),
        client.from('payments').select('id,user_id').limit(200),
      ]);
      final users=results[0] as List,stores=results[1] as List,products=results[2] as List,orders=results[3] as List,payments=results[4] as List;
      counts.addAll({'users':users.length,'stores':stores.length,'products':products.length,'orders':orders.length,'payments':payments.length});
      final noRole=users.where((x)=>(x as Map)['role']==null).length;
      final noOwnerStores=stores.where((x)=>(x as Map)['owner_id']==null).length;
      final noOwnerProducts=products.where((x)=>(x as Map)['owner_id']==null).length;
      if(noRole>0)findings.add('يوجد $noRole مستخدم بلا role واضح في العينة.');
      if(noOwnerStores>0)findings.add('يوجد $noOwnerStores متجر بلا مالك واضح في العينة.');
      if(noOwnerProducts>0)findings.add('يوجد $noOwnerProducts منتج بلا مالك واضح في العينة.');
      if(findings.isEmpty)findings.add('لم يظهر خلل حرج في العينة المفحوصة؛ الحد 200 سجل لكل مجموعة.');
      final uid=SupabaseService.client.auth.currentUser?.id;
      if(uid!=null){
        await client.from('security_reports').insert({'actor_uid':uid,'role':_role,'findings':findings,'counts':counts,'type':'automated_security_scan'});
        await _writeAudit(action:'security_scan',result:'success',details:{'findingsCount':findings.length,'counts':counts});
      }
    }catch(e){findings.add('تعذر إكمال الفحص: $e');await _writeAudit(action:'security_scan',result:'failed',details:{'error':e.toString()});}
    if(!mounted)return;
    setState(()=>{_findings=findings,_counts=counts,_lastScan=DateTime.now(),_scanning=false});
  }

  @override Widget build(BuildContext context){
    if(_loading)return const Scaffold(body:Center(child:CircularProgressIndicator()));
    if(!_allowed)return const Directionality(textDirection:TextDirection.rtl,child:Scaffold(body:Center(child:Padding(padding:EdgeInsets.all(24),child:Text('هذه المنطقة محمية. لا توجد لديك صلاحية المطور.',textAlign:TextAlign.center)))));
    return Directionality(textDirection:TextDirection.rtl,child:Scaffold(
      appBar:AppBar(title:const Text('مركز المطور والأمن',style:TextStyle(fontWeight:FontWeight.w900)),actions:[IconButton(onPressed:_load,icon:const Icon(Icons.refresh))]),
      body:ListView(padding:const EdgeInsets.all(16),children:[
        _heroCard(),const SizedBox(height:14),_sectionTitle('🛡️ حماية المنصة'),
        _securityCard('Supabase Auth + RLS','مفعلة — الصلاحيات مفروضة على الخادم',Icons.lock_outline),
        _securityCard('صلاحية الحساب',_role,Icons.admin_panel_settings_outlined),
        const SizedBox(height:14),_sectionTitle('🤖 الفحص الحقيقي'),
        Card(child:ListTile(leading:const Icon(Icons.radar_outlined),title:const Text('فحص أمني للبيانات',style:TextStyle(fontWeight:FontWeight.w900)),subtitle:Text(_lastScan==null?'يفحص المستخدمين والمتاجر والمنتجات والطلبات والمدفوعات الحقيقية.':'آخر فحص: ${_lastScan!.toLocal()}'),trailing:FilledButton.icon(onPressed:_scanning?null:_runSecurityScan,icon:_scanning?const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.play_arrow),label:const Text('فحص')))),
        if(_counts.isNotEmpty)_dataOverview(),if(_findings.isNotEmpty)_findingsCard(),
        const SizedBox(height:14),_sectionTitle('👤 الحساب الحالي'),
        _DevCard(icon:Icons.person,title:_profile['name']?.toString()??'حساب المستخدم',subtitle:'UID: ${SupabaseService.client.auth.currentUser?.id??'-'}\nالبريد: ${SupabaseService.client.auth.currentUser?.email??'-'}\nالدور: $_role'),
      ]),
    ));
  }

  Widget _heroCard()=>Card(color:const Color(0xFF0B6E4F),child:const Padding(padding:EdgeInsets.all(20),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(Icons.shield_outlined,color:Colors.white,size:38),SizedBox(height:10),Text('مركز المطور الحقيقي',style:TextStyle(color:Colors.white,fontSize:24,fontWeight:FontWeight.w900)),SizedBox(height:6),Text('تطوير • فحص • أتمتة • أمن • Supabase',style:TextStyle(color:Colors.white70))])));
  Widget _sectionTitle(String t)=>Padding(padding:const EdgeInsets.only(bottom:8),child:Text(t,style:const TextStyle(fontSize:18,fontWeight:FontWeight.w900)));
  Widget _securityCard(String t,String v,IconData i)=>Card(child:ListTile(leading:Icon(i),title:Text(t,style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text(v)));
  Widget _dataOverview()=>Card(child:Padding(padding:const EdgeInsets.all(16),child:Wrap(spacing:10,runSpacing:10,children:_counts.entries.map((e)=>Chip(label:Text('${e.key}: ${e.value}'))).toList())));
  Widget _findingsCard()=>Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('نتائج الفحص',style:TextStyle(fontWeight:FontWeight.w900,fontSize:17)),const SizedBox(height:8),..._findings.map((x)=>Padding(padding:const EdgeInsets.symmetric(vertical:4),child:Text('• $x')))])));
}

class _DevCard extends StatelessWidget{
 final IconData icon;final String title;final String subtitle;
 const _DevCard({required this.icon,required this.title,required this.subtitle});
 @override Widget build(BuildContext context)=>Card(child:ListTile(leading:Icon(icon),title:Text(title,style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text(subtitle)));
}
