import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'admin_data_entry.dart';

class PlatformControlPage extends StatefulWidget {
  const PlatformControlPage({super.key});

  @override
  State<PlatformControlPage> createState() => _PlatformControlPageState();
}

class _PlatformControlPageState extends State<PlatformControlPage> {
  final _db = FirebaseFirestore.instance;
  int _tab = 0;

  Future<void> _sectionDialog({DocumentSnapshot<Map<String, dynamic>>? doc}) async {
    final data = doc?.data() ?? {};
    final id = TextEditingController(text: data['id']?.toString() ?? '');
    final title = TextEditingController(text: data['title']?.toString() ?? '');
    final subtitle = TextEditingController(text: data['subtitle']?.toString() ?? '');
    final icon = TextEditingController(text: data['icon']?.toString() ?? 'storefront');
    final enabled = ValueNotifier<bool>(data['enabled'] != false);

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(doc == null ? 'إضافة قسم حقيقي' : 'تعديل القسم'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: id, enabled: doc == null, decoration: const InputDecoration(labelText: 'المعرف التقني')),
            TextField(controller: title, decoration: const InputDecoration(labelText: 'اسم القسم')),
            TextField(controller: subtitle, decoration: const InputDecoration(labelText: 'الوصف')),
            TextField(controller: icon, decoration: const InputDecoration(labelText: 'الأيقونة')),
            ValueListenableBuilder<bool>(valueListenable: enabled, builder: (_, value, __) => SwitchListTile(title: const Text('مفعل للمستخدمين'), value: value, onChanged: (v) => enabled.value = v)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              final sectionId = id.text.trim();
              if (sectionId.isEmpty || title.text.trim().isEmpty) return;
              final payload = <String, dynamic>{
                'id': sectionId,
                'title': title.text.trim(),
                'subtitle': subtitle.text.trim(),
                'icon': icon.text.trim().isEmpty ? 'storefront' : icon.text.trim(),
                'enabled': enabled.value,
                'updatedAt': FieldValue.serverTimestamp(),
              };
              if (doc == null) {
                payload['createdAt'] = FieldValue.serverTimestamp();
                await _db.collection('sections').doc(sectionId).set(payload);
              } else {
                await doc.reference.update(payload);
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('حفظ فعلي'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSection(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف القسم؟'),
        content: const Text('سيتم حذف تعريف القسم من Firestore. لا نحذف المتاجر أو المنتجات التابعة له تلقائيًا.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok == true) await doc.reference.delete();
  }

  Future<void> _providerDialog({DocumentSnapshot<Map<String, dynamic>>? doc}) async {
    final data = doc?.data() ?? {};
    final id = TextEditingController(text: data['id']?.toString() ?? '');
    final name = TextEditingController(text: data['name']?.toString() ?? '');
    final type = TextEditingController(text: data['type']?.toString() ?? 'wallet');
    final docsUrl = TextEditingController(text: data['docsUrl']?.toString() ?? '');
    final enabled = ValueNotifier<bool>(data['enabled'] == true);

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(doc == null ? 'إضافة مزود دفع' : 'تعديل مزود الدفع'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: id, enabled: doc == null, decoration: const InputDecoration(labelText: 'المعرف')),
          TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم المزود')),
          TextField(controller: type, decoration: const InputDecoration(labelText: 'النوع')),
          TextField(controller: docsUrl, decoration: const InputDecoration(labelText: 'رابط وثائق الربط الرسمية')),
          ValueListenableBuilder<bool>(valueListenable: enabled, builder: (_, value, __) => SwitchListTile(title: const Text('مفعل'), value: value, onChanged: (v) => enabled.value = v)),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(onPressed: () async {
            final providerId = id.text.trim();
            if (providerId.isEmpty || name.text.trim().isEmpty) return;
            final payload = <String, dynamic>{
              'id': providerId,
              'name': name.text.trim(),
              'type': type.text.trim(),
              'docsUrl': docsUrl.text.trim(),
              'enabled': enabled.value,
              'configurationStatus': enabled.value ? 'needs_credentials' : 'disabled',
              'updatedAt': FieldValue.serverTimestamp(),
            };
            if (doc == null) {
              payload['createdAt'] = FieldValue.serverTimestamp();
              await _db.collection('paymentProviders').doc(providerId).set(payload);
            } else {
              await doc.reference.update(payload);
            }
            if (context.mounted) Navigator.pop(context);
          }, child: const Text('حفظ فعلي')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('مركز تشغيل المنصة')),
        body: Column(children: [
          Padding(padding: const EdgeInsets.all(12), child: SegmentedButton<int>(segments: const [
            ButtonSegment(value: 0, label: Text('الأقسام'), icon: Icon(Icons.category_outlined)),
            ButtonSegment(value: 1, label: Text('الدفع'), icon: Icon(Icons.account_balance_wallet_outlined)),
            ButtonSegment(value: 2, label: Text('التجار'), icon: Icon(Icons.storefront_outlined)),
          ], selected: {_tab}, onSelectionChanged: (s) => setState(() => _tab = s.first))),
          Expanded(child: switch (_tab) {
            0 => _SectionsTab(db: _db, onAdd: () => _sectionDialog(), onEdit: _sectionDialog, onDelete: _deleteSection),
            1 => _ProvidersTab(db: _db, onAdd: () => _providerDialog(), onEdit: _providerDialog),
            _ => const _MerchantsTab(),
          }),
        ]),
      ),
    );
  }
}

class _SectionsTab extends StatelessWidget {
  final FirebaseFirestore db;
  final VoidCallback onAdd;
  final Future<void> Function({DocumentSnapshot<Map<String, dynamic>>? doc}) onEdit;
  final Future<void> Function(DocumentSnapshot<Map<String, dynamic>>) onDelete;
  const _SectionsTab({required this.db, required this.onAdd, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: db.collection('sections').orderBy('title').snapshots(),
    builder: (context, snapshot) {
      final docs = snapshot.data?.docs ?? const [];
      return ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [const Expanded(child: Text('الأقسام الديناميكية', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900))), FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('إضافة'))]),
        const SizedBox(height: 8),
        const Text('أي قسم تحفظه هنا يصبح مصدرًا حقيقيًا للمنصة. لا نعتمد على تغيير نصوص وهمية داخل الواجهة.'),
        const SizedBox(height: 12),
        if (snapshot.hasError) const Text('تعذر تحميل الأقسام. تحقق من صلاحيات الأدمن.'),
        ...docs.map((doc) {
          final d = doc.data();
          return Card(child: ListTile(
            leading: const Icon(Icons.category_outlined),
            title: Text('${d['title'] ?? doc.id}', style: const TextStyle(fontWeight: FontWeight.w900)),
            subtitle: Text('${d['id'] ?? doc.id} • ${d['enabled'] == false ? 'متوقف' : 'مفعل'}'),
            trailing: Wrap(children: [IconButton(onPressed: () => onEdit(doc: doc), icon: const Icon(Icons.edit_outlined)), IconButton(onPressed: () => onDelete(doc), icon: const Icon(Icons.delete_outline))]),
          ));
        }),
      ]);
    },
  );
}

