import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/official_accounts_service.dart';

const _blue = Color(0xFF0D6EFD);

/// Creates an Official Account (حساب رسمي) for the signed-in user.
class OfficialAccountFormPage extends StatefulWidget {
  const OfficialAccountFormPage({super.key});

  @override
  State<OfficialAccountFormPage> createState() => _OfficialAccountFormPageState();
}

class _OfficialAccountFormPageState extends State<OfficialAccountFormPage> {
  final _name = TextEditingController();
  final _bio = TextEditingController();
  String _kind = 'personal';
  Uint8List? _avatar;
  String _avatarExt = 'jpg';
  bool _saving = false;

  Future<void> _pickAvatar() async {
    final files = await FilePicker.pickFiles(type: FileType.image);
    if (files.isEmpty) return;
    final file = files.first;
    final bytes = await file.readAsBytes();
    setState(() {
      _avatar = bytes;
      _avatarExt = file.extension ?? 'jpg';
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل اسم الحساب.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final service = const OfficialAccountsService();
      String? avatarUrl;
      if (_avatar != null) avatarUrl = await service.uploadImage(_avatar!, _avatarExt, folder: 'avatars');
      await service.createAccount(name: name, bio: _bio.text.trim(), kind: _kind, avatarUrl: avatarUrl);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إنشاء الحساب الرسمي.')));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر الإنشاء: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('حساب رسمي جديد')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: InkWell(
                onTap: _pickAvatar,
                borderRadius: BorderRadius.circular(50),
                child: CircleAvatar(
                  radius: 44,
                  backgroundColor: const Color(0xFFE7F0FF),
                  backgroundImage: _avatar == null ? null : MemoryImage(_avatar!),
                  child: _avatar == null ? const Icon(Icons.add_a_photo_outlined, color: _blue, size: 30) : null,
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'اسم الحساب', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bio,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'نبذة', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _kind,
              decoration: const InputDecoration(labelText: 'النوع', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'personal', child: Text('شخصي')),
                DropdownMenuItem(value: 'business', child: Text('تجاري')),
              ],
              onChanged: (v) => setState(() => _kind = v ?? _kind),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check),
              label: Text(_saving ? 'جارٍ الإنشاء…' : 'إنشاء الحساب'),
            ),
          ],
        ),
      ),
    );
  }
}
