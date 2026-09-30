import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

class MediaService {
  const MediaService._();

  static const bucket = 'media';

  static Future<String> uploadProductImage({
    required String ownerId,
    required Uint8List bytes,
    required String extension,
    String? productId,
  }) async {
    final safeExt = extension.replaceAll('.', '').toLowerCase();
    final suffix = productId == null || productId.isEmpty
        ? DateTime.now().microsecondsSinceEpoch.toString()
        : productId;
    final path = '$ownerId/products/$suffix.$safeExt';

    await SupabaseService.client.storage.from(bucket).uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(cacheControl: '31536000', upsert: false),
    );

    final publicUrl = SupabaseService.client.storage.from(bucket).getPublicUrl(path);

    await SupabaseService.client.from('media_assets').insert({
      'owner_id': ownerId,
      'entity_type': 'product',
      'entity_id': productId,
      'source': 'supabase_storage',
      'bucket': bucket,
      'object_path': path,
      'public_url': publicUrl,
      'mime_type': _mimeType(safeExt),
      'is_public': true,
      'metadata': {'storage': 'supabase', 'purpose': 'product_image'},
    });

    return publicUrl;
  }

  static String _mimeType(String extension) => switch (extension) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    'avif' => 'image/avif',
    'heic' => 'image/heic',
    _ => 'application/octet-stream',
  };
}