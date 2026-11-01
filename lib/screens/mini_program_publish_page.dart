import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/mini_programs_service.dart';

/// Publish a new mini program (نشر برنامج مصغّر).
///
/// Staff only: the backend RLS rejects non-staff inserts, and this page also
/// hides the form from everyone else so the intent is clear up front.
class MiniProgramPublishPage extends StatefulWidget {
  const MiniProgramPublishPage({super.key});

  @override
  State<MiniProgramPublishPage> createState() => _MiniProgramPublishPageState();
}

class _MiniProgramPublishPageState extends State<MiniProgramPublishPage> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _route = TextEditingController(text: 'section:markets');
  final _category = TextEditingController(text: 'عام');
  String _icon = 'explore';
  bool _featured = false;
  bool _verified = false;
  bool _checking = true;
  bool _canPublish = false;
  bool _saving = false;

  static const _icons = <String>[
    'explore', 'storefront', 'restaurant', 'pharmacy', 'beauty', 'construction',
    'car', 'flight', 'hotel', 'account_balance', 'handyman', 'devices', 'home',
    'work', 'school', 'medical', 'play', 'photo', 'live',
    'account_balance_wallet', 'auto_awesome', 'support_agent',
  ];

  @override
  void initState() {
    super.initState();
    _checkAccess();
  }

  Future<void> _checkAccess() async {
    final allowed = await AuthService().canOpenDeveloperCenter();
    if (!mounted) return;
    setState(() { _canPublish = allowed; _checking = false; });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final route = _route.text.trim();
    if (name.isEmpty || route.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل اسم البرنامج ومسار الوصول.')));
      return;
    }
    if (!(route.startsWith('section:') || route.startsWith('screen:'))) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('المسار يجب أن يبدأ بـ section: أو screen:')));
      return;
    }
    setState(() => _saving = true);
    try {
      await const MiniProgramsService().register(
        name: name,
        description: _description.text.trim(),
        icon: _icon,
        route: route,
        category: _category.text.trim().isEmpty ? 'عام' : _category.text.trim(),
        featured: _featured,
        verified: _verified,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نشر البرنامج المصغّر.')));
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
    _name.dispose();
    _description.dispose();
    _route.dispose();
    _category.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('نشر برنامج مصغّر')),
        body: _checking
            ? const Center(child: CircularProgressIndicator())
            : !_canPublish
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('نشر البرامج المصغّرة متاح لفريق المنصة فقط.', textAlign: TextAlign.center),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      TextField(
                        controller: _name,
                        decoration: const InputDecoration(labelText: 'اسم البرنامج', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _description,
                        maxLines: 3,
                        decoration: const InputDecoration(labelText: 'الوصف', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _icon,
                        decoration: const InputDecoration(labelText: 'الأيقونة', border: OutlineInputBorder()),
                        items: [for (final i in _icons) DropdownMenuItem(value: i, child: Text(i))],
                        onChanged: (v) => setState(() => _icon = v ?? _icon),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _route,
                        decoration: const InputDecoration(
                          labelText: 'مسار الوصول',
                          helperText: 'مثال: section:markets أو screen:reels',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _category,
                        decoration: const InputDecoration(labelText: 'التصنيف', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 6),
                      SwitchListTile(
                        value: _featured,
                        onChanged: (v) => setState(() => _featured = v),
                        title: const Text('مميّز'),
                      ),
                      SwitchListTile(
                        value: _verified,
                        onChanged: (v) => setState(() => _verified = v),
                        title: const Text('موثّق'),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: const Icon(Icons.publish_outlined),
                        label: Text(_saving ? 'جارٍ النشر…' : 'نشر البرنامج'),
                      ),
                    ],
                  ),
      ),
    );
  }
}
