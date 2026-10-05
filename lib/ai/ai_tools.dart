import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';

class AlfaeqAiToolRegistry {
  static const _max=8;
  final SupabaseClient _db;
  AlfaeqAiToolRegistry({SupabaseClient? client}):_db=client??SupabaseService.client;

  Future<Map<String,Object?>> execute(String name,Map<String,Object?> args,{required Future<void> Function({required String action,required String result,Map<String,dynamic>? details}) audit,bool userConfirmed=false}) async {
    try {
      switch(name){
        case 'search_catalog': return await _search(args);
        case 'get_my_orders': return await _orders(args);
        case 'get_my_order': return await _order(args);
        case 'get_my_account_summary': return await _account();
        case 'get_my_cart': return await _cart();
        case 'add_to_cart': return await _cartChange(args,'add',userConfirmed);
        case 'update_cart_item': return await _cartChange(args,'update',userConfirmed);
        case 'remove_from_cart': return await _cartChange(args,'remove',userConfirmed);
        case 'create_order_draft': return await _createOrder(args,userConfirmed);
        default:return {'ok':false,'error':'الأداة غير مسموحة.'};
      }
    }catch(e){await audit(action:'ai_tool_$name',result:'failed',details:{'error':e.toString()});return {'ok':false,'error':'تعذر تنفيذ الأداة بأمان.'};}
  }

  Future<Map<String,Object?>> _search(Map<String,Object?> a) async {
    final raw=(a['query']??'').toString().trim();
    if(raw.isEmpty)return {'ok':false,'error':'أدخل ما تريد البحث عنه.'};
    // PostgREST or() splits on commas and treats parentheses as grouping, so
    // strip those (and wildcards) to keep the filter well-formed.
    final q=raw.replaceAll(RegExp(r'[,()%*]'),' ').replaceAll(RegExp(r'\s+'),' ').trim();
    if(q.isEmpty)return {'ok':false,'error':'أدخل ما تريد البحث عنه.'};
    final products=<Map<String,Object?>>[],stores=<Map<String,Object?>>[];
    final rows=await _db.from('products').select().eq('status','active')
        .or('name.ilike.%$q%,description.ilike.%$q%,metadata->>barcode.ilike.%$q%')
        .order('name').limit(_max);
    for(final rawRow in rows){final d=Map<String,dynamic>.from(rawRow);products.add({'id':d['id'],'name':d['name'],'price':d['price'],'currency':d['currency']??'YER','storeId':d['store_id'],'available':d['stock_base']});}
    final ss=await _db.from('stores').select().inFilter('status',['approved','active'])
        .or('name.ilike.%$q%,address.ilike.%$q%').order('name').limit(_max);
    for(final rawRow in ss){final d=Map<String,dynamic>.from(rawRow);stores.add({'id':d['id'],'name':d['name'],'address':d['address']});}
    return {'ok':true,'products':products,'stores':stores};
  }

  Future<Map<String,Object?>> _orders(Map<String,Object?> a) async {
    final u=_db.auth.currentUser;if(u==null)return {'ok':false,'error':'يجب تسجيل الدخول أولاً.'};
    final status=(a['status']??'all').toString();final rows=await _db.from('orders').select('id,status,total,currency,created_at').eq('customer_id',u.id).order('created_at',ascending:false).limit(20);
    return {'ok':true,'orders':rows.where((r)=>status=='all'||r['status']==status).take(_max).map((r)=>{'id':r['id'],'status':r['status'],'total':r['total'],'currency':r['currency']??'YER','createdAt':r['created_at']}).toList()};
  }

  Future<Map<String,Object?>> _order(Map<String,Object?> a) async {
    final u=_db.auth.currentUser;if(u==null)return {'ok':false,'error':'يجب تسجيل الدخول أولاً.'};final id=(a['orderId']??'').toString();
    final rows=await _db.from('orders').select().eq('id',id).eq('customer_id',u.id).limit(1);if(rows.isEmpty)return {'ok':false,'error':'الطلب غير موجود.'};return {'ok':true,'order':Map<String,Object?>.from(rows.first)};
  }

