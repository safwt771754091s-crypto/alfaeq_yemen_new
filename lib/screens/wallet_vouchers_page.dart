import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/money.dart';
import '../services/supabase_service.dart';

/// Staff console for prepaid wallet recharge vouchers. Staff issue batches of
/// codes, hand them to customers, and the customer redeems them in the wallet.
class WalletVouchersPage extends StatefulWidget {
  const WalletVouchersPage({super.key});
  @override
  State<WalletVouchersPage> createState() => _WalletVouchersPageState();
}

class _WalletVouchersPageState extends State<WalletVouchersPage> {
  List<Map<String, dynamic>> _vouchers = const [];
  List<String> _lastBatch = const [];
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
      final res = await SupabaseService.client.rpc('list_wallet_vouchers', params: {'p_limit': 200});
      final rows = ((res as Map?)?['vouchers'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (mounted) setState(() { _vouchers = rows; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _issue() async {
    final count = TextEditingController(text: '10');
    final amount = TextEditingController(text: '5');
    String currency = 'USD';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('إصدار رموز شحن'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: count, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'عدد الرموز (1-500)')),
            const SizedBox(height: 8),
            TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'قيمة كل رمز')),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: currency,
              decoration: const InputDecoration(labelText: 'العملة'),
              items: const [
                DropdownMenuItem(value: 'USD', child: Text('دولار USD')),
                DropdownMenuItem(value: 'YER', child: Text('ريال يمني YER')),
                DropdownMenuItem(value: 'SAR', child: Text('ريال سعودي SAR')),
              ],
              onChanged: (v) => setLocal(() => currency = v ?? 'USD'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('إصدار')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final n = int.tryParse(count.text.trim()) ?? 0;
    final value = double.tryParse(amount.text.trim()) ?? 0;
    if (n < 1 || value <= 0) {
      _snack('أدخل عدداً وقيمة صالحين.');
      return;
    }
    try {
      final res = await SupabaseService.client.rpc('issue_wallet_vouchers', params: {
        'p_count': n, 'p_amount': value, 'p_currency': currency,
      });
      final codes = ((res as Map?)?['codes'] as List? ?? []).map((e) => e.toString()).toList();
      setState(() => _lastBatch = codes);
      _snack('تم إصدار $n رمزاً بقيمة ${formatAmount(value)} $currency.');
      _load();
    } catch (e) {
      _snack('تعذر الإصدار: $e');
    }
  }

  void _snack(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('رموز شحن المحفظة', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [IconButton(onPressed: _issue, icon: const Icon(Icons.add_card), tooltip: 'إصدار رموز')],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('شحن المحفظة برموز مدفوعة', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            const Text('أصدر دفعة رموز، اطبعها أو سلّمها للعملاء، ثم يستبدلها العميل من محفظته لشحن رصيده. كل رمز يُستخدم مرة واحدة فقط.'),
            const SizedBox(height: 10),
            FilledButton.icon(onPressed: _issue, icon: const Icon(Icons.add_card), label: const Text('إصدار دفعة رموز')),
          ]))),
          if (_lastBatch.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('دفعة الرموز الأخيرة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.new_releases_outlined, color: Colors.green),
                const SizedBox(width: 8),
                const Expanded(child: Text('انسخ الرموز وسلّمها للعملاء.', style: TextStyle(fontWeight: FontWeight.w700))),
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _lastBatch.join('\n')));
                    _snack('تم نسخ كل الرموز.');
                  },
                  icon: const Icon(Icons.copy_all), label: const Text('انسخ الكل'),
                ),
              ]),
              const Divider(),
              ..._lastBatch.map((c) => SelectableText(c, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700))),
            ]))),
          ],
          const SizedBox(height: 16),
          const Text('الرموز السابقة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          if (_loading) const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
          else if (_error != null) Card(child: ListTile(leading: const Icon(Icons.error_outline), title: const Text('تعذر تحميل الرموز'), subtitle: Text(_error!)))
          else if (_vouchers.isEmpty) const Card(child: ListTile(title: Text('لا توجد رموز بعد.')))
          else ..._vouchers.map((v) {
            final status = (v['status'] ?? '').toString();
            final redeemed = status == 'redeemed';
            return Card(child: ListTile(
              leading: Icon(redeemed ? Icons.check_circle : Icons.card_giftcard, color: redeemed ? Colors.green : Colors.orange),
              title: SelectableText((v['code'] ?? '').toString(), style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w800)),
              subtitle: Text('${formatAmount(num.tryParse('${v['amount']}') ?? 0)} ${v['currency']} • ${redeemed ? 'مستخدم' : 'متاح'}${redeemed && v['redeemed_at'] != null ? '\n${v['redeemed_at']}' : ''}'),
              isThreeLine: redeemed,
            ));
          }),
        ]),
      ),
    ),
  );
}
