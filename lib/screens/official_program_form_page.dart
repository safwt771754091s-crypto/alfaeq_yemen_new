import 'package:flutter/material.dart';

import '../core/app_sections.dart';
import '../services/mini_programs_service.dart';

const _blue = Color(0xFF0D6EFD);
const _navy = Color(0xFF0A2540);

/// Lets an Official Account owner bind a mini program (小程序) to their account.
/// The destination is chosen from the platform's real product surfaces so the
/// published program always opens.
class OfficialProgramFormPage extends StatefulWidget {
  final String accountId;
  final String accountName;
  const OfficialProgramFormPage({super.key, required this.accountId, required this.accountName});

  @override
  State<OfficialProgramFormPage> createState() => _OfficialProgramFormPageState();
}

class _OfficialProgramFormPageState extends State<OfficialProgramFormPage> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  String _icon = 'explore';
  late AppSection _section = appSections.first;
  bool _saving = false;

  static const _icons = <String, IconData>{
    'explore': Icons.explore_outlined,
    'storefront': Icons.storefront_outlined,
    'restaurant': Icons.restaurant_outlined,
    'pharmacy': Icons.local_pharmacy_outlined,
    'car': Icons.directions_car_outlined,
    'flight': Icons.flight_takeoff_outlined,
    'hotel': Icons.hotel_outlined,
    'work': Icons.work_outline,
    'school': Icons.school_outlined,
    'medical': Icons.medical_services_outlined,
    'play': Icons.play_circle_outline,
    'photo': Icons.photo_library_outlined,
  };

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اكتب اسم البرنامج.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await const MiniProgramsService().registerForAccount(
        accountId: widget.accountId,
        name: name,
        description: _description.text.trim(),
        icon: _icon,
        route: 'section:${_section.id}',
        publisherName: widget.accountName,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذّر إضافة البرنامج. تأكد من ملكية الحساب.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إضافة برنامج مصغّر'), backgroundColor: _blue, foregroundColor: Colors.white),
      body: ListView(
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
            decoration: const InputDecoration(labelText: 'وصف مختصر', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          const Text('الأيقونة', style: TextStyle(color: _navy, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in _icons.entries)
                ChoiceChip(
                  selected: _icon == entry.key,
                  onSelected: (_) => setState(() => _icon = entry.key),
                  avatar: Icon(entry.value, size: 18, color: _icon == entry.key ? Colors.white : _blue),
                  label: const SizedBox.shrink(),
                  selectedColor: _blue,
                ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('يفتح على', style: TextStyle(color: _navy, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          DropdownButtonFormField<AppSection>(
            initialValue: _section,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: [for (final s in appSections) DropdownMenuItem(value: s, child: Text(s.title))],
            onChanged: (s) => setState(() => _section = s ?? _section),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.add),
            label: const Text('إضافة البرنامج'),
          ),
        ],
      ),
    );
  }
}
