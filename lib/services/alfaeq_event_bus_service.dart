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
    final id = eventId ?? 'app-' + DateTime.now().toUtc().microsecondsSinceEpoch.toString();
    final response = await _db.functions.invoke('automation-event-gateway', body: {
      'source': source, 'version': version, 'eventId': id,
      'eventType': eventType,
      'occurredAt': (occurredAt ?? DateTime.now().toUtc()).toIso8601String(),
      'data': data,
    });
    if (response.data is Map) return Map<String, dynamic>.from(response.data as Map);
    throw StateError('Automation gateway returned an invalid response.');
  }

  Future<Map<String, dynamic>> publishInventoryChanged(
    String productId, {
    Map<String, dynamic> data = const {},
  }) {
    final eventVersion = data['version']?.toString() ?? 'v1';
    return publish(
      eventType: 'inventory.changed',
      eventId: 'inventory.changed:' + productId + ':' + eventVersion,
      data: {'aggregateId': productId, ...data},
    );
  }

  Future<Map<String, dynamic>> publishMerchantUpdated(String merchantId, {Map<String, dynamic> data = const {}}) =>
      publish(eventType: 'merchant.updated', eventId: 'merchant.updated:' + merchantId + ':' + (data['version'] ?? 'v1').toString(), data: {'aggregateId': merchantId, ...data});

  Future<Map<String, dynamic>> publishStoreUpdated(String storeId, {Map<String, dynamic> data = const {}}) =>
      publish(eventType: 'store.updated', eventId: 'store.updated:' + storeId + ':' + (data['version'] ?? 'v1').toString(), data: {'aggregateId': storeId, ...data});

  Future<Map<String, dynamic>> publishProductCreated(String productId, {Map<String, dynamic> data = const {}}) =>
      publish(eventType: 'product.created', eventId: 'product.created:' + productId + ':v1', data: {'aggregateId': productId, ...data});
}