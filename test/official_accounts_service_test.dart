import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:alfaeq_yemen/services/official_accounts_service.dart';

void main() {
  group('OfficialAccount.fromRow', () {
    test('parses the directory row', () {
      final account = OfficialAccount.fromRow({
        'id': 'a1',
        'slug': 'alpha-store',
        'name': 'متجر ألفا',
        'bio': 'عروض يومية',
        'avatar_url': 'https://x/y.png',
        'kind': 'business',
        'verified': true,
        'follower_count': 42,
        'article_count': 3,
        'following': true,
        'is_owner': false,
      });
      expect(account.id, 'a1');
      expect(account.name, 'متجر ألفا');
      expect(account.kind, 'business');
      expect(account.verified, isTrue);
      expect(account.followerCount, 42);
      expect(account.articleCount, 3);
      expect(account.following, isTrue);
      expect(account.isOwner, isFalse);
    });

    test('defaults safely when columns are absent', () {
      final account = OfficialAccount.fromRow({'id': 'a2', 'name': 'x'});
      expect(account.bio, '');
      expect(account.kind, 'personal');
      expect(account.verified, isFalse);
      expect(account.followerCount, 0);
      expect(account.following, isFalse);
    });
  });

  group('AccountArticle.fromRow', () {
    test('parses the feed row', () {
      final article = AccountArticle.fromRow({
        'id': 'ar1',
        'account_id': 'a1',
        'account_name': 'متجر ألفا',
        'account_verified': true,
        'title': 'تخفيضات',
        'excerpt': 'خصم 20%',
        'view_count': 7,
        'is_owner': true,
      });
      expect(article.id, 'ar1');
      expect(article.accountName, 'متجر ألفا');
      expect(article.accountVerified, isTrue);
      expect(article.excerpt, 'خصم 20%');
      expect(article.viewCount, 7);
      expect(article.isOwner, isTrue);
    });
  });

  group('Official Accounts guardrails', () {
    test('migration defines the tables, RLS, RPCs and the media bucket', () {
      final migration = File('supabase/migrations/20261101020000_official_accounts_v1.sql').readAsStringSync();
      expect(migration, contains('create table if not exists public.official_accounts'));
      expect(migration, contains('create table if not exists public.account_articles'));
      expect(migration, contains('create table if not exists public.account_followers'));
      expect(migration, contains('enable row level security'));
      expect(migration, contains('create or replace function public.official_accounts_list'));
      expect(migration, contains('create or replace function public.account_toggle_follow'));
      expect(migration, contains('create or replace function public.account_article_detail'));
      expect(migration, contains("'official-accounts'"));
      // Anonymous callers must not be able to read the platform.
      expect(migration, contains('from public, anon'));
    });

    test('account writes are owner-scoped in the database', () {
      final migration = File('supabase/migrations/20261101020000_official_accounts_v1.sql').readAsStringSync();
      final insertPolicy = migration.substring(
        migration.indexOf('official_accounts_insert'),
        migration.indexOf('official_accounts_update'),
      );
      expect(insertPolicy, contains('owner_id = auth.uid()'));
      final articleInsert = migration.substring(
        migration.indexOf('account_articles_insert'),
        migration.indexOf('account_articles_update'),
      );
      expect(articleInsert, contains('author_id = auth.uid()'));
      expect(articleInsert, contains('a.owner_id = auth.uid()'));
    });

    test('the service is RPC-first and the launcher routes to the accounts hub', () {
      final service = File('lib/services/official_accounts_service.dart').readAsStringSync();
      expect(service, contains("rpc('official_accounts_list'"));
      expect(service, contains("rpc('account_toggle_follow'"));
      expect(service, contains("from('account_articles').insert"));
      expect(service, contains("bucket = 'official-accounts'"));

      final world = File('lib/screens/world_home_page.dart').readAsStringSync();
      expect(world, contains('OfficialAccountsPage()'));

      final launcher = File('lib/screens/mini_programs_page.dart').readAsStringSync();
      expect(launcher, contains("case 'accounts': return const OfficialAccountsPage();"));

      final seeds = File('supabase/migrations/20261101010000_mini_programs_v1.sql').readAsStringSync();
      expect(seeds, contains("'screen:accounts'"));
    });
  });
}
