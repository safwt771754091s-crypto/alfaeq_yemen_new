import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class DriverCenterPage extends StatelessWidget {
  const DriverCenterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('مركز السائق')),
    );
  }
}

class _Stat extends StatelessWidget {
  final String title, value;
  final IconData icon;

  const _Stat({required this.title, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                  Text(title),
                ],
              ),
            ],
          ),
        ),
      );
}

class _DriverOrderTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final bool busy;
  final Future<void> Function(QueryDocumentSnapshot<Map<String, dynamic>>, String) onStatus;

  const _DriverOrderTile({required this.doc, required this.busy, required this.onStatus});

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final status = '${data['deliveryStatus'] ?? 'assigned'}';
    final shortId = doc.id.substring(0, doc.id.length > 8 ? 8 : doc.id.length);

    return Card(
      elevation: 0,
      child: ExpansionTile(
        leading: const Icon(Icons.local_shipping_outlined),
        title: Text('طلب #$shortId'),
        subtitle: Text('$status • ${data['address'] ?? '—'}'),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (status == 'assigned')
                  FilledButton(
                    onPressed: busy ? null : () => onStatus(doc, 'picked_up'),
                    child: const Text('استلام الطلب'),
                  ),
                if (status == 'picked_up')
                  FilledButton(
                    onPressed: busy ? null : () => onStatus(doc, 'out_for_delivery'),
                    child: const Text('خرج للتوصيل'),
                  ),
                if (status == 'out_for_delivery')
                  FilledButton(
                    onPressed: busy ? null : () => onStatus(doc, 'delivered'),
                    child: const Text('تم التسليم'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
