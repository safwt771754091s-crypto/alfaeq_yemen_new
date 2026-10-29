import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/group_join_service.dart';

const _navy = Color(0xFF0A2540);
const _green = Color(0xFF07C160);

/// WeChat-style "group QR" sheet: shows a scannable code that anyone signed in
/// can scan to join this group, with copy/share and a rotate action.
class GroupQrPage extends StatefulWidget {
  final String threadId;
  final String title;
  const GroupQrPage({super.key, required this.threadId, required this.title});

  @override
  State<GroupQrPage> createState() => _GroupQrPageState();
}

class _GroupQrPageState extends State<GroupQrPage> {
  String? _code;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool rotate = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final code = await const GroupJoinService().joinCode(widget.threadId, rotate: rotate);
      if (!mounted) return;
      setState(() {
        _code = code;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذر تجهيز رمز المجموعة: $e';
        _loading = false;
      });
    }
  }

  Future<void> _rotate() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تجديد الرمز؟'),
        content: const Text('سيتوقف الرمز الحالي عن العمل ولا يمكن لمن معه الانضمام. هل تريد المتابعة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('تجديد')),
        ],
      ),
    );
    if (ok == true) await _load(rotate: true);
  }

  Future<void> _copy() async {
    final code = _code;
    if (code == null) return;
    await Clipboard.setData(ClipboardData(text: GroupJoinService.payload(code)));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ رابط المجموعة ✅')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          backgroundColor: _navy,
          foregroundColor: Colors.white,
          title: const Text('رمز المجموعة', style: TextStyle(fontWeight: FontWeight.w900)),
          actions: [
            IconButton(tooltip: 'تجديد الرمز', onPressed: _code == null ? null : _rotate, icon: const Icon(Icons.refresh)),
          ],
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _loading
                ? const CircularProgressIndicator()
                : _error != null
                    ? Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red))
                    : _body(),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    final code = _code!;
    final payload = GroupJoinService.payload(code);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          const Text('امسح الرمز للانضمام إلى المجموعة', style: TextStyle(color: Colors.black54)),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.black12)),
            child: QrImageView(
              data: payload,
              version: QrVersions.auto,
              size: 220,
              gapless: true,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          SelectableText(
            code,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 18, letterSpacing: 2, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(onPressed: _copy, icon: const Icon(Icons.copy), label: const Text('نسخ الرابط')),
              const SizedBox(width: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: _green),
                onPressed: _rotate,
                icon: const Icon(Icons.autorenew),
                label: const Text('تجديد'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'ملاحظة: كل من يملك هذا الرمز يستطيع الانضمام. جدّده إذا تسرّب.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black45, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
