import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/unsloth_ai_service.dart';
import '../services/supabase_service.dart';
import 'ai_permission_gateway.dart';
import 'ai_tools.dart';
import 'alfaeq_prompt_library.dart';

class AlfaeqAiService {
  final AlfaeqAiToolRegistry _tools;
  final AlfaeqAiPermissionGateway _permissions;
  final UnslothAiService _ai;
  final SupabaseClient _client;
  final List<Map<String,dynamic>> _messages=[];
  _PendingAiAction? _pending;
  AlfaeqAiService({AlfaeqAiToolRegistry? tools,AlfaeqAiPermissionGateway? permissions,UnslothAiService? ai,SupabaseClient? client})
      :_tools=tools??AlfaeqAiToolRegistry(),_permissions=permissions??AlfaeqAiPermissionGateway(),_ai=ai??UnslothAiService(),_client=client??SupabaseService.client{resetConversation();}
  bool get hasPendingConfirmation=>_pending!=null;
  String get pendingActionDescription=>_pending==null?'':'العملية: '+_pending!.name+'\nالبيانات: '+jsonEncode(_pending!.args);
  void resetConversation(){_messages..clear()..add({'role':'system','content':AlfaeqPromptLibrary.baseSystem});_pending=null;}
  Future<void> _audit({required String action,required String result,Map<String,dynamic>? details}) async {final u=_client.auth.currentUser;if(u==null)return;try{await _client.from('ai_tool_audit_logs').insert({'actor_uid':u.id,'tool_name':action.replaceFirst('ai_tool_',''),'result':result,'confirmed':details?['confirmed']==true,'details':details??{}});}catch(_){}}
  Future<Map<String,Object?>> _execute(String name,Map<String,Object?> args,{bool confirmed=false}) async {final d=await _permissions.authorize(name,userConfirmed:confirmed);if(!d.allowed)return {'ok':false,'error':d.message,'permission':d.requiresConfirmation?'confirmation_required':'denied'};return _tools.execute(name,args,audit:_audit,userConfirmed:confirmed);}
  Future<String> _run() async {for(var round=0;round<6;round++){final data=await _ai.chatCompletion(messages:List<Map<String,dynamic>>.from(_messages),tools:_schemas,maxTokens:1400);final assistant=_ai.extractAssistantMessage(data);final calls=_ai.extractToolCalls(data);_messages.add(assistant);if(calls.isEmpty){final text=_ai.extractContent(data);return text.isEmpty?'لم يصل رد نصي من خدمة الذكاء.':text;}for(final call in calls){final fn=call['function'];if(fn is! Map)continue;final name=(fn['name']??'').toString();Map<String,dynamic> args={};try{final raw=fn['arguments'];final decoded=raw is String?jsonDecode(raw):raw;if(decoded is Map)args=Map<String,dynamic>.from(decoded);}catch(_){}final result=await _execute(name,Map<String,Object?>.from(args));if(result['permission']=='confirmation_required'){_pending=_PendingAiAction(name:name,args:Map<String,Object?>.from(args),id:(call['id']??'').toString());return 'هذه العملية تحتاج تأكيدك. راجع التفاصيل ثم اضغط «تأكيد التنفيذ».';}_messages.add({'role':'tool','tool_call_id':call['id']??'','name':name,'content':jsonEncode(result)});}}return 'توقفت العملية بعد الحد الآمن للاستدعاءات.';}
  Future<String> sendMessage(String text) async {final t=text.trim();if(t.isEmpty)return '';_messages.add({'role':'user','content':t});try{return await _run();}catch(e){return 'تعذر الاتصال بخدمة ذكاء الفائق يمن حالياً. '+e.toString();}}
  Future<String> confirmPendingAction() async {final p=_pending;if(p==null)return 'لا توجد عملية معلقة.';_pending=null;final result=await _execute(p.name,p.args,confirmed:true);_messages.add({'role':'tool','tool_call_id':p.id,'name':p.name,'content':jsonEncode(result)});try{return await _run();}catch(_){return result['message']?.toString()??'تم التنفيذ لكن تعذر الحصول على الرد النهائي.';}}
  void cancelPendingAction()=>_pending=null;
  List<Map<String,dynamic>> get _schemas=>[
    _tool('search_catalog','البحث الحقيقي في المنتجات والمتاجر.',{'query':{'type':'string'},'type':{'type':'string','enum':['products','stores','both']}},['query']),
    _tool('get_my_orders','قراءة طلبات المستخدم الحالية.',{'status':{'type':'string','enum':['all','pending','confirmed','preparing','shipped','delivered','cancelled']}}),
    _tool('get_my_order','قراءة طلب محدد للمستخدم.',{'orderId':{'type':'string'}},['orderId']),
    _tool('get_my_account_summary','ملخص حساب المستخدم.',{}),
    _tool('get_my_cart','قراءة السلة الحالية.',{}),
    _tool('add_to_cart','إضافة منتج للسلة بعد التأكيد.',{'productId':{'type':'string'},'quantity':{'type':'integer','minimum':1,'maximum':100}},['productId','quantity']),
    _tool('update_cart_item','تعديل كمية منتج بعد التأكيد.',{'productId':{'type':'string'},'quantity':{'type':'integer','minimum':1,'maximum':100}},['productId','quantity']),
    _tool('remove_from_cart','حذف منتج من السلة بعد التأكيد.',{'productId':{'type':'string'}},['productId']),
    _tool('create_order_draft','إنشاء طلب حقيقي معلّق بعد التأكيد، دون تحصيل الدفع.',{'items':{'type':'array','minItems':1,'maxItems':20,'items':{'type':'object','properties':{'productId':{'type':'string'},'quantity':{'type':'integer','minimum':1,'maximum':100},'name':{'type':'string'}},'required':['productId','quantity']}},'address':{'type':'string'},'paymentMethod':{'type':'string','enum':['cash_on_delivery','al_kuraimi','cash_wallet','jeeb_wallet']}},['items','address','paymentMethod'])
  ];
  Map<String,dynamic> _tool(String name,String description,Map<String,dynamic> properties,[List<String> required=const[]])=>{'type':'function','function':{'name':name,'description':description,'parameters':{'type':'object','properties':properties,'required':required,'additionalProperties':false}}};
}
class _PendingAiAction{final String name;final Map<String,Object?> args;final String id;_PendingAiAction({required this.name,required this.args,required this.id});}