import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';

/// أدوات ذكاء الفائق — Supabase فقط.
class AlfaeqAiToolRegistry {
  static const int _maxResults = 8;
  final SupabaseClient _client;

  AlfaeqAiToolRegistry({SupabaseClient? client}) : _client = client ?? SupabaseService.client;

  Future<Map<String,Object?>> execute(String name, Map<String,Object?> args,{
    required Future<void> Function({required String action,required String result,Map<String,dynamic>? details}) audit,
    bool userConfirmed=false,
  }) async {
    try {
      switch(name){
        case 'search_catalog': return await _searchCatalog(args);
        case 'get_my_orders': return await _getMyOrders(args);
        case 'get_my_order': return await _getMyOrder(args);
        case 'get_my_account_summary': return await _getMyAccountSummary();
        case 'get_security_summary': return await _getSecuritySummary(audit:audit);
        case 'get_my_cart': return await _getMyCart();
        case 'add_to_cart': return await _addToCart(args,userConfirmed:userConfirmed);
        case 'update_cart_item': return await _updateCartItem(args,userConfirmed:userConfirmed);
        case 'remove_from_cart': return await _removeFromCart(args,userConfirmed:userConfirmed);
        case 'create_order_draft': return await _createOrderDraft(args,userConfirmed:userConfirmed);
        default:return {'ok':false,'error':'الأداة غير مسموحة.'};
      }
    } catch(e) {
      await audit(action:'ai_tool_$name',result:'failed',details:{'error':e.toString()});
      return {'ok':false,'error':'تعذر تنفيذ الأداة بأمان.'};
    }
  }

  Future<Map<String,Object?>> _searchCatalog(Map<String,Object?> args) async {
    final q=(args['query']??'').toString().trim().toLowerCase();
    final type=(args['type']??'both').toString();
    if(q.isEmpty||q.length>80)return {'ok':false,'error':'عبارة البحث غير صالحة.'};
    final products=<Map<String,Object?>>[],stores=<Map<String,Object?>>[];
    if(type=='products'||type=='both'){
      final rows=await _client.from('products').select().eq('status','active').order('name').limit(80);
      for(final raw in rows){final d=Map<String,dynamic>.from(raw),name=(d['name']??'').toString(),cat=(d['section_id']??'').toString();if('$name $cat'.toLowerCase().contains(q)){products.add({'id':d['id'],'name':name,'category':cat,'price':d['price'],'currency':d['currency']??'YER','storeId':d['store_id'],'available':d['stock_base']});if(products.length>=_maxResults)break;}}
    }
    if(type=='stores'||type=='both'){
      final rows=await _client.from('stores').select().inFilter('status',['approved','active']).order('name').limit(80);
      for(final raw in rows){final d=Map<String,dynamic>.from(raw),name=(d['name']??'').toString(),cat=(d['section_id']??'').toString();if('$name $cat'.toLowerCase().contains(q)){stores.add({'id':d['id'],'name':name,'category':cat,'city':d['address'],'active':true});if(stores.length>=_maxResults)break;}}
    }
    return {'ok':true,'query':q,'products':products,'stores':stores,'resultCount':products.length+stores.length};
  }

  Future<Map<String,Object?>> _getMyOrders(Map<String,Object?> args) async {
    final u=_client.auth.currentUser;if(u==null)return {'ok':false,'error':'يجب تسجيل الدخول أولاً.'};
    final wanted=(args['status']??'all').toString();final out=<Map<String,Object?>>[];
    final rows=await _client.from('orders').select().eq('customer_id',u.id).order('created_at',ascending:false).limit(20);
    for(final raw in rows){final d=Map<String,dynamic>.from(raw),status=(d['status']??'').toString();if(wanted!='all'&&wanted!=status)continue;out.add({'id':d['id'],'status':status,'total':d['total'],'currency':d['currency']??'YER','createdAt':d['created_at'],'itemCount':d['items'] is List?(d['items'] as List).length:null});if(out.length>=_maxResults)break;}
    return {'ok':true,'orders':out,'resultCount':out.length};
  }

  Future<Map<String,Object?>> _getMyOrder(Map<String,Object?> args) async {
    final u=_client.auth.currentUser;if(u==null)return {'ok':false,'error':'يجب تسجيل الدخول أولاً.'};
    final id=(args['orderId']??'').toString().trim();if(id.isEmpty||id.length>128)return {'ok':false,'error':'رقم الطلب غير صالح.'};
    final rows=await _client.from('orders').select().eq('id',id).eq('customer_id',u.id).limit(1);
    if(rows.isEmpty)return {'ok':false,'error':'الطلب غير موجود.'};
    final d=Map<String,dynamic>.from(rows.first);
    return {'ok':true,'order':{'id':d['id'],'status':d['status'],'deliveryStatus':d['delivery_status'],'itemCount':d['items'] is List?(d['items'] as List).length:null,'total':d['total'],'currency':d['currency']??'YER','paymentMethod':d['payment_method'],'createdAt':d['created_at'],'updatedAt':d['updated_at']}};
  }

