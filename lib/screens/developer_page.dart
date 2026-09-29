import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';

class DeveloperPage extends StatefulWidget {
  const DeveloperPage({super.key});
  @override State<DeveloperPage> createState()=>_DeveloperPageState();
}
class _DeveloperPageState extends State<DeveloperPage>{
  final _auth=AuthService();
  final _title=TextEditingController();
  final _description=TextEditingController();
  bool _allowed=false,_loading=true,_busy=false,_scanning=false;
  String _role='',_status='';
  Map<String,dynamic> _profile={};
  Map<String,int> _counts={};
  List<String> _findings=[];
  List<Map<String,dynamic>> _runs=[];

  @override void initState(){super.initState();_load();}
  @override void dispose(){_title.dispose();_description.dispose();super.dispose();}
  Future<void> _audit(String action,String result,{Map<String,dynamic>? details})async{
    final u=SupabaseService.client.auth.currentUser;if(u==null)return;
    try{await SupabaseService.client.from('audit_logs').insert({'actor_uid':u.id,'actor_email':u.email,'role':_role,'action':action,'result':result,'details':details??{},'source':'developer_center'});}catch(_){}
  }
  Future<void> _load()async{
    final u=SupabaseService.client.auth.currentUser;
    if(u==null){if(mounted)setState(()=>_loading=false);return;}
    try{
      final rows=await SupabaseService.client.from('users').select().eq('uid',u.id).limit(1);
      final data=rows.isEmpty?<String,dynamic>{}:Map<String,dynamic>.from(rows.first);
      final role=await _auth.role();final allowed=await _auth.canOpenDeveloperCenter();
      if(mounted)setState(()=>{_role=role,_profile=data,_allowed=allowed,_loading=false});
      if(allowed){await _audit('developer_center_access','success');await _loadRuns();}
    }catch(e){if(mounted)setState(()=>{_loading=false,_status='تعذر تحميل المركز: '+e.toString()});}
  }
  Future<void> _executeTask()async{
    final title=_title.text.trim(),description=_description.text.trim();
    if(title.isEmpty||description.isEmpty){setState(()=>_status='اكتب عنوان المهمة ووصفها.');return;}
    setState(()=>{_busy=true,_status='جارٍ بدء التنفيذ الآمن...'});
    try{
      final r=await SupabaseService.client.functions.invoke('developer-control',body:{'action':'execute_task','title':title,'description':description,'branch':'main'});
      if(r.status<200||r.status>=300)throw StateError(r.data.toString());
      await _audit('developer_execute_task','accepted',details:{'title':title});
      _title.clear();_description.clear();setState(()=>_status='تم قبول المهمة وبدء الوكيل الهندسي.');
      await _loadRuns();
    }catch(e){setState(()=>_status='تعذر بدء المهمة: '+e.toString());await _audit('developer_execute_task','failed',details:{'error':e.toString()});}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  Future<void> _loadRuns()async{
    try{
      final r=await SupabaseService.client.functions.invoke('developer-control',body:{'action':'status'});
      if(r.status>=200&&r.status<300&&r.data is Map){
        final raw=(r.data as Map)['runs'];
        if(raw is List)setState(()=>_runs=List<Map<String,dynamic>>.from(raw.whereType<Map>().map((e)=>Map<String,dynamic>.from(e))));
      }
    }catch(_){}
  }
  Future<void> _runAutomation() async {
    setState(()=>_status='جارٍ تشغيل عامل أتمتة الفائق...');
    try {
      final r=await SupabaseService.client.functions.invoke('developer-control',body:{'action':'run_automation_worker'});
      if(r.status<200||r.status>=300)throw StateError(r.data.toString());
      setState(()=>_status='تم تشغيل عامل الأتمتة واستلام النتيجة من Supabase.');
      await _audit('automation_worker_run','accepted');
    } catch(e) {
      setState(()=>_status='تعذر تشغيل الأتمتة: '+e.toString());
      await _audit('automation_worker_run','failed',details:{'error':e.toString()});
    }
  }

  Future<void> _scan()async{
    if(_scanning)return;setState(()=>_scanning=true);
    final findings=<String>[],counts=<String,int>{};
    try{
      final c=SupabaseService.client;
      final rs=await Future.wait([c.from('users').select('uid,role').limit(200),c.from('stores').select('id,owner_id').limit(200),c.from('products').select('id,owner_id').limit(200),c.from('orders').select('id,customer_id').limit(200),c.from('payments').select('id,user_id').limit(200)]);
      final users=rs[0] as List,stores=rs[1] as List,products=rs[2] as List,orders=rs[3] as List,payments=rs[4] as List;
      counts.addAll({'users':users.length,'stores':stores.length,'products':products.length,'orders':orders.length,'payments':payments.length});
      if(users.any((x)=>(x as Map)['role']==null))findings.add('يوجد مستخدم بلا role واضح في العينة.');
      if(stores.any((x)=>(x as Map)['owner_id']==null))findings.add('يوجد متجر بلا مالك واضح في العينة.');
      if(products.any((x)=>(x as Map)['owner_id']==null))findings.add('يوجد منتج بلا مالك واضح في العينة.');
      if(findings.isEmpty)findings.add('لم يظهر خلل حرج في العينة المفحوصة.');
      final uid=c.auth.currentUser?.id;if(uid!=null)await c.from('security_reports').insert({'actor_uid':uid,'role':_role,'findings':findings,'counts':counts,'type':'automated_security_scan'});
      await _audit('security_scan','success',details:{'counts':counts});
    }catch(e){findings.add('تعذر الفحص: '+e.toString());}
    if(mounted)setState(()=>{_findings=findings,_counts=counts,_scanning=false});
  }
  @override Widget build(BuildContext context){
    if(_loading)return const Scaffold(body:Center(child:CircularProgressIndicator()));
    if(!_allowed)return const Directionality(textDirection:TextDirection.rtl,child:Scaffold(body:Center(child:Padding(padding:EdgeInsets.all(24),child:Text('هذه المنطقة محمية.',textAlign:TextAlign.center)))));
    return Directionality(textDirection:TextDirection.rtl,child:Scaffold(
      appBar:AppBar(title:const Text('مطور الفائق — مركز المالك',style:TextStyle(fontWeight:FontWeight.w900)),actions:[IconButton(onPressed:_load,icon:const Icon(Icons.refresh))]),
      body:ListView(padding:const EdgeInsets.all(16),children:[
        Card(color:const Color(0xFF0B6E4F),child:const Padding(padding:EdgeInsets.all(20),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(Icons.engineering,color:Colors.white,size:38),SizedBox(height:8),Text('مركز تنفيذ الفائق',style:TextStyle(color:Colors.white,fontSize:24,fontWeight:FontWeight.w900)),SizedBox(height:6),Text('بناء • صيانة • تطوير • أتمتة • أمن',style:TextStyle(color:Colors.white70))]))),
        const SizedBox(height:16),
        const Text('تنفيذ بناء أو تطوير',style:TextStyle(fontSize:19,fontWeight:FontWeight.w900)),
        const SizedBox(height:8),
        TextField(controller:_title,decoration:const InputDecoration(labelText:'عنوان المهمة',border:OutlineInputBorder())),
        const SizedBox(height:8),
        TextField(controller:_description,minLines:4,maxLines:8,decoration:const InputDecoration(labelText:'وصف ما تريد تنفيذه أو إصلاحه',border:OutlineInputBorder())),
        const SizedBox(height:8),
        FilledButton.icon(onPressed:_busy?null:_executeTask,icon:_busy?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.play_arrow),label:const Text('تنفيذ الآن')),
        if(_status.isNotEmpty)Padding(padding:const EdgeInsets.only(top:8),child:Text(_status)),
        const SizedBox(height:18),
        const Text('جلسات التنفيذ',style:TextStyle(fontSize:19,fontWeight:FontWeight.w900)),
        if(_runs.isEmpty)const Card(child:ListTile(title:Text('لا توجد جلسات مسجلة بعد.'))),
        ..._runs.take(10).map((r)=>Card(child:ListTile(leading:Icon(r['status']=='failed'?Icons.error_outline:Icons.engineering_outlined),title:Text((r['provider']??'agent').toString()+' • '+(r['status']??'unknown').toString()),subtitle:Text('Task: '+(r['task_id']??'-').toString()+'\n'+(r['repository']??'').toString()+' @ '+(r['branch']??'').toString())))),
        const SizedBox(height:18),
        const Text('أتمتة الفائق داخل التطبيق',style:TextStyle(fontSize:19,fontWeight:FontWeight.w900)),
        const SizedBox(height:8),
        Card(child:ListTile(
          leading:const Icon(Icons.account_tree_outlined),
          title:const Text('تشغيل عامل الأتمتة'),
          subtitle:const Text('معالجة Event Inbox وإرسال الأحداث إلى n8n عبر طبقة Supabase.'),
          trailing:FilledButton.icon(onPressed:_busy?null:_runAutomation,icon:const Icon(Icons.play_arrow),label:const Text('تشغيل')),
        )),
        const SizedBox(height:18),
        const Text('الفحص والأمان',style:TextStyle(fontSize:19,fontWeight:FontWeight.w900)),
        Card(child:ListTile(title:const Text('Supabase Auth + RLS'),subtitle:Text('الدور الحالي: '+_role))),
        Card(child:ListTile(title:const Text('الفحص الأمني الحقيقي'),subtitle:Text(_counts.isEmpty?'فحص المستخدمين والمتاجر والمنتجات والطلبات والمدفوعات.':'users: '+(_counts['users']??0).toString()+' • stores: '+(_counts['stores']??0).toString()+' • products: '+(_counts['products']??0).toString()+' • orders: '+(_counts['orders']??0).toString()),trailing:FilledButton(onPressed:_scanning?null:_scan,child:Text(_scanning?'...':'فحص')))),
        ..._findings.map((x)=>Padding(padding:const EdgeInsets.symmetric(vertical:4),child:Text('• '+x))),
        const SizedBox(height:12),
        Card(child:ListTile(leading:const Icon(Icons.person),title:Text(_profile['name']?.toString()??'المالك/المطور'),subtitle:Text('UID: '+(SupabaseService.client.auth.currentUser?.id??'-')+'\nالدور: '+_role)))
      ]),
    ));
  }
}