import 'package:flutter/material.dart';

import '../services/official_accounts_service.dart';
import 'article_reader_page.dart';
import 'official_article_form_page.dart';

const _blue = Color(0xFF0D6EFD);
const _navy = Color(0xFF0A2540);
const _surface = Color(0xFFF5F7FA);

/// Official Account profile (صفحة الحساب الرسمي): identity, follow action and
/// the account's published articles. Owners also get a publish entry.
class OfficialAccountDetailPage extends StatefulWidget {
  final String accountId;
  const OfficialAccountDetailPage({super.key, required this.accountId});

  @override
  State<OfficialAccountDetailPage> createState() => _OfficialAccountDetailPageState();
}

class _OfficialAccountDetailPageState extends State<OfficialAccountDetailPage> {
  final _service = const OfficialAccountsService();
  OfficialAccount? _account;
  List<AccountArticle> _articles = const [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final account = await _service.accountDetail(widget.accountId);
      final articles = await _service.articles(accountId: widget.accountId);
      if (!mounted) return;
      setState(() { _account = account; _articles = articles; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleFollow() async {
    final account = _account;
    if (account == null || _busy) return;
    setState(() => _busy = true);
    try {
      final following = await _service.toggleFollow(account.id);
      if (!mounted) return;
      setState(() {
        _account = OfficialAccount(
          id: account.id, slug: account.slug, name: account.name, bio: account.bio,
          avatarUrl: account.avatarUrl, kind: account.kind, verified: account.verified,
          followerCount: account.followerCount + (following ? 1 : -1),
          articleCount: account.articleCount, following: following, isOwner: account.isOwner,
        );
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تنفيذ العملية: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _publish() async {
    final account = _account;
    if (account == null) return;
    final published = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => OfficialArticleFormPage(accountId: account.id)));
    if (published == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final account = _account;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _surface,
        appBar: AppBar(title: Text(account?.name ?? 'الحساب الرسمي', style: const TextStyle(fontWeight: FontWeight.w900))),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : account == null
                ? const Center(child: Text('الحساب غير متاح.', style: TextStyle(color: Colors.black54)))
                : ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE3E8EF))),
                        child: Column(
                          children: [
                            CircleAvatar(radius: 34, backgroundColor: const Color(0xFFE7F0FF), backgroundImage: (account.avatarUrl ?? '').isEmpty ? null : NetworkImage(account.avatarUrl!)),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Flexible(child: Text(account.name, style: const TextStyle(color: _navy, fontSize: 20, fontWeight: FontWeight.w900))),
                                if (account.verified) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.verified, color: _blue, size: 18)),
                              ],
                            ),
                            if (account.bio.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(account.bio, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
                            ],
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _stat('${account.followerCount}', 'متابع'),
                                const SizedBox(width: 24),
                                _stat('${account.articleCount}', 'مقالة'),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (account.isOwner)
                              FilledButton.icon(onPressed: _publish, icon: const Icon(Icons.edit_note), label: const Text('نشر مقالة'))
                            else
                              FilledButton.icon(
                                onPressed: _busy ? null : _toggleFollow,
                                icon: Icon(account.following ? Icons.check : Icons.add),
                                label: Text(account.following ? 'متابَع' : 'متابعة'),
                                style: FilledButton.styleFrom(backgroundColor: account.following ? Colors.grey.shade600 : _blue),
                              ),
                          ],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(4, 18, 4, 8),
                        child: Text('المقالات', style: TextStyle(color: _navy, fontWeight: FontWeight.w900, fontSize: 17)),
                      ),
                      if (_articles.isEmpty)
                        const Padding(padding: EdgeInsets.all(16), child: Text('لا توجد مقالات منشورة بعد.', style: TextStyle(color: Colors.black54)))
                      else
                        for (final article in _articles)
                          Card(
                            elevation: 0,
                            margin: const EdgeInsets.only(bottom: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFE3E8EF))),
                            child: ListTile(
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ArticleReaderPage(article: article))),
                              leading: (article.coverUrl ?? '').isEmpty
                                  ? const CircleAvatar(backgroundColor: Color(0xFFE7F0FF), child: Icon(Icons.article_outlined, color: _blue))
                                  : ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(article.coverUrl!, width: 48, height: 48, fit: BoxFit.cover)),
                              title: Text(article.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                              subtitle: Text(article.excerpt, maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                          ),
                    ],
                  ),
      ),
    );
  }

  Widget _stat(String value, String label) => Column(
        children: [
          Text(value, style: const TextStyle(color: _navy, fontWeight: FontWeight.w900, fontSize: 18)),
          Text(label, style: const TextStyle(color: Colors.black54, fontSize: 12)),
        ],
      );
}
