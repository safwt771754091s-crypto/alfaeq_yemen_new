import 'package:flutter/material.dart';

import '../services/catalog_service.dart';
import '../services/follow_service.dart';
import 'store_detail_page.dart';

/// المتابعات — the stores and people the signed-in user follows (WeChat 关注).
class MyFollowsPage extends StatefulWidget {
  const MyFollowsPage({super.key});

  @override
  State<MyFollowsPage> createState() => _MyFollowsPageState();
}

class _MyFollowsPageState extends State<MyFollowsPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await FollowService().myFollows();
      if (!mounted) return;
      setState(() {
        _items = rows;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذّر تحميل قائمة المتابعة، حاول لاحقاً';
        _loading = false;
      });
    }
  }

  Future<void> _unfollow(Map<String, dynamic> row) async {
    try {
      await FollowService().toggle(
        targetType: (row['target_type'] ?? '').toString(),
        targetId: (row['target_id'] ?? '').toString(),
      );
      if (mounted) setState(() => _items = _items.where((r) => r != row).toList());
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذّر إلغاء المتابعة')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('متابعاتي', style: TextStyle(fontWeight: FontWeight.w900))),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _message(_error!, Icons.error_outline)
                : _items.isEmpty
                    ? _message('لا تتابع أي متجر بعد. تابع متجرك المفضّل ليظهر هنا.', Icons.favorite_border)
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final row = _items[i];
                            final isStore = (row['target_type'] ?? '') == 'store';
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: const Color(0xFFE7F0FF),
                                child: Icon(isStore ? Icons.storefront_outlined : Icons.person_outline,
                                    color: const Color(0xFF0D6EFD)),
                              ),
                              title: Text((row['label'] ?? '').toString(),
                                  style: const TextStyle(fontWeight: FontWeight.w800)),
                              subtitle: Text(isStore ? 'متجر' : 'مستخدم'),
                              trailing: TextButton(
                                onPressed: () => _unfollow(row),
                                child: const Text('إلغاء المتابعة'),
                              ),
                              onTap: isStore ? () => _openStore(row['target_id'].toString()) : null,
                            );
                          },
                        ),
                      ),
      ),
    );
  }

  Future<void> _openStore(String id) async {
    try {
      final store = await CatalogService().storeById(id);
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => StoreDetailPage(store: store)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذّر فتح المتجر')));
    }
  }

  Widget _message(String text, IconData icon) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: Colors.grey),
              const SizedBox(height: 12),
              Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 15)),
            ],
          ),
        ),
      );
}
