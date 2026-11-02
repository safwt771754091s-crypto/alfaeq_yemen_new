import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/official_accounts_service.dart';

/// Publishes an article to an Official Account the user owns.
class OfficialArticleFormPage extends StatefulWidget {
  final String accountId;
  const OfficialArticleFormPage({super.key, required this.accountId});

  @override
  State<OfficialArticleFormPage> createState() => _OfficialArticleFormPageState();
}

class _OfficialArticleFormPageState extends State<OfficialArticleFormPage> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  Uint8List? _cover;
  String _coverExt = 'jpg';
  bool _saving = false;

  Future<void> _pickCover() async {
    final files = await FilePicker.pickFiles(type: FileType.image);
    if (files.isEmpty) return;
    final file = files.first;
    final bytes = await file.readAsBytes();
    setState(() {
      _cover = bytes;
      _coverExt = file.extension ?? 'jpg';
    });
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل عنوان المقالة.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final service = const OfficialAccountsService();
      String? coverUrl;
      if (_cover != null) coverUrl = await service.uploadImage(_cover!, _coverExt, folder: 'covers');
      await service.publishArticle(accountId: widget.accountId, title: title, body: _body.text.trim(), coverUrl: coverUrl);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نشر المقالة.')));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر النشر: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('نشر مقالة')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'عنوان المقالة', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _body,
              maxLines: 10,
              decoration: const InputDecoration(labelText: 'المحتوى', alignLabelWithHint: true, border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickCover,
              icon: const Icon(Icons.image_outlined),
              label: Text(_cover == null ? 'إضافة صورة الغلاف' : 'تغيير صورة الغلاف'),
            ),
            if (_cover != null) ...[
              const SizedBox(height: 10),
              ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(_cover!, height: 160, fit: BoxFit.cover)),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.publish_outlined),
              label: Text(_saving ? 'جارٍ النشر…' : 'نشر'),
            ),
          ],
        ),
      ),
    );
  }
}