  Future<Map<String,Object?>> _getMyAccountSummary() async {
    final u=_client.auth.currentUser;if(u==null)return {'ok':false,'error':'يجب تسجيل الدخول أولاً.'};
    final rows=await _client.from('users').select().eq('uid',u.id).limit(1);final d=rows.isEmpty?<String,dynamic>{}:Map<String,dynamic>.from(rows.first);
    final meta=u.userMetadata ?? const <String,dynamic>{};
    return {'ok':true,'uid':u.id,'email':u.email,'displayName':d['name']??meta['full_name']??meta['name'],'role':d['role']??'customer','phoneVerified':u.phone!=null,'emailVerified':u.emailConfirmedAt!=null};
  }

  Future<Map<String,Object?>> _getSecuritySummary({required Future<void> Function({required String action,required String result,Map<String,dynamic>? details}) audit}) async {
    final u=_client.auth.currentUser;if(u==null)return {'ok':false,'error':'يجب تسجيل الدخول أولاً.'};
    final profile=await _client.from('users').select('role').eq('uid',u.id).limit(1);final role=profile.isEmpty?'':(profile.first['role']??'').toString();
    if(!{'owner','admin','developer'}.contains(role)){await audit(action:'ai_tool_get_security_summary',result:'denied',details:{'role':role});return {'ok':false,'error':'هذه الأداة متاحة للمستخدمين المصرح لهم فقط.'};}
    final logs=await _client.from('audit_logs').select('result,severity').order('created_at',ascending:false).limit(20);
    final failures=logs.where((x)=>x['result']=='failed').length,warnings=logs.where((x)=>x['severity']=='warning'||x['result']=='warning').length;
    await audit(action:'ai_tool_get_security_summary',result:'success',details:{'role':role});
    return {'ok':true,'role':role,'recentAuditEntries':logs.length,'recentFailures':failures,'recentWarnings':warnings,'scope':'ملخص أمني غير حساس فقط.'};
  }

  Future<Map<String,Object?>> _getMyCart() async {
    final u=_client.auth.currentUser;if(u==null)return {'ok':false,'error':'يجب تسجيل الدخول أولاً.'};
    final rows=await _client.from('carts').select().eq('uid',u.id).limit(1);
    if(rows.isEmpty)return {'ok':true,'items':<Map<String,Object?>>[],'itemCount':0,'total':0,'currency':'YER'};
    final d=Map<String,dynamic>.from(rows.first);final items=_normalizeCartItems(d['items']);
    return {'ok':true,'items':items,'itemCount':items.length,'total':_cartTotal(items),'currency':d['metadata'] is Map?((d['metadata'] as Map)['currency']??'YER'):'YER'};
  }

  Future<void> _saveCart(String uid,List<Map<String,Object?>> items,{String currency='YER'}) async {
    await _client.from('carts').upsert({'uid':uid,'owner_id':uid,'items':items,'metadata':{'currency':currency},'updated_at':DateTime.now().toUtc().toIso8601String()},onConflict:'uid');
  }

  Future<Map<String,Object?>> _addToCart(Map<String,Object?> args,{required bool userConfirmed}) async {
    if(!userConfirmed)return {'ok':false,'error':'ينتظر تأكيد المستخدم.','permission':'confirmation_required'};
    final u=_client.auth.currentUser;if(u==null)return {'ok':false,'error':'يجب تسجيل الدخول أولاً.'};
    final id=(args['productId']??'').toString().trim(),qty=(args['quantity'] as num?)?.toInt()??0;
    if(id.isEmpty||qty<1||qty>100)return {'ok':false,'error':'بيانات السلة غير صالحة.'};
    final rows=await _client.from('products').select().eq('id',id).eq('status','active').limit(1);if(rows.isEmpty)return {'ok':false,'error':'المنتج غير موجود أو غير متاح.'};
    final p=Map<String,dynamic>.from(rows.first),stock=(p['stock_base'] as num?)?.toDouble()??0;if(stock<=0)return {'ok':false,'error':'المنتج غير متوفر.'};
    final cart=await _getMyCart();final items=List<Map<String,Object?>>.from((cart['items'] as List).map((e)=>Map<String,Object?>.from(e as Map)));
    final i=items.indexWhere((x)=>x['productId']==id),old=i<0?0:((items[i]['quantity'] as num?)?.toInt()??0),next=old+qty;if(next>100||next>stock)return {'ok':false,'error':'الكمية المطلوبة تتجاوز المخزون أو الحد المسموح.'};
    final item=<String,Object?>{'productId':id,'name':p['name']??'منتج','quantity':next,'price':p['price'],'currency':p['currency']??'YER','storeId':p['store_id']};
    if(i<0)items.add(item);else items[i]=item;await _saveCart(u.id,items,currency:(p['currency']??'YER').toString());
    return {'ok':true,'action':'added','productId':id,'quantity':next,'total':_cartTotal(items)};
  }

