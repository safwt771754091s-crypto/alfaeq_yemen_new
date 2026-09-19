import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

class WhatsAppAutomationPage extends StatefulWidget {
  const WhatsAppAutomationPage({super.key});
  @override State<WhatsAppAutomationPage> createState() => _WhatsAppAutomationPageState();
}

class _WhatsAppAutomationPageState extends State<WhatsAppAutomationPage> {
  final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');
  bool _loading = false;

  Future<Map<String, dynamic>> _load() async {
    final results = await Future.wait([
      _functions.httpsCallable('listWhatsAppConnections').call({}),
      _functions.httpsCallable('listWhatsAppProductImports').call({'limit': 50}),
    ]);
    final connections = ((results[0].data as Map?)?['connections'] as List? ?? []).map((e) => Map<String,dynamic>.from(e as Map)).toList();
    final imports = ((results[1].data as Map?)?['imports'] as List? ?? []).map((e) => Map<String,dynamic>.from(e as Map)).toList();
    return {'connections': connections, 'imports': imports};
  }

  Future<void> _bindNumber() async {
    final phone=TextEditingController(); final store=TextEditingController(); final merchant=TextEditingController();
    bool auto=false;
    final ok=await showDialog<bool>(context:context,builder:(context)=>StatefulBuilder(builder:(context,setLocal)=>AlertDialog(
      title: const Text('ربط رقم واتساب بمتجر'),
      content: SingleChildScrollView(child:Column(children:[
        TextField(controller:phone,keyboardType:TextInputType.phone,decoration:const InputDecoration(labelText:'رقم واتساب بصيغة دولية بدون +')),
        TextField(controller:store,decoration:const InputDecoration(labelText:'معرّف المتجر Store ID')),
        TextField(controller:merchant,decoration:const InputDecoration(labelText:'معرّف مالك المتجر Merchant UID')),
        SwitchListTile(value:auto,onChanged:(v)=>setLocal(()=>auto=v),title:const Text('نشر تلقائي للمنتج'),subtitle:const Text('اتركه مغلقًا في البداية للمراجعة الآمنة.'),contentPadding:EdgeInsets.zero),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('حفظ الربط'))],
    )));
    if(ok!=true)return;
    setState(()=>_loading=true);
    try {
      await _functions.httpsCallable('setWhatsAppConnection').call({'phone':phone.text,'storeId':store.text,'merchantUid':merchant.text,'autoPublish':auto});
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تم ربط رقم واتساب بالمتجر.')));
      setState((){});
    } on FirebaseFunctionsException catch(e) {
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('فشل الربط: '+(e.message??e.code))));
    } finally { if(mounted)setState(()=>_loading=false); }
  }

  Future<void> _confirm(Map<String,dynamic> item) async {
    final name=TextEditingController(text:(item['parsed']?['name']??'').toString());
    final price=TextEditingController(text:(item['parsed']?['price']??'').toString());
    final stock=TextEditingController(text:(item['parsed']?['stock']??'0').toString());
    final values=await showDialog<Map<String,String>>(context:context,builder:(context)=>AlertDialog(
      title:const Text('اعتماد منتج واتساب'),
      content:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:name,decoration:const InputDecoration(labelText:'اسم المنتج')),TextField(controller:price,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'السعر ر.ي')),TextField(controller:stock,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'المخزون'))]),
      actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(context,{'name':name.text,'price':price.text,'stock':stock.text}),child:const Text('إنشاء المنتج'))],
    ));
    if(values==null)return;
    setState(()=>_loading=true);
    try { await _functions.httpsCallable('confirmWhatsAppProductImport').call({'importId':item['id'],'name':values['name'],'price':double.tryParse(values['price']??''),'stock':int.tryParse(values['stock']??''),'publish':false}); if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تم إنشاء المنتج بأمان.'))); setState((){}); }
    on FirebaseFunctionsException catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('فشل الاعتماد: '+(e.message??e.code))));}
    finally{if(mounted)setState(()=>_loading=false);}
  }

  @override Widget build(BuildContext context){
    return Directionality(textDirection:TextDirection.rtl,child:Scaffold(
      appBar:AppBar(title:const Text('أتمتة واتساب',style:TextStyle(fontWeight:FontWeight.w900)),actions:[IconButton(onPressed:_bindNumber,icon:const Icon(Icons.add_link),tooltip:'ربط رقم')]),
      body:FutureBuilder<Map<String,dynamic>>(future:_load(),builder:(context,snapshot){
        if(snapshot.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator());
        if(snapshot.hasError)return Center(child:Padding(padding:const EdgeInsets.all(24),child:Text('تعذر تحميل واتساب: '+snapshot.error.toString())));
        final data=snapshot.data??{}; final connections=(data['connections'] as List? ?? []).cast<Map<String,dynamic>>(); final imports=(data['imports'] as List? ?? []).cast<Map<String,dynamic>>();
        return ListView(padding:const EdgeInsets.all(16),children:[
          Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            const Text('WhatsApp Business → الفائق يمن',style:TextStyle(fontSize:20,fontWeight:FontWeight.w900)),const SizedBox(height:8),
            const Text('Webhook رسمي يستقبل رسائل التجار، يربط الرقم بالمتجر، يستخرج بيانات المنتج ويضعها في مسودة آمنة مع سجل تدقيق.'),const SizedBox(height:10),
            const SelectableText('https://us-central1-alfaeq-yemen-fed37.cloudfunctions.net/whatsappWebhook',style:TextStyle(fontFamily:'monospace',fontSize:12)),
          ]))),
          const SizedBox(height:12),
          const Text('الأرقام المرتبطة',style:TextStyle(fontSize:18,fontWeight:FontWeight.w900)),
          if(connections.isEmpty)const Card(child:Padding(padding:EdgeInsets.all(16),child:Text('لم يتم ربط أي رقم بعد. اضغط + لإضافة رقم واتساب للتاجر.')))
          else ...connections.map((c)=>Card(child:ListTile(leading:const Icon(Icons.phone_android),title:Text((c['phone']??'').toString()),subtitle:Text('المتجر: '+(c['storeId']??'').toString()+' • نشر تلقائي: '+(c['autoPublish']==true?'نعم':'لا'))))),
          const SizedBox(height:12),
          const Text('واردات المنتجات',style:TextStyle(fontSize:18,fontWeight:FontWeight.w900)),
          if(_loading)const LinearProgressIndicator(),
          if(imports.isEmpty)const Card(child:Padding(padding:EdgeInsets.all(16),child:Text('لا توجد رسائل منتجات بعد.')))
          else ...imports.map((item){final parsed=Map<String,dynamic>.from(item['parsed'] as Map? ?? {});final status=(item['status']??'unknown').toString();return Card(child:ListTile(leading:const CircleAvatar(child:Icon(Icons.message_outlined)),title:Text((parsed['name']??item['text']??'رسالة واتساب').toString(),style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text('الحالة: '+status+'\nالهاتف: '+(item['phone']??'').toString()),isThreeLine:true,trailing:status=='pending_confirmation'?IconButton(icon:const Icon(Icons.check_circle_outline),onPressed:()=>_confirm(item)):null));}),
        ]);
      }),
    ));
  }
}