import 'package:flutter/material.dart';
import '../services/mini_programs_service.dart';
import '../services/official_accounts_service.dart';
import '../services/supabase_service.dart';
import 'article_reader_page.dart';
import 'official_account_detail_page.dart';
import 'program_checkout_page.dart';

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  Future<void> _markRead(String id) async {
    await SupabaseService.client.from('notifications').update({
      'read_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  /// Opens the destination carried in a notification's `data` payload. Account
  /// article notifications (公众号) open the article reader directly.
  Future<void> _open(BuildContext context, Map<String, dynamic> row) async {
    final data = (row['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    final type = (row['type'] ?? '').toString();
    if (type == 'account_article') {
      final articleId = (data['article_id'] ?? '').toString();
      final accountId = (data['account_id'] ?? '').toString();
      if (articleId.isEmpty) {
        if (accountId.isNotEmpty) {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => OfficialAccountDetailPage(accountId: accountId)));
        }
        return;
      }
      final article = OfficialAccountsService.articleFromPayload(data);
      await Navigator.push(context, MaterialPageRoute(builder: (_) => ArticleReaderPage(article: article)));
      return;
    }
    if (type == 'program_refund') {
      final programId = (data['program_id'] ?? '').toString();
      final program = programId.isEmpty ? null : await MiniProgramsService().byId(programId);
      if (program != null && context.mounted) {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => ProgramCheckoutPage(program: program)));
      }
      return;
    }
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
                onTap: () async {
                  try { if (!read) await _markRead(row['id'].toString()); } catch (_) {}
                  if (context.mounted) await _open(context, row);
                },
              ));
            },
          );
        },
      ),
    ));
  }
}