import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// A registered mini program (برنامج مصغّر) — a self-contained "app" inside
/// الفائق يمن, in the spirit of WeChat's 小程序 platform.
class MiniProgram {
  final String id;
  final String slug;
  final String name;
  final String description;
  final String icon;
  final String route;
  final String category;
  final String? publisherName;
  final bool verified;
  final bool featured;
  final int usageCount;
  final int sortOrder;

  const MiniProgram({
    required this.id,
    required this.slug,
    required this.name,
    required this.description,
    required this.icon,
    required this.route,
    required this.category,
    this.publisherName,
    this.verified = false,
    this.featured = false,
    this.usageCount = 0,
    this.sortOrder = 100,
  });

  factory MiniProgram.fromRow(Map<String, dynamic> row) => MiniProgram(
        id: (row['id'] ?? '').toString(),
        slug: (row['slug'] ?? '').toString(),
        name: (row['name'] ?? '').toString(),
        description: (row['description'] ?? '').toString(),
        icon: (row['icon'] ?? 'explore').toString(),
        route: (row['route'] ?? '').toString(),
        category: (row['category'] ?? 'عام').toString(),
        publisherName: row['publisher_name']?.toString(),
        verified: row['verified'] == true,
        featured: row['featured'] == true,
        usageCount: (row['usage_count'] as num?)?.toInt() ?? 0,
        sortOrder: (row['sort_order'] as num?)?.toInt() ?? 100,
      );
}

/// Data access for the mini-program platform. Reads go through the
/// `mini_programs_list` RPC; publishing is staff-gated in the database.
class MiniProgramsService {
  const MiniProgramsService();

  static SupabaseClient get _db => SupabaseService.client;

  /// Returns the active mini-program catalog ordered by the server.
  Future<List<MiniProgram>> list({int limit = 200}) async {
    final data = await _db.rpc('mini_programs_list', params: {'p_limit': limit});
    final rows = (data as List).cast<Map<String, dynamic>>();
    return rows.map(MiniProgram.fromRow).toList();
  }

  /// Registers a new mini program. The row is only persisted if the caller is
  /// platform staff (enforced by RLS); the client still needs a unique id/slug.
  Future<void> register({
    required String name,
    required String description,
    required String icon,
    required String route,
    String category = 'عام',
    String? publisherName,
    bool verified = false,
    bool featured = false,
    int sortOrder = 100,
  }) async {
    final base = slugify(name);
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    await _db.from('mini_programs').insert({
      'id': 'mp-$base-$stamp',
      'slug': '$base-$stamp',
      'name': name.trim(),
      'description': description.trim(),
      'icon': icon,
      'route': route.trim(),
      'category': category,
      'publisher_id': _db.auth.currentUser?.id,
      'publisher_name': publisherName,
      'verified': verified,
      'featured': featured,
      'sort_order': sortOrder,
    });
  }

  /// Records a launch so the catalog can rank by popularity. Best-effort.
  Future<void> registerUse(String id) async {
    try {
      await _db.rpc('mini_program_register_use', params: {'p_id': id});
    } catch (_) {
      // Usage telemetry must never block opening a mini program.
    }
  }

  /// Builds a URL-safe slug from a (possibly Arabic) display name. Arabic
  /// letters are preserved; everything else collapses into single dashes.
  static String slugify(String name) {
    final lowered = name.trim().toLowerCase();
    final cleaned = lowered.replaceAll(RegExp(r'[^a-z0-9\u0600-\u06FF]+'), '-');
    final trimmed = cleaned.replaceAll(RegExp(r'^-+|-+$'), '');
    return trimmed.isEmpty ? 'program' : trimmed;
  }
}
