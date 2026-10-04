import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/moments_service.dart';
import '../services/supabase_service.dart';

const _blue = Color(0xFF0D6EFD);
const _navy = Color(0xFF0A2540);
const _surface = Color(0xFFF5F7FA);

/// WeChat-style Moments (朋友圈) feed.
class MomentsPage extends StatefulWidget {
  const MomentsPage({super.key});

  @override
  State<MomentsPage> createState() => _MomentsPageState();
}

class _MomentsPageState extends State<MomentsPage> {
  final _service = const MomentsService();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.feed();
  }

  void _reload() => setState(() => _future = _service.feed());

  Future<void> _openComposer() async {
    final published = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const MomentsComposerPage()),
    );
    if (published == true) _reload();
  }

  Future<void> _toggleLike(Map<String, dynamic> moment) async {
    final id = moment['id']?.toString() ?? '';
    final liked = moment['liked_by_me'] == true;
    try {
      await _service.setLike(id, !liked);
      if (!mounted) return;
      setState(() {
        moment['liked_by_me'] = !liked;
        final count = (moment['like_count'] as num?)?.toInt() ?? 0;
        moment['like_count'] = liked ? (count - 1).clamp(0, 1 << 31) : count + 1;
      });
    } catch (e) {
      _snack('تعذر تحديث الإعجاب: $e');
    }
  }

  Future<void> _openComments(Map<String, dynamic> moment) async {
    final id = moment['id']?.toString() ?? '';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _CommentsSheet(momentId: id, service: _service, onChanged: _reload),
    );
  }

  Future<void> _delete(Map<String, dynamic> moment) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف المنشور'),
        content: const Text('هل تريد حذف هذا المنشور نهائيًا؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.deleteMoment(moment['id']?.toString() ?? '');
      _reload();
    } catch (e) {
      _snack('تعذر الحذف: $e');
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final me = SupabaseService.client.auth.currentUser?.id;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _surface,
        appBar: AppBar(
          backgroundColor: _navy,
          foregroundColor: Colors.white,
          title: const Text('اللحظات', style: TextStyle(fontWeight: FontWeight.w900)),
          actions: [
            IconButton(onPressed: _reload, icon: const Icon(Icons.refresh), tooltip: 'تحديث'),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _openComposer,
          backgroundColor: _blue,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('نشر لحظة', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _EmptyState(icon: Icons.cloud_off, title: 'تعذر تحميل اللحظات', subtitle: '${snapshot.error}');
            }
            final rows = snapshot.data ?? const <Map<String, dynamic>>[];
            if (rows.isEmpty) {
              return const _EmptyState(icon: Icons.auto_awesome_outlined, title: 'لا توجد لحظات بعد', subtitle: 'كن أول من يشارك لحظة مع مجتمع الفائق.');
            }
            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                itemCount: rows.length,
                itemBuilder: (context, i) {
                  final moment = rows[i];
                  return _MomentCard(
                    moment: moment,
                    isMine: moment['author_id']?.toString() == me,
                    onLike: () => _toggleLike(moment),
                    onComment: () => _openComments(moment),
                    onDelete: () => _delete(moment),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MomentCard extends StatelessWidget {
  final Map<String, dynamic> moment;
  final bool isMine;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onDelete;

  const _MomentCard({
    required this.moment,
    required this.isMine,
    required this.onLike,
    required this.onComment,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final name = (moment['author_name'] ?? 'مستخدم الفائق').toString();
    final avatar = moment['author_avatar']?.toString();
    final content = (moment['content'] ?? '').toString();
    final media = (moment['media_urls'] as List?)?.whereType<String>().toList() ?? const <String>[];
    final liked = moment['liked_by_me'] == true;
    final likeCount = (moment['like_count'] as num?)?.toInt() ?? 0;
    final commentCount = (moment['comment_count'] as num?)?.toInt() ?? 0;
    final createdAt = DateTime.tryParse(moment['created_at']?.toString() ?? '')?.toLocal();

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFFE3E8EF))),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFFF1F6FF),
                backgroundImage: (avatar != null && avatar.isNotEmpty) ? NetworkImage(avatar) : null,
                child: (avatar == null || avatar.isEmpty)
                    ? const Icon(Icons.person_outline, color: _blue)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.w900, color: _navy)),
                  Text(_timeAgo(createdAt), style: const TextStyle(fontSize: 12, color: Colors.black45)),
                ]),
              ),
              if (isMine)
                IconButton(onPressed: onDelete, icon: const Icon(Icons.delete_outline, color: Colors.black38), tooltip: 'حذف'),
            ]),
            if (content.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(content, style: const TextStyle(fontSize: 15.5, height: 1.5)),
            ],
            if (media.isNotEmpty) ...[
              const SizedBox(height: 10),
              _MediaGrid(urls: media),
            ],
            const SizedBox(height: 6),
            Row(children: [
              _ActionChip(
                icon: liked ? Icons.favorite : Icons.favorite_border,
                color: liked ? Colors.redAccent : _navy,
                label: likeCount > 0 ? '$likeCount' : 'إعجاب',
                onTap: onLike,
              ),
              const SizedBox(width: 8),
              _ActionChip(
                icon: Icons.mode_comment_outlined,
                color: _navy,
                label: commentCount > 0 ? '$commentCount' : 'تعليق',
                onTap: onComment,
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  const _ActionChip({required this.icon, required this.color, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
          ]),
        ),
      );
}

class _MediaGrid extends StatelessWidget {
  final List<String> urls;
  const _MediaGrid({required this.urls});

