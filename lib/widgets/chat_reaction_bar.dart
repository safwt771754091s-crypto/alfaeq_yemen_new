import 'package:flutter/material.dart';

/// WeChat-style reaction strip shown under a chat bubble: grouped emoji chips
/// with live counts. The current user's own reaction is highlighted; tapping a
/// chip toggles it.
class ChatReactionBar extends StatelessWidget {
  final List<Map<String, dynamic>> reactions;
  final String? myUid;
  final ValueChanged<String> onToggle;
  final VoidCallback onAdd;
  const ChatReactionBar({
    super.key,
    required this.reactions,
    required this.myUid,
    required this.onToggle,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    // Preserve first-seen order of emojis while counting.
    final counts = <String, int>{};
    final mine = <String>{};
    for (final r in reactions) {
      final emoji = (r['emoji'] ?? '').toString();
      if (emoji.isEmpty) continue;
      counts[emoji] = (counts[emoji] ?? 0) + 1;
      if ((r['user_id'] ?? '').toString() == myUid) mine.add(emoji);
    }

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final entry in counts.entries)
          _chip(context, entry.key, entry.value, mine.contains(entry.key)),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onAdd,
          child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
            ),
            child: const Icon(Icons.add_reaction_outlined, size: 15, color: Colors.black45),
          ),
        ),
      ],
    );
  }

  Widget _chip(BuildContext context, String emoji, int count, bool isMine) {
    return GestureDetector(
      onTap: () => onToggle(emoji),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isMine ? const Color(0xFF07C160).withValues(alpha: 0.15) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isMine ? const Color(0xFF07C160) : Colors.black12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          if (count > 1) ...[
            const SizedBox(width: 3),
            Text('$count', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
          ],
        ]),
      ),
    );
  }
}
