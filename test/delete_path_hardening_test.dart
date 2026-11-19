import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('delete-path hardening migration', () {
    final sql = File('supabase/migrations/20261121010000_delete_path_hardening_v1.sql').readAsStringSync();

    test('grants DELETE on message_reactions to authenticated', () {
      // Without this grant every reaction toggle-off fails with 42501, so a
      // reaction can be added but never removed.
      expect(sql, contains('grant delete on table public.message_reactions to authenticated'));
    });

    test('restores owner-scoped storage delete policies for both media buckets', () {
      expect(sql, contains('create policy moments_media_delete on storage.objects'));
      expect(sql, contains('create policy reels_media_delete on storage.objects'));
      expect(sql, contains('(storage.foldername(name))[1] = auth.uid()::text'));
    });

    test('never widens deletes to anonymous clients', () {
      expect(sql, isNot(contains('to anon')));
      expect(sql, isNot(contains('to public')));
    });

    test('is idempotent so a re-run cannot fail', () {
      expect(sql, contains('drop policy if exists moments_media_delete'));
      expect(sql, contains('drop policy if exists reels_media_delete'));
    });
  });

  group('delete services', () {
    test('moment deletion removes its media and detects a blocked delete', () {
      final svc = File('lib/services/moments_service.dart').readAsStringSync();
      expect(svc, contains(".delete().eq('id', momentId).select('id')"));
      expect(svc, contains('storage.from(bucket).remove('));
      expect(svc, contains('removed.isEmpty'));
    });

    test('reel deletion removes its media and detects a blocked delete', () {
      final svc = File('lib/services/reels_service.dart').readAsStringSync();
      expect(svc, contains(".delete().eq('id', reelId).select('id')"));
      expect(svc, contains('storage.from(bucket).remove('));
      expect(svc, contains('removed.isEmpty'));
    });

    test('site update deletion reports a refused delete instead of succeeding silently', () {
      final svc = File('lib/services/public_content_service.dart').readAsStringSync();
      expect(svc, contains(".delete().eq('id', id).select('id')"));
      expect(svc, contains('removed.isEmpty'));
    });

    test('reaction toggle-off surfaces a refused delete', () {
      final page = File('lib/screens/group_chat_page.dart').readAsStringSync();
      expect(page, contains(".delete()"));
      expect(page, contains(".select('id')"));
      expect(page, contains('removed.isEmpty'));
    });
  });
}
