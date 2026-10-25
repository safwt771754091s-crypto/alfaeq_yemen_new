import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../services/reels_service.dart';

const _blue = Color(0xFF0D6EFD);
const _navy = Color(0xFF0A2540);
const _surface = Color(0xFFF5F7FA);

/// WeChat-Channels style short-video feed (فيديو الفائق).
class ReelsPage extends StatefulWidget {
  const ReelsPage({super.key});

  @override
  State<ReelsPage> createState() => _ReelsPageState();
}

class _ReelsPageState extends State<ReelsPage> {
  final _service = const ReelsService();
  final _controller = PageController();
  late Future<List<Map<String, dynamic>>> _future;
  List<Map<String, dynamic>> _reels = const [];
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await _service.feed();
    _reels = rows;
    if (rows.isNotEmpty) _service.registerView(rows.first['id'].toString());
    return rows;
  }

  void _reload() => setState(() => _future = _load());

  void _onPageChanged(int i) {
    setState(() => _index = i);
    if (i < _reels.length) _service.registerView(_reels[i]['id'].toString());
  }

  Future<void> _openComposer() async {
    final published = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ReelsComposerPage()),
    );
    if (published == true) _reload();
  }

  Future<void> _toggleLike(Map<String, dynamic> reel) async {
    final id = reel['id']?.toString() ?? '';
    final liked = reel['liked_by_me'] == true;
    try {
      await _service.setLike(id, !liked);
      if (!mounted) return;
      setState(() {
        reel['liked_by_me'] = !liked;
        final count = (reel['like_count'] as num?)?.toInt() ?? 0;
        reel['like_count'] = liked ? (count - 1).clamp(0, 1 << 31) : count + 1;
      });
    } catch (e) {
      _snack('تعذر تحديث الإعجاب: $e');
    }
  }

  Future<void> _openComments(Map<String, dynamic> reel) async {
    final id = reel['id']?.toString() ?? '';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _CommentsSheet(reelId: id, service: _service, onChanged: _reload),
    );
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
            title: const Text('فيديو الفائق', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _openComposer,
            backgroundColor: _blue,
            icon: const Icon(Icons.videocam_outlined),
            label: const Text('انشر فيديو', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
          body: FutureBuilder<List<Map<String, dynamic>>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: Colors.white));
              }
              if (snap.hasError) {
                return _empty('تعذر تحميل الفيديوهات', '${snap.error}', _reload);
              }
              final rows = snap.data ?? const [];
              if (rows.isEmpty) {
                return _empty('لا توجد فيديوهات بعد', 'كن أول من ينشر فيديو على الفائق.', _reload);
              }
              return PageView.builder(
                controller: _controller,
                scrollDirection: Axis.vertical,
                itemCount: rows.length,
                onPageChanged: _onPageChanged,
                itemBuilder: (context, i) => _ReelView(
                  reel: rows[i],
                  active: i == _index,
                  onLike: () => _toggleLike(rows[i]),
                  onComments: () => _openComments(rows[i]),
                ),
              );
            },
          ),
        ),
      );

  Widget _empty(String title, String subtitle, VoidCallback onRetry) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.movie_creation_outlined, color: Colors.white54, size: 64),
              const SizedBox(height: 14),
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 18),
              FilledButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
            ],
          ),
        ),
      );
}

/// A single full-screen reel: the video, its author, caption and actions.
class _ReelView extends StatefulWidget {
  final Map<String, dynamic> reel;
  final bool active;
  final VoidCallback onLike;
  final VoidCallback onComments;

  const _ReelView({
    required this.reel,
    required this.active,
    required this.onLike,
    required this.onComments,
  });

  @override
  State<_ReelView> createState() => _ReelViewState();
}

class _ReelViewState extends State<_ReelView> {
  VideoPlayerController? _video;
  bool _ready = false;
  bool _failed = false;
  bool _muted = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final url = widget.reel['video_url']?.toString() ?? '';
    if (url.isEmpty) {
      setState(() => _failed = true);
      return;
    }
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(_muted ? 0 : 1);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _video = controller;
        _ready = true;
      });
      if (widget.active) await controller.play();
    } catch (_) {
      await controller.dispose();
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void didUpdateWidget(covariant _ReelView old) {
    super.didUpdateWidget(old);
    final video = _video;
    if (video == null) return;
    if (widget.active && !old.active) {
      video.play();
    } else if (!widget.active && old.active) {
      video.pause();
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final video = _video;
    if (video == null) return;
    setState(() {
      if (video.value.isPlaying) {
        video.pause();
      } else {
        video.play();
      }
    });
  }

  void _toggleMute() {
    final video = _video;
    if (video == null) return;
    setState(() {
      _muted = !_muted;
      video.setVolume(_muted ? 0 : 1);
    });
  }

  String get _author => widget.reel['author_name']?.toString().trim().isNotEmpty == true
      ? widget.reel['author_name'].toString()
      : 'مستخدم الفائق';

  @override
  Widget build(BuildContext context) {
    final caption = widget.reel['caption']?.toString() ?? '';
    final likeCount = (widget.reel['like_count'] as num?)?.toInt() ?? 0;
    final commentCount = (widget.reel['comment_count'] as num?)?.toInt() ?? 0;
    final viewCount = (widget.reel['view_count'] as num?)?.toInt() ?? 0;
    final liked = widget.reel['liked_by_me'] == true;
    final poster = widget.reel['thumbnail_url']?.toString() ?? '';

    return Stack(
      fit: StackFit.expand,
      children: [
        _stage(poster),
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.center,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withValues(alpha: .72)],
              ),
            ),
          ),
        ),
        Positioned(
          left: 12,
          bottom: 22,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _action(Icons.favorite, liked ? Colors.redAccent : Colors.white, likeCount.toString(), widget.onLike),
              const SizedBox(height: 18),
              _action(Icons.mode_comment_outlined, Colors.white, commentCount.toString(), widget.onComments),
              const SizedBox(height: 18),
              _action(_muted ? Icons.volume_off : Icons.volume_up, Colors.white, '', _toggleMute),
            ],
          ),
        ),
        Positioned(
          right: 16,
          left: 84,
          bottom: 26,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('@$_author', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
              if (caption.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(caption, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 14)),
              ],
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.play_circle_outline, color: Colors.white70, size: 16),
                const SizedBox(width: 4),
                Text('$viewCount مشاهدة', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ]),
            ],
          ),
        ),
        if (!_ready && !_failed)
          const Center(child: CircularProgressIndicator(color: Colors.white)),
        if (_failed)
          const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.broken_image_outlined, color: Colors.white54, size: 56),
                SizedBox(height: 10),
                Text('تعذر تشغيل الفيديو', style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _stage(String poster) {
    final video = _video;
    if (_ready && video != null) {
      return GestureDetector(
        onTap: _togglePlay,
        child: Center(
          child: AspectRatio(
            aspectRatio: video.value.aspectRatio == 0 ? 9 / 16 : video.value.aspectRatio,
            child: VideoPlayer(video),
          ),
        ),
      );
    }
    if (poster.isNotEmpty) {
      return Image.network(poster, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox.shrink());
    }
    return const SizedBox.shrink();
  }

  Widget _action(IconData icon, Color color, String label, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            if (label.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ],
        ),
      );
}