class _ProvidersTab extends StatelessWidget {
  final FirebaseFirestore db;
  final VoidCallback onAdd;
  final Future<void> Function({DocumentSnapshot<Map<String, dynamic>>? doc}) onEdit;
  const _ProvidersTab({required this.db, required this.onAdd, required this.onEdit});

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: db.collection('paymentProviders').orderBy('name').snapshots(),
    builder: (context, snapshot) {
      final docs = snapshot.data?.docs ?? const [];
      return ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [const Expanded(child: Text('مزودو الدفع', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900))), FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('إضافة'))]),
        const SizedBox(height: 8),
        const Text('الكريمي، أم فلوس، بن دول، بنك الشرق أو أي مزود رسمي يضاف هنا. تفعيل المزود لا يعني اختلاق API؛ الربط لا يصبح فعالًا إلا بعد استكمال القناة الرسمية.'),
        const SizedBox(height: 12),
        ...docs.map((doc) {
          final d = doc.data();
          return Card(child: ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: Text('${d['name'] ?? doc.id}', style: const TextStyle(fontWeight: FontWeight.w900)),
            subtitle: Text('${d['type'] ?? 'wallet'} • ${d['configurationStatus'] ?? 'غير مهيأ'}'),
            trailing: IconButton(onPressed: () => onEdit(doc: doc), icon: const Icon(Icons.settings_outlined)),
          ));
        }),
      ]);
    },
  );
}

class _MerchantsTab extends StatelessWidget {
  const _MerchantsTab();
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    const Text('إدارة التجار', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
    const SizedBox(height: 8),
    const Text('التاجر يضاف من المسار الإداري الحقيقي ثم يخضع للاعتماد قبل ظهوره للمستخدمين.'),
    const SizedBox(height: 16),
    FilledButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminDataEntry())), icon: const Icon(Icons.person_add_alt_1), label: const Text('إضافة تاجر / متجر')),
    const SizedBox(height: 10),
    OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.fact_check_outlined), label: const Text('مراجعة طلبات الاعتماد')),
  ]);
}
