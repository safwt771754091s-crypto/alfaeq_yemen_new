import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';

class SmartDispatchPage extends StatefulWidget {
  const SmartDispatchPage({super.key});
  @override State<SmartDispatchPage> createState() => _SmartDispatchPageState();
}

class _SmartDispatchPageState extends State<SmartDispatchPage> {
  final _auth = AuthService();
  bool _busy = false;

  Future<bool> _staff() async {
    final role = await _auth.role();
    return role == 'admin' || role == 'owner' || role == 'developer';
  }

  double _score(Map<String, dynamic> d) {
    final approved = d['approved'] == true;
    final online = d['is_online'] == true;
    final active = (d['active_order_count'] as num?)?.toDouble() ?? 0;
    final rating = (d['rating'] as num?)?.toDouble() ?? 5;
    var score = (approved ? 50 : 0).toDouble() + (online ? 40 : 0).toDouble() + (10 - active).clamp(0, 10).toDouble() + rating.clamp(0, 5).toDouble();
    if (d['latitude'] is num && d['longitude'] is num) score += 5;
    return score;
  }

  Future<void> _assign(Map<String,dynamic> order, Map<String,dynamic> driver) async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null || !await _staff()) return;
    setState(() => _busy = true);
    try {
      final driverId = driver['id'].toString();
      await SupabaseService.client.from('orders').update({
        'driver_id': driverId,
        'delivery_status': 'assigned',
        'assigned_at': DateTime.now().toUtc().toIso8601String(),
        'assigned_by': user.id,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', order['id']);
      await SupabaseService.client.from('delivery_events').insert({
        'order_id': order['id'],
        'driver_id': driverId,
        'status': 'assigned',
        'assigned_by': user.id,
      });
      await SupabaseService.client.from('audit_logs').insert({
        'actor_uid': user.id,
        'actor_email': user.email,
        'role': await _auth.role(),
        'action': 'smart_dispatch_assign',
        'result': 'success',
        'source': 'smart_dispatch',
        'details': {'orderId': order['id'], 'driverId': driverId, 'score': _score(driver)},
      });
      _message('تم إسناد الطلب للمندوب الأفضل حالياً.');
    } catch (e) {
      _message('تعذر الإسناد: $e');
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _showAssignDialog(Map<String,dynamic> order, List<Map<String,dynamic>> drivers) async {
    final ranked = [...drivers]..sort((a,b)=>_score(b).compareTo(_score(a)));
    if (ranked.isEmpty) { _message('لا يوجد مندوبون مؤهلون حالياً.'); return; }
    final selected = await showModalBottomSheet<Map<String,dynamic>>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('اختيار المندوب', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            ...ranked.map((d) => Card(child: ListTile(
              leading: Icon(d['is_online'] == true ? Icons.wifi_tethering : Icons.wifi_off_outlined),
              title: Text('${d['name'] ?? d['display_name'] ?? d['id']}'),
              subtitle: Text('الحمولة: ${d['active_order_count'] ?? 0} • التقييم: ${d['rating'] ?? 5} • النقاط: ${_score(d).toStringAsFixed(1)}'),
              onTap: () => Navigator.pop(context, d),
            ))),
          ],
        )),
      ),
    );
    if (selected != null) await _assign(order, selected);
  }

  void _message(String text) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text))); }

  @override Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: FutureBuilder<bool>(
      future: _staff(),
      builder: (context, access) {
        if (access.connectionState != ConnectionState.done) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        if (access.data != true) return const Scaffold(body: Center(child: Text('مركز التوزيع الذكي مخصص للإدارة المصرح لها.')));
        return Scaffold(
          appBar: AppBar(title: const Text('التوزيع الذكي')),
          body: StreamBuilder<List<Map<String,dynamic>>>(
            stream: SupabaseService.client.from('orders').stream(primaryKey: ['id']).eq('delivery_status','awaiting_assignment').limit(50),
            builder: (context, orderSnap) {
              if (orderSnap.hasError) return Center(child: Text('تعذر تحميل الطلبات: ${orderSnap.error}'));
              final orders = orderSnap.data ?? const <Map<String,dynamic>>[];
              return StreamBuilder<List<Map<String,dynamic>>>(
                stream: SupabaseService.client.from('drivers').stream(primaryKey: ['id']).eq('approved',true).limit(100),
                builder: (context, driverSnap) {
                  if (driverSnap.hasError) return Center(child: Text('تعذر تحميل المندوبين: ${driverSnap.error}'));
                  final drivers = driverSnap.data ?? const <Map<String,dynamic>>[];
                  final ranked = [...drivers]..sort((a,b)=>_score(b).compareTo(_score(a)));
                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Icon(Icons.alt_route,size:38), const SizedBox(height:8),
                        const Text('محرك التوزيع الذكي',style:TextStyle(fontSize:25,fontWeight:FontWeight.w900)),
                        const SizedBox(height:6), const Text('يرتب المندوبين حسب الاعتماد والاتصال والحمولة والتقييم وتوفر الموقع.'),
                        const SizedBox(height:12), Text('طلبات تنتظر الإسناد: ${orders.length}'), Text('مندوبون معتمدون: ${drivers.length}')
                      ]))),
                      const SizedBox(height:16),
                      if (orders.isEmpty) const Card(child: Padding(padding:EdgeInsets.all(24),child:Text('لا توجد طلبات تنتظر التوزيع حالياً.'))),
                      ...orders.map((o) {
                        final d=ranked.isEmpty?null:ranked.first;
                        return Card(margin:const EdgeInsets.only(bottom:12),child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                          Text('طلب #${o['id']}',style:const TextStyle(fontSize:17,fontWeight:FontWeight.w900)),
                          Text('العنوان: ${o['address'] ?? '—'}'),
                          Text('الإجمالي: ${o['total'] ?? 0} ${o['currency'] ?? 'YER'}'),
                          if(d!=null) Text('المقترح: ${d['name'] ?? d['display_name'] ?? d['id']} • الحمولة ${d['active_order_count'] ?? 0}',style:const TextStyle(fontWeight:FontWeight.w800)),
                          const SizedBox(height:10),
                          FilledButton.icon(onPressed:_busy||drivers.isEmpty?null:()=>_showAssignDialog(o,drivers),icon:const Icon(Icons.route_outlined),label:Text(d==null?'اختر مندوباً':'توزيع ذكي'))
                        ])));
                      }),
                    ],
                  );
                },
              );
            },
          ),
        );
      },
    ),
  );
}
