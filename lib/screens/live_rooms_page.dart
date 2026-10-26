import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../core/sound_prefs.dart';
import '../services/live_service.dart';

const _blue = Color(0xFF0D6EFD);
const _navy = Color(0xFF0A2540);
const _surface = Color(0xFFF5F7FA);

/// WeChat-style live lobby (البث المباشر): who is live right now.
class LiveLobbyPage extends StatefulWidget {
  const LiveLobbyPage({super.key});

  @override
  State<LiveLobbyPage> createState() => _LiveLobbyPageState();
}

class _LiveLobbyPageState extends State<LiveLobbyPage> {
  final _service = const LiveService();
  late Future<List<Map<String, dynamic>>> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _service.rooms(status: 'all');
  }

  void _reload() => setState(() => _future = _service.rooms(status: 'all'));

  Future<void> _startRoom() async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('بدء بث مباشر'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'عنوان البث', hintText: 'مثال: عرض اليوم'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('ابدأ')),
        ],
      ),
    );
    if (title == null) return;
    setState(() => _busy = true);
    try {
      final roomId = await _service.startRoom(title: title);
      if (!mounted) return;
      _reload();
      await Navigator.push(context, MaterialPageRoute(builder: (_) => LiveRoomPage(roomId: roomId, isHost: true)));
      _reload();
    } catch (e) {
      _snack('تعذر بدء البث: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: _surface,
          appBar: AppBar(
            backgroundColor: _navy,
            foregroundColor: Colors.white,
            title: const Text('البث المباشر', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _busy ? null : _startRoom,
            backgroundColor: _blue,
            icon: const Icon(Icons.sensors),
            label: const Text('ابدأ بثّك', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
          body: FutureBuilder<List<Map<String, dynamic>>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final rows = snap.data ?? const [];
              if (snap.hasError || rows.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.sensors_off, size: 64, color: Colors.black26),
                        SizedBox(height: 12),
                        Text('لا يوجد بث مباشر الآن', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _navy)),
                        SizedBox(height: 6),
                        Text('ابدأ بثّك أو عد لاحقاً.', style: TextStyle(color: Colors.black54)),
                      ],
                    ),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) => _RoomCard(room: rows[i], onOpen: () => _openRoom(rows[i])),
              );
            },
          ),
        ),
      );

  Future<void> _openRoom(Map<String, dynamic> room) async {
    final id = room['id']?.toString() ?? '';
    if (id.isEmpty) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => LiveRoomPage(roomId: id)));
    _reload();
  }
}

class _RoomCard extends StatelessWidget {
  final Map<String, dynamic> room;
  final VoidCallback onOpen;

  const _RoomCard({required this.room, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final live = room['status'] == 'live';
    final host = room['host_name']?.toString() ?? 'مستخدم الفائق';
    final title = room['title']?.toString() ?? '';
    final viewers = (room['viewer_count'] as num?)?.toInt() ?? 0;
    final cover = room['cover_url']?.toString() ?? '';

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFE3E8EF))),
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (cover.isNotEmpty)
                    Image.network(cover, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder())
                  else
                    _placeholder(),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: _badge(live ? 'مباشر' : 'منتهي', live ? Colors.red : Colors.black54),
                  ),
                  Positioned(
                    bottom: 10,
                    left: 10,
                    child: _badge('$viewers 👁', Colors.black54),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text('@$host', style: const TextStyle(fontWeight: FontWeight.w900)),
              subtitle: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.chevron_left),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [_navy, _blue]),
        ),
        child: const Center(child: Icon(Icons.sensors, color: Colors.white54, size: 46)),
      );

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
      );
}

/// The watch room: player, live chat, gifts and (for the host) an end button.
class LiveRoomPage extends StatefulWidget {
  final String roomId;
  final bool isHost;

  const LiveRoomPage({required this.roomId, this.isHost = false});

  @override
  State<LiveRoomPage> createState() => _LiveRoomPageState();
}

class _LiveRoomPageState extends State<LiveRoomPage> {
  final _service = const LiveService();
  final _input = TextEditingController();
  VideoPlayerController? _video;
  List<Map<String, dynamic>> _messages = const [];
  bool _ready = false;
  bool _muted = true;

