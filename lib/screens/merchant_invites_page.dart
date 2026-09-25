import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class MerchantInvitesPage extends StatefulWidget {
  const MerchantInvitesPage({super.key});

  @override
  State<MerchantInvitesPage> createState() => _MerchantInvitesPageState();
}

class _MerchantInvitesPageState extends State<MerchantInvitesPage> {
  final _label = TextEditingController();
  bool _busy = false;
  String? _lastLink;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _createInvite() async {
    if (_busy) return;
    final label = _label.text.trim();
    setState(() => _busy = true);
    try {
      final response = await SupabaseService.client.functions.invoke(
        'create-merchant-invite',
        body: <String, dynamic>{'label': label},
      );
      final raw = response.data;
      final data = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      final link = data['url']?.toString().trim() ?? '';
      if (link.isEmpty || !Uri.tryParse(link).toString().startsWith('http')) {
        throw StateError('لم يعُد الخادم رابط دعوة صالحاً.');
      }
      if (!mounted) return;
      setState(() => _lastLink = link);
      _label.clear();
      await Clipboard.setData(ClipboardData(text: link));
      _message('تم إنشاء الرابط وعرضه ونسخه للحافظة.');
    } on PostgrestException catch (e) {
      _message(e.message);
    } catch (e) {
      _message('تعذر إنشاء رابط التاجر: $e');
    } catch (e) {
      _message('تعذر إنشاء الرابط: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy() async {
    final link = _lastLink;
    if (link == null || link.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: link));
    _message('تم نسخ رابط التاجر.');
  }

  Future<void> _openWhatsApp() async {
    final link = _lastLink;
    if (link == null || link.isEmpty) {
      _message('أنشئ رابط التاجر أولاً.');
      return;
    }
    final message = 'مرحباً، نرسل لك رابط التسجيل كتاجر في الفائق يمن:\n$link';
    final encoded = Uri.encodeComponent(message);
    final appUri = Uri.parse('whatsapp://send?text=$encoded');
    final webUri = Uri.parse('https://wa.me/?text=$encoded');
    try {
      if (await canLaunchUrl(appUri)) {
        await launchUrl(appUri, mode: LaunchMode.externalApplication);
        return;
      }
      if (await canLaunchUrl(webUri)) {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
        return;
      }
      _message('تعذر فتح واتساب على هذا الجهاز. تم نسخ الرابط، ويمكنك إرساله يدويًا.');
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: link));
      _message('تعذر فتح واتساب؛ تم نسخ الرابط للحافظة.');
    }
  }

  Future<void> _shareInvite() async {
    final link = _lastLink;
    if (link == null || link.isEmpty) return;
    await _copy();
    _message('الرابط جاهز للمشاركة. استخدم زر واتساب لإرساله مباشرة.');
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('روابط التجار')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.link, size: 42),
                  const SizedBox(height: 10),
                  const Text('دعوة تاجر حقيقي', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  const Text('أنشئ رابط دعوة صالحاً للتسجيل. يظهر الرابط داخل الصفحة ويبقى متاحاً للنسخ والمشاركة عبر واتساب.'),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _label,
                    decoration: const InputDecoration(
                      labelText: 'اسم أو وصف التاجر (اختياري)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _createInvite,
                      icon: const Icon(Icons.add_link),
                      label: Text(_busy ? 'جاري الإنشاء...' : 'إنشاء رابط تاجر'),
                    ),
                  ),
                ]),
              ),
            ),
            if (_lastLink != null) ...[
              const SizedBox(height: 16),
              Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Row(children: [
                      Icon(Icons.verified_outlined),
                      SizedBox(width: 8),
                      Expanded(child: Text('رابط التاجر جاهز', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
                    ]),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Theme.of(context).dividerColor),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SelectableText(_lastLink!, style: const TextStyle(fontSize: 13, height: 1.5)),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _copy,
                          icon: const Icon(Icons.copy),
                          label: const Text('نسخ'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _openWhatsApp,
                          icon: const Icon(Icons.chat),
                          label: const Text('واتساب'),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: _shareInvite,
                        icon: const Icon(Icons.share_outlined),
                        label: const Text('نسخ وتجهيز المشاركة'),
                      ),
                    ),
                  ]),
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Card(
              elevation: 0,
              child: ListTile(
                leading: Icon(Icons.security_outlined),
                title: Text('الحماية'),
                subtitle: Text('الرابط لا يمنح صلاحيات الإدارة. هو مخصص لتسجيل حساب تاجر فقط، وبعد الاسترداد يسجل النظام العملية في auditLogs.'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
