import 'package:flutter/material.dart';

/// WeChat-style emoji picker for the chat composer. Renders an inline grid (no
/// external asset pack) and appends the chosen emoji to the current draft.
class EmojiPicker extends StatelessWidget {
  final ValueChanged<String> onEmoji;
  const EmojiPicker({super.key, required this.onEmoji});

  static const List<String> _emojis = [
    '😀','😃','😄','😁','😆','😅','😂','🤣','😊','😇','🙂','🙃','😉','😌','😍','🥰',
    '😘','😗','😙','😚','😋','😛','😝','😜','🤪','🤨','🧐','🤓','😎','🥳','😏','😒',
    '😞','😔','😟','😕','🙁','☹️','😣','😖','😫','😩','🥺','😢','😭','😤','😠','😡',
    '🤬','🤯','😳','🥵','🥶','😱','😨','😰','😥','😓','🤗','🤔','🤭','🤫','🤥','😶',
    '😐','😑','😬','🙄','😯','😦','😧','😮','😲','🥱','😴','🤤','😪','😵','🤐','🥴',
    '🤢','🤮','🤧','😷','🤒','🤕','🤑','🤠','😈','👿','👹','👺','🤡','💩','👻','💀',
    '👽','👾','🤖','🎃','😺','😸','😹','😻','😼','😽','🙀','😿','😾','🙈','🙉','🙊',
    '👍','👎','👌','✌️','🤞','🤟','🤘','🤙','👈','👉','👆','👇','☝️','✋','🤚','🖐',
    '🖖','👋','🤝','🙏','✍️','💅','🤳','💪','🦾','🦵','🦶','👂','🦻','👃','🧠','🦷',
    '❤️','🧡','💛','💚','💙','💜','🖤','🤍','🤎','💔','❣️','💕','💞','💓','💗','💖',
    '💘','💝','💟','✨','⭐','🌟','💫','⚡','🔥','💥','💯','🎉','🎊','🎁','🎈','🧧',
    '🌹','🌸','🌺','🌻','🌼','🌷','🍀','🌈','☀️','🌙','⛅','🌧','⛈','❄️','⛄','🌊',
    '🍎','🍊','🍋','🍌','🍉','🍇','🍓','🍒','🍑','🥭','🍍','🥥','🥝','🍅','🥑','🍆',
    '🍔','🍟','🍕','🌭','🥪','🌮','🍜','🍲','🍛','🍣','🍱','🍚','🍙','🍘','🍥','🥟',
    '☕','🍵','🧃','🥤','🍺','🍻','🥂','🍷','🥃','🍸','🍹','🍾','🧉','🍽','🍴','🥄',
    '⚽','🏀','🏈','⚾','🎾','🏐','🏉','🎱','🏓','🏸','🥊','🥋','⛳','🏹','🎣','🎽',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 260,
      color: const Color(0xFFF5F7FA),
      child: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 8,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
        ),
        itemCount: _emojis.length,
        itemBuilder: (context, i) => InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onEmoji(_emojis[i]),
          child: Center(child: Text(_emojis[i], style: const TextStyle(fontSize: 24))),
        ),
      ),
    );
  }
}
