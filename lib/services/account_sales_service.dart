import 'package:supabase_flutter/supabase_flutter.dart';

import 'program_payments_service.dart';
import 'supabase_service.dart';

/// One program's share of an account's sales.
class ProgramSales {
  final String programId;
  final String programName;
  final num total;
  final int orders;
  const ProgramSales({required this.programId, required this.programName, required this.total, required this.orders});

  factory ProgramSales.fromRow(Map<String, dynamic> row) => ProgramSales(
        programId: (row['program_id'] ?? '').toString(),
        programName: (row['program_name'] ?? '').toString(),
        total: (row['total'] as num?) ?? 0,
        orders: (row['orders'] as num?)?.toInt() ?? 0,
      );
}

/// Owner-facing sales dashboard for an Official Account (لوحة مبيعات الحساب
/// الرسمي) — a WeChat 商家后台-style summary: revenue, order counts, per-program
/// breakdown and recent receipts, plus a seller-initiated refund.
class AccountSales {
  final num totalRevenue;
  final num monthRevenue;
  final int paidOrders;
  final int refundedOrders;
  final List<ProgramSales> byProgram;
  const AccountSales({
    required this.totalRevenue,
    required this.monthRevenue,
    required this.paidOrders,
    required this.refundedOrders,
    required this.byProgram,
  });

  factory AccountSales.fromMap(Map<String, dynamic> map) => AccountSales(
        totalRevenue: (map['total_revenue'] as num?) ?? 0,
        monthRevenue: (map['month_revenue'] as num?) ?? 0,
        paidOrders: (map['paid_orders'] as num?)?.toInt() ?? 0,
        refundedOrders: (map['refunded_orders'] as num?)?.toInt() ?? 0,
        byProgram: ((map['by_program'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(ProgramSales.fromRow)
            .toList(),
      );
}

class AccountSalesService {
  const AccountSalesService();

  static SupabaseClient get _db => SupabaseService.client;

  Future<AccountSales> summary(String accountId) async {
    final res = await _db.rpc('account_sales_summary', params: {'p_account_id': accountId});
    final map = (res is Map) ? Map<String, dynamic>.from(res) : const <String, dynamic>{};
    return AccountSales.fromMap(map);
  }

  Future<List<ProgramOrder>> orders(String accountId, {int limit = 50}) async {
    final rows = await _db.rpc('account_sales_orders', params: {'p_account_id': accountId, 'p_limit': limit});
    return (rows as List).cast<Map<String, dynamic>>().map(ProgramOrder.fromRow).toList();
  }

  /// Refunds a paid order back to the buyer's wallet; the seller's wallet is
  /// debited. Idempotent per order.
  Future<void> refund(String orderId, {String? reason}) async {
    await _db.rpc('refund_program_order', params: {'p_order_id': orderId, 'p_reason': reason ?? ''});
  }
}
