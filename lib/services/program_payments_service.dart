import 'package:supabase_flutter/supabase_flutter.dart';

import 'mini_programs_service.dart';
import 'supabase_service.dart';

/// A paid receipt from buying inside a mini program (برنامج مصغّر).
class ProgramOrder {
  final String id;
  final String programId;
  final String programName;
  final String title;
  final num amount;
  final String currency;
  final String status;
  final DateTime? createdAt;

  const ProgramOrder({
    required this.id,
    required this.programId,
    required this.programName,
    required this.title,
    required this.amount,
    required this.currency,
    this.status = 'paid',
    this.createdAt,
  });

  factory ProgramOrder.fromRow(Map<String, dynamic> row) => ProgramOrder(
        id: (row['id'] ?? '').toString(),
        programId: (row['program_id'] ?? '').toString(),
        programName: (row['program_name'] ?? '').toString(),
        title: (row['title'] ?? '').toString(),
        amount: (row['amount'] as num?) ?? 0,
        currency: (row['currency'] ?? 'USD').toString(),
        status: (row['status'] ?? 'paid').toString(),
        createdAt: DateTime.tryParse((row['created_at'] ?? '').toString()),
      );
}

/// Checkout for mini programs: pays from the in-app wallet and records a
/// receipt. Mirrors WeChat's in-app payments (小程序支付).
class ProgramPaymentsService {
  const ProgramPaymentsService();

  static SupabaseClient get _db => SupabaseService.client;

  /// Pays [amount] in [currency] for [program] and returns the receipt. The
  /// [idempotencyKey] makes retries safe (no double charge).
  Future<ProgramOrder> pay({
    required MiniProgram program,
    required num amount,
    required String currency,
    String? title,
    required String idempotencyKey,
  }) async {
    final res = await _db.rpc('pay_mini_program', params: {
      'p_program_id': program.id,
      'p_title': (title ?? program.name).trim(),
      'p_amount': amount,
      'p_currency': currency,
      'p_idempotency_key': idempotencyKey,
    });
    final map = (res is Map) ? Map<String, dynamic>.from(res) : const <String, dynamic>{};
    return ProgramOrder(
      id: (map['order_id'] ?? '').toString(),
      programId: program.id,
      programName: program.name,
      title: (title ?? program.name).trim(),
      amount: amount,
      currency: currency,
      status: 'paid',
      createdAt: DateTime.now(),
    );
  }

  /// The caller's recent mini-program receipts.
  Future<List<ProgramOrder>> myOrders({int limit = 50}) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return const [];
    final rows = await _db
        .from('program_orders')
        .select()
        .eq('buyer_id', uid)
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List).cast<Map<String, dynamic>>().map(ProgramOrder.fromRow).toList();
  }
}