  Future<Map<String,Object?>> _updateCartItem(Map<String,Object?> args,{required bool userConfirmed}) async {
    if(!userConfirmed)return {'ok':false,'error':'ينتظر تأكيد المستخدم.','permission':'confirmation_required'};
    final id=(args['productId']??'').toString(),qty=(args['quantity'] as num?)?.toInt()??0;if(id.isEmpty||qty<1||qty>100)return {'ok':false,'error':'بيانات السلة غير صالحة.'};
    final cart=await _getMyCart();final items=List<Map<String,Object?>>.from((cart['items'] as List).map((e)=>Map<String,Object?>.from(e as Map)));final i=items.indexWhere((x)=>x['productId']==id);if(i<0)return {'ok':false,'error':'المنتج غير موجود في السلة.'};
    items[i]['quantity']=qty;final u=_client.auth.currentUser!;await _saveCart(u.id,items,currency:(cart['currency']??'YER').toString());return {'ok':true,'action':'updated','productId':id,'quantity':qty,'total':_cartTotal(items)};
  }

  Future<Map<String,Object?>> _removeFromCart(Map<String,Object?> args,{required bool userConfirmed}) async {
    if(!userConfirmed)return {'ok':false,'error':'ينتظر تأكيد المستخدم.','permission':'confirmation_required'};
    final u=_client.auth.currentUser;if(u==null)return {'ok':false,'error':'يجب تسجيل الدخول أولاً.'};final id=(args['productId']??'').toString();
    final cart=await _getMyCart();final items=List<Map<String,Object?>>.from((cart['items'] as List).map((e)=>Map<String,Object?>.from(e as Map)));final before=items.length;items.removeWhere((x)=>x['productId']==id);if(before==items.length)return {'ok':false,'error':'المنتج غير موجود في السلة.'};
    await _saveCart(u.id,items,currency:(cart['currency']??'YER').toString());return {'ok':true,'action':'removed','productId':id,'itemCount':items.length,'total':_cartTotal(items)};
  }

  List<Map<String,Object?>> _normalizeCartItems(dynamic raw){
    if(raw is! List)return <Map<String,Object?>>[];final out=<Map<String,Object?>>[];
    for(final v in raw.take(20)){if(v is! Map)continue;final id=v['productId']?.toString()??'',name=v['name']?.toString()??'',q=v['quantity'] is num?(v['quantity'] as num).toInt():0,p=v['price'];if(id.isEmpty||name.isEmpty||q<1||q>100||p is! num||p<0)continue;out.add({'productId':id,'name':name,'quantity':q,'price':p,'currency':v['currency']?.toString()??'YER','storeId':v['storeId']?.toString()??''});}
    return out;
  }

  num _cartTotal(List<Map<String,Object?>> items){num total=0;for(final x in items){final p=x['price'],q=x['quantity'];if(p is num&&q is int)total+=p*q;}return total;}

  Future<Map<String,Object?>> _createOrderDraft(Map<String,Object?> args,{required bool userConfirmed}) async {
    final u=_client.auth.currentUser;if(u==null)return {'ok':false,'error':'يجب تسجيل الدخول أولاً.'};if(!userConfirmed)return {'ok':false,'error':'ينتظر تأكيد المستخدم.','permission':'confirmation_required'};
    final raw=args['items'],address=(args['address']??'').toString().trim(),payment=(args['paymentMethod']??'').toString();
    const methods={'cash_on_delivery','al_kuraimi','cash_wallet','jeeb_wallet'};
    if(raw is! List||raw.isEmpty||raw.length>20||address.isEmpty||address.length>300||!methods.contains(payment))return {'ok':false,'error':'بيانات الطلب أو طريقة الدفع غير صالحة.'};
    final rpcItems=raw.whereType<Map>().map((x)=>{'product_id':x['productId'],'quantity':x['quantity']}).toList();
    final orderId=await _client.rpc('create_order',params:{'p_items':rpcItems,'p_address':address,'p_payment_method':payment});
    await _saveCart(u.id,[]);
    return {'ok':true,'orderId':orderId.toString(),'status':'pending','paymentProcessed':false,'message':'تم إنشاء الطلب المعلّق بعد التحقق من الخادم. لم تتم أي عملية دفع.'};
  }
}