  Future<Map<String,Object?>> _account() async {
    final u=_db.auth.currentUser;if(u==null)return {'ok':false,'error':'يجب تسجيل الدخول أولاً.'};final row=await _db.from('users').select('uid,name,email,role').eq('uid',u.id).maybeSingle();return {'ok':true,'account':{...Map<String,dynamic>.from(row??{}),'emailVerified':u.emailConfirmedAt!=null}};
  }

  Future<Map<String,Object?>> _cart() async {
    final u=_db.auth.currentUser;if(u==null)return {'ok':false,'error':'يجب تسجيل الدخول أولاً.'};final row=await _db.from('carts').select('items,metadata').eq('uid',u.id).maybeSingle();final raw=row?['items'];return {'ok':true,'items':raw is List?raw:const [],'currency':row?['metadata'] is Map?((row!['metadata'] as Map)['currency']??'YER'):'YER'};
  }

  Future<Map<String,Object?>> _cartChange(Map<String,Object?> a,String action,bool confirmed) async {
    if(!confirmed)return {'ok':false,'permission':'confirmation_required','error':'ينتظر تأكيد المستخدم.'};
    final u=_db.auth.currentUser;if(u==null)return {'ok':false,'error':'يجب تسجيل الدخول أولاً.'};final id=(a['productId']??'').toString();final qty=(a['quantity'] as num?)?.toInt();
    final row=await _db.from('carts').select('items').eq('uid',u.id).maybeSingle();final raw=row?['items'];final items=List<Map<String,dynamic>>.from((raw is List?raw:const []).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)));
    if(action=='add'){final pRows=await _db.from('products').select('id,name,price,currency,store_id,stock_base').eq('id',id).eq('status','active').limit(1);if(pRows.isEmpty)return {'ok':false,'error':'المنتج غير متاح.'};final p=Map<String,dynamic>.from(pRows.first);final stock=(p['stock_base'] as num?)?.toDouble()??0;final add=qty??0;final i=items.indexWhere((e)=>e['productId']==id);final old=i<0?0:((items[i]['quantity'] as num?)?.toInt()??0);final next=old+add;if(add<1||next>100||next>stock)return {'ok':false,'error':'الكمية تتجاوز المخزون أو الحد المسموح.'};final item={'productId':id,'name':p['name'],'quantity':next,'price':p['price'],'currency':p['currency']??'YER','storeId':p['store_id']};if(i<0)items.add(item);else items[i]=item;}
    else if(action=='update'){final i=items.indexWhere((e)=>e['productId']==id);if(i<0||qty==null||qty<1||qty>100)return {'ok':false,'error':'عنصر السلة غير صالح.'};items[i]['quantity']=qty;}
    else {final before=items.length;items.removeWhere((e)=>e['productId']==id);if(before==items.length)return {'ok':false,'error':'المنتج غير موجود في السلة.'};}
    await _db.from('carts').upsert({'uid':u.id,'owner_id':u.id,'items':items,'updated_at':DateTime.now().toUtc().toIso8601String()},onConflict:'uid');return {'ok':true,'action':action,'items':items};
  }

  Future<Map<String,Object?>> _createOrder(Map<String,Object?> a,bool confirmed) async {
    if(!confirmed)return {'ok':false,'permission':'confirmation_required','error':'ينتظر تأكيد المستخدم.'};final u=_db.auth.currentUser;if(u==null)return {'ok':false,'error':'يجب تسجيل الدخول أولاً.'};
    final raw=a['items'];final address=(a['address']??'').toString().trim();final payment=(a['paymentMethod']??'').toString();if(raw is! List||raw.isEmpty||address.isEmpty)return {'ok':false,'error':'بيانات الطلب غير مكتملة.'};
    final rpcItems=raw.whereType<Map>().map((e)=>{'product_id':e['productId'],'quantity':e['quantity']}).toList();final orderId=await _db.rpc('create_order',params:{'p_items':rpcItems,'p_address':address,'p_payment_method':payment});await _db.from('carts').delete().eq('uid',u.id);
    return {'ok':true,'orderId':orderId.toString(),'status':'pending','paymentProcessed':false,'message':'تم إنشاء الطلب عبر المعاملة الحقيقية في Supabase.'};
  }
}