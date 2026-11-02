import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'mini_programs_service.dart';
import 'supabase_service.dart';

/// An Official Account (حساب رسمي) — a WeChat-style 公众号 that publishes
/// articles and can be followed.
class OfficialAccount {
  final String id;
  final String slug;
  final String name;
  final String bio;
  final String? avatarUrl;
  final String kind;
  final bool verified;
  final int followerCount;
  final int articleCount;
  final bool following;
  final bool isOwner;

  const OfficialAccount({
    required this.id,
    required this.slug,
    required this.name,
    required this.bio,
    this.avatarUrl,
    this.kind = 'personal',
    this.verified = false,
    this.followerCount = 0,
    this.articleCount = 0,
    this.following = false,
    this.isOwner = false,
  });

  factory OfficialAccount.fromRow(Map<String, dynamic> row) => OfficialAccount(
        id: (row['id'] ?? '').toString(),
        slug: (row['slug'] ?? '').toString(),
        name: (row['name'] ?? '').toString(),
        bio: (row['bio'] ?? '').toString(),
        avatarUrl: row['avatar_url']?.toString(),
        kind: (row['kind'] ?? 'personal').toString(),
        verified: row['verified'] == true,
        followerCount: (row['follower_count'] as num?)?.toInt() ?? 0,
        articleCount: (row['article_count'] as num?)?.toInt() ?? 0,
        following: row['following'] == true,
        isOwner: row['is_owner'] == true,
      );
}

/// A published article inside an Official Account.
class AccountArticle {
  final String id;
  final String accountId;
  final String accountName;
  final String? accountAvatar;
  final bool accountVerified;
  final String title;
  final String? coverUrl;
  final String excerpt;
  final int viewCount;
  final int likeCount;
  final bool published;
  final bool isOwner;

  const AccountArticle({
    required this.id,
    required this.accountId,
    required this.accountName,
    this.accountAvatar,
    this.accountVerified = false,
    required this.title,
    this.coverUrl,
    this.excerpt = '',
    this.viewCount = 0,
    this.likeCount = 0,
    this.published = true,
    this.isOwner = false,
  });

  factory AccountArticle.fromRow(Map<String, dynamic> row) => AccountArticle(
        id: (row['id'] ?? '').toString(),
        accountId: (row['account_id'] ?? '').toString(),
        accountName: (row['account_name'] ?? '').toString(),
        accountAvatar: row['account_avatar']?.toString(),
        accountVerified: row['account_verified'] == true,
        title: (row['title'] ?? '').toString(),
        coverUrl: row['cover_url']?.toString(),
        excerpt: (row['excerpt'] ?? '').toString(),
        viewCount: (row['view_count'] as num?)?.toInt() ?? 0,
        likeCount: (row['like_count'] as num?)?.toInt() ?? 0,
        published: row['published'] != false,
        isOwner: row['is_owner'] == true,
      );
}

/// Data access for the Official Accounts (公众号) platform.
class OfficialAccountsService {
  const OfficialAccountsService();

  static const bucket = 'official-accounts';

  static SupabaseClient get _db => SupabaseService.client;

  String? get currentUserId => _db.auth.currentUser?.id;

  List<Map<String, dynamic>> _rows(dynamic data) =>
      (data as List).cast<Map<String, dynamic>>();

  Future<List<OfficialAccount>> listAccounts({int limit = 50, int offset = 0}) async {
    final data = await _db.rpc('official_accounts_list', params: {'p_limit': limit, 'p_offset': offset});
    return _rows(data).map(OfficialAccount.fromRow).toList();
  }

  Future<OfficialAccount?> accountDetail(String id) async {
    final data = await _db.rpc('official_account_detail', params: {'p_id': id});
    final rows = _rows(data);
    return rows.isEmpty ? null : OfficialAccount.fromRow(rows.first);
  }

  Future<List<AccountArticle>> articles({String? accountId, int limit = 30, int offset = 0}) async {
    final data = await _db.rpc('account_articles_list', params: {
      'p_account_id': accountId,
      'p_limit': limit,
      'p_offset': offset,
    });
    return _rows(data).map(AccountArticle.fromRow).toList();
  }

  Future<List<AccountArticle>> myFeed({int limit = 30, int offset = 0}) async {
    final data = await _db.rpc('my_account_feed', params: {'p_limit': limit, 'p_offset': offset});
    return _rows(data).map(AccountArticle.fromRow).toList();
  }

  /// Full article (including the body) for the reader.
  Future<({AccountArticle article, String body})?> articleDetail(String id) async {
    final data = await _db.rpc('account_article_detail', params: {'p_id': id});
    final rows = _rows(data);
    if (rows.isEmpty) return null;
    final row = rows.first;
    return (article: AccountArticle.fromRow(row), body: (row['body'] ?? '').toString());
  }

  Future<List<OfficialAccount>> following() async {
    final data = await _db.rpc('account_following_list');
    return _rows(data).map(OfficialAccount.fromRow).toList();
  }

  /// Creates an account for the current user and returns its id.
  Future<String> createAccount({
    required String name,
    required String bio,
    String kind = 'personal',
    String? avatarUrl,
  }) async {
    final uid = currentUserId;
    if (uid == null) throw StateError('يجب تسجيل الدخول لإنشاء حساب رسمي.');
    final base = MiniProgramsService.slugify(name);
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final row = await _db
        .from('official_accounts')
        .insert({
          'slug': '$base-$stamp',
          'name': name.trim(),
          'bio': bio.trim(),
          'kind': kind,
          'avatar_url': avatarUrl,
          'owner_id': uid,
        })
        .select('id')
        .single();
    return (row['id'] ?? '').toString();
  }

  Future<void> updateAccount({
    required String id,
    required String name,
    required String bio,
    String? avatarUrl,
  }) async {
    await _db.from('official_accounts').update({
      'name': name.trim(),
      'bio': bio.trim(),
      if (avatarUrl != null) 'avatar_url': avatarUrl,
    }).eq('id', id);
  }

  /// Toggles follow and returns the new followed state.
  Future<bool> toggleFollow(String accountId) async {
    final res = await _db.rpc('account_toggle_follow', params: {'p_account_id': accountId});
    return res == true;
  }

  Future<void> publishArticle({
    required String accountId,
    required String title,
    required String body,
    String? coverUrl,
    bool published = true,
  }) async {
    final uid = currentUserId;
    if (uid == null) throw StateError('يجب تسجيل الدخول للنشر.');
    await _db.from('account_articles').insert({
      'account_id': accountId,
      'author_id': uid,
      'title': title.trim(),
      'body': body.trim(),
      'cover_url': coverUrl,
      'published': published,
    });
  }

  Future<void> registerView(String articleId) async {
    try {
      await _db.rpc('account_article_register_view', params: {'p_article_id': articleId});
    } catch (_) {
      // Views are best-effort telemetry.
    }
  }

  /// Uploads an image (avatar or cover) and returns its public URL.
  Future<String> uploadImage(Uint8List bytes, String extension, {String folder = 'covers'}) async {
    final uid = currentUserId;
    if (uid == null) throw StateError('يجب تسجيل الدخول للرفع.');
    final path = '$uid/$folder/${DateTime.now().microsecondsSinceEpoch}.$extension';
    await _db.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: 'image/$extension', upsert: true),
        );
    return _db.storage.from(bucket).getPublicUrl(path);
  }
}
