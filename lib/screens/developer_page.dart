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

  final TextEditingController _auditSearchController = TextEditingController();
  String _auditActionFilter = 'الكل';
  String _auditResultFilter = 'الكل';

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { _auditSearchController.dispose(); super.dispose(); }

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
    } catch (_) {}
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
      if (allowed) { await _checkAppIntegrity(); await _writeAudit(action: 'developer_center_access', result: 'success'); }
    } catch (_) { if (mounted) setState(() => _loading = false); }
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
        await FirebaseFirestore.instance.collection('securityReports').add({'actorUid': uid, 'role': _role, 'findings': findings, 'counts': counts, 'appCheck': _appCheckStatus, 'createdAt': FieldValue.serverTimestamp(), 'type': 'automated_security_scan'});
        await _writeAudit(action: 'security_scan', result: 'success', details: {'findingsCount': findings.length, 'counts': counts, 'appCheck': _appCheckStatus});
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
    return Directionality(textDirection: TextDirection.rtl, child: Scaffold(
      appBar: AppBar(title: const Text('مركز المطور والأمن', style: TextStyle(fontWeight: FontWeight.w900)), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _heroCard(), const SizedBox(height: 14), _sectionTitle('🛡️ الحماية السيبرانية'),
        _securityCard('App Check', _appCheckStatus, Icons.verified_user_outlined),
        _securityCard('صلاحية الحساب', _role, Icons.admin_panel_settings_outlined),
        _securityCard('Firebase Auth + Rules', 'مفعلة — الصلاحيات مفروضة على الخادم', Icons.lock_outline),
        const SizedBox(height: 14), _sectionTitle('🤖 الأتمتة والفحص'),
        Card(child: ListTile(leading: const Icon(Icons.radar_outlined), title: const Text('فحص أمني تلقائي للبيانات', style: TextStyle(fontWeight: FontWeight.w900)), subtitle: Text(_lastScan == null ? 'يفحص عينة حقيقية من المستخدمين والمتاجر والمنتجات والطلبات والمدفوعات.' : 'آخر فحص: ${_lastScan!.toLocal()}'), trailing: FilledButton.icon(onPressed: _scanning ? null : _runSecurityScan, icon: _scanning ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.play_arrow), label: const Text('فحص')))),
        if (_counts.isNotEmpty) _dataOverview(), if (_findings.isNotEmpty) _findingsCard(),
        const SizedBox(height: 14), _sectionTitle('📜 سجل التدقيق'), _auditLogCard(),
        const SizedBox(height: 14), _sectionTitle('💻 تطوير التطبيق'),
        const _DevCard(icon: Icons.code, title: 'مراجعة الكود', subtitle: 'مركز المطور ينسق نتائج الفحص والإنذارات؛ فحص المصدر الكامل يتم عبر CI قبل النشر.'),
        const _DevCard(icon: Icons.storage, title: 'فحص البيانات', subtitle: 'يبحث عن ملكيات قديمة، أدوار ناقصة، ومؤشرات غير طبيعية في البيانات الحقيقية ضمن عينة محددة.'),
        const _DevCard(icon: Icons.auto_awesome, title: 'مساعد التطوير والأتمتة', subtitle: 'اختصاصه: الأمن، اكتشاف المخاطر، أتمتة الفحوصات، ومتابعة جودة النظام قبل أي إطلاق.'),
        const SizedBox(height: 14), _sectionTitle('👤 الحساب الحالي'),
        _DevCard(icon: Icons.person, title: _profile['name']?.toString() ?? 'حساب المستخدم', subtitle: 'UID: ${FirebaseAuth.instance.currentUser?.uid ?? '-'}\nالبريد: ${FirebaseAuth.instance.currentUser?.email ?? '-'}\nالدور: $_role'),
      ]),
    ));
  }

  Widget _auditLogCard() {
    final query = FirebaseFirestore.instance.collection('auditLogs').orderBy('createdAt', descending: true).limit(50);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: query.snapshots(), builder: (context, snapshot) {
      if (snapshot.hasError) return Card(child: ListTile(leading: const Icon(Icons.error_outline), title: const Text('تعذر تحميل سجل التدقيق'), subtitle: Text('${snapshot.error}')));
      if (snapshot.connectionState == ConnectionState.waiting) return const Card(child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())));
      final docs = snapshot.data?.docs ?? [];
      final filtered = docs.where(_matchesAuditFilters).toList();
      final actions = docs.map((d) => (d.data()['action'] ?? '').toString()).where((v) => v.isNotEmpty).toSet().toList()..sort();
      return Card(child: Column(children: [
        _auditFilters(actions), const Divider(height: 1),
        Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 8), child: Row(children: [const Icon(Icons.history), const SizedBox(width: 8), const Expanded(child: Text('آخر العمليات', style: TextStyle(fontWeight: FontWeight.w900))), Text('${filtered.length} من ${docs.length}')])),
        if (filtered.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Column(children: [Icon(Icons.search_off, size: 38), SizedBox(height: 8), Text('لا توجد نتائج مطابقة للفلاتر.', style: TextStyle(fontWeight: FontWeight.w700))])) else ...filtered.map((doc) => _auditTile(doc)),
      ]));
    });
  }

  Widget _auditFilters(List<String> actions) => Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 8), child: Column(children: [
    TextField(controller: _auditSearchController, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: 'بحث في المستخدم أو العملية أو التفاصيل', hintText: 'البريد، UID، اسم العملية...', prefixIcon: const Icon(Icons.search), suffixIcon: _auditSearchController.text.isEmpty ? null : IconButton(onPressed: () { _auditSearchController.clear(); setState(() {}); }, icon: const Icon(Icons.clear)), border: const OutlineInputBorder())),
    const SizedBox(height: 10), Wrap(spacing: 8, runSpacing: 8, children: [
      DropdownButton<String>(value: actions.contains(_auditActionFilter) || _auditActionFilter == 'الكل' ? _auditActionFilter : 'الكل', items: ['الكل', ...actions].map((value) => DropdownMenuItem(value: value, child: Text(value == 'الكل' ? 'كل العمليات' : _actionLabel(value)))).toList(), onChanged: (value) { if (value != null) setState(() => _auditActionFilter = value); }),
      DropdownButton<String>(value: _auditResultFilter, items: const [DropdownMenuItem(value: 'الكل', child: Text('كل الحالات')), DropdownMenuItem(value: 'success', child: Text('نجاح')), DropdownMenuItem(value: 'failed', child: Text('فشل')), DropdownMenuItem(value: 'warning', child: Text('تحذير'))], onChanged: (value) { if (value != null) setState(() => _auditResultFilter = value); }),
      OutlinedButton.icon(onPressed: () { _auditSearchController.clear(); setState(() { _auditActionFilter = 'الكل'; _auditResultFilter = 'الكل'; }); }, icon: const Icon(Icons.filter_alt_off), label: const Text('مسح الفلاتر')),
    ]),
  ]));

  bool _matchesAuditFilters(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final action = (data['action'] ?? '').toString(), result = (data['result'] ?? '').toString(), severity = (data['severity'] ?? '').toString();
    final email = (data['actorEmail'] ?? '').toString(), uid = (data['actorUid'] ?? '').toString(), details = (data['details'] ?? '').toString();
    final search = _auditSearchController.text.trim().toLowerCase();
    final actionMatches = _auditActionFilter == 'الكل' || action == _auditActionFilter;
    final resultMatches = _auditResultFilter == 'الكل' || result == _auditResultFilter || (_auditResultFilter == 'warning' && severity == 'warning');
    final searchMatches = search.isEmpty || '$action $email $uid $details'.toLowerCase().contains(search);
    return actionMatches && resultMatches && searchMatches;
  }

  Widget _auditTile(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final result = (data['result'] ?? 'unknown').toString(), severity = (data['severity'] ?? 'info').toString(), action = (data['action'] ?? 'عملية غير معروفة').toString();
    final rawDetails = data['details'];
    final details = rawDetails is Map ? rawDetails.entries.map((e) => '${e.key}: ${e.value}').join(' • ') : (rawDetails ?? '').toString();
    final email = (data['actorEmail'] ?? data['actorUid'] ?? 'غير معروف').toString();
    final timestamp = data['createdAt'];
    final date = timestamp is Timestamp ? timestamp.toDate() : null;
    final status = _auditStatus(result, severity);
    return InkWell(onTap: () => _showAuditDetails(doc), child: ListTile(
      leading: CircleAvatar(backgroundColor: status.color.withValues(alpha: .12), child: Icon(status.icon, color: status.color)),
      title: Text(_actionLabel(action), style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text('$email\n${details.isEmpty ? 'بدون تفاصيل' : details}${date == null ? '' : '\n${date.toLocal()}'}'), isThreeLine: true,
      trailing: Chip(label: Text(status.label)),
    ));
  }

  void _showAuditDetails(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final action = (data['action'] ?? 'عملية غير معروفة').toString();
    final result = (data['result'] ?? 'غير معروف').toString();
    final severity = (data['severity'] ?? 'info').toString();
    final status = _auditStatus(result, severity);
    final timestamp = data['createdAt'];
    final date = timestamp is Timestamp ? timestamp.toDate() : null;
    final details = data['details'];
    final detailsText = details is Map ? details.entries.map((e) => '${e.key}: ${e.value}').join('\n') : (details ?? 'لا توجد تفاصيل تقنية').toString();
    showModalBottomSheet<void>(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (context) => Directionality(textDirection: TextDirection.rtl, child: DraggableScrollableSheet(initialChildSize: .72, minChildSize: .45, maxChildSize: .94, expand: false, builder: (context, controller) => Material(borderRadius: const BorderRadius.vertical(top: Radius.circular(24)), child: ListView(controller: controller, padding: const EdgeInsets.fromLTRB(20, 12, 20, 28), children: [
      Center(child: Container(width: 44, height: 5, decoration: BoxDecoration(color: Theme.of(context).dividerColor, borderRadius: BorderRadius.circular(10)))),
      const SizedBox(height: 14),
      Row(children: [CircleAvatar(radius: 24, backgroundColor: status.color.withValues(alpha: .12), child: Icon(status.icon, color: status.color)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_actionLabel(action), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)), const SizedBox(height: 4), Chip(label: Text(status.label))]))]),
      const SizedBox(height: 18),
      _detailSection('العملية', _actionLabel(action), Icons.bolt_outlined),
      _detailSection('النتيجة', result, status.icon, valueColor: status.color),
      _detailSection('المستوى', severity, Icons.warning_amber_outlined),
      _detailSection('المنفذ', (data['actorEmail'] ?? 'غير متوفر').toString(), Icons.person_outline),
      _detailSection('UID', (data['actorUid'] ?? 'غير متوفر').toString(), Icons.fingerprint),
      _detailSection('الدور', (data['role'] ?? 'غير متوفر').toString(), Icons.admin_panel_settings_outlined),
      _detailSection('المصدر', (data['source'] ?? 'غير متوفر').toString(), Icons.source_outlined),
      _detailSection('وقت التنفيذ', date == null ? 'غير متوفر' : date.toLocal().toString(), Icons.schedule),
      const SizedBox(height: 8),
      const Text('التفاصيل التقنية', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      Container(width: double.infinity, padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)), child: SelectableText(detailsText.isEmpty ? 'لا توجد تفاصيل تقنية.' : detailsText, style: const TextStyle(fontFamily: 'monospace', height: 1.5))),
      const SizedBox(height: 16),
      _detailSection('معرّف سجل التدقيق', doc.id, Icons.tag),
    ]))));
  }

  Widget _detailSection(String label, String value, IconData icon, {Color? valueColor}) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(border: Border.all(color: Theme.of(context).dividerColor), borderRadius: BorderRadius.circular(12)), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, size: 20), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)), const SizedBox(height: 3), SelectableText(value, style: TextStyle(fontWeight: FontWeight.w800, color: valueColor))]))])));

  ({String label, IconData icon, Color color}) _auditStatus(String result, String severity) {
    if (result == 'failed' || result == 'failure' || severity == 'critical') return (label: 'فشل', icon: Icons.error, color: Colors.red);
    if (result == 'warning' || severity == 'warning') return (label: 'تحذير', icon: Icons.warning_amber, color: Colors.orange);
    return (label: 'نجاح', icon: Icons.check_circle, color: Colors.green);
  }

  String _actionLabel(String action) => const {'security_scan': 'فحص أمني', 'developer_center_access': 'فتح مركز المطور'}[action] ?? action;
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
