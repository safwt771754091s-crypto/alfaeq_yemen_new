import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class DeveloperPage extends StatefulWidget {
  const DeveloperPage({super.key});
  @override
  State<DeveloperPage> createState() => _DeveloperPageState();
}

class _DeveloperPageState extends State<DeveloperPage> {
  final _auth = AuthService();
  bool _allowed = false, _loading = true, _scanning = false;
  String _role = '', _appCheckStatus = 'غير مفحوص';
  Map<String, dynamic> _profile = {};
  Map<String, int> _counts = {};
  List<String> _findings = [];
  DateTime? _lastScan;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _writeAudit({required String action, required String result, Map<String, dynamic>? details}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance.collection('auditLogs').add({
        'actorUid': user.uid,
        'actorEmail': user.email,
        'role': _role,
        'action': action,
        'result': result,
        'details': details ?? <String, dynamic>{},
        'source': 'developer_center',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Audit failures must never crash the developer center.
    }
  }

  Future<void> _load() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) { if (mounted) setState(() => _loading = false); return; }
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = snap.data() ?? {};
      final role = await _auth.role();
      final allowed = await _auth.canOpenDeveloperCenter();
      if (mounted) setState(() { _role = role; _profile = data; _allowed = allowed; _loading = false; });
      if (allowed) {
        await _checkAppIntegrity();
        await _writeAudit(action: 'developer_center_access', result: 'success');
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _checkAppIntegrity() async {
    try {
      final token = await FirebaseAppCheck.instance.getToken();
      if (!mounted) return;
      setState(() => _appCheckStatus = token == null ? 'غير نشط — يلزم إعداد مزود App Check' : 'نشط ومصادق عليه');
    } catch (_) { if (mounted) setState(() => _appCheckStatus = 'تعذر التحقق من App Check'); }
  }

  Future<void> _runSecurityScan() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    final findings = <String>[];
    final counts = <String, int>{};
    try {
      final results = await Future.wait([
        FirebaseFirestore.instance.collection('users').limit(200).get(),
        FirebaseFirestore.instance.collection('stores').limit(200).get(),
        FirebaseFirestore.instance.collection('products').limit(200).get(),
        FirebaseFirestore.instance.collection('orders').limit(200).get(),
        FirebaseFirestore.instance.collection('payments').limit(200).get(),
      ]);
      final users = results[0].docs, stores = results[1].docs, products = results[2].docs;
      final orders = results[3].docs, payments = results[4].docs;
      counts.addAll({'users': users.length, 'stores': stores.length, 'products': products.length, 'orders': orders.length, 'payments': payments.length});
      final legacyStores = stores.where((d) => d.data()['ownerId'] == 'admin-created').length;
      final legacyProducts = products.where((d) => d.data()['ownerId'] == 'admin-created').length;
      final usersWithoutRole = users.where((d) => (d.data()['role'] as String?) == null).length;
      if (legacyStores > 0) findings.add('يوجد $legacyStores متجر بملكية قديمة admin-created ويحتاج ربطه بحساب حقيقي.');
      if (legacyProducts > 0) findings.add('يوجد $legacyProducts منتج بملكية قديمة admin-created ويحتاج ربطه بمالك حقيقي.');
      if (usersWithoutRole > 0) findings.add('يوجد $usersWithoutRole مستخدم بلا role واضح في البيانات المفحوصة.');
      if (_appCheckStatus != 'نشط ومصادق عليه') findings.add('App Check غير نشط بالكامل لهذه البيئة؛ لا نعتبر الحماية مكتملة حتى تفعيل المزود في Firebase.');
      if (findings.isEmpty) findings.add('لم يظهر خلل حرج في العينة المفحوصة. الفحص الحالي حدّه 200 سجل لكل مجموعة.');
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await FirebaseFirestore.instance.collection('securityReports').add({
          'actorUid': uid,
          'role': _role,
          'findings': findings,
          'counts': counts,
          'appCheck': _appCheckStatus,
          'createdAt': FieldValue.serverTimestamp(),
          'type': 'automated_security_scan',
        });
        await _writeAudit(
          action: 'security_scan',
          result: 'success',
          details: {
            'findingsCount': findings.length,
            'counts': counts,
            'appCheck': _appCheckStatus,
          },
        );
      }
    } catch (e) {
      findings.add('تعذر إكمال الفحص: $e');
      await _writeAudit(action: 'security_scan', result: 'failed', details: {'error': e.toString()});
    }
    if (!mounted) return;
    setState(() { _findings = findings; _counts = counts; _lastScan = DateTime.now(); _scanning = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (!_allowed) return Directionality(textDirection: TextDirection.rtl, child: Scaffold(appBar: AppBar(title: const Text('مركز المطور')), body: const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('هذه المنطقة محمية. لا توجد لديك صلاحية المطور.', textAlign: TextAlign.center)))));
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('مركز المطور والأمن', style: TextStyle(fontWeight: FontWeight.w900)), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))]),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          _heroCard(), const SizedBox(height: 14), _sectionTitle('🛡️ الحماية السيبرانية'),
          _securityCard('App Check', _appCheckStatus, Icons.verified_user_outlined),
          _securityCard('صلاحية الحساب', _role, Icons.admin_panel_settings_outlined),
          _securityCard('Firebase Auth + Rules', 'مفعلة — الصلاحيات مفروضة على الخادم', Icons.lock_outline),
          const SizedBox(height: 14), _sectionTitle('🤖 الأتمتة والفحص'),
          Card(child: ListTile(leading: const Icon(Icons.radar_outlined), title: const Text('فحص أمني تلقائي للبيانات', style: TextStyle(fontWeight: FontWeight.w900)), subtitle: Text(_lastScan == null ? 'يفحص عينة حقيقية من المستخدمين والمتاجر والمنتجات والطلبات والمدفوعات.' : 'آخر فحص: ${_lastScan!.toLocal()}'), trailing: FilledButton.icon(onPressed: _scanning ? null : _runSecurityScan, icon: _scanning ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.play_arrow), label: const Text('فحص')))),
          if (_counts.isNotEmpty) _dataOverview(), if (_findings.isNotEmpty) _findingsCard(),
          const SizedBox(height: 14), _sectionTitle('💻 تطوير التطبيق'),
          const _DevCard(icon: Icons.code, title: 'مراجعة الكود', subtitle: 'مركز المطور ينسق نتائج الفحص والإنذارات؛ فحص المصدر الكامل يتم عبر CI قبل النشر.'),
          const _DevCard(icon: Icons.storage, title: 'فحص البيانات', subtitle: 'يبحث عن ملكيات قديمة، أدوار ناقصة، ومؤشرات غير طبيعية في البيانات الحقيقية ضمن عينة محددة.'),
          const _DevCard(icon: Icons.auto_awesome, title: 'مساعد التطوير والأتمتة', subtitle: 'اختصاصه: الأمن، اكتشاف المخاطر، أتمتة الفحوصات، ومتابعة جودة النظام قبل أي إطلاق.'),
          const SizedBox(height: 14), _sectionTitle('👤 الحساب الحالي'),
          _DevCard(icon: Icons.person, title: _profile['name']?.toString() ?? 'حساب المستخدم', subtitle: 'UID: ${FirebaseAuth.instance.currentUser?.uid ?? '-'}\nالبريد: ${FirebaseAuth.instance.currentUser?.email ?? '-'}\nالدور: $_role'),
        ]),
      ),
    );
  }

  Widget _heroCard() => Card(color: const Color(0xFF0B6E4F), child: const Padding(padding: EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.shield_outlined, color: Colors.white, size: 38), SizedBox(height: 10), Text('مركز المطور الذكي', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)), SizedBox(height: 6), Text('تطوير • فحص • أتمتة • أمن سيبراني • حماية البيانات', style: TextStyle(color: Colors.white70))])));
  Widget _sectionTitle(String text) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)));
  Widget _securityCard(String title, String value, IconData icon) => Card(child: ListTile(leading: Icon(icon), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text(value)));
  Widget _dataOverview() => Card(child: Padding(padding: const EdgeInsets.all(16), child: Wrap(spacing: 10, runSpacing: 10, children: _counts.entries.map((e) => Chip(label: Text('${e.key}: ${e.value}'))).toList())));
  Widget _findingsCard() => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('نتائج الفحص', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)), const SizedBox(height: 8), ..._findings.map((item) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text('• $item')))])));
}

class _DevCard extends StatelessWidget {
  final IconData icon; final String title; final String subtitle;
  const _DevCard({required this.icon, required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) => Card(child: ListTile(leading: Icon(icon), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text(subtitle)));
}
