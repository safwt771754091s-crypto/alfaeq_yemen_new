import 'package:flutter/material.dart';

import '../core/money.dart';

/// WeChat-style green transfer bubble shown in chat. Tapping it opens the
/// transfer detail (amount, currency, note, direction).
class ChatTransferBubble extends StatelessWidget {
  final Map meta;
  final bool mine;
  const ChatTransferBubble({super.key, required this.meta, required this.mine});

  @override
  Widget build(BuildContext context) {
    final amount = meta['amount'];
    final currency = (meta['currency'] ?? '').toString();
    final note = (meta['note'] ?? '').toString();
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: () => _showDetail(context),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 300),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF07C160), Color(0xFF059B4D)]),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(children: [
            const Icon(Icons.send_to_mobile, color: Colors.white, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${mine ? 'تحويل مُرسل' : 'تحويل مُستلم'}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 2),
                Text('${formatAmount(amount)} $currency', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17)),
                if (note.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(note, style: const TextStyle(color: Colors.white70, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
              ]),
            ),
            const Icon(Icons.chevron_left, color: Colors.white70),
          ]),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تفاصيل التحويل'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('المبلغ: ${formatAmount(meta['amount'])} ${meta['currency'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('الاتجاه: ${mine ? 'مُرسل منك' : 'مُستلم إليك'}'),
              if ((meta['note'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('ملاحظة: ${meta['note']}'),
              ],
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق'))],
        ),
      ),
    );
  }
}
