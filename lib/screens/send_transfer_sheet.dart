import 'package:flutter/material.dart';

import '../core/money.dart';
import '../services/chat_transfer_service.dart';
import '../services/order_service.dart';

/// WeChat Pay-style "send money" sheet used from a 1:1 chat composer.
/// Returns true when the transfer was executed and posted to the chat.
Future<bool> showSendTransferSheet(
  BuildContext context, {
  required String threadId,
  required String toUid,
  required String toName,
}) async {
  final amount = TextEditingController();
  final note = TextEditingController();
  bool busy = false;

  String currency = 'YER';
  num? balance;
  try {
    final info = await OrderService(preferSupabase: true).walletInfo();
    currency = info.currency;
    balance = info.balance;
  } catch (_) {/* best effort */}

  if (!context.mounted) return false;

  return await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(
            builder: (ctx, setState) => Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 16, right: 16, top: 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    const Icon(Icons.send_to_mobile, color: Color(0xFF07C160)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('تحويل إلى $toName', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                    ),
                  ]),
                  if (balance != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('رصيد محفظتك: ${formatAmount(balance)} $currency', style: const TextStyle(color: Colors.black54, fontSize: 12)),
                    ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: amount,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: 'المبلغ ($currency)', border: const OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: note,
                    maxLength: 60,
                    decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF07C160)),
                    onPressed: busy
                        ? null
                        : () async {
                            final value = num.tryParse(amount.text.trim());
                            if (value == null || value <= 0) {
                              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('أدخل مبلغاً صالحاً.')));
                              return;
                            }
                            if (balance != null && value > balance) {
                              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('رصيد المحفظة غير كافٍ.')));
                              return;
                            }
                            setState(() => busy = true);
                            try {
                              await const ChatTransferService().send(
                                threadId: threadId,
                                toUid: toUid,
                                amount: value,
                                note: note.text.trim().isEmpty ? null : note.text.trim(),
                              );
                              if (ctx.mounted) Navigator.pop(ctx, true);
                            } catch (e) {
                              setState(() => busy = false);
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(friendlyChatTransferError(e))));
                              }
                            }
                          },
                    icon: const Icon(Icons.send),
                    label: Text(busy ? 'جاري التحويل...' : 'تحويل الآن'),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
        ),
      ) ??
      false;
}
