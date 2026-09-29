import 'package:flutter/material.dart';
import '../services/supabase_service.dart';

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  Future<void> _markRead(String id) async {
    await SupabaseService.client.from('notifications').update({
      'read_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  @override
  Widget build(BuildContext context) {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return const Scaffold(body: Center(child: Text('يجب تسجيل الدخول أولاً.')));
    final stream = SupabaseService.client.from('notifications').stream(primaryKey: ['id']).eq('user_id', user.id).order('created_at', ascending: false).limit(100);
    return Directionality(textDirection: TextDirection.rtl, child: Scaffold(
      appBar: AppBar(title: const Text('الإشعارات', style: TextStyle(fontWeight: FontWeight.w900))),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('تعذر تحميل الإشعارات من Supabase.\n' + snapshot.error.toString(), textAlign: TextAlign.center)));
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          final rows = snapshot.data ?? const <Map<String, dynamic>>[];
          if (rows.isEmpty) return const Center(child: Text('لا توجد إشعارات حالياً.'));
          return ListView.separated(
            padding: const EdgeInsets.all(12), itemCount: rows.length, separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final row = rows[index]; final read = row['read_at'] != null;
              return Card(elevation: 0, child: ListTile(
                leading: CircleAvatar(backgroundColor: read ? Colors.grey.shade100 : Theme.of(context).colorScheme.primaryContainer, child: Icon(read ? Icons.notifications_none : Icons.notifications_active_outlined)),
                title: Text((row['title'] ?? 'إشعار الفائق').toString(), style: TextStyle(fontWeight: read ? FontWeight.w600 : FontWeight.w900)),
                subtitle: Text((row['body'] ?? '').toString()),
                trailing: read ? null : const Icon(Icons.circle, size: 9),
                onTap: read ? null : () async { try { await _markRead(row['id'].toString()); } catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تحديث الإشعار: $e'))); } },
              ));
            },
          );
        },
      ),
    ));
  }
}