import 'package:flutter/material.dart';

import '../services/public_content_service.dart';

/// Staff editor for the public "آخر تحديثات الفائق" feed shown on the home
/// page. Updates are stored in `public_site_updates`; publishing one makes it
/// appear on the live home page immediately.
class SiteUpdatesPage extends StatefulWidget {
  const SiteUpdatesPage({super.key});
  @override
  State<SiteUpdatesPage> createState() => _SiteUpdatesPageState();
}

class _SiteUpdatesPageState extends State<SiteUpdatesPage> {
  final _service = const PublicContentService();
  List<SiteUpdateDocument> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _service.allUpdates();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _edit({SiteUpdateDocument? existing}) async {
    final data = existing?.data ?? const <String, dynamic>{};
    final title = TextEditingController(text: data['title']?.toString() ?? '');
    final summary = TextEditingController(text: data['summary']?.toString() ?? '');
    final body = TextEditingController(text: data['body']?.toString() ?? '');
    final imageUrl = TextEditingController(text: data['image_url']?.toString() ?? '');
    final ctaLabel = TextEditingController(text: data['cta_label']?.toString() ?? '');
    final ctaUrl = TextEditingController(text: data['cta_url']?.toString() ?? '');
    var published = (data['status']?.toString() ?? 'published') == 'published';

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'تحديث جديد' : 'تعديل التحديث'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: title, decoration: const InputDecoration(labelText: 'العنوان', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: summary, maxLines: 2, decoration: const InputDecoration(labelText: 'ملخص قصير', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: body, maxLines: 4, decoration: const InputDecoration(labelText: 'النص الكامل (اختياري)', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: imageUrl, decoration: const InputDecoration(labelText: 'رابط صورة (اختياري)', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: ctaLabel, decoration: const InputDecoration(labelText: 'نص الزر (اختياري)', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: ctaUrl, decoration: const InputDecoration(labelText: 'رابط الزر (اختياري)', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                SwitchListTile(contentPadding: EdgeInsets.zero, value: published, title: const Text('نشر التحديث'), subtitle: const Text('عند التعطيل يُحفظ كمسودة ولا يظهر للعملاء'), onChanged: (v) => setDialogState(() => published = v)),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );

    if (saved != true) return;
    if (title.text.trim().isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('العنوان مطلوب.')));
      return;
    }
    try {
      await _service.upsertUpdate(
        id: existing?.id,
        title: title.text,
        summary: summary.text,
        body: body.text,
        imageUrl: imageUrl.text,
        ctaLabel: ctaLabel.text,
        ctaUrl: ctaUrl.text,
        status: published ? 'published' : 'draft',
        sortOrder: (data['sort_order'] as num?)?.toInt() ?? 0,
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ التحديث.')));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر الحفظ: $e')));
    }
  }

  Future<void> _delete(SiteUpdateDocument item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف التحديث'),
        content: const Text('هل تريد حذف هذا التحديث نهائياً؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.deleteUpdate(item.id);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر الحذف: $e')));
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: const Text('تحديثات الصفحة الرئيسية')),
          floatingActionButton: FloatingActionButton.extended(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('تحديث جديد')),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('تعذر تحميل التحديثات: $_error', textAlign: TextAlign.center)))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
                        const Text('كل تحديث يُنشر يظهر فوراً في قسم «آخر تحديثات الفائق» بالصفحة الرئيسية.', style: TextStyle(color: Colors.black54)),
                        const SizedBox(height: 12),
                        if (_items.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('لا توجد تحديثات بعد. أضف أول تحديث ليظهر للعملاء.'))),
                        ..._items.map((item) {
                          final d = item.data;
                          final isPublished = (d['status']?.toString() ?? '') == 'published';
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              title: Text(d['title']?.toString() ?? 'تحديث', style: const TextStyle(fontWeight: FontWeight.w800)),
                              subtitle: Text(d['summary']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                              leading: Icon(isPublished ? Icons.public : Icons.edit_note, color: isPublished ? Colors.green : Colors.orange),
                              trailing: PopupMenuButton<String>(onSelected: (a) { if (a == 'edit') _edit(existing: item); if (a == 'delete') _delete(item); }, itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('تعديل')), PopupMenuItem(value: 'delete', child: Text('حذف'))]),
                            ),
                          );
                        }),
                      ]),
                    ),
        ),
      );
}
