import 'package:flutter/material.dart';

import '../services/order_service.dart';
import '../services/red_packet_service.dart';
import '../core/money.dart';

/// WeChat-style "send a red packet" sheet used from a chat composer.
Future<bool> showSendRedPacketSheet(BuildContext context, {required String threadId}) async {
  final total = TextEditingController(text: '1000');
  final count = TextEditingController(text: '1');
  final wish = TextEditingController(text: 'أتمنى لك التوفيق!');
  String type = 'random';
  bool busy = false;

  String? walletCurrency;
  num? balance;
  try {
    final info = await OrderService(preferSupabase: true).walletInfo();
    walletCurrency = info.currency;
    balance = info.balance;
  } catch (_) {/* best effort */}

  if (!context.mounted) return false;

  return await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(
            builder: (ctx, setState) {
              final currency = walletCurrency ?? 'YER';
              return Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 16, right: 16, top: 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Row(children: [
                      Icon(Icons.card_giftcard, color: Color(0xFFC0392B)),
                      SizedBox(width: 8),
                      Text('حزمة حمراء 🧧', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                    ]),
                    if (balance != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('رصيد محفظتك: ${formatAmount(balance)} $currency', style: const TextStyle(color: Colors.black54, fontSize: 12)),
                      ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: total,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: 'المبلغ الإجمالي ($currency)', border: const OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: count,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'عدد الحزم (الأشخاص)', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'random', label: Text('عشوائي'), icon: Icon(Icons.shuffle)),
                        ButtonSegment(value: 'equal', label: Text('بالتساوي'), icon: Icon(Icons.balance)),
                      ],
                      selected: {type},
                      onSelectionChanged: (s) => setState(() => type = s.first),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: wish,
                      maxLength: 60,
                      decoration: const InputDecoration(labelText: 'رسالة الحزمة', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC0392B)),
                      onPressed: busy
                          ? null
                          : () async {
                              final amount = num.tryParse(total.text.trim());
                              final n = int.tryParse(count.text.trim()) ?? 1;
                              if (amount == null || amount <= 0) {
                                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('أدخل مبلغاً صالحاً.')));
                                return;
                              }
                              if (n < 1 || n > 100) {
                                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('عدد الحزم يجب أن يكون بين 1 و 100.')));
                                return;
                              }
                              setState(() => busy = true);
                              try {
                                await const RedPacketService().create(
                                  threadId: threadId,
                                  total: amount,
                                  count: n,
                                  type: type,
                                  wish: wish.text.trim(),
                                );
                                if (ctx.mounted) Navigator.pop(ctx, true);
                              } catch (e) {
                                setState(() => busy = false);
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('تعذر إرسال الحزمة: ${_friendly(e)}')));
                                }
                              }
                            },
                      icon: const Icon(Icons.send),
                      label: Text(busy ? 'جاري الإرسال...' : 'إرسال الحزمة'),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              );
            },
          ),
        ),
      ) ??
      false;
}

String _friendly(Object e) {
  final t = e.toString();
  if (t.contains('insufficient_wallet_balance')) return 'رصيد المحفظة غير كافٍ.';
  if (t.contains('amount_too_small')) return 'المبلغ صغير جداً على عدد الحزم.';
  if (t.contains('not_a_member')) return 'أنت لست عضواً في هذه المحادثة.';
  return t;
}