/// Composer: pick a video, add a caption, publish.
class ReelsComposerPage extends StatefulWidget {
  const ReelsComposerPage({super.key});

  @override
  State<ReelsComposerPage> createState() => _ReelsComposerPageState();
}

class _ReelsComposerPageState extends State<ReelsComposerPage> {
  final _service = const ReelsService();
  final _caption = TextEditingController();
  Uint8List? _bytes;
  String _extension = 'mp4';
  String _fileName = '';
  bool _busy = false;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp4', 'mov', 'webm', 'm4v'],
    );
    if (files.isEmpty) return;
    final file = files.single;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      _snack('تعذر قراءة الملف. جرّب ملفاً أصغر.');
      return;
    }
    setState(() {
      _bytes = bytes;
      _fileName = file.name;
      _extension = file.extension ?? 'mp4';
    });
  }

  Future<void> _publish() async {
    final bytes = _bytes;
    if (bytes == null) {
      _snack('اختر مقطع فيديو أولاً.');
      return;
    }
    setState(() => _busy = true);
    try {
      final url = await _service.uploadMedia(bytes, _extension);
      await _service.publish(caption: _caption.text, videoUrl: url);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      _snack('تعذر النشر: $e');
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
            title: const Text('فيديو جديد', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFE3E8EF))),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: _busy ? null : _pick,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Icon(_bytes == null ? Icons.video_library_outlined : Icons.check_circle, color: _bytes == null ? _blue : Colors.green, size: 46),
                        const SizedBox(height: 10),
                        Text(
                          _bytes == null ? 'اختر مقطع فيديو' : _fileName,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w800, color: _navy),
                        ),
                        const SizedBox(height: 4),
                        const Text('MP4 / MOV / WEBM — حتى 50 ميجابايت', style: TextStyle(color: Colors.black54, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _caption,
                maxLines: 3,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'وصف الفيديو',
                  hintText: 'اكتب وصفاً قصيراً...',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _busy ? null : _publish,
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.upload),
                label: Text(_busy ? 'جارٍ النشر...' : 'نشر الفيديو', style: const TextStyle(fontWeight: FontWeight.w800)),
                style: FilledButton.styleFrom(backgroundColor: _blue, minimumSize: const Size.fromHeight(50)),
              ),
            ],
          ),
        ),
      );
}

/// Comments bottom sheet shared by the feed.
class _CommentsSheet extends StatefulWidget {
  final String reelId;
  final ReelsService service;
  final VoidCallback onChanged;

  const _CommentsSheet({required this.reelId, required this.service, required this.onChanged});

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _input = TextEditingController();
  late Future<List<Map<String, dynamic>>> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = widget.service.comments(widget.reelId);
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _reload() => setState(() => _future = widget.service.comments(widget.reelId));

  Future<void> _send() async {
    final body = _input.text.trim();
    if (body.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.service.comment(widget.reelId, body);
      _input.clear();
      _reload();
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إرسال التعليق: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .62,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('التعليقات', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                ),
                const Divider(height: 1),
                Expanded(
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: _future,
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final rows = snap.data ?? const [];
                      if (rows.isEmpty) {
                        return const Center(child: Text('لا توجد تعليقات بعد.'));
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: rows.length,
                        separatorBuilder: (_, __) => const Divider(height: 18),
                        itemBuilder: (context, i) {
                          final c = rows[i];
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const CircleAvatar(radius: 16, child: Icon(Icons.person, size: 18)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(c['author_name']?.toString() ?? 'مستخدم', style: const TextStyle(fontWeight: FontWeight.w800)),
                                    const SizedBox(height: 2),
                                    Text(c['body']?.toString() ?? ''),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _input,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                          decoration: const InputDecoration(
                            hintText: 'أضف تعليقاً...',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _busy ? null : _send,
                        icon: const Icon(Icons.send),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