  @override
  Widget build(BuildContext context) {
    if (urls.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.network(urls.first, fit: BoxFit.cover, width: double.infinity, height: 220, errorBuilder: _broken),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: urls.length.clamp(0, 9),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 6, mainAxisSpacing: 6),
      itemBuilder: (context, i) => ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(urls[i], fit: BoxFit.cover, errorBuilder: _broken),
      ),
    );
  }

  Widget _broken(BuildContext context, Object error, StackTrace? stack) => Container(
        color: const Color(0xFFF1F6FF),
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image_outlined, color: _blue),
      );
}

class _CommentsSheet extends StatefulWidget {
  final String momentId;
  final MomentsService service;
  final VoidCallback onChanged;
  const _CommentsSheet({required this.momentId, required this.service, required this.onChanged});

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _controller = TextEditingController();
  late Future<List<Map<String, dynamic>>> _future;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _future = widget.service.comments(widget.momentId);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.service.comment(widget.momentId, text);
      _controller.clear();
      setState(() => _future = widget.service.comments(widget.momentId));
      widget.onChanged();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إرسال التعليق: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(children: [
            const SizedBox(height: 10),
            Container(width: 44, height: 4, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2))),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('التعليقات', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: _navy)),
            ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final rows = snapshot.data ?? const <Map<String, dynamic>>[];
                  if (rows.isEmpty) {
                    return const Center(child: Text('لا توجد تعليقات بعد. اكتب أول تعليق.', style: TextStyle(color: Colors.black45)));
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 16),
                    itemBuilder: (context, i) {
                      final row = rows[i];
                      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const CircleAvatar(radius: 16, backgroundColor: Color(0xFFF1F6FF), child: Icon(Icons.person_outline, size: 18, color: _blue)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text((row['author_name'] ?? 'مستخدم').toString(), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                            const SizedBox(height: 2),
                            Text((row['body'] ?? '').toString(), style: const TextStyle(height: 1.4)),
                          ]),
                        ),
                      ]);
                    },
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: 'اكتب تعليقًا…',
                      filled: true,
                      fillColor: _surface,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _sending
                    ? const SizedBox(width: 44, height: 44, child: Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2)))
                    : IconButton.filled(onPressed: _send, icon: const Icon(Icons.send), style: IconButton.styleFrom(backgroundColor: _blue)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class MomentsComposerPage extends StatefulWidget {
  const MomentsComposerPage({super.key});

  @override
  State<MomentsComposerPage> createState() => _MomentsComposerPageState();
}

class _MomentsComposerPageState extends State<MomentsComposerPage> {
  final _service = const MomentsService();
  final _controller = TextEditingController();
  final List<_PickedImage> _images = [];
  String _visibility = 'public';
  bool _publishing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (result == null) return;
    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null) continue;
      final ext = (file.extension ?? 'jpg');
      _images.add(_PickedImage(bytes: bytes, extension: ext));
    }
    setState(() {});
  }

  Future<void> _publish() async {
    final text = _controller.text.trim();
    if (text.isEmpty && _images.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اكتب نصًا أو أضف صورة.')));
      return;
    }
    setState(() => _publishing = true);
    try {
      final urls = <String>[];
      for (final image in _images) {
        urls.add(await _service.uploadImage(image.bytes, image.extension));
      }
      await _service.publish(content: text, mediaUrls: urls, visibility: _visibility);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _publishing = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر النشر: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: _navy,
          foregroundColor: Colors.white,
          title: const Text('لحظة جديدة', style: TextStyle(fontWeight: FontWeight.w900)),
          actions: [
            TextButton(
              onPressed: _publishing ? null : _publish,
              child: _publishing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('نشر', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _controller,
              maxLines: 6,
              maxLength: 2000,
              decoration: const InputDecoration(
                hintText: 'بماذا تفكر؟ شارك لحظتك مع مجتمع الفائق…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            if (_images.isNotEmpty)
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _images.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
                itemBuilder: (context, i) => Stack(children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(_images[i].bytes, fit: BoxFit.cover),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    left: 4,
                    child: GestureDetector(
                      onTap: () => setState(() => _images.removeAt(i)),
                      child: Container(
                        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                        child: const Icon(Icons.close, color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                ]),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _publishing ? null : _pickImages,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(_images.isEmpty ? 'إضافة صور' : 'إضافة المزيد (${_images.length})'),
            ),
            const SizedBox(height: 16),
            const Text('من يرى المنشور؟', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'public', label: Text('عام'), icon: Icon(Icons.public)),
                ButtonSegment(value: 'followers', label: Text('المتابعون'), icon: Icon(Icons.people_outline)),
                ButtonSegment(value: 'private', label: Text('خاص'), icon: Icon(Icons.lock_outline)),
              ],
              selected: {_visibility},
              onSelectionChanged: (s) => setState(() => _visibility = s.first),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickedImage {
  final Uint8List bytes;
  final String extension;
  const _PickedImage({required this.bytes, required this.extension});
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _EmptyState({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 64, color: Colors.black26),
            const SizedBox(height: 14),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _navy)),
            const SizedBox(height: 6),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
          ]),
        ),
      );
}

String _timeAgo(DateTime? time) {
  if (time == null) return '';
  final diff = DateTime.now().difference(time);
  if (diff.inSeconds < 60) return 'الآن';
  if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes} دقيقة';
  if (diff.inHours < 24) return 'قبل ${diff.inHours} ساعة';
  if (diff.inDays < 30) return 'قبل ${diff.inDays} يوم';
  return '${time.year}/${time.month.toString().padLeft(2, '0')}/${time.day.toString().padLeft(2, '0')}';
}
