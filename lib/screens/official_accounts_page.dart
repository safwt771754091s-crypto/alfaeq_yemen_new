import 'package:flutter/material.dart';

import '../services/official_accounts_service.dart';
import 'article_reader_page.dart';
import 'official_account_detail_page.dart';
import 'official_account_form_page.dart';

const _blue = Color(0xFF0D6EFD);
const _navy = Color(0xFF0A2540);
const _surface = Color(0xFFF5F7FA);

/// WeChat-style Official Accounts hub (الحسابات الرسمية / 公众号): the accounts
/// you follow plus the public directory, with an entry to open your own.
class OfficialAccountsPage extends StatefulWidget {
  const OfficialAccountsPage({super.key});

  @override
  State<OfficialAccountsPage> createState() => _OfficialAccountsPageState();
}

class _OfficialAccountsPageState extends State<OfficialAccountsPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final _service = const OfficialAccountsService();
  List<OfficialAccount> _following = const [];
  List<OfficialAccount> _all = const [];
  List<AccountArticle> _feed = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _service.following(),
        _service.listAccounts(),
        _service.myFeed(),
      ]);
      if (!mounted) return;
      setState(() {
        _following = results[0] as List<OfficialAccount>;
        _all = results[1] as List<OfficialAccount>;
        _feed = results[2] as List<AccountArticle>;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openAccount(OfficialAccount account) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => OfficialAccountDetailPage(accountId: account.id)));
    await _load();
  }

  Future<void> _createAccount() async {
    final created = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const OfficialAccountFormPage()));
    if (created == true) await _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الحسابات الرسمية', style: TextStyle(fontWeight: FontWeight.w900)),
          bottom: TabBar(
            controller: _tabs,
            tabs: const [Tab(text: 'متابعاتي'), Tab(text: 'استكشف')],
          ),
          actions: [
            IconButton(onPressed: _createAccount, tooltip: 'أنشئ حساباً رسمياً', icon: const Icon(Icons.add_circle_outline)),
          ],
        ),
        backgroundColor: _surface,
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabs,
                children: [
                  _followingTab(),
                  _exploreTab(),
                ],
              ),
      ),
    );
  }

  Widget _followingTab() {
    if (_following.isEmpty && _feed.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('لم تتابع أي حساب رسمي بعد. افتح تبويب «استكشف» واشترك.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (_following.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Text('حساباتي', style: TextStyle(color: _navy, fontWeight: FontWeight.w900, fontSize: 17)),
          ),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              reverse: true,
              itemCount: _following.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) => _FollowingChip(account: _following[i], onTap: () => _openAccount(_following[i])),
            ),
          ),
        ],
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Text('أحدث المقالات', style: TextStyle(color: _navy, fontWeight: FontWeight.w900, fontSize: 17)),
        ),
        if (_feed.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('لا توجد مقالات من الحسابات التي تتابعها بعد.', style: TextStyle(color: Colors.black54)),
          )
        else
          for (final article in _feed) _ArticleTile(article: article),
      ],
    );
  }

  Widget _exploreTab() {
    if (_all.isEmpty) {
      return const Center(child: Text('لا توجد حسابات رسمية بعد.', style: TextStyle(color: Colors.black54)));
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [for (final account in _all) _AccountTile(account: account, onTap: () => _openAccount(account))],
    );
  }
}

class _FollowingChip extends StatelessWidget {
  final OfficialAccount account;
  final VoidCallback onTap;
  const _FollowingChip({required this.account, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: 78,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE3E8EF))),
          child: Column(
            children: [
              CircleAvatar(radius: 20, backgroundColor: const Color(0xFFE7F0FF), backgroundImage: (account.avatarUrl ?? '').isEmpty ? null : NetworkImage(account.avatarUrl!)),
              const SizedBox(height: 6),
              Text(account.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: _navy)),
            ],
          ),
        ),
      );
}

class _AccountTile extends StatelessWidget {
  final OfficialAccount account;
  final VoidCallback onTap;
  const _AccountTile({required this.account, required this.onTap});

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFE3E8EF))),
        child: ListTile(
          onTap: onTap,
          leading: CircleAvatar(radius: 24, backgroundColor: const Color(0xFFE7F0FF), backgroundImage: (account.avatarUrl ?? '').isEmpty ? null : NetworkImage(account.avatarUrl!)),
          title: Row(
            children: [
              Flexible(child: Text(account.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900))),
              if (account.verified) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.verified, size: 16, color: _blue)),
            ],
          ),
          subtitle: Text(account.bio.isEmpty ? '${account.articleCount} مقالة · ${account.followerCount} متابع' : account.bio, maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: account.following
              ? const Chip(label: Text('متابَع', style: TextStyle(fontSize: 11)))
              : const Icon(Icons.chevron_left),
        ),
      );
}

class _ArticleTile extends StatelessWidget {
  final AccountArticle article;
  const _ArticleTile({required this.article});

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFE3E8EF))),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ArticleReaderPage(article: article))),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((article.coverUrl ?? '').isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(article.coverUrl!, width: 84, height: 84, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                  )
                else
                  Container(width: 84, height: 84, decoration: BoxDecoration(color: const Color(0xFFE7F0FF), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.article_outlined, color: _blue)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(article.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, color: _navy, fontSize: 15)),
                      const SizedBox(height: 4),
                      if (article.excerpt.isNotEmpty) Text(article.excerpt, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.black54, fontSize: 12.5)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.visibility_outlined, size: 13, color: Colors.black38),
                          const SizedBox(width: 3),
                          Text('${article.viewCount}', style: const TextStyle(fontSize: 11, color: Colors.black45)),
                          const SizedBox(width: 10),
                          Flexible(child: Text(article.accountName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.black45))),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
