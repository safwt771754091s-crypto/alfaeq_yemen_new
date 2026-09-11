import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class PlatformAutomationPage extends StatelessWidget {
  const PlatformAutomationPage({super.key});

  Stream<QuerySnapshot<Map<String, dynamic>>> _stream() => FirebaseFirestore.instance
      .collection('platformAutomation')
      .orderBy('updatedAt', descending: true)
      .limit(200)
      .snapshots();

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('أتمتة تشغيل المنصة', style: TextStyle(fontWeight: FontWeight.w900)),
          actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.refresh))],
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _stream(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('تعذر قراءة حالة الأتمتة: ${snapshot.error}')));
            }
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

            final docs = snapshot.data!.docs;
            final ready = docs.where((d) => d.data()['ready'] == true).length;
            final needs = docs.length - ready;
            final bySource = <String, int>{};
            for (final doc in docs) {
              final source = (doc.data()['source'] ?? 'unknown').toString();
              bySource[source] = (bySource[source] ?? 0) + 1;
            }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _summary(ready, needs, docs.length),
                const SizedBox(height: 16),
                const Text('ماذا يفعل المركز؟', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                const Card(child: Padding(padding: EdgeInsets.all(14), child: Text('كل قسم أو مزود دفع أو متجر أو منتج يتم حفظه في Firestore يُفحص خادميًا وتُنشأ له حالة جاهزية. المركز يعرض النتيجة فقط؛ لا يكتب العميل حالة الجاهزية ولا يعدّل الرصيد أو السجل المالي.'))),
                const SizedBox(height: 16),
                _sourceSummary(bySource),
                const SizedBox(height: 16),
                if (docs.isEmpty)
                  const Card(child: Padding(padding: EdgeInsets.all(24), child: Center(child: Text('لا توجد نتائج أتمتة بعد. أضف قسمًا أو مزود دفع أو متجرًا أو منتجًا من الإدارة.'))))
                else
                  ...docs.map((doc) => _automationTile(context, doc)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _summary(int ready, int needs, int total) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('حالة المنصة', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _metric('جاهز', ready, Icons.check_circle_outline)),
            const SizedBox(width: 8),
            Expanded(child: _metric('يحتاج إعداد', needs, Icons.warning_amber_outlined)),
            const SizedBox(width: 8),
            Expanded(child: _metric('الإجمالي', total, Icons.apps_outlined)),
          ]),
        ]),
      ),
    );
  }

  Widget _metric(String label, int value, IconData icon) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(12)),
        child: Column(children: [Icon(icon), const SizedBox(height: 6), Text('$value', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)), Text(label, textAlign: TextAlign.center)]),
      );

  Widget _sourceSummary(Map<String, int> values) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('مصادر الأتمتة', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 8),
          ...values.entries.map((e) => ListTile(dense: true, leading: const Icon(Icons.account_tree_outlined), title: Text(_sourceLabel(e.key)), trailing: Text('${e.value}'))),
        ]),
      ),
    );
  }

  Widget _automationTile(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final source = (data['source'] ?? 'unknown').toString();
    final status = (data['status'] ?? 'unknown').toString();
    final isReady = data['ready'] == true;
    final checklist = (data['checklist'] is List) ? List<String>.from(data['checklist'].map((e) => e.toString())) : const <String>[];
    final nextAction = (data['nextAction'] ?? '').toString();

    return Card(
      child: ExpansionTile(
        leading: Icon(isReady ? Icons.check_circle : Icons.pending_actions, color: isReady ? Colors.green : Colors.orange),
        title: Text('${_sourceLabel(source)} — ${data['sourceId'] ?? doc.id}', style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(_statusLabel(status)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          if (checklist.isNotEmpty)
            Align(alignment: Alignment.centerRight, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('قائمة التحقق', style: TextStyle(fontWeight: FontWeight.w800)),
              ...checklist.map((item) => ListTile(dense: true, leading: Icon(isReady ? Icons.check : Icons.arrow_back), title: Text(_checkLabel(item)))),
            ])),
          if (nextAction.isNotEmpty) Align(alignment: Alignment.centerRight, child: Text('الإجراء التالي: ${_checkLabel(nextAction)}', style: const TextStyle(fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }

  String _sourceLabel(String value) {
    const labels = {'section': 'قسم', 'payment_provider': 'مزود دفع', 'store': 'متجر', 'product': 'منتج'};
    return labels[value] ?? value;
  }

  String _statusLabel(String value) {
    const labels = {'ready': 'جاهز للتشغيل', 'ready_for_transactions': 'جاهز للمعاملات', 'needs_configuration': 'يحتاج إعدادًا', 'disabled_or_incomplete': 'متوقف أو غير مكتمل', 'removed': 'محذوف'};
    return labels[value] ?? value;
  }

  String _checkLabel(String value) {
    const labels = {
      'section_saved': 'تم حفظ القسم',
      'public_catalog_source_ready': 'مصدر الكتالوج العام جاهز',
      'merchant_assignment_ready': 'إسناد التجار جاهز',
      'complete_title': 'أكمل اسم القسم',
      'enable_section': 'فعّل القسم',
      'provider_name': 'أضف اسم مزود الدفع',
      'enable_provider': 'فعّل مزود الدفع',
      'official_credentials_and_api_configuration': 'أكمل إعداد API والاعتماد الرسمي',
      'server_credentials_present': 'بيانات الخادم موجودة',
      'provider_enabled': 'مزود الدفع مفعّل',
      'store_name': 'اسم المتجر',
      'real_owner_account': 'حساب مالك حقيقي',
      'section_assignment': 'إسناد القسم',
      'store_approval': 'اعتماد المتجر',
      'catalog_entry_ready': 'إدخال الكتالوج جاهز',
      'product_name': 'اسم المنتج',
      'store_assignment': 'إسناد المنتج للمتجر',
      'valid_price': 'سعر صحيح',
      'valid_stock': 'مخزون صحيح',
      'activate_product': 'تفعيل المنتج',
      'catalog_ready': 'المنتج جاهز للكتالوج',
      'complete_official_provider_configuration': 'أكمل إعداد مزود الدفع الرسمي',
      'complete_store_setup_and_approval': 'أكمل إعداد واعتماد المتجر',
      'complete_product_setup': 'أكمل إعداد المنتج',
      'none': 'لا يوجد إجراء مطلوب',
    };
    return labels[value] ?? value;
  }
}
