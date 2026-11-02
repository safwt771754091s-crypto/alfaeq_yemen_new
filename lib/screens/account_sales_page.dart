import 'package:flutter/material.dart';

import '../services/account_sales_service.dart';
import '../services/currency_service.dart';
import '../services/program_payments_service.dart';

const _blue = Color(0xFF0D6EFD);
const _navy = Color(0xFF0A2540);
const _surface = Color(0xFFF5F7FA);
const _green = Color(0xFF16A34A);

/// Owner sales dashboard for an Official Account (لوحة مبيعات الحساب الرسمي):
/// revenue KPIs, a per-program breakdown, recent receipts and a one-tap refund.
/// Mirrors WeChat's 商家后台 (merchant console).
class AccountSalesPage extends StatefulWidget {
  final String accountId;
  final String accountName;
  const AccountSalesPage({super.key, required this.accountId, required this.accountName});

  @override
  State<AccountSalesPage> createState() => _AccountSalesPageState();
}

class _AccountSalesPageState extends State<AccountSalesPage> {
  final _service = const AccountSalesService();
  AccountSales? _sales;
  List<ProgramOrder> _orders = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final sales = await _service.summary(widget.accountId);
      final orders = await _service.orders(widget.accountId);
      if (!mounted) return;
      setState(() { _sales = sales; _orders = orders; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'تعذّر تحميل المبيعات. تأكد أنك صاحب الحساب.'; });
    }
  }

  String _money(num usd) => CurrencyService.instance.format(usd.toDouble());

  Future<void> _refund(ProgramOrder order) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('استرداد الطلب'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('سيُعاد مبلغ ${_money(order.amount)} إلى محفظة المشتري، ويُخصم من محفظتك.'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(labelText: 'سبب الاسترداد (اختياري)', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('استرداد'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.refund(order.id, reason: reasonCtrl.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم استرداد الطلب بنجاح')));
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر الاسترداد — تأكد من كفاية رصيد محفظتك.'), backgroundColor: Color(0xFFDC2626)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('لوحة المبيعات'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54))))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(widget.accountName, style: const TextStyle(color: _navy, fontSize: 20, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      const Text('مبيعات البرامج المصغّرة', style: TextStyle(color: Colors.black54)),
                      const SizedBox(height: 16),
                      Row(children: [
                        Expanded(child: _kpi('إجمالي الإيرادات', _money(_sales!.totalRevenue), Icons.payments, _green)),
                        const SizedBox(width: 12),
                        Expanded(child: _kpi('إيراد هذا الشهر', _money(_sales!.monthRevenue), Icons.trending_up, _blue)),
                      ]),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(child: _kpi('الطلبات المدفوعة', '${_sales!.paidOrders}', Icons.receipt_long, _navy)),
                        const SizedBox(width: 12),
                        Expanded(child: _kpi('المستردة', '${_sales!.refundedOrders}', Icons.undo, Colors.orange.shade800)),
                      ]),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(4, 22, 4, 8),
                        child: Text('الأكثر مبيعاً حسب البرنامج', style: TextStyle(color: _navy, fontWeight: FontWeight.w900, fontSize: 16)),
                      ),
                      if (_sales!.byProgram.isEmpty)
                        const Padding(padding: EdgeInsets.all(8), child: Text('لا توجد مبيعات بعد.', style: TextStyle(color: Colors.black54)))
                      else
                        Card(
                          elevation: 0,
                          color: Colors.white,
                          child: Column(
                            children: [
                              for (final p in _sales!.byProgram)
                                ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.apps, color: _blue),
                                  title: Text(p.programName, style: const TextStyle(fontWeight: FontWeight.w700)),
                                  subtitle: Text('${p.orders} طلب'),
                                  trailing: Text(_money(p.total), style: const TextStyle(color: _green, fontWeight: FontWeight.w900)),
                                ),
                            ],
                          ),
                        ),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(4, 22, 4, 8),
                        child: Text('أحدث الطلبات', style: TextStyle(color: _navy, fontWeight: FontWeight.w900, fontSize: 16)),
                      ),
                      if (_orders.isEmpty)
                        const Padding(padding: EdgeInsets.all(8), child: Text('لا توجد طلبات بعد.', style: TextStyle(color: Colors.black54)))
                      else
                        for (final o in _orders) _orderTile(o),
                    ],
                  ),
                ),
    );
  }

  Widget _kpi(String label, String value, IconData icon, Color color) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: Colors.black54, fontSize: 12.5)),
          ],
        ),
      );

  Widget _orderTile(ProgramOrder o) {
    final refunded = o.status == 'refunded';
    return Card(
      elevation: 0,
      color: Colors.white,
      child: ListTile(
        leading: Icon(refunded ? Icons.undo : Icons.check_circle, color: refunded ? Colors.orange.shade800 : _green),
        title: Text(o.title.isEmpty ? o.programName : o.title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${o.programName} • ${o.createdAt?.toLocal().toString().split('.').first ?? ''}'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(_money(o.amount), style: TextStyle(color: refunded ? Colors.black45 : _navy, fontWeight: FontWeight.w900)),
            if (refunded)
              const Text('مُسترد', style: TextStyle(color: Colors.orange, fontSize: 11))
            else
              InkWell(
                onTap: () => _refund(o),
                child: const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Text('استرداد', style: TextStyle(color: _blue, fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
