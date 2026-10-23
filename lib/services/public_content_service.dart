import 'supabase_service.dart';

class PromotionDocument {
  final String id;
  final Map<String, dynamic> data;
  const PromotionDocument({required this.id, required this.data});
}

class SiteUpdateDocument {
  final String id;
  final Map<String, dynamic> data;
  const SiteUpdateDocument({required this.id, required this.data});
}

/// Single public-content gateway used by the Flutter client.
/// Published content is read directly from the production Supabase database,
/// so the app never needs a separately maintained copy of promotions.
class PublicContentService {
  const PublicContentService();

  Future<List<PromotionDocument>> activePromotions({int limit = 20}) async {
    if (!SupabaseService.isInitialized) {
      throw StateError('خدمة المحتوى غير مفعلة.');
    }
    final rows = await SupabaseService.client
        .from('promotions')
        .select()
        .eq('status', 'published')
        .lte('starts_at', DateTime.now().toUtc().toIso8601String())
        .or('ends_at.is.null,ends_at.gt.${DateTime.now().toUtc().toIso8601String()}')
        .order('starts_at', ascending: false)
        .limit(limit);
    return rows.map((row) {
      final copy = Map<String, dynamic>.from(row);
      final id = (copy.remove('id') ?? '').toString();
      return PromotionDocument(id: id, data: copy);
    }).toList();
  }

  Future<List<SiteUpdateDocument>> publishedUpdates({int limit = 20}) async {
    if (!SupabaseService.isInitialized) {
      throw StateError('خدمة المحتوى غير مفعلة.');
    }
    final rows = await SupabaseService.client
        .from('public_site_updates')
        .select()
        .eq('status', 'published')
        .or('published_at.is.null,published_at.lte.${DateTime.now().toUtc().toIso8601String()}')
        .order('sort_order')
        .order('published_at', ascending: false)
        .limit(limit);
    return rows.map((row) {
      final copy = Map<String, dynamic>.from(row);
      final id = (copy.remove('id') ?? '').toString();
      return SiteUpdateDocument(id: id, data: copy);
    }).toList();
  }

  Stream<List<PromotionDocument>> watchPromotions({int limit = 20}) async* {
    while (true) {
      yield await activePromotions(limit: limit);
      await Future<void>.delayed(const Duration(minutes: 2));
    }
  }

  /// Staff-only: list every update regardless of status (drafts included).
  Future<List<SiteUpdateDocument>> allUpdates({int limit = 200}) async {
    if (!SupabaseService.isInitialized) {
      throw StateError('خدمة المحتوى غير مفعلة.');
    }
    final rows = await SupabaseService.client
        .from('public_site_updates')
        .select()
        .order('sort_order')
        .order('published_at', ascending: false)
        .limit(limit);
    return rows.map((row) {
      final copy = Map<String, dynamic>.from(row);
      final id = (copy.remove('id') ?? '').toString();
      return SiteUpdateDocument(id: id, data: copy);
    }).toList();
  }

  Future<void> upsertUpdate({
    String? id,
    required String title,
    String? summary,
    String? body,
    String? imageUrl,
    String? ctaLabel,
    String? ctaUrl,
    required String status,
    int sortOrder = 0,
  }) async {
    if (!SupabaseService.isInitialized) {
      throw StateError('خدمة المحتوى غير مفعلة.');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final payload = <String, dynamic>{
      'title': title.trim(),
      'summary': _nullIfBlank(summary),
      'body': _nullIfBlank(body),
      'image_url': _nullIfBlank(imageUrl),
      'cta_label': _nullIfBlank(ctaLabel),
      'cta_url': _nullIfBlank(ctaUrl),
      'status': status,
      'sort_order': sortOrder,
      'updated_at': now,
      if (status == 'published') 'published_at': now,
    };
    if (id == null || id.isEmpty) {
      payload['id'] = 'update-${DateTime.now().microsecondsSinceEpoch}';
      await SupabaseService.client.from('public_site_updates').insert(payload);
    } else {
      await SupabaseService.client.from('public_site_updates').update(payload).eq('id', id);
    }
  }

  Future<void> deleteUpdate(String id) async {
    if (!SupabaseService.isInitialized) {
      throw StateError('خدمة المحتوى غير مفعلة.');
    }
    await SupabaseService.client.from('public_site_updates').delete().eq('id', id);
  }

  static String? _nullIfBlank(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }
}