  @override
  void initState() {
    super.initState();
    _service.registerView(widget.roomId, 1);
    _loadMessages();
    _initVideo();
  }

  @override
  void dispose() {
    _service.registerView(widget.roomId, -1);
    _input.dispose();
    _video?.dispose();
    super.dispose();
  }

  Future<void> _initVideo() async {
    final rows = await _service.rooms(status: 'all');
    final room = rows.firstWhere((r) => r['id']?.toString() == widget.roomId, orElse: () => const {});
    final url = room['playback_url']?.toString() ?? '';
    if (url.isEmpty) return;
    final soundOn = await SoundPrefs.load();
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await controller.initialize();
      await controller.setLooping(true);
      _muted = !soundOn;
      await controller.setVolume(_muted ? 0 : 1);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _video = controller;
        _ready = true;
      });
      await controller.play();
    } catch (_) {
      await controller.dispose();
    }
  }

  Future<void> _loadMessages() async {
    try {
      final rows = await _service.messages(widget.roomId);
      if (mounted) setState(() => _messages = rows);
    } catch (_) {}
  }

  Future<void> _send() async {
    final body = _input.text.trim();
    if (body.isEmpty) return;
    _input.clear();
    try {
      await _service.sendMessage(widget.roomId, body);
      await _loadMessages();
    } catch (e) {
      _snack('تعذر الإرسال: $e');
    }
  }

  Future<void> _gift() async {
    try {
      await _service.sendGift(widget.roomId, 'أرسل هدية 🎁');
      await _loadMessages();
    } catch (e) {
      _snack('تعذر إرسال الهدية: $e');
    }
  }

  Future<void> _end() async {
    try {
      await _service.endRoom(widget.roomId);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      _snack('تعذر إنهاء البث: $e');
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: const Text('غرفة البث', style: TextStyle(fontWeight: FontWeight.w900)),
            actions: [
              if (widget.isHost)
                TextButton(
                  onPressed: _end,
                  child: const Text('إنهاء', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900)),
                ),
            ],
          ),
          body: Column(
            children: [
              AspectRatio(aspectRatio: 16 / 9, child: _stage()),
              Expanded(child: _chat()),
              _composer(),
            ],
          ),
        ),
      );

  Widget _stage() {
    final video = _video;
    if (_ready && video != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Center(child: AspectRatio(aspectRatio: video.value.aspectRatio == 0 ? 16 / 9 : video.value.aspectRatio, child: VideoPlayer(video))),
          Positioned(
            bottom: 8,
            left: 8,
            child: IconButton(
              onPressed: () => setState(() {
                _muted = !_muted;
                video.setVolume(_muted ? 0 : 1);
                SoundPrefs.set(!_muted);
              }),
              icon: Icon(_muted ? Icons.volume_off : Icons.volume_up, color: Colors.white),
            ),
          ),
        ],
      );
    }
    return Container(
      color: Colors.black,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sensors, color: Colors.white38, size: 52),
            SizedBox(height: 8),
            Text('في انتظار إشارة البث', style: TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }

  Widget _chat() => Container(
        color: const Color(0xFF0E1420),
        child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: _messages.length,
          itemBuilder: (context, i) {
            final m = _messages[i];
            final kind = m['kind']?.toString() ?? 'chat';
            final name = m['author_name']?.toString() ?? 'مستخدم';
            final body = m['body']?.toString() ?? '';
            if (kind == 'gift') {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text('🎁 $name $body', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.w800)),
              );
            }
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: RichText(
                text: TextSpan(
                  children: [
                    TextSpan(text: '$name: ', style: const TextStyle(color: _blue, fontWeight: FontWeight.w900)),
                    TextSpan(text: body, style: const TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            );
          },
        ),
      );

  Widget _composer() => SafeArea(
        top: false,
        child: Container(
          color: const Color(0xFF0E1420),
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  style: const TextStyle(color: Colors.white),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: 'اكتب رسالة...',
                    hintStyle: const TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: Colors.white10,
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(onPressed: _gift, icon: const Icon(Icons.card_giftcard, color: Colors.amber)),
              IconButton.filled(onPressed: _send, icon: const Icon(Icons.send)),
            ],
          ),
        ),
      );
}
