import 'package:flutter/material.dart';

import '../services/currency_service.dart';
import '../services/mini_programs_service.dart';
import '../services/program_payments_service.dart';
import '../services/wallet_service.dart';

const _blue = Color(0xFF0D6EFD);
const _navy = Color(0xFF0A2540);
const _green = Color(0xFF16A34A);

/// In-mini-program checkout (الدفع داخل البرنامج): pick an amount, pay from the
/// in-app wallet, and get a receipt. Mirrors WeChat's 小程序 payment sheet.
class ProgramCheckoutPage extends StatefulWidget {
  final MiniProgram program;
  final num? suggestedAmount;
  final String? suggestedTitle;
  const ProgramCheckoutPage({
    super.key,
    required this.program,
    this.suggestedAmount,
    this.suggestedTitle,
  });

  @override
  State<ProgramCheckoutPage> createState() => _ProgramCheckoutPageState();
}

class _ProgramCheckoutPageState extends State<ProgramCheckoutPage> {
  final _service = const ProgramPaymentsService();
  final _wallet = const WalletService();
  final _amount = TextEditingController();
  final _title = TextEditingController();
  String _currency = CurrencyService.instance.displayCurrency;
  bool _busy = false;
  num? _walletBalance;

  @override
  void initState() {
    super.initState();
    if (widget.suggestedAmount != null) _amount.text = _trim(widget.suggestedAmount!);
    if ((widget.suggestedTitle ?? '').isNotEmpty) _title.text = widget.suggestedTitle!;
    _loadWallet();
  }

  @override
  void dispose() {
    _amount.dispose();
    _title.dispose();
    super.dispose();
  }

  static String _trim(num v) {
    final s = v.toString();
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  Future<void> _loadWallet() async {
    try {
      final w = await _wallet.ensureMyWallet(currency: _currency);
      if (mounted) setState(() => _walletBalance = (w['available_balance'] as num?) ?? 0);
    } catch (_) {
      // Balance is informational; payment still validates server-side.
    }
  }

  Future<void> _pay() async {
    final amount = num.tryParse(_amount.text.trim().replaceAll(',', ''));
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل مبلغاً صحيحاً.')));
      return;
    }
    setState(() => _busy = true);
    final key = 'mppay:${widget.program.id}:${DateTime.now().microsecondsSinceEpoch}';
    try {
      final order = await _service.pay(
        program: widget.program,
        amount: amount,
        currency: _currency,
        title: _title.text.trim().isEmpty ? widget.program.name : _title.text.trim(),
        idempotencyKey: key,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: _green, size: 40),
          title: const Text('تم الدفع بنجاح'),
          content: Text('دفعت ${CurrencyService.instance.formatNative(amount, _currency)} في «${widget.program.name}».'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('تم'))],
        ),
      );
      if (mounted) Navigator.pop(context, order);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final msg = e.toString().contains('insufficient')
          ? 'رصيد المحفظة غير كافٍ. اشحن محفظتك ثم أعد المحاولة.'
          : 'تعذّر إتمام الدفع. حاول مرة أخرى.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('الدفع في البرنامج'), backgroundColor: _blue, foregroundColor: Colors.white),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFE3E8EF))),
              child: ListTile(
                leading: const CircleAvatar(backgroundColor: Color(0xFFE7F0FF), child: Icon(Icons.apps, color: _blue)),
                title: Text(widget.program.name, style: const TextStyle(fontWeight: FontWeight.w900, color: _navy)),
                subtitle: Text(widget.program.category),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'البيان (اختياري)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'المبلغ', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 10),
                DropdownButton<String>(
                  value: _currency,
                  items: [for (final c in CurrencyService.supported) DropdownMenuItem(value: c, child: Text(CurrencyService.symbolFor(c)))],
                  onChanged: (c) {
                    if (c == null) return;
                    setState(() => _currency = c);
                    _loadWallet();
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.account_balance_wallet_outlined, size: 18, color: _navy),
                const SizedBox(width: 6),
                Text(
                  _walletBalance == null
                      ? 'جاري قراءة رصيد المحفظة...'
                      : 'رصيد المحفظة: ${CurrencyService.instance.formatNative(_walletBalance!, _currency)}',
                  style: const TextStyle(color: Colors.black54),
                ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _pay,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.lock_outline),
              label: Text(_busy ? 'جاري الدفع...' : 'ادفع من المحفظة'),
            ),
            const SizedBox(height: 8),
            const Text('الدفع آمن ويُخصم من محفظتك مباشرة.', style: TextStyle(color: Colors.black45, fontSize: 12), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
