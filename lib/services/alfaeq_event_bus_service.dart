import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

class AlfaeqEventBusService {
  static SupabaseClient get _db => SupabaseService.client;

  Future<Map<String, dynamic>> publish({
    required String eventType,
    required Map<String, dynamic> data,
    String source = 'alfaeq_yemen_new',
    int version = 1,
    String? eventId,
    DateTime? occurredAt,
  }) async {
    final id = eventId ?? 'app-${DateTime.now().toUtc().microsecondsSinceEpoch}';
    final response = await _db.functions.invoke('automation-event-gateway', body: {
      'source': source, 'version': version, 'eventId': id,
      'eventType': eventType,
      'occurredAt': (occurredAt ?? DateTime.now().toUtc()).toIso8601String(),
      'data': data,
    });
    if (response.data is Map) return Map<String, dynamic>.from(response.data as Map);
    throw StateError('Automation gateway returned an invalid response.');
  }

  Future<Map<String, dynamic>> publishOrderCreated(String orderId, {Map<String, dynamic> data = const {}}) =>
      publish(eventType: 'order.created', data: {'aggregateId': orderId, ...data});

  Future<Map<String, dynamic>> publishInventoryChanged(String productId, {Map<String, dynamic> data = const {}}) =>
      publish(eventType: 'inventory.changed', data: {'aggregateId': productId, ...data});
}