import 'package:flutter/material.dart';

import '../services/official_accounts_service.dart';

const _blue = Color(0xFF0D6EFD);
const _navy = Color(0xFF0A2540);

/// Full-screen article reader for an Official Account (公众号) article.
class ArticleReaderPage extends StatefulWidget {
  final AccountArticle article;
  const ArticleReaderPage({super.key, required this.article});

  @override
  State<ArticleReaderPage> createState() => _ArticleReaderPageState();
}

class _ArticleReaderPageState extends State<ArticleReaderPage> {
  final _service = const OfficialAccountsService();
  String? _body;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _service.registerView(widget.article.id);
    _load();
  }

  Future<void> _load() async {
    final detail = await _service.articleDetail(widget.article.id);
    if (!mounted) return;
    setState(() {
      _body = detail?.body ?? widget.article.excerpt;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final article = widget.article;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('مقالة', style: TextStyle(fontWeight: FontWeight.w900))),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
          children: [
            Text(article.title, style: const TextStyle(color: _navy, fontSize: 24, fontWeight: FontWeight.w900, height: 1.35)),
            const SizedBox(height: 10),
            Row(
              children: [
                CircleAvatar(radius: 16, backgroundColor: const Color(0xFFE7F0FF), backgroundImage: (article.accountAvatar ?? '').isEmpty ? null : NetworkImage(article.accountAvatar!)),
                const SizedBox(width: 8),
                Flexible(child: Text(article.accountName, style: const TextStyle(fontWeight: FontWeight.w800, color: _navy))),
                if (article.accountVerified) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.verified, size: 15, color: _blue)),
                const Spacer(),
                const Icon(Icons.visibility_outlined, size: 14, color: Colors.black38),
                const SizedBox(width: 3),
                Text('${article.viewCount}', style: const TextStyle(fontSize: 12, color: Colors.black45)),
              ],
            ),
            if ((article.coverUrl ?? '').isNotEmpty) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(article.coverUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
              ),
            ],
            const SizedBox(height: 18),
            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else
              SelectableText((_body ?? '').isEmpty ? 'لا يوجد محتوى.' : _body!, style: const TextStyle(fontSize: 16.5, height: 1.9, color: Colors.black87)),
          ],
        ),
      ),
    );
  }
}
