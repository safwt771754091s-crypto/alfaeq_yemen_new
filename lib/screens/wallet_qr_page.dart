import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/money.dart';
import '../services/order_service.dart';
import '../services/supabase_service.dart';

/// WeChat Pay-style wallet page: receive code (QR), scan/paste-to-pay, and a
/// recent transfers list. All money movement happens in the server-side
/// `wallet_transfer` RPC -- the client never edits balances directly.
class WalletQrPage extends StatefulWidget {
  const WalletQrPage({super.key});
  @override
  State<WalletQrPage> createState() => _WalletQrPageState();
}

class _WalletQrPageState extends State<WalletQrPage> {
  int _refresh = 0;

  void _reload() => setState(() => _refresh++);

  Future<void> _pasteAndPay() async {
    final controller = TextEditingController();
    final payload = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 16, right: 16, top: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('الدفع عبر الرمز', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              const Text('الصق رمز الدفع (alfaeq://pay?...) أو أدخل معرّف المستلم.', style: TextStyle(color: Colors.black54, fontSize: 12)),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(hintText: 'alfaeq://pay?uid=...', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context, controller.text.trim()),
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('متابعة'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (payload == null || payload.isEmpty) return;
    final uid = _extractUid(payload);
    if (uid == null) {
      _snack('رمز الدفع غير صالح.');
      return;
    }
    await _pay(uid);
  }

  String? _extractUid(String raw) {
    try {
      final uri = Uri.parse(raw);
      final fromQuery = uri.queryParameters['uid'];
      if (fromQuery != null && fromQuery.isNotEmpty) return fromQuery;
    } catch (_) {}
    // Allow pasting a bare user id.
    final bare = raw.trim();
    return bare.isNotEmpty && !bare.contains(' ') ? bare : null;
  }

  Future<void> _pay(String payeeUid) async {
    final me = SupabaseService.client.auth.currentUser?.id;
    if (me == null) {
      _snack('يجب تسجيل الدخول أولاً.');
      return;
    }
    if (payeeUid == me) {
      _snack('لا يمكنك الدفع لنفسك.');
      return;
    }

    String payeeName = 'مستخدم الفائق';
    try {
      final res = await SupabaseService.client.rpc('lookup_payee_name', params: {'p_uid': payeeUid});
      if (res != null) payeeName = res.toString();
    } catch (_) {}

    if (!mounted) return;
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد الدفع', style: TextStyle(fontWeight: FontWeight.w900)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('الدفع إلى: $payeeName', style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'المبلغ (YER)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)', border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('ادفع')),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    final amount = double.tryParse(amountController.text.trim());
    if (amount == null || amount <= 0) {
      _snack('المبلغ غير صالح.');
      return;
    }

    try {
      final idem = 'xfer-${DateTime.now().microsecondsSinceEpoch}';
      final walletCurrency = (await OrderService(preferSupabase: true).walletInfo()).currency;
      final balance = await SupabaseService.client.rpc('wallet_transfer', params: {
        'p_to_uid': payeeUid,
        'p_amount': amount,
        'p_currency': walletCurrency,
        'p_idempotency_key': idem,
        'p_note': noteController.text.trim().isEmpty ? null : noteController.text.trim(),
      });
      _snack('تم الدفع بنجاح. رصيدك الآن: ${formatAmount(num.tryParse('$balance') ?? 0)} $walletCurrency');
      _reload();
    } catch (e) {
      _snack('تعذر إتمام الدفع: ${_friendly(e)}');
    }
  }

  String _friendly(Object e) {
    final s = e.toString();
    if (s.contains('insufficient_wallet_balance')) return 'الرصيد غير كافٍ.';
    if (s.contains('recipient_not_found')) return 'المستلم غير موجود.';
    if (s.contains('cannot_pay_self')) return 'لا يمكنك الدفع لنفسك.';
    if (s.contains('sender_wallet_missing')) return 'لا توجد محفظة. أنشئ محفظتك أولاً.';
    if (s.contains('sender_currency_mismatch') || s.contains('recipient_currency_mismatch') || s.contains('wallet_currency_mismatch')) {
      return 'عملة المحفظة لا تطابق عملة العملية.';
    }
    return s;
  }

  void _snack(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('يجب تسجيل الدخول أولاً.')));
    }
    final name = ((user.userMetadata ?? const <String, dynamic>{})['full_name'] ??
            (user.userMetadata ?? const <String, dynamic>{})['name'] ??
            'مستخدم الفائق')
        .toString();
    final payload = 'alfaeq://pay?uid=${user.id}&name=${Uri.encodeComponent(name)}';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('الدفع والمحفظة', style: TextStyle(fontWeight: FontWeight.w900))),
        body: FutureBuilder<({num balance, String currency})>(
          key: ValueKey(_refresh),
          future: OrderService(preferSupabase: true).walletInfo(),
          builder: (context, snapshot) {
            final info = snapshot.data;
            final balance = info?.balance ?? 0;
            final walletCurrency = info?.currency ?? 'YER';
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: const Color(0xFF0A2540), borderRadius: BorderRadius.circular(20)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('الرصيد المتاح', style: TextStyle(color: Colors.white70)),
                      const SizedBox(height: 6),
                      Text(formatMoney(balance, walletCurrency, fallback: '0'), style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _pasteAndPay,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('ادفع'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: payload));
                        _snack('تم نسخ رمز الاستلام.');
                      },
                      icon: const Icon(Icons.copy_outlined),
                      label: const Text('انسخ رمزي'),
                    ),
                  ),
                ]),
                const SizedBox(height: 22),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFFE3E8EF))),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        const Text('امسح الرمز للدفع لي', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                        const SizedBox(height: 4),
                        Text(name, style: const TextStyle(color: Colors.black54)),
                        const SizedBox(height: 18),
                        QrImageView(
                          data: payload,
                          version: QrVersions.auto,
                          size: 220,
                          backgroundColor: Colors.white,
                          eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF0A2540)),
                          dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF0A2540)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('آخر العمليات', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                FutureBuilder<List<Map<String, dynamic>>>(
                  key: ValueKey('ledger-$_refresh'),
                  future: SupabaseService.client
                      .from('wallet_ledger')
                      .select()
                      .eq('user_id', user.id)
                      .order('created_at', ascending: false)
                      .limit(20),
                  builder: (context, ledger) {
                    if (ledger.connectionState == ConnectionState.waiting) {
                      return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
                    }
                    if (ledger.hasError) return Text('تعذر تحميل العمليات: ${ledger.error}');
                    final rows = ledger.data ?? const <Map<String, dynamic>>[];
                    if (rows.isEmpty) return const Card(child: ListTile(title: Text('لا توجد عمليات بعد.')));
                    return Column(children: rows.map((row) {
                      final type = row['entry_type']?.toString() ?? '';
                      final isOut = type == 'debit' || type == 'transfer_out';
                      final amount = row['amount'] ?? 0;
                      return Card(
                        elevation: 0,
                        child: ListTile(
                          leading: Icon(isOut ? Icons.arrow_upward : Icons.arrow_downward, color: isOut ? Colors.redAccent : Colors.green),
                          title: Text('${isOut ? 'صادر' : 'وارد'} • '+formatAmount(num.tryParse('$amount') ?? 0)+' $walletCurrency', style: const TextStyle(fontWeight: FontWeight.w800)),
                          subtitle: Text((row['reference_type'] ?? type).toString()),
                        ),
                      );
                    }).toList());
                  },
                ),
                const SizedBox(height: 12),
                const Card(
                  elevation: 0,
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text(
                      'تُنفَّذ كل عمليات الدفع في الخادم بشكل آمن ومتكرّر الحماية (idempotent). لا تشارك رمزك إلا مع من تثق به.',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
