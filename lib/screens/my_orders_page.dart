import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/supabase_service.dart';
import 'delivery_tracking.dart';

class MyOrdersPage extends StatelessWidget {
  const MyOrdersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = const AuthService().currentUser;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('طلباتي', style: TextStyle(fontWeight: FontWeight.w900))),
        body: user == null
            ? const Center(child: Text('يجب تسجيل الدخول لعرض طلباتك.'))
            : SupabaseService.isInitialized
                ? _SupabaseOrders(userId: user.uid)
                : const Center(child: Text('قاعدة بيانات الإنتاج غير متاحة حالياً.')),
      ),
    );
  }
}

class _SupabaseOrders extends StatelessWidget {
  final String userId;
  const _SupabaseOrders({required this.userId});

  @override
  Widget build(BuildContext context) {
    final stream = FirestoreService(preferSupabase: true).supabaseMyOrders(userId);
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('تعذر تحميل الطلبات من الخادم.\n${snapshot.error}', textAlign: TextAlign.center),
          ));
        }
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        return _OrdersList(orders: snapshot.data ?? const <Map<String, dynamic>>[]);
      },
    );
  }
}

class _OrdersList extends StatelessWidget {
  final List<Map<String, dynamic>> orders;
  const _OrdersList({required this.orders});

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.receipt_long_outlined, size: 64),
          SizedBox(height: 12),
          Text('لا توجد طلبات بعد', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          SizedBox(height: 6),
          Text('ستظهر طلباتك هنا مع التحديث الفوري لحالتها.'),
        ]),
      ));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: orders.length,
      separatorBuilder: (_, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final data = orders[index];
        final id = (data['id'] ?? '').toString();
        final status = (data['status'] ?? 'pending').toString();
        final deliveryStatus = (data['delivery_status'] ?? data['deliveryStatus'] ?? 'awaiting_assignment').toString();
        final total = data['total'];
        final currency = (data['currency'] ?? 'YER').toString();
        final rawItems = data['items'];
        final itemCount = rawItems is List ? rawItems.length : 0;

        return Card(
          elevation: 0,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: id.isEmpty ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => DeliveryTracking(orderId: id))),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.receipt_long_outlined),
                  const SizedBox(width: 10),
                  Expanded(child: Text('الطلب #${id.length > 8 ? id.substring(0, 8) : id}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17))),
                  _StatusChip(label: _orderLabel(status), status: status),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: Text('$itemCount ${itemCount == 1 ? 'صنف' : 'أصناف'}')),
                  Text('${total ?? 0} $currency', style: const TextStyle(fontWeight: FontWeight.w900)),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.local_shipping_outlined, size: 18),
                  const SizedBox(width: 6),
                  Expanded(child: Text(_deliveryLabel(deliveryStatus))),
                  const Icon(Icons.chevron_left),
                ]),
              ]),
            ),
          ),
        );
      },
    );
  }

  static String _orderLabel(String value) => switch (value) {
    'pending' => 'قيد المراجعة',
    'confirmed' => 'تم التأكيد',
    'preparing' => 'قيد التجهيز',
    'shipped' => 'تم الشحن',
    'delivered' => 'تم التسليم',
    'cancelled' => 'ملغي',
    _ => value,
  };

  static String _deliveryLabel(String value) => switch (value) {
    'awaiting_assignment' => 'بانتظار تعيين مندوب',
    'assigned' => 'تم تعيين المندوب',
    'picked_up' => 'استلم المندوب الطلب',
    'on_the_way' => 'الطلب في الطريق',
    'in_transit' => 'الطلب قيد التوصيل',
    'delivered' => 'تم التسليم',
    'cancelled' => 'تم إلغاء التوصيل',
    _ => value,
  };
}

class _StatusChip extends StatelessWidget {
  final String label;
  final String status;
  const _StatusChip({required this.label, required this.status});

  @override
  Widget build(BuildContext context) {
    final cancelled = status == 'cancelled';
    final delivered = status == 'delivered';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: cancelled
            ? Colors.red.withValues(alpha: .10)
            : delivered
                ? Colors.green.withValues(alpha: .10)
                : Theme.of(context).colorScheme.primary.withValues(alpha: .10),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}
