import 'package:flutter/material.dart';

import '../core/money.dart';
import '../services/red_packet_service.dart';
import '../services/supabase_service.dart';

/// WeChat-style red packet page: open a packet, see who claimed what, and let
/// the sender reclaim an expired packet's remaining balance.
class RedPacketPage extends StatefulWidget {
  final String packetId;
  final String? title;
  const RedPacketPage({super.key, required this.packetId, this.title});

  @override
  State<RedPacketPage> createState() => _RedPacketPageState();
}

class _RedPacketPageState extends State<RedPacketPage> {
  final _svc = const RedPacketService();
  bool _loading = true;
  bool _busy = false;
  Map<String, dynamic>? _packet;
  List<Map<String, dynamic>> _claims = [];
  RedPacketOpenResult? _result;

  String? get _uid => SupabaseService.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _packet = await _svc.details(widget.packetId);
      _claims = await _svc.claims(widget.packetId);
    } catch (_) {
      _packet = null;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open() async {
    setState(() => _busy = true);
    try {
      final res = await _svc.open(widget.packetId);
      setState(() => _result = res);
      await _load();
    } catch (e) {
      _snack('تعذر فتح الحزمة: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reclaim() async {
    setState(() => _busy = true);
    try {
      final balance = await _svc.reclaim(widget.packetId);
      _snack('تم استرجاع المتبقي. رصيدك الآن: ${formatAmount(balance)}');
      await _load();
    } catch (e) {
      _snack(e.toString().contains('packet_not_expired') ? 'لا يمكن الاسترجاع قبل انتهاء صلاحية الحزمة.' : 'تعذر الاسترجاع: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String t) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t))); }

  @override
  Widget build(BuildContext context) {
    final p = _packet;
    final currency = (p?['currency'] ?? 'YER').toString();
    final myAmount = _result?.amount ?? (p?['my_amount'] as num?);
    final isSender = p?['sender_uid']?.toString() == _uid;
    final expired = _isExpired(p?['expires_at']);
    final finished = (p?['status']?.toString() ?? '') != 'open';
    final remaining = (p?['remaining_amount'] as num?) ?? 0;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6EFE6),
        appBar: AppBar(
          backgroundColor: const Color(0xFFC0392B),
          foregroundColor: Colors.white,
          title: Text(widget.title ?? 'الحزمة الحمراء 🧧', style: const TextStyle(fontWeight: FontWeight.w900)),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : p == null
                ? const Center(child: Text('لم يتم العثور على الحزمة أو لا تملك صلاحية عرضها.'))
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _headerCard(p, currency, myAmount, finished),
                      const SizedBox(height: 16),
                      if (!finished && myAmount == null)
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC0392B), padding: const EdgeInsets.symmetric(vertical: 16)),
                            onPressed: _busy ? null : _open,
                            icon: const Icon(Icons.touch_app),
                            label: const Text('افتح الحزمة 🧧', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                          ),
                        ),
                      if (!finished && myAmount == null)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text('اضغط لفتح الحزمة والحصول على نصيبك.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
                        ),
                      if (myAmount != null && myAmount > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('نصيبك: ${formatAmount(myAmount)} $currency', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFFC0392B))),
                        ),
                      if (isSender && (expired || remaining > 0) && (finished || expired))
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : _reclaim,
                            icon: const Icon(Icons.replay),
                            label: Text('استرجاع المتبقي (${formatAmount(remaining)} $currency)'),
                          ),
                        ),
                      const SizedBox(height: 20),
                      Text('سجل الفتح (${_claims.length})', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 8),
                      if (_claims.isEmpty)
                        const Padding(padding: EdgeInsets.all(12), child: Text('لم يفتح أحد الحزمة بعد.', style: TextStyle(color: Colors.black54)))
                      else
                        ..._claims.map((c) => Card(
                              elevation: 0,
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: const CircleAvatar(backgroundColor: Color(0xFFFBE3C6), child: Text('🧧')),
                                title: Text((c['name'] ?? 'مستخدم').toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
                                trailing: Text('${formatAmount((c['amount'] as num?) ?? 0)} $currency', style: const TextStyle(fontWeight: FontWeight.w900)),
                              ),
                            )),
                    ],
                  ),
      ),
    );
  }

  Widget _headerCard(Map<String, dynamic> p, String currency, num? myAmount, bool finished) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFC0392B), Color(0xFF8E2B1F)]),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(children: [
        const Icon(Icons.card_giftcard, color: Colors.white, size: 44),
        const SizedBox(height: 10),
        if (p['wish'] != null && '${p['wish']}'.isNotEmpty)
          Text('${p['wish']}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Text(
          myAmount != null
              ? '${formatAmount(myAmount)} $currency'
              : '${formatAmount((p['total_amount'] as num?) ?? 0)} $currency',
          style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(
          finished
              ? 'انتهت الحزمة — فُتحت ${p['opened_count']}/${p['share_count']}'
              : 'حزمة ${p['packet_type'] == 'equal' ? 'بالتساوي' : 'عشوائية'} • ${p['opened_count']}/${p['share_count']} فُتحت',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
      ]),
    );
  }

  bool _isExpired(Object? expiresAt) {
    if (expiresAt == null) return false;
    final dt = DateTime.tryParse(expiresAt.toString());
    return dt != null && dt.isBefore(DateTime.now());
  }
}
