import 'package:flutter/material.dart';

import '../core/geo_util.dart';

/// One row of the shared order journey: created -> accepted -> preparing ->
/// ready -> assigned -> picked up -> out for delivery -> delivered.
class DeliveryTimeline extends StatelessWidget {
  final Map<String, dynamic> order;
  final List<Map<String, dynamic>> events;
  final bool dense;

  const DeliveryTimeline({
    super.key,
    required this.order,
    this.events = const <Map<String, dynamic>>[],
    this.dense = false,
  });

  DateTime? _eventTime(String event) {
    for (final e in events) {
      if ('${e['event']}' == event) return GeoUtil.parseTime(e['created_at']);
    }
    return null;
  }

  DateTime? _orderTime(String column) => GeoUtil.parseTime(order[column]);

  List<_Step> _steps() {
    final createdAt = _orderTime('created_at');
    final readyAt = _orderTime('merchant_ready_at') ?? _eventTime('ready_for_pickup');
    final assignedAt = _orderTime('assigned_at') ?? _eventTime('assigned');
    final pickedAt = _orderTime('picked_up_at') ?? _eventTime('picked_up');
    final outAt = _orderTime('out_for_delivery_at') ?? _eventTime('out_for_delivery');
    final deliveredAt = _orderTime('delivered_at') ?? _eventTime('delivered');
    final cancelledAt = _orderTime('cancelled_at') ?? _eventTime('cancelled');
    final delivery = '${order['delivery_status'] ?? 'pending'}';
    final status = '${order['status'] ?? 'pending'}';
    final cancelled = delivery == 'cancelled' || status == 'cancelled';

    bool reached(DateTime? t, List<String> states) => t != null || states.contains(delivery) || states.contains(status);

    return [
      _Step('تم إنشاء الطلب', Icons.receipt_long_outlined, createdAt,
          reached(createdAt, const ['pending'])),
      _Step('قبله التاجر', Icons.storefront_outlined, _eventTime('accepted'),
          reached(_eventTime('accepted'), const ['accepted', 'preparing', 'ready_for_pickup'])),
      _Step('قيد التجهيز', Icons.inventory_2_outlined, _eventTime('preparing'),
          reached(_eventTime('preparing'), const ['preparing', 'ready_for_pickup'])),
      _Step('جاهز للاستلام من التاجر', Icons.inventory_outlined, readyAt,
          reached(readyAt, const ['ready_for_pickup'])),
      _Step('أُسند إلى مندوب', Icons.assignment_ind_outlined, assignedAt,
          reached(assignedAt, const ['assigned', 'picked_up', 'out_for_delivery', 'on_the_way'])),
      _Step('استلم المندوب البضاعة', Icons.local_shipping_outlined, pickedAt,
          reached(pickedAt, const ['picked_up', 'out_for_delivery', 'on_the_way'])),
      _Step('خرج للتوصيل', Icons.directions_car_outlined, outAt,
          reached(outAt, const ['out_for_delivery', 'on_the_way'])),
      _Step('تم التسليم للعميل', Icons.check_circle_outline, deliveredAt,
          deliveredAt != null || delivery == 'delivered' || status == 'delivered'),
      if (cancelled)
        _Step('أُلغي الطلب', Icons.cancel_outlined, cancelledAt, true),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final steps = _steps();
    final activeColor = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++)
          _TimelineRow(
            step: steps[i],
            isLast: i == steps.length - 1,
            activeColor: activeColor,
            dense: dense,
          ),
      ],
    );
  }
}

class _Step {
  final String label;
  final IconData icon;
  final DateTime? time;
  final bool done;
  const _Step(this.label, this.icon, this.time, this.done);
}

class _TimelineRow extends StatelessWidget {
  final _Step step;
  final bool isLast;
  final Color activeColor;
  final bool dense;

  const _TimelineRow({
    required this.step,
    required this.isLast,
    required this.activeColor,
    required this.dense,
  });

  @override
  Widget build(BuildContext context) {
    final color = step.done ? activeColor : Colors.black26;
    final clock = GeoUtil.formatClock(step.time);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Icon(step.icon, size: dense ? 18 : 22, color: color),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: step.done ? activeColor.withValues(alpha: 0.4) : Colors.black12,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: dense ? 8 : 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      step.label,
                      style: TextStyle(
                        fontWeight: step.done ? FontWeight.w800 : FontWeight.w500,
                        color: step.done ? null : Colors.black45,
                        fontSize: dense ? 13 : 15,
                      ),
                    ),
                  ),
                  if (clock != null)
                    Text(
                      clock,
                      style: TextStyle(
                        fontSize: dense ? 12 : 13,
                        fontWeight: FontWeight.w700,
                        color: step.done ? activeColor : Colors.black38,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
