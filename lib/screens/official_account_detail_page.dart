import 'package:flutter/material.dart';

import '../services/mini_programs_service.dart';
import '../services/official_accounts_service.dart';
import 'article_reader_page.dart';
import 'mini_programs_page.dart';
import 'official_article_form_page.dart';
import 'official_program_form_page.dart';
import 'program_checkout_page.dart';

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
  final _programsService = const MiniProgramsService();
  OfficialAccount? _account;
  List<AccountArticle> _articles = const [];
  List<MiniProgram> _programs = const [];
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
      List<MiniProgram> programs = const [];
      try {
        programs = await _programsService.listForAccount(widget.accountId);
      } catch (_) {
        // Programs are optional; the profile still renders without them.
      }
      if (!mounted) return;
      setState(() { _account = account; _articles = articles; _programs = programs; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addProgram() async {
    final account = _account;
    if (account == null) return;
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => OfficialProgramFormPage(accountId: account.id, accountName: account.name)),
    );
    if (added == true) await _load();
  }

  void _openProgram(MiniProgram program) {
    final destination = miniProgramDestination(program);
    if (destination == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('هذا البرنامج غير متاح على هذا الإصدار بعد.')));
      return;
    }
    _programsService.registerUse(program.id);
    Navigator.push(context, MaterialPageRoute(builder: (_) => destination));
  }

  Future<void> _payProgram(MiniProgram program) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProgramCheckoutPage(program: program)),
    );
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
                        child: Text('البرامج المصغّرة', style: TextStyle(color: _navy, fontWeight: FontWeight.w900, fontSize: 17)),
                      ),
                      if (_programs.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            (_account?.isOwner ?? false) ? 'لم تُضف برامج بعد — أضف أول برنامج لحسابك.' : 'لا توجد برامج مصغّرة لهذا الحساب.',
                            style: const TextStyle(color: Colors.black54),
                          ),
                        )
                      else
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (final program in _programs)
                              _ProgramChip(
                                program: program,
                                onTap: () => _openProgram(program),
                                onPay: () => _payProgram(program),
                              ),
                          ],
                        ),
                      if (_account?.isOwner ?? false) ...[
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _addProgram,
                          icon: const Icon(Icons.add),
                          label: const Text('إضافة برنامج مصغّر'),
                        ),
                      ],
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

/// A tappable mini-program tile shown on an account profile.
class _ProgramChip extends StatelessWidget {
  final MiniProgram program;
  final VoidCallback onTap;
  final VoidCallback onPay;
  const _ProgramChip({required this.program, required this.onTap, required this.onPay});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 104,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE3E8EF)),
        ),
        child: Column(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: const Color(0xFFE7F0FF),
              child: Icon(miniProgramIcon(program.icon), color: _blue),
            ),
            const SizedBox(height: 8),
            Text(
              program.name,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _navy, fontWeight: FontWeight.w700, fontSize: 12),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: onPay,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: _blue,
              ),
              child: const Text('دفع', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }
}
